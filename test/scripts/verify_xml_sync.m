function verify_xml_sync()
%  XML→M 回灌验证（第二级编辑路线）
%
%  验证的是什么：snp_sync_m 把 .slx 的 XML 编辑翻译成 M 侧改动（经 snp_patch
%  应用到 M 快照）之后，回灌出的 M 与「编辑件经 snp_export 重导出的 M」语义一致。
%
%  三条判据（每个案例）：
%    A 回灌正确：synced M vs 重导出 M 的差异只允许两类——
%      ① 含 Points 的行（几何副作用，XML 侧编辑不管几何）；
%      ② 同一新块的 add_block 行参数多少不同（导出器写全参数、patch 写最小集，
%        逐段包含比较：synced 的每个参数段必须在 exported 里原样出现）；
%    B 判据不空转：原 M vs 重导出 M 的两个方向差异里，**必须**存在非 Points 差异
%      （证明这次编辑确实改变了结构；删除的差异在 repo 侧，新增的在 exported 侧）；
%    C 编辑件可用：编辑件被 Simulink 载入且仿真成功。
%
%  输出：末行 XML_SYNC_TOTAL ok=<n>/<m>；报告 scratch/xml_sync_tmp/report.txt
R = fileparts(fileparts(mfilename('fullpath'))); while ~exist(fullfile(R,'src','snp_export.m'),'file') && ~strcmp(R,fileparts(R)), R = fileparts(R); end
addpath(fullfile(R, 'src'));

outRoot = fullfile(R, 'test', 'scratch', 'xml_sync_tmp');
if isfolder(outRoot), rmdir(outRoot, 's'); end
mkdir(outRoot);
fid = fopen(fullfile(outRoot, 'report.txt'), 'w', 'n', 'UTF-8');
logf = @(varargin) fprintf(fid, varargin{:});

model = 'ToyBasic';
origSlx = fullfile(R, 'test', 'models', [model '.slx']);
snapRepo = fullfile(R, 'test', 'snapshots', ['snapshot_' model '.m']);
nOk = 0; nTot = 0;

cases = {
  'set_param', {{'g1', 'Gain', '1.234567'}}, '改 g1 参数'
  'struct_add', {{'add_block', '', 'Gain', 'SnPSyncGain', {{'Gain', '2.0'}}}, ...
                 {'add_line', '', 'g1', 1, 'SnPSyncGain', 1}}, '增块+接线'
  'struct_remove', {{'@SCOPE@'}}, '删 Scope（运行时解析名字）'
};

scopeName = findScopeName(R, model);

for c = 1:size(cases, 1)
  tag = cases{c, 1};
  ops = cases{c, 2};
  if strcmp(tag, 'struct_remove')
    if isempty(scopeName)
      logf('\n===== 案例 %s SKIP：无顶层 Scope =====\n', tag);
      continue;
    end
    ops = {{'remove_block', scopeName}};
  end
  logf('\n===== 案例 %s：%s =====\n', tag, cases{c, 3});
  nTot = nTot + 1;
  ok = run_case(fid, R, outRoot, model, origSlx, snapRepo, tag, ops);
  if ok, nOk = nOk + 1; end
end

fprintf('XML_SYNC_TOTAL ok=%d/%d\n', nOk, nTot);
logf('\n===== 汇总：ok=%d/%d =====\n', nOk, nTot);
fclose(fid);
end

% ===========================================================================
function ok = run_case(fid, R, outRoot, model, origSlx, snapRepo, tag, ops)
ok = false;
caseDir = fullfile(outRoot, tag);
mkdir(caseDir);
syncedM = fullfile(caseDir, ['snapshot_' model '.m']);
editedSlx = fullfile(caseDir, [model '.slx']);
snapExport = fullfile(caseDir, 'snaps');
mkdir(snapExport);

copyfile(snapRepo, syncedM);

% 1) 回灌：XML 编辑 + mops 应用到 syncedM
try
  info = snp_sync_m(origSlx, syncedM, ops, 'DstSlx', editedSlx);
catch ME
  fprintf(fid, '  FAIL：snp_sync_m 抛错: %s\n', ME.message(1:min(200, end)));
  return;
end
fprintf(fid, '  回灌操作 %d 条：', numel(info.mops));
for k = 1:numel(info.mops)
  fprintf(fid, ' [%s]', char(info.mops{k}{1}));
end
fprintf(fid, '\n');

% 2) 编辑件重导出
try
  close_model(model);
  load_system(editedSlx);
  o = struct();
  o.OutDir = snapExport; o.LibDir = fullfile(R, 'test', 'lib', 'blocks');
  o.AliasMap = cell(0, 2); o.ExtraHeader = {};
  o.LibRel = '..\lib\blocks'; o.SaveRel = '..\models'; o.InlineMasks = true;
  snp_export(model, o);
  close_model(model);
