function verify_behavior()
% 行为等价验证：原模型 vs 快照重建模型，逐信号数值对比
%
%  为什么需要它：结构等价（导出→重建→再导出→文本 diff=0）只证明"重建出来的
%  模型和原模型长得一样"，不证明"跑起来波形一样"。本脚本补上这一层。
%
%  判据：每个 To Workspace 信号上
%      max|a - b| <= tolAbs + tolRel * max|a|
%  （tolAbs 兜住"原件本身几乎为 0"的信号，tolRel 兜住量级大的信号）
%
%  不可判定的情况照实记录，不算通过：
%    · 原模型该信号无有限样本（NaN/Inf 或空）→ 记"原件无有效输出"
%    · 重建模型仿真报错 → 记 ERR
R = fileparts(fileparts(mfilename('fullpath'))); while ~exist(fullfile(R,'src','snp_export.m'),'file') && ~strcmp(R,fileparts(R)), R = fileparts(R); end
addpath(fullfile(R, 'src'));

% 模型清单从 test/models/ 枚举（无 To Workspace 输出的模型记 SKIP，不算失败）
d = dir(fullfile(R, 'test', 'models', '*.slx'));
mdls = {d.name};
mdls = cellfun(@(s) s(1:end-4), mdls, 'UniformOutput', false);
stopTime = '0.05';
tolAbs = 1e-9;
tolRel = 1e-6;
tmpDir = fullfile(R, 'test', 'scratch', 'behavior');
if ~isfolder(tmpDir), mkdir(tmpDir); end
snapTmp = fullfile(tmpDir, 'snaps');
modelTmp = fullfile(tmpDir, 'models');
if ~isfolder(snapTmp), mkdir(snapTmp); end
if ~isfolder(modelTmp), mkdir(modelTmp); end
logPath = fullfile(R, 'test', 'scratch', 'dbg_behavior.txt');
if ~isfolder(fileparts(logPath)), mkdir(fileparts(logPath)); end
fid = fopen(logPath, 'w');

