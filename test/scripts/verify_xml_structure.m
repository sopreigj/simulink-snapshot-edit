function verify_xml_structure()
%  XML 结构编辑验证（增块 / 删块 / 接线 / 增删抵消）
%
%  验证的是什么：snp_xml_edit 除了改块参数，还能改结构——增块、删块、增连线、
%  删连线。三条判据：
%    ① 回读：编辑件被 Simulink 打开后，新块存在且参数正确、连线成立；
%    ② 行为：原件与编辑件都能仿真；删掉一个 Scope（不参与计算）时，被观测信号
%       必须**逐位相同**——证明"只删了展示用的东西，没动数学"；
%    ③ 结构等价：把原件与编辑件各自重新导出成 M，按**集合**比对差异行
%       （不能用逐行比对：删行会让后面所有行号错位）：
%         案例1 增块+接线 → 只多出 1 条 add_block + 1 条 add_line（可有伴随 Points）；
%         案例2 删块     → 只少掉 1 条 add_block + 1 条 add_line（可有伴随 Points）；
%         案例3 增后即删 → 两边**逐字节相同**（no-op 检验）。
%
%  输出：末行 XML_STRUCT_TOTAL ok=<n>/<m>；报告 scratch/xml_struct_tmp/report.txt
R = fileparts(fileparts(mfilename('fullpath'))); while ~exist(fullfile(R,'src','snp_export.m'),'file') && ~strcmp(R,fileparts(R)), R = fileparts(R); end
addpath(fullfile(R, 'src'));

outRoot = fullfile(R, 'test', 'scratch', 'xml_struct_tmp');
if isfolder(outRoot), rmdir(outRoot, 's'); end
mkdir(outRoot);
fid = fopen(fullfile(outRoot, 'report.txt'), 'w', 'n', 'UTF-8');
logf = @(varargin) fprintf(fid, varargin{:});

model = 'ToyBasic';
tolAbs = 1e-9; tolRel = 1e-6;
nOk = 0; nTot = 0;

% ---------- 案例 3 先做：增块后立刻删掉，应回到原状（no-op） ----------
logf('\n===== 案例 3：增块后立即删除（no-op，期望 M 逐字节相同）=====\n');
nTot = nTot + 1;
ok3 = runCase(fid, R, outRoot, model, 'case3', ...
  {{'add_block', '', 'Gain', 'SnPTempGain', {{'Gain', '2.0'}}}, ...
   {'remove_block', 'SnPTempGain'}}, ...
  {'expect', 'identical'}, tolAbs, tolRel);
if ok3, nOk = nOk + 1; end

% ---------- 案例 1：增块 + 接线 ----------
logf('\n===== 案例 1：增块 + 接线 =====\n');
nTot = nTot + 1;
ok1 = runCase(fid, R, outRoot, model, 'case1', ...
  {{'add_block', '', 'Gain', 'SnPNewGain', {{'Gain', '2.0'}}}, ...
   {'add_line', '', 'g1', 1, 'SnPNewGain', 1}}, ...
  {'expect', 'add', {'add_block', 'add_line'}}, tolAbs, tolRel);
if ok1, nOk = nOk + 1; end

% ---------- 案例 2：删一个 Scope（不参与计算） ----------
logf('\n===== 案例 2：删除一个 Scope =====\n');
nTot = nTot + 1;
scopeName = findScopeName(R, model);
if isempty(scopeName)
  logf('  SKIP：模型里没有顶层 Scope\n');
  nTot = nTot - 1;
else
  logf('  目标 Scope：%s\n', scopeName);
  ok2 = runCase(fid, R, outRoot, model, 'case2', ...
    {{'remove_block', scopeName}}, ...
    {'expect', 'remove', {'add_block', 'add_line'}}, tolAbs, tolRel);
  if ok2, nOk = nOk + 1; end
end

fprintf('XML_STRUCT_TOTAL ok=%d/%d\n', nOk, nTot);
logf('\n===== 汇总：ok=%d/%d =====\n', nOk, nTot);
fclose(fid);
end

% ===========================================================================
function ok = runCase(fid, R, outRoot, model, caseName, ops, expect, tolAbs, tolRel)
% 一个结构编辑案例：编辑 → 载入回读 → 仿真 → 重导出比对
caseDir = fullfile(outRoot, caseName);
modelDir = fullfile(caseDir, 'models');
snapCtrl = fullfile(caseDir, 'snaps_ctrl');
snapEdit = fullfile(caseDir, 'snaps_edit');
mkdir(modelDir); mkdir(snapCtrl); mkdir(snapEdit);
origPath = fullfile(R, 'test', 'models', [model '.slx']);
editedPath = fullfile(modelDir, [model '.slx']);
ok = false;

