%% demo_local_edit.m — 局部编辑工作流演示（simulink-snapshot-edit）
%
%  流程：搭一个玩具模型 → 导出快照 → snp_patch 局部改参数/位置
%        → 重跑快照 → 验证只有目标块变了。
%
%  运行：demo_local_edit（在 test/scripts/ 下执行；R2023b）

function demo_local_edit()
  here = fileparts(mfilename('fullpath'));
  addpath(fullfile(here, '..', '..', 'src'));       % src/ 在仓库根（test/scripts 的上上级）
  c = snp_config();                                    % 环境配置（snp_config 优先本机 config_local.m）
  outDir = fullfile(fileparts(fileparts(here)), c.OutDir);   % 仓库根 + 配置的目录（默认 scratch）
  if ~isfolder(outDir), mkdir(outDir); end

  %% 1) 玩具模型：正弦 → 增益 → 示波器
  mdl = 'demo_toy';
  if bdIsLoaded(mdl), close_system(mdl, 0); end
  new_system(mdl); m = get_param(bdroot, 'Name');
  add_block('simulink/Sources/Sine Wave', [m '/Src'], 'Position', [40 40 100 70]);
  add_block('simulink/Math Operations/Gain', [m '/K'], 'Position', [150 45 210 65], 'Gain', '2');
  add_block('simulink/Sinks/Scope', [m '/Sc'], 'Position', [260 40 320 70]);
  add_line(m, 'Src/1', 'K/1'); add_line(m, 'K/1', 'Sc/1');
  save_system(m, fullfile(outDir, [mdl '.slx']));

  %% 2) 导出快照
  snp_export(mdl, struct('OutDir', outDir));

  %% 3) 局部编辑：只改 Gain 的增益与 Scope 的位置
  snap = fullfile(outDir, ['snapshot_' mdl '.m']);
  before = fileread(snap);
  snp_patch(snap, 'K', 'Gain', '3.5');
  snp_patch(snap, 'Sc', 'Position', [300 200 360 230]);

  %% 4) 重跑快照重建模型
  run(snap);

  %% 5) 验证：Gain==3.5、Scope 位置已变、Src 原样
  m = get_param(load_system(fullfile(outDir, [mdl '.slx'])), 'Name');
  assert(strcmp(get_param([m '/K'], 'Gain'), '3.5'), 'Gain 未被局部修改');
  p = get_param([m '/Sc'], 'Position');
  assert(isequal(p, [300 200 360 230]), 'Scope 位置未被局部修改');
  btSrc = get_param([m '/Src'], 'BlockType');
  assert(strcmp(btSrc, 'Sin') || strcmp(btSrc, 'SineWave'), 'Src 块被误改');
  % 其他行未动：快照文本除两行外逐字节一致
  after = fileread(snap);
  assert(~strcmp(before, after) && numel(strfind(before, 'add_block')) == numel(strfind(after, 'add_block')));
  close_system(m, 0);
  fprintf('DEMO OK: 局部修改（Gain 2->3.5, Scope 移位）生效，其余原样\n');
end
