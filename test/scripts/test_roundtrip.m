%% test_roundtrip.m — 双向保留测试（simulink-snapshot-edit）
%
%  验证目标：
%    A. agent 方向：LLM 快照（含分节注释+块注释）→ run → 模型 == 原模型；
%       改一行参数 → 再 run → 最小变更生效，注释仍在。
%    B. 人类方向：在 GUI（程序化模拟）改模型（改参数/加块/删块）→ snp_pull →
%       快照反映变更 + LLM 注释全部保留 + 差异报告正确。
%    C. 一致性：verify_fidelity 报告快照==模型。

function test_roundtrip()
  here = fileparts(mfilename('fullpath'));
  root = here; while ~exist(fullfile(root, 'src', 'snp_export.m'), 'file') && ~strcmp(root, fileparts(root)), root = fileparts(root); end
  addpath(fullfile(root, 'src'));
  out = fullfile(here, 'rt_tmp');
  if isfolder(out), rmdir(out, 's'); end
  mkdir(out);

  %% A. agent 方向：带注释的 LLM 快照
  mdl = 'rt_toy';
  if bdIsLoaded(mdl), close_system(mdl, 0); end
  new_system(mdl); m = get_param(bdroot, 'Name');
  % 手工搭一个带注释的"LLM 快照"
  snap = fullfile(out, 'snapshot_rt_toy.m');
  fid = fopen(snap, 'w');
  fprintf(fid, ['function snapshot_rt_toy()\n' ...
    '  %% LLM 写的：玩具模型——验证双向保留\n' ...
    '  if bdIsLoaded(''rt_toy''), close_system(''rt_toy'', 0); end\n' ...
    '  new_system(''rt_toy'');\n' ...
    '  m = get_param(bdroot, ''Name'');\n' ...
    '\n  %% ---- solver / config / model params ----\n' ...
    '  set_param(m, ''SolverName'', ''ode4'');\n' ...
    '\n  %% ---- blocks (positions & full parameters preserved) ----\n' ...
    '  %% 源：信号发生器\n' ...
    '  add_block(''simulink/Sources/Ramp'', [m ''/Ramp1''], ''Position'', [40 40 100 70], ''slope'', ''2'');\n' ...
    '  %% 增益：放大一倍\n' ...
    '  add_block(''simulink/Math Operations/Gain'', [m ''/K''], ''Position'', [150 45 210 65], ''Gain'', ''2'');\n' ...
    '  add_block(''simulink/Sinks/Scope'', [m ''/Sc''], ''Position'', [260 40 320 70]);\n' ...
    '\n  %% ---- lines ----\n' ...
    '  add_line(m, ''Ramp1/1'', ''K/1'', ''autorouting'', ''off'');\n' ...
    '  add_line(m, ''K/1'', ''Sc/1'', ''autorouting'', ''off'');\n' ...
    '\n  save_system(m, fullfile(pwd, ''rt_toy.slx''));\n' ...
    '  close_system(m, 0);\n' ...
    'end\n']);
  fclose(fid);
  cd(out); run(snap); cd(here);

  % A1: 结构 diff=0（模型 == 快照重建）
  addpath(out);
  rA = verify_fidelity(mdl, struct('OutDir', out));
  fprintf('A1 快照重建 == 模型: diff=%d\n', rA.diff);

  % A2: agent 最小改动（改 K 增益 2→3）→ run → 生效 + 注释仍在
  try, close_system(mdl, 0); catch, end
  txt = fileread(snap);
  txt = strrep(txt, '''Gain'', ''2''', '''Gain'', ''3''');
  fid = fopen(snap, 'w'); fwrite(fid, txt); fclose(fid);
  cd(out); run(snap); cd(here);
  mA = get_param(load_system(mdl), 'Name');
  gainOK = strcmp(get_param([mA '/K'], 'Gain'), '3');
  noteOK = contains(fileread(snap), '% 增益：放大一倍');
  fprintf('[dbg] snap=%s has_note=%d has_llm=%d\n', snap, noteOK, contains(fileread(snap), '% LLM 写的'));
  fprintf('A2 最小改动生效=%d 注释保留=%d\n', gainOK, noteOK);

  %% B. 人类方向：模拟 GUI 修改
  % B1: 改位置（人类拖动）
  set_param([mA '/Sc'], 'Position', [400 100 460 130]);
  % B2: 加一个块（人类拖入 Constant，经新 Sum 汇入 K 的输入端）
  add_block('simulink/Sources/Constant', [mA '/C1'], 'Position', [150 150 200 180], 'Value', '1');
  add_block('simulink/Math Operations/Sum', [mA '/SumIn'], 'Position', [150 90 180 120], 'Inputs', '2');
  delete_line(mA, 'K/1', 'Sc/1');
  add_line(mA, 'C1/1', 'SumIn/2');
  delete_line(mA, 'Ramp1/1', 'K/1');   % 先断旧线再走新路径
  add_line(mA, 'Ramp1/1', 'SumIn/1');
  add_line(mA, 'SumIn/1', 'K/1');
  add_line(mA, 'K/1', 'Sc/1');
  % B3: 删一个块（人类删除 Ramp1）
  delete_line(mA, 'Ramp1/1', 'SumIn/1');
  delete_block([mA '/Ramp1']);
  bs = find_system(mdl, 'LookUnderMasks', 'none', 'FollowLinks', 'off', 'Type', 'block');
  fprintf('[dbg] B 段保存前块数=%d\n', numel(bs));
  save_system(mA);                        % 用句柄保存（避开同名 shadow 解析歧义）
  close_system(mA, 0);
  % 落盘验证：从磁盘重载，看 save 是否真把 4 块写进去了
  addpath(out);
  load_system(mdl);
  bs2 = find_system(mdl, 'LookUnderMasks', 'none', 'FollowLinks', 'off', 'Type', 'block');
  fprintf('[dbg] 磁盘重载块数=%d FileName=%s\n', numel(bs2), get_param(mdl, 'FileName'));
  close_system(mdl, 0);

  rep = snp_pull(mdl, snap, struct('OutDir', out));
  fprintf('B. pull: +%d -%d ~%d 注释保留 %d\n', rep.nAdd, rep.nDel, rep.nChg, rep.nNoteKept);
  noteOK2 = contains(fileread(snap), '% LLM 写的：玩具模型');
  fprintf('B. LLM 节注释保留=%d；增益注释保留=%d\n', noteOK2, ...
    contains(fileread(snap), '% 增益：放大一倍'));

  % C. pull 后快照再 run → 应与 GUI 改后模型一致（diff=0）
  try, close_system(mdl, 0); catch, end
  addpath(out);
  cd(out); run(snap); cd(here);
  rC = verify_fidelity(mdl, struct('OutDir', out));
  fprintf('C. pull 后快照重建 == GUI 改后模型: diff=%d\n', rC.diff);

  okA = (rA.diff == 0) && gainOK && noteOK;
  okB = rep.nAdd >= 2 && rep.nDel >= 1 && noteOK2;   % nAdd 累计各节（块+线）：C1/SumIn
  okC = rC.diff == 0;
  fprintf('\n=== %s ===\n', merge(okA && okB && okC, 'ROUNDTRIP PASS', 'ROUNDTRIP FAIL'));
end

function s = merge(c, a, b), if c, s = a; else, s = b; end, end