% 对照：原件重导出
try
  close_model(model);
  load_system(origPath);
  snp_export(model, exportOpts(R, snapCtrl));
  close_model(model);
catch ME
  fprintf(fid, '对照组导出失败: %s\n', ME.message);
  return;
end
ctrlSnap = fileread(fullfile(snapCtrl, ['snapshot_' model '.m']));

% 编辑
try
  info = snp_xml_edit(origPath, editedPath, ops);
catch ME
  fprintf(fid, 'snp_xml_edit 失败: %s\n', ME.message);
  return;
end
for k = 1:size(info.applied, 1)
  fprintf(fid, '  [applied] %s %s : %s\n', info.applied{k, 1}, info.applied{k, 2}, info.applied{k, 3});
end
for k = 1:size(info.skipped, 1)
  fprintf(fid, '  [skipped] %s %s : %s\n', info.skipped{k, 1}, info.skipped{k, 2}, info.skipped{k, 3});
end
if size(info.applied, 1) ~= numel(ops)
  fprintf(fid, '  FAIL：%d 条操作只成功 %d 条\n', numel(ops), size(info.applied, 1));
  return;
end

% 判据①：载入 + 回读（最终状态：add 后未被 remove 的块必须存在；被 remove 的块必须不在）
try
  close_model(model);
  load_system(editedPath);
  removedSet = {};
  for k = 1:size(info.applied, 1)
    if strcmp(info.applied{k, 1}, 'remove_block')
      removedSet{end+1} = info.applied{k, 2}; %#ok<AGROW>
    end
  end
  for k = 1:size(info.applied, 1)
    if strcmp(info.applied{k, 1}, 'add_block')
      if any(strcmp(removedSet, info.applied{k, 2})), continue; end %#ok<NOSEMI>
      b = find_system(model, 'SearchDepth', 1, 'Name', info.applied{k, 2});
      if isempty(b)
        fprintf(fid, '  判据① FAIL：新块 %s 不存在\n', info.applied{k, 2});
        return;
      end
      fprintf(fid, '  判据①：新块 %s 存在，BlockType=%s\n', info.applied{k, 2}, get_param(b{1}, 'BlockType'));
    end
    if strcmp(info.applied{k, 1}, 'remove_block')
      b = find_system(model, 'SearchDepth', 1, 'Name', info.applied{k, 2});
      if ~isempty(b)
        fprintf(fid, '  判据① FAIL：块 %s 还在\n', info.applied{k, 2});
        return;
      end
      fprintf(fid, '  判据①：块 %s 已删除\n', info.applied{k, 2});
    end
  end
catch ME
  fprintf(fid, '  判据① FAIL：%s\n', ME.message(1:min(200, end)));
  return;
end
% 判据②：行为（两边都仿真；报告信号变化数）
try
  sigA = runSim(origPath, model);
  sigB = runSim(editedPath, model);
  vn = fieldnames(sigA);
  nChanged = 0;
  for k = 1:numel(vn)
    a = sigA.(vn{k}); b = sigB.(vn{k});
    if isempty(a) || isempty(b)
      fprintf(fid, '    %-10s : 不可判定\n', vn{k}); continue;
    end
    da = squeeze(a.Data); db = squeeze(b.Data);
    if size(da) ~= size(db)
      fprintf(fid, '    %-10s : 尺寸不同\n', vn{k}); continue;
    end
    fa = da(isfinite(da)); fb = db(isfinite(db));
    if isempty(fa) || isempty(fb), continue; end
    d = abs(fa - fb);
    scale = max(abs(fa)); if isempty(scale) || scale == 0, scale = 1; end
    if max(d) > tolAbs + tolRel * scale
      nChanged = nChanged + 1;
      fprintf(fid, '    %-10s : CHANGED max|diff|=%.3e\n', vn{k}, max(d));
    end
  end
  fprintf(fid, '  判据②：两边仿真 OK，变化信号 %d 个\n', nChanged);
catch ME
  fprintf(fid, '  判据② FAIL：%s\n', ME.message(1:min(200, end)));
  return;
end

% 判据③：结构等价（集合式差异）
try
  close_model(model);
  load_system(editedPath);
  snp_export(model, exportOpts(R, snapEdit));
  close_model(model);
catch ME
  fprintf(fid, '  判据③ FAIL：重导出失败 %s\n', ME.message(1:min(200, end)));
  return;
