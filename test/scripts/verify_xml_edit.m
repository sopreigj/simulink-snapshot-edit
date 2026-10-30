function verify_xml_edit()
%  XML 原地编辑（改 .slx 内部 XML → 重打包）验证
%
%  验证的是什么：snp_xml_edit 改一个块参数后产出的新 .slx，
%    ① Simulink 能正常打开，且参数读回就是新值；
%    ② 该模型重新导出（snp_export）后，与仓库已提交快照的文本差异**只**在被改
%       的那一个参数上——也就是"改 XML"与"改 M 快照"在语义上等价；
%    ③ 原件与编辑件都能仿真，且至少一个信号发生变化（否则说明编辑没起作用）。
%
%  对照组：原件重新导出后与仓库快照必须**零差异**。没有这条对照，就分不清
%    差异是编辑造成的，还是导出本身有噪声（教训：产物必须能与当前
%    生成器输出逐字节比对）。
%
%  输出：末行 XML_EDIT_TOTAL ok=<n>/<m>；详细报告 scratch/xml_edit_tmp/report.txt
R = fileparts(fileparts(mfilename('fullpath'))); while ~exist(fullfile(R,'src','snp_export.m'),'file') && ~strcmp(R,fileparts(R)), R = fileparts(R); end
addpath(fullfile(R, 'src'));

outRoot = fullfile(R, 'test', 'scratch', 'xml_edit_tmp');
if isfolder(outRoot), rmdir(outRoot, 's'); end
mkdir(outRoot);
fid = fopen(fullfile(outRoot, 'report.txt'), 'w', 'n', 'UTF-8');
logf = @(varargin) fprintf(fid, varargin{:});

% 案例：{模型, 块路径('' = 运行时发现), 参数, 新值, 说明}
cases = { ...
  'ToyBasic',  'g1', 'Gain', '1.234567', '顶层 Gain'; ...
  'ToyLibRef', 'tl', 'UpperLimit', '2.5', '库实例的实例级参数（限幅上限）'; ...
  'ToyLibRef', 'tm', 'Kp', '7.7', 'mask 实例的实例级参数' };

tolAbs = 1e-9;
tolRel = 1e-6;
nOk = 0; nTot = 0; nObservable = 0;

