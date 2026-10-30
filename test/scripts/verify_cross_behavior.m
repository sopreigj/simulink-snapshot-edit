function verify_cross_behavior(step)
% 跨版本行为一致性：R2023b 原件 vs R2026a 由 R2023b 快照重建的模型，逐信号波形对比。
%
%  三步（各自独立 -batch 调用，串行执行）：
%    verify_cross_behavior('baseline')  在 R2023b 下仿真 models/ 全部原件，
%                                       按 verify_behavior.m 口径捕获 To Workspace
%                                       信号 → multiver/cross_behavior/baseline_R2023b.mat
%    verify_cross_behavior('rebuild')   在 R2026a 下：把 snapshots/ 全部快照复制到
%                                       cross_behavior/snap_work/（只用副本），run 副本
%                                       重建模型 → cross_behavior/models_r2026a/,
%                                       用与 baseline 完全相同的捕获逻辑仿真
%                                       → rebuilt_R2026a.mat
%    verify_cross_behavior('compare')   配对两 mat，逐信号算 max|diff|/max|a|，
%                                       按阈值1=1e-9+1e-6·max|a|（同版本保真）、
%                                       阈值2=1e-4·max|a|（工程）分类，写 REPORT.md，
%                                       stdout 打 XVERB_TOTAL 汇总行。
%
%  捕获口径与 verify_behavior.m 一致（ReturnWorkspaceOutputs='on'，simout 优先、
%  base workspace 兜底）；StopTime 同样取 0.05。
%  所有产物只落 test/scripts/multiver/cross_behavior/（已 gitignore），绝不碰
%  models/ 与 snapshots/；仿真前用 Simulink.fileGenControl 把缓存/代码生成
%  目录指到 cross_behavior 内部，隔离 slprj。
here = fileparts(mfilename('fullpath'));
R = here; while ~exist(fullfile(R,'src','snp_export.m'),'file') && ~strcmp(R,fileparts(R)), R = fileparts(R); end
cb = fullfile(here, 'multiver', 'cross_behavior');
if ~isfolder(cb), mkdir(cb); end

mdls = collectModels(R);

switch step
  case 'baseline'
    run_baseline(R, cb, mdls);
  case 'rebuild'
    run_rebuild(R, cb, mdls);
  case 'compare'
    run_compare(cb, mdls);
  otherwise
    error('未知步骤 %s（用 baseline / rebuild / compare）', step);
end
end

% ==================== 第一步：R2023b 原件基线 ====================
function run_baseline(R, cb, mdls)
workDir = fullfile(cb, 'work_r2023b');
if ~isfolder(workDir), mkdir(workDir); end
isolate_filegen(workDir);
env = collect_env();
fprintf('XVERB_BASELINE release=%s\n', env.release);

res = empty_res();
for i = 1:numel(mdls)
  nm = mdls{i};
  entry = struct('model', nm, 'vars', {{}}, 'sig', {{}}, 'err', '');
  try
    try, close_system(nm, 0); catch, end
    load_system(fullfile(R, 'test', 'models', [nm '.slx']));
    vars = tw_vars(nm);
    set_param(nm, 'StopTime', '0.05', 'ReturnWorkspaceOutputs', 'on');
    out = sim(nm);                       % sim 内含编译
    entry.vars = vars;
    entry.sig = grab_signals(out, vars);
    try, close_system(nm, 0); catch, end
    fprintf('  BASELINE %-18s OK (%d 信号)\n', nm, numel(vars));
  catch ME
    entry.err = ME.message;
    fprintf('  BASELINE %-18s ERR: %s\n', nm, ME.message(1:min(140, end)));
    try, close_system(nm, 0); catch, end
  end
  res(end+1) = entry; %#ok<AGROW>
end
save(fullfile(cb, 'baseline_R2023b.mat'), 'res', 'env', '-v7.3');
fprintf('XVERB_BASELINE_DONE %s\n', fullfile(cb, 'baseline_R2023b.mat'));
end