catch ME
  fprintf(fid, '  FAIL：编辑件重导出失败: %s\n', ME.message(1:min(200, end)));
  return;
end

syncedTxt = fileread(syncedM);
exportedTxt = fileread(fullfile(snapExport, ['snapshot_' model '.m']));
repoTxt = fileread(snapRepo);

% 判据 A：回灌正确
[onlySynced, onlyExported] = diffSets(syncedTxt, exportedTxt);
badA = non_geometry_diffs(onlySynced, onlyExported);
fprintf(fid, '  判据A：synced vs 重导出 差异 %d/%d 行，非几何差异 %d 行\n', ...
  numel(onlySynced), numel(onlyExported), numel(badA));
for k = 1:min(4, numel(badA)), fprintf(fid, '    %s\n', shorten(badA{k}, 150)); end
if ~isempty(badA), return; end

% 判据 B：判据不空转（两个方向都查：删除的差异在 repo 侧，新增的在 exported 侧）
[onlyRepo, onlyExp2] = diffSets(repoTxt, exportedTxt);
nNonPts = 0;
for k = 1:numel(onlyRepo)
  if isempty(strfind(onlyRepo{k}, 'Points')) %#ok<STREMP>
    nNonPts = nNonPts + 1;
  end
end
for k = 1:numel(onlyExp2)
  if isempty(strfind(onlyExp2{k}, 'Points')) %#ok<STREMP>
    nNonPts = nNonPts + 1;
  end
end
fprintf(fid, '  判据B：原 M vs 重导出 的非 Points 差异 = %d 行\n', nNonPts);
if nNonPts == 0
  fprintf(fid, '  FAIL：编辑没有改变结构（判据空转）\n');
  return;
end

% 判据 C：编辑件载入 + 仿真
try
  sig = runSim(editedSlx, model);
  fprintf(fid, '  判据C：编辑件仿真 OK（%d 个信号）\n', numel(fieldnames(sig)));
catch ME
  fprintf(fid, '  FAIL：编辑件仿真失败: %s\n', ME.message(1:min(200, end)));
  return;
end

ok = true;
fprintf(fid, '  >>> 案例通过\n');
end

% ===========================================================================
function bad = non_geometry_diffs(onlyA, onlyB)
% 差异分类：含 Points 的行 = 几何副作用（允许）；
% 同一新块的 add_block 行（参数量不同）= 逐段包含比较；
% 其余 = 真差异。
bad = {};
isGeomA = cellfun(@(x) ~isempty(strfind(x, 'Points')), onlyA); %#ok<STREMP>
isGeomB = cellfun(@(x) ~isempty(strfind(x, 'Points')), onlyB); %#ok<STREMP>
idxA = find(~isGeomA);
idxB = find(~isGeomB);
usedB = false(size(idxB));
for k = 1:numel(idxA)
  la = onlyA{idxA(k)};
  blk = extract_block_name(la);
  hit = 0;
  for q = 1:numel(idxB)
    lb = onlyB{idxB(q)};
    if ~isempty(blk) && ~isempty(strfind(lb, sprintf('[m ''/%s''', blk))) %#ok<STREMP>
      if ~addblock_params_match(la, lb)
        bad{end+1} = sprintf('参数不一致 @ %s', blk); %#ok<AGROW>
      end
      hit = q;
      break;
    end
  end
  if hit == 0
    bad{end+1} = ['synced 独有: ' la]; %#ok<AGROW>
  else
    usedB(hit) = true;
  end
end
for q = 1:numel(idxB)
  if ~usedB(q)
    bad{end+1} = ['exported 独有: ' onlyB{idxB(q)}]; %#ok<AGROW>
  end
end
end

function blk = extract_block_name(line)
m = regexp(line, '\[m ''/([^'']+)''\]', 'tokens', 'once');
if isempty(m), blk = ''; else, blk = m{1}; end
end

function tf = addblock_params_match(la, lb)
% la（精简行）的每个参数段必须在 lb（全参数行）里原样出现
segStarts = regexp(la, ', ''[^'']+'', ');
tf = true;
if isempty(segStarts), return; end
for k = 1:numel(segStarts)
  if k < numel(segStarts)
    seg = la(segStarts(k):segStarts(k+1)-1);
  else
    seg = la(segStarts(k):end);
  end
  if endsWith(seg, ');'), seg = seg(1:end-2); end  % 最后一段截掉 ');' 再比
  if ~contains(lb, seg)
    tf = false;
    return;
  end
end
end

% ===========================================================================
function [onlyA, onlyB] = diffSets(a, b)
la = splitlines(a); lb = splitlines(b);
onlyA = {}; onlyB = {};
used = false(size(lb));
for k = 1:numel(la)
  hit = 0;
  for q = 1:numel(lb)
    if ~used(q) && strcmp(la{k}, lb{q}), hit = q; break; end
  end
  if hit == 0, onlyA{end+1} = la{k}; else, used(hit) = true; end %#ok<AGROW>
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