for c = 1:size(cases, 1)
  model = cases{c, 1};
  blkPath = cases{c, 2};
  pname = cases{c, 3};
  newVal = cases{c, 4};
  logf('\n===== 案例 %d：%s / %s . %s -> %s（%s）=====\n', c, model, ...
    blkPath, pname, newVal, cases{c, 5});
  nTot = nTot + 1;

  origPath = fullfile(R, 'test', 'models', [model '.slx']);
  caseDir = fullfile(outRoot, sprintf('case%d', c));
  modelDir = fullfile(caseDir, 'models');
  snapCtrl = fullfile(caseDir, 'snaps_ctrl');
  snapEdit = fullfile(caseDir, 'snaps_edit');
  mkdir(modelDir); mkdir(snapCtrl); mkdir(snapEdit);
  editedPath = fullfile(modelDir, [model '.slx']);

  % ---------- 运行时发现块路径（案例 3） ----------
  if isempty(blkPath)
    try
      try, close_system(model, 0); catch, end
      load_system(origPath);
      gs = find_system(model, 'SearchDepth', 1, 'BlockType', 'Gain');
      close_model(model);
      if ~isempty(gs)
        rel = strsplit(gs{1}, '/');
        blkPath = rel{end};
      end
    catch ME
      logf('  发现块失败: %s\n', ME.message(1:min(140, end)));
    end
    if isempty(blkPath)
      logf('  SKIP：未发现可用的 Gain 块\n');
      nTot = nTot - 1;
      continue;
    end
    logf('  运行时发现块路径：%s\n', blkPath);
  end

  % ---------- 编辑 ----------
  try
    info = snp_xml_edit(origPath, editedPath, {{blkPath, pname, newVal}});
  catch ME
    logf('  FAIL：snp_xml_edit 抛错: %s\n', ME.message(1:min(200, end)));
    continue;
  end
  if isempty(info.applied)
    logf('  FAIL：编辑未生效\n');
    for q = 1:size(info.skipped, 1)
      logf('    skipped: %s . %s : %s\n', info.skipped{q, 1}, info.skipped{q, 2}, info.skipped{q, 3});
    end
    continue;
  end
  logf('  编辑：[%s] %s : %s\n', info.applied{1, 1}, info.applied{1, 2}, ...
    info.applied{1, 3});

  % ---------- 判据1：回读 ----------
  ok1 = false;
  try
    close_model(model);
    load_system(editedPath);
    got = get_param([model '/' blkPath], pname);
    ok1 = strcmp(got, newVal);
    logf('  判据1 回读：get_param=%s 期望=%s  %s\n', got, newVal, tern(ok1, 'OK', 'FAIL'));
  catch ME
    logf('  判据1 FAIL：编辑件打不开或读不到: %s\n', ME.message(1:min(200, end)));
  end
  close_model(model);
  if ~ok1, continue; end

  % ---------- 对照组：原件重新导出应与仓库快照零差异 ----------
  ctrlDiff = [];
  try
    close_model(model);
    load_system(origPath);
    snp_export(model, exportOpts(R, snapCtrl));
    close_model(model);
    ctrlDiff = diffLines(fileread(fullfile(R, 'test', 'snapshots', ['snapshot_' model '.m'])), ...
      fileread(fullfile(snapCtrl, ['snapshot_' model '.m'])));
    logf('  对照组：原件重导出与仓库快照差异行数 = %d %s\n', numel(ctrlDiff), ...
      tern(isempty(ctrlDiff), 'OK', 'FAIL(导出有噪声)'));
  catch ME
    logf('  对照组 FAIL: %s\n', ME.message(1:min(200, end)));
  end
  if ~isempty(ctrlDiff)
    logf('    差异行：%s\n', mat2str(ctrlDiff(1:min(8, end))));
    continue;
  end

  % ---------- 判据2：编辑件重导出，差异只含被改参数 ----------
  ok2 = false;
  try
    close_model(model);
    load_system(editedPath);
    snp_export(model, exportOpts(R, snapEdit));
    close_model(model);
    editDiff = diffLines(fileread(fullfile(R, 'test', 'snapshots', ['snapshot_' model '.m'])), ...
      fileread(fullfile(snapEdit, ['snapshot_' model '.m'])));
    if isempty(editDiff)
      logf('  判据2 FAIL：编辑件重导出与原件无差异（编辑没落到快照里）\n');
    else
      newTxt = fileread(fullfile(snapEdit, ['snapshot_' model '.m']));
      lines = splitlines(newTxt);
      bad = editDiff(~arrayfun(@(k) contains(lines{k}, newVal), editDiff));
      ok2 = isempty(bad);
      logf('  判据2 结构等价：差异行数=%d，全部含新值=%s\n', numel(editDiff), tern(ok2, 'OK', 'FAIL'));
      for k = 1:numel(editDiff)
        logf('    L%d: %s\n', editDiff(k), shorten(lines{editDiff(k)}, 160));
      end
      if ~isempty(bad)
        logf('    以下差异行不含新值：%s\n', mat2str(bad));
      end
    end
  catch ME
    logf('  判据2 FAIL: %s\n', ME.message(1:min(200, end)));
  end
  if ~ok2, continue; end

  % ---------- 判据3：行为 ----------
  %  单案例要求：原件与编辑件**都仿真成功**（编辑件没被改坏）。
  %  「信号有变化」不作为单案例要求——改一个不进入被观测路径的参数（如参考转速），
  %  信号本就不变，那是正确结果。变化的可观测性提升为**验证集级**要求：
  %  整轮里至少要有一个案例观测到信号变化，否则说明判据空转（见汇总行 observable）。
  ok3 = false;
  nChanged = 0; nSame = 0;
  try
    sigA = runSim(origPath, model);
    sigB = runSim(editedPath, model);
    vn = fieldnames(sigA);
    for k = 1:numel(vn)
      a = sigA.(vn{k}); b = sigB.(vn{k});
      if isempty(a) || isempty(b)
        logf('    %-10s : 不可判定\n', vn{k}); continue;
      end
      da = squeeze(a.Data); db = squeeze(b.Data);
      if size(da) ~= size(db)
        logf('    %-10s : 尺寸不同（异常）\n', vn{k}); continue;
      end
      fa = da(isfinite(da)); fb = db(isfinite(db));
      if isempty(fa) || isempty(fb)
        logf('    %-10s : 不可判定\n', vn{k}); continue;
      end
      d = abs(fa - fb);
      scale = max(abs(fa)); if isempty(scale) || scale == 0, scale = 1; end
      md = max(d);
      if md <= tolAbs + tolRel * scale
        nSame = nSame + 1;
        logf('    %-10s : IDENTICAL max|diff|=%.3e\n', vn{k}, md);
      else
        nChanged = nChanged + 1;
        logf('    %-10s : CHANGED   max|diff|=%.3e 量级=%.3e\n', vn{k}, md, scale);
      end
    end
    ok3 = true;
    if nChanged > 0
      nObservable = nObservable + 1;
    end
    logf('  判据3 行为：两边仿真 OK，变化信号 %d 个 / 不变 %d 个 %s\n', nChanged, nSame, ...
      tern(nChanged > 0, '（本例可观测到编辑效果）', '（本例改动不在被观测路径上，信号不变属预期）'));
  catch ME
    logf('  判据3 FAIL: %s\n', ME.message(1:min(200, end)));
  end

  if ok1 && ok2 && ok3
    nOk = nOk + 1;
    logf('  >>> 案例 %d 通过\n', c);
  end