% ==================== 第二步：R2026a 快照重建 ====================
function run_rebuild(R, cb, mdls)
% 快照只认副本：复制到 snap_work/ 后 run，产物模型落到
% <snap_work>/../models（快照尾部路径硬编码），再移入 models_r2026a/。
setenv('SNP_ALLOW_UNTESTED', '1');   % 与 verify_cross_version 同款放行方式
snapWork = fullfile(cb, 'snap_work');
if isfolder(snapWork), rmdir(snapWork, 's'); end
mkdir(snapWork);
% 库快照的 head 以 fileparts(mfilename)+相对找库（..\lib\blocks），
% snap_work 的上一级要有 lib\blocks 副本——复制整个库目录到 cb/，
% 快照只接触副本（工作树可能被另一会话改动）。
libDst = fullfile(cb, 'lib', 'blocks');
if ~isfolder(fileparts(libDst)), mkdir(fileparts(libDst)); end
copyfile(fullfile(R, 'test', 'lib', 'blocks', '*.slx'), libDst);
modelsOut = fullfile(cb, 'models_r2026a');
if isfolder(modelsOut), rmdir(modelsOut, 's'); end
mkdir(modelsOut);
workDir = fullfile(cb, 'work_r2026a');
if ~isfolder(workDir), mkdir(workDir); end
isolate_filegen(workDir);
env = collect_env();
fprintf('XVERB_REBUILD release=%s\n', env.release);

% 复制快照副本（实验只认副本，工作树可能被另一会话改动）
for i = 1:numel(mdls)
  nm = mdls{i};
  copyfile(fullfile(R, 'test', 'snapshots', ['snapshot_' nm '.m']), ...
           fullfile(snapWork, ['snapshot_' nm '.m']));
end

res = empty_res();
for i = 1:numel(mdls)
  nm = mdls{i};
  entry = struct('model', nm, 'vars', {{}}, 'sig', {{}}, 'err', '');
  try
    try, close_system(nm, 0); catch, end
    cwd = pwd;
    try
      cd(snapWork);
      feval(['snapshot_' nm]);           % ← 基线版本快照在本版本 run
    catch ME
      cd(cwd);
      rethrow(ME);
    end
    cd(cwd);
    % 快照存到 <snapWork>/../models/<Name>.slx，移入 models_r2026a/
    rebuilt = fullfile(cb, 'models', [nm '.slx']);
    if ~isfile(rebuilt)
      error('快照 run 后没有产出模型 %s', nm);
    end
    movefile(rebuilt, fullfile(modelsOut, [nm '.slx']), 'f');
    load_system(fullfile(modelsOut, [nm '.slx']));
    vars = tw_vars(nm);
    set_param(nm, 'StopTime', '0.05', 'ReturnWorkspaceOutputs', 'on');
    out = sim(nm);
    entry.vars = vars;
    entry.sig = grab_signals(out, vars);
    try, close_system(nm, 0); catch, end
    fprintf('  REBUILD  %-18s OK (%d 信号)\n', nm, numel(vars));
  catch ME
    entry.err = ME.message;
    fprintf('  REBUILD  %-18s ERR: %s\n', nm, ME.message(1:min(140, end)));
    cd(cwd_safe());
    try, close_system(nm, 0); catch, end
  end
  res(end+1) = entry; %#ok<AGROW>
end
if isfolder(fullfile(cb, 'models')), rmdir(fullfile(cb, 'models'), 's'); end
save(fullfile(cb, 'rebuilt_R2026a.mat'), 'res', 'env', '-v7.3');
fprintf('XVERB_REBUILD_DONE %s\n', fullfile(cb, 'rebuilt_R2026a.mat'));
end

% ==================== 第三步：逐信号对比 ====================
function run_compare(cb, mdls)
A = load(fullfile(cb, 'baseline_R2023b.mat'));   % R2023b 原件
B = load(fullfile(cb, 'rebuilt_R2026a.mat'));    % R2026a 重建

rows = {};   % {model, var, maxDiff, scale, rel, thr1, thr2, tDiff, class, note}
trouble = {};
nId = 0; nDrift = 0; nDiv = 0; nUnd = 0;