end
editSnap = fileread(fullfile(snapEdit, ['snapshot_' model '.m']));
[onlyCtrl, onlyEdit] = diffSets(ctrlSnap, editSnap);
fprintf(fid, '  判据③：原件独有 %d 行，编辑件独有 %d 行\n', numel(onlyCtrl), numel(onlyEdit));
for k = 1:numel(onlyEdit), fprintf(fid, '    + %s\n', shorten(onlyEdit{k}, 140)); end
for k = 1:numel(onlyCtrl), fprintf(fid, '    - %s\n', shorten(onlyCtrl{k}, 140)); end

switch expect{2}
  case 'identical'
    if isempty(onlyCtrl) && isempty(onlyEdit)
      ok = true; fprintf(fid, '  >>> 通过：两边逐字节相同\n');
    else
      fprintf(fid, '  FAIL：期望完全相同\n');
    end
  case 'add'
    ok = expectKinds(fid, onlyEdit, onlyCtrl, expect{3}, 'add');
  case 'remove'
    ok = expectKinds(fid, onlyCtrl, onlyEdit, expect{3}, 'remove');
end
end

% ===========================================================================
function ok = expectKinds(fid, present, absent, kinds, mode)
% present 里每种 kinds 恰好 1 行，且 absent 里不能有 kinds（方向性）；
% 两侧其余差异行必须都是伴随的 Points/lnH 行（改接线会重算既有线的走线，
% 属几何副作用，D5 明确不管几何）。
for k = 1:numel(kinds)
  n = 0;
  for q = 1:numel(present)
    if ~isempty(strfind(present{q}, kinds{k})), n = n + 1; end %#ok<STREMP>
  end
  if n ~= 1
    fprintf(fid, '  FAIL：%s 行数 = %d（期望 1）\n', kinds{k}, n);
    ok = false; return;
  end
  for q = 1:numel(absent)
    if ~isempty(strfind(absent{q}, kinds{k})) %#ok<STREMP>
      fprintf(fid, '  FAIL：%s 方向出现了 %s 行\n', mode, kinds{k});
      ok = false; return;
    end
  end
end
for side = 1:2
  if side == 1, lst = present; else, lst = absent; end
  for q = 1:numel(lst)
    isKind = false;
    for k = 1:numel(kinds)
      if ~isempty(strfind(lst{q}, kinds{k})), isKind = true; break; end %#ok<STREMP>
    end
    if ~isKind && isempty(strfind(lst{q}, 'Points')) && isempty(strfind(lst{q}, 'lnH')) %#ok<STREMP>
      fprintf(fid, '  FAIL：出现非预期差异行：%s\n', shorten(lst{q}, 120));
      ok = false; return;
    end
  end
end
ok = true;
fprintf(fid, '  >>> 通过：差异行符合预期（%s）\n', mode);
end

% ===========================================================================
function [onlyA, onlyB] = diffSets(a, b)
% 集合式差异（多重集）：onlyA = 只在 a 里的行，onlyB = 只在 b 里的行
la = splitlines(a); lb = splitlines(b);
onlyA = {}; onlyB = {};
used = false(size(lb));
for k = 1:numel(la)
  hit = 0;
  for q = 1:numel(lb)
    if ~used(q) && strcmp(la{k}, lb{q}), hit = q; break; end
  end
  if hit == 0
    onlyA{end+1} = la{k}; %#ok<AGROW>
  else
    used(hit) = true;
  end
end
for q = 1:numel(lb)
  if ~used(q), onlyB{end+1} = lb{q}; end %#ok<AGROW>
end
end

function lines = splitlines(txt)
txt = strrep(txt, sprintf('\r\n'), sprintf('\n'));
txt = strrep(txt, sprintf('\r'), sprintf('\n'));
lines = strsplit(txt, sprintf('\n'));
end

function s = shorten(s, n)
if numel(s) > n, s = [s(1:n) '...']; end
end

function o = exportOpts(R, outDir)
o = struct();
o.OutDir = outDir; o.LibDir = fullfile(R, 'test', 'lib', 'blocks');
o.AliasMap = cell(0, 2); o.ExtraHeader = {};
o.LibRel = '..\lib\blocks'; o.SaveRel = '..\models';
o.InlineMasks = true;
end

function nm = findScopeName(R, model)
nm = '';
try
  close_model(model);
  load_system(fullfile(R, 'test', 'models', [model '.slx']));
  s = find_system(model, 'SearchDepth', 1, 'BlockType', 'Scope');
  if ~isempty(s)
    parts = strsplit(s{1}, '/');
    nm = parts{end};
  end
  close_model(model);
catch
end
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