end

fprintf('XML_EDIT_TOTAL ok=%d/%d observable=%d\n', nOk, nTot, nObservable);
logf('\n===== 汇总：ok=%d/%d observable=%d =====\n', nOk, nTot, nObservable);
if nObservable == 0
  logf('警告：整轮没有观测到任何信号变化——判据可能空转（本轮不判为通过）\n');
end
fclose(fid);
end

% ---------------------------------------------------------------------------
function o = exportOpts(R, outDir)
o = struct();
o.OutDir = outDir; o.LibDir = fullfile(R, 'test', 'lib', 'blocks');
o.AliasMap = cell(0, 2); o.ExtraHeader = {};
o.LibRel = '..\lib\blocks'; o.SaveRel = '..\models';
o.InlineMasks = true;
end

function idx = diffLines(a, b)
% 逐行比较两段文本，返回不同的行号（行数不同则整体报差异）
la = splitlines(a); lb = splitlines(b);
if numel(la) ~= numel(lb)
  idx = 1:max(numel(la), numel(lb));
  return;
end
idx = find(~strcmp(la, lb));
end

function lines = splitlines(txt)
txt = strrep(txt, sprintf('\r\n'), sprintf('\n'));
txt = strrep(txt, sprintf('\r'), sprintf('\n'));
lines = strsplit(txt, sprintf('\n'));
end

function s = shorten(s, n)
if numel(s) > n, s = [s(1:n) '...']; end
end

function s = tern(c, a, b)
if c, s = a; else, s = b; end
end

function close_model(mdl)
try, close_system(mdl, 0); catch, end
end

function sig = runSim(slxPath, mdlName)
sig = struct();
close_model(mdlName);
load_system(slxPath);
tws = find_system(mdlName, 'SearchDepth', 1, 'BlockType', 'ToWorkspace');
vars = cell(1, numel(tws));
for k = 1:numel(tws), vars{k} = get_param(tws{k}, 'VariableName'); end
set_param(mdlName, 'StopTime', '0.05', 'ReturnWorkspaceOutputs', 'on');
o = sim(mdlName);
for k = 1:numel(vars)
  v = [];
  try, v = o.(vars{k}); catch, end
  sig.(vars{k}) = v;
end
close_model(mdlName);
end