nPass = 0; nFail = 0; nSkip = 0;
for i = 1:numel(mdls)
  nm = mdls{i};
  fprintf(fid, '\n===== %s =====\n', nm);
  try, close_system(nm, 0); catch, end
  % ---------- 1. 原模型：仿真并取 To Workspace 信号 ----------
  vars = {}; sigA = {};
  origOk = false;
  try
    load_system(fullfile(R, 'test', 'models', [nm '.slx']));
    tws = find_system(nm, 'SearchDepth', 1, 'BlockType', 'ToWorkspace');
    for k = 1:numel(tws)
      vars{end+1} = get_param(tws{k}, 'VariableName'); %#ok<AGROW>
    end
    set_param(nm, 'StopTime', stopTime, 'ReturnWorkspaceOutputs', 'on');
    outA = sim(nm);
    origOk = true;
    sigA = grab_signals(outA, vars);
    close_system(nm, 0);
    fprintf(fid, '  原模型：仿真 OK，To Workspace %d 个\n', numel(vars));
  catch ME
    fprintf(fid, '  原模型自身仿真失败 → 行为不可判定（非重建问题）：%s\n', ME.message(1:min(140,end)));
    nSkip = nSkip + numel(vars);
    try, close_system(nm, 0); catch, end
  end
  if ~origOk, continue; end
  % ---------- 2. 重建：导出 → 跑快照 → 仿真重建模型 ----------
  sigB = {};
  % 快照导出到临时目录（不碰仓库里已提交的 test/snapshots/）。路径用相对形式：
  % 快照目录 = <项目>/test/scratch/behavior/snaps → LibRel '..\..\test\lib\blocks'、
  % SaveRel '..\models' 都相对该目录解析（绝对路径不能套 fullfile）。
  try
    o = struct(); o.OutDir = snapTmp; o.LibDir = fullfile(R, 'test', 'lib', 'blocks');
    o.AliasMap = cell(0, 2); o.ExtraHeader = {}; o.LibRel = '..\..\test\lib\blocks';
    o.InlineMasks = true; o.SaveRel = '..\models';
    load_system(fullfile(R, 'test', 'models', [nm '.slx']));
    snp_export(nm, o);
    close_system(nm, 0);
    cd(snapTmp);
    feval(['snapshot_' nm]);
    cd(R);
    % 快照脚本末尾保存并关闭了模型——重建件已落盘到 modelTmp，
    % 必须重新加载才能仿真（否则 set_param 报"对象名称无效"）
    load_system(fullfile(modelTmp, [nm '.slx']));
    set_param(nm, 'StopTime', stopTime, 'ReturnWorkspaceOutputs', 'on');
    outB = sim(nm);
    sigB = grab_signals(outB, vars);
    close_system(nm, 0);
    fprintf(fid, '  重建模型：仿真 OK\n');
  catch ME
    fprintf(fid, '  重建模型 ERR: %s\n', ME.message(1:min(160,end)));
    nFail = nFail + numel(vars);
    for k = 1:numel(vars), fprintf(fid, '    %-10s : 重建失败\n', vars{k}); end
    continue;
  end
  % ---------- 3. 逐信号比较 ----------
  for k = 1:numel(vars)
    a = sigA{k}; b = sigB{k};
    if isempty(a) || isempty(b)
      fprintf(fid, '    %-10s : 不可判定（缺数据）\n', vars{k}); nSkip = nSkip + 1; continue;
    end
    da = squeeze(a.Data); db = squeeze(b.Data);
    if size(da) ~= size(db)
      fprintf(fid, '    %-10s : DIFF 尺寸不同 %s vs %s\n', vars{k}, ...
        mat2str(size(da)), mat2str(size(db))); nFail = nFail + 1; continue;
    end
    fa = da(isfinite(da)); fb = db(isfinite(db));
    if isempty(fa)
      fprintf(fid, '    %-10s : 不可判定（原件无有效样本）\n', vars{k}); nSkip = nSkip + 1; continue;
    end
    d = abs(fa - fb);
    scale = max(abs(fa));
    if isempty(scale) || scale == 0, scale = 1; end
    maxDiff = max(d);
    if ~isempty(a.Time) && ~isempty(b.Time) && numel(a.Time) == numel(b.Time)
      tDiff = max(abs(a.Time(:) - b.Time(:)));
    else
      tDiff = NaN;
    end
    ok = (maxDiff <= tolAbs + tolRel * scale) && (isnan(tDiff) || tDiff <= 1e-9);
    if ok
      fprintf(fid, '    %-10s : IDENTICAL  max|diff|=%.3e  量级=%.3e  t差=%.3e\n', ...
        vars{k}, maxDiff, scale, tDiff);
      nPass = nPass + 1;
    else
      fprintf(fid, '    %-10s : DIFF       max|diff|=%.3e  量级=%.3e  t差=%.3e\n', ...
        vars{k}, maxDiff, scale, tDiff);
      nFail = nFail + 1;
    end
  end
end
fprintf(fid, '\n===== 行为等价汇总：PASS=%d FAIL=%d 不可判定=%d =====\n', nPass, nFail, nSkip);
fclose(fid);
fprintf('BEHAVIOR_DONE pass=%d fail=%d skip=%d\n', nPass, nFail, nSkip);
end

function sigs = grab_signals(simOut, vars)
% 从 Simulink.SimulationOutput 取 To Workspace 信号（timeseries）。
% ReturnWorkspaceOutputs='on' 时 To Workspace 变量收在 sim 返回值里，
% 不写 base workspace（实测：base 里根本没有 log_* 变量）。
sigs = cell(1, numel(vars));
for k = 1:numel(vars)
  v = [];
  try, v = simOut.(vars{k}); catch, end
  sigs{k} = v;
end
end