for i = 1:numel(mdls)
  nm = mdls{i};
  ea = find_model(A.res, nm);
  eb = find_model(B.res, nm);
  if isempty(ea) || isempty(eb)
    rows(end+1,:) = {nm, '-', NaN, NaN, NaN, NaN, NaN, NaN, 'undecidable', '缺一侧数据'}; %#ok<AGROW>
    nUnd = nUnd + 1;
    continue;
  end
  if ~isempty(ea.err)
    % 原件侧仿真失败 → 该模型全部信号不可判定
    rows(end+1,:) = {nm, '-', NaN, NaN, NaN, NaN, NaN, NaN, 'undecidable', ...
      sprintf('原件仿真失败：%s', ea.err(1:min(90,end)))}; %#ok<AGROW>
    nUnd = nUnd + max(1, numel(ea.vars));
    trouble{end+1} = sprintf('%s baseline ERR: %s', nm, ea.err); %#ok<AGROW>
    continue;
  end
  if ~isempty(eb.err)
    rows(end+1,:) = {nm, '-', NaN, NaN, NaN, NaN, NaN, NaN, 'undecidable', ...
      sprintf('重建件仿真失败：%s', eb.err(1:min(90,end)))}; %#ok<AGROW>
    nUnd = nUnd + max(1, numel(ea.vars));
    trouble{end+1} = sprintf('%s rebuild ERR: %s', nm, eb.err); %#ok<AGROW>
    continue;
  end
  for k = 1:numel(ea.vars)
    v = ea.vars{k};
    kb = find(strcmp(eb.vars, v), 1);
    if isempty(kb)
      rows(end+1,:) = {nm, v, NaN, NaN, NaN, NaN, NaN, NaN, 'undecidable', '重建件缺该信号'}; %#ok<AGROW>
      nUnd = nUnd + 1; continue;
    end
    [cls, maxDiff, scale, rel, thr1, thr2, tDiff, note] = ...
      classify(ea.sig{k}, eb.sig{kb});
    rows(end+1,:) = {nm, v, maxDiff, scale, rel, thr1, thr2, tDiff, cls, note}; %#ok<AGROW>
    switch cls
      case 'identical',   nId = nId + 1;
      case 'numeric_drift', nDrift = nDrift + 1;
      case 'diverged',    nDiv = nDiv + 1;
      otherwise,          nUnd = nUnd + 1;
    end
  end
end

% ---- REPORT.md ----
fid = fopen(fullfile(cb, 'REPORT.md'), 'w');
fprintf(fid, '# 跨版本行为一致性对比（R2023b 原件 vs R2026a 快照重建）\n\n');
fprintf(fid, '- 基线：R2023b 下 `models/` 8 个原件，StopTime=0.05（与 verify_behavior 同口径）。\n');
fprintf(fid, '- 被试：R2023b 导出的 8 份快照副本在 **R2026a** 下 run 重建（`snap_work/` 副本 → `models_r2026a/`）。\n');
fprintf(fid, '- 判据：每个 To Workspace 信号比较 max|diff| 与 max|a|。\n');
fprintf(fid, '  阈值1 = 1e-9 + 1e-6·max|a|（同版本保真阈值，跨版本预期更松）；\n');
fprintf(fid, '  阈值2 = 1e-4·max|a|（工程阈值）。分类：identical / numeric_drift / diverged / undecidable。\n\n');
fprintf(fid, '## 环境信息\n\n');
fprintf(fid, '### R2023b（基线侧）\n\n```\n');
fprintf(fid, 'release=%s\nversion=%s\n', A.env.release, A.env.version);
if isfield(A.env, 'simulink'),  fprintf(fid, 'simulink=%s\n', A.env.simulink); end
if isfield(A.env, 'stateflow'), fprintf(fid, 'stateflow=%s\n', A.env.stateflow); end
fprintf(fid, '```\n\n### R2026a（重建侧）\n\n```\n');
fprintf(fid, 'release=%s\nversion=%s\n', B.env.release, B.env.version);
if isfield(B.env, 'simulink'),  fprintf(fid, 'simulink=%s\n', B.env.simulink); end
if isfield(B.env, 'stateflow'), fprintf(fid, 'stateflow=%s\n', B.env.stateflow); end
fprintf(fid, '```\n\n');
fprintf(fid, '## 汇总\n\n');
fprintf(fid, '| 分类 | 信号数 |\n|---|---|\n');
fprintf(fid, '| identical | %d |\n| numeric_drift | %d |\n| diverged | %d |\n| undecidable | %d |\n\n', ...
  nId, nDrift, nDiv, nUnd);
fprintf(fid, '## 逐信号结果\n\n');
fprintf(fid, '| 模型 | 信号 | max|diff| | max|a| | 相对误差 | 阈值1 | 阈值2 | t差 | 分类 | 备注 |\n');
fprintf(fid, '|---|---|---|---|---|---|---|---|---|---|\n');
for r = 1:size(rows,1)
  fprintf(fid, '| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n', ...
    rows{r,1}, rows{r,2}, fmtnum(rows{r,3}), fmtnum(rows{r,4}), fmtnum(rows{r,5}), ...
    fmtnum(rows{r,6}), fmtnum(rows{r,7}), fmtnum(rows{r,8}), rows{r,9}, rows{r,10});
end
fprintf(fid, '\n## Troubleshooting\n\n');
if isempty(trouble)
  fprintf(fid, '（无失败。）\n');
else
  for t = 1:numel(trouble), fprintf(fid, '- %s\n', trouble{t}); end
end
fclose(fid);

fprintf('XVERB_TOTAL identical=%d drift=%d diverged=%d undecidable=%d\n', nId, nDrift, nDiv, nUnd);
fprintf('XVERB_REPORT %s\n', fullfile(cb, 'REPORT.md'));
end

% ==================== 子函数 ====================
function mdls = collectModels(R)
% 枚举 models/ 下的模型名（去 .slx 扩展）——清单不再硬编码。
d = dir(fullfile(R, 'test', 'models', '*.slx'));
mdls = cell(1, numel(d));
for k = 1:numel(d)
  mdls{k} = extractBefore(d(k).name, '.slx');
end
end

function res = empty_res()
res = struct('model', {}, 'vars', {}, 'sig', {}, 'err', {});
end

function e = find_model(res, nm)
idx = find(strcmp({res.model}, nm), 1);
if isempty(idx), e = []; else, e = res(idx); end
end

function vars = tw_vars(nm)
% 与 verify_behavior.m 相同的信号枚举：顶层 To Workspace 块的 VariableName
tws = find_system(nm, 'SearchDepth', 1, 'BlockType', 'ToWorkspace');
vars = cell(1, numel(tws));
for k = 1:numel(tws)
  vars{k} = get_param(tws{k}, 'VariableName');
end
end

function sigs = grab_signals(simOut, vars)
% 与 verify_behavior 同口径：ReturnWorkspaceOutputs='on' 时信号收在 simout；
% T11：simout 优先，base workspace 兜底。
sigs = cell(1, numel(vars));
for k = 1:numel(vars)
  v = [];
  try, v = simOut.(vars{k}); catch, end
  if isempty(v)
    try, v = evalin('base', vars{k}); catch, end
  end
  sigs{k} = v;
end
end

function [cls, maxDiff, scale, rel, thr1, thr2, tDiff, note] = classify(a, b)
cls = 'undecidable'; maxDiff = NaN; scale = NaN; rel = NaN;
thr1 = NaN; thr2 = NaN; tDiff = NaN; note = '';
if isempty(a) || isempty(b)
  note = '缺数据'; return;
end
if ~isa(a, 'timeseries') || ~isa(b, 'timeseries')
  note = '非 timeseries，口径不可比'; return;
end
da = squeeze(a.Data); db = squeeze(b.Data);
if ~isequal(size(da), size(db))
  note = sprintf('尺寸不同 %s vs %s', mat2str(size(da)), mat2str(size(db)));
  cls = 'diverged'; return;
end
fa = da(isfinite(da)); fb = db(isfinite(db));
if isempty(fa)
  note = '原件无有效样本'; return;
end
d = abs(fa - fb);
scale = max(abs(fa));
if isempty(scale) || scale == 0, scale = 1; end
maxDiff = max(d);
rel = maxDiff / scale;
thr1 = 1e-9 + 1e-6 * scale;
thr2 = 1e-4 * scale;
if ~isempty(a.Time) && ~isempty(b.Time) && numel(a.Time) == numel(b.Time)
  tDiff = max(abs(a.Time(:) - b.Time(:)));
else
  tDiff = NaN;
end
if maxDiff <= thr1 && (isnan(tDiff) || tDiff <= 1e-9)
  cls = 'identical';
elseif maxDiff <= thr2
  cls = 'numeric_drift';
  if isnan(tDiff), note = '时间向量不可比'; end
else
  cls = 'diverged';
end
end

function s = fmtnum(x)
if isnan(x), s = '-'; else, s = sprintf('%.3e', x); end
end

function env = collect_env()
env = struct();
env.release = version('-release');
env.version = strtrim(version);
v = ver('simulink');
if ~isempty(v), env.simulink = sprintf('%s (%s)', v.Version, v.Release); end
v = ver('stateflow');
if ~isempty(v), env.stateflow = sprintf('%s (%s)', v.Version, v.Release); end
end

function isolate_filegen(workDir)
% 把 Simulink 缓存/代码生成目录指到 cross_behavior 内部，slprj 不落在仓库别处
try
  Simulink.fileGenControl('set', 'CacheFolder', workDir, ...
    'CodeGenFolder', workDir, 'createDir', true);
catch
end
end

function d = cwd_safe()
try, d = pwd; catch, d = tempdir; end
end

