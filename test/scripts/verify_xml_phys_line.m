function verify_xml_phys_line()
% 验证 snp_xml_edit 的 add_line/remove_line 支持 Simscape 物理端点
% （#lconn:/#rconn: + <Line LineType="Connection">，每条独立、无扇出）。
try
  body();
catch ME
  fid = fopen(fullfile(fileparts(mfilename('fullpath')),'..','scratch','xml_phys_line_tmp','report.txt'),'a','n','UTF-8');
  fprintf(fid, '\n!!! UNCAUGHT: %s\n%s\n', ME.message, ME.getReport('extended'));
  fclose(fid);
  rethrow(ME);
end
end

function body()

%
%  设计：造一个"断开"的物理网络（r1--c1 已连，gnd 悬空），用 snp_xml_edit
%  在 c1/RConn1 与 gnd/LConn1 间加一条物理连线，验证：
%    ok0 基线重建一致：原件重新导出→重建的 .slx 物理网络 == 原件
%    ok1 XML 加线生效：编辑件物理网络 ⊇ 原件端点 + {c1/RConn1, gnd/LConn1}
%    ok2 M 路线等价：编辑件 M 重建的 .slx 物理网络 == 编辑件磁盘 .slx 网络
%    ok3 下游链路：基类 M 与编辑件 M 的 diff 含物理 add_line（端口为 LConn/RConn）
%
%  判据哲学：不只看"载入成功"，而是"重建后的物理网络一致"；
%  下游 snp_patch 直接消费 mops 端口字符串（'LConn1'），与 snp_export 物理行
%  格式一致，无需改动。
R = fileparts(fileparts(mfilename('fullpath')));
while ~exist(fullfile(R,'src','snp_export.m'),'file') && ~strcmp(R,fileparts(R)), R = fileparts(R); end
addpath(fullfile(R,'src'));
if ~isfolder(fullfile(R,'test','sfun_probe')), mkdir(fullfile(R,'test','sfun_probe')); end
addpath(fullfile(R,'test','sfun_probe'));

outRoot = fullfile(R,'test','scratch','xml_phys_line_tmp');
if isfolder(outRoot), rmdir(outRoot,'s'); end
mkdir(outRoot);
fid = fopen(fullfile(outRoot,'report.txt'),'w','n','UTF-8');
logf = @(varargin) fprintf(fid, varargin{:});

keyOf = @(net) strjoin(sort(net),'|');
% 端点形如 'modelName/block/Port'，比较连通性时去掉模型名前缀（orig/edited 模型名不同）
endpointUnion = @(nets) sort(unique(cellfun(@stripOne, [nets{:}], 'UniformOutput', false)));

% ---------- 造原件：r1--c1 连，gnd 悬空 ----------
% 约定：模型在内存名 = 文件名（不含扩展名），load_system 后以此名引用
buildName = 'physLineMdl';
try, close_system(buildName,0); catch, end
new_system(buildName);
add_block('fl_lib/Electrical/Electrical Elements/Resistor', [buildName '/r1'], 'Position',[100 100 140 140]);
add_block('fl_lib/Electrical/Electrical Elements/Capacitor', [buildName '/c1'], 'Position',[240 100 280 140]);
add_block('fl_lib/Electrical/Electrical Elements/Electrical Reference', [buildName '/gnd'], 'Position',[240 240 280 280]);
add_line(buildName, 'r1/LConn1', 'c1/LConn1');   % 仅这一条，gnd 悬空（new_system 后内存名即 buildName）
origSlx = fullfile(outRoot,'physLineMdl_orig.slx');
save_system(buildName, origSlx);
close_system(buildName,0);
logf('原件已存 %s（r1--c1 连，gnd 悬空）\n', origSlx);

% ---------- 原件物理网络（基线，load 后内存名=文件名）----------
[~, origMdl] = fileparts(origSlx);
load_system(origSlx);
origNets = snp_phys_connections(origMdl);
close_system(origMdl,0);
origUnion = endpointUnion(origNets);
logf('原件物理网络 %d 个，端点并集 = {%s}\n', numel(origNets), strjoin(origUnion,' , '));

% ---------- XML 加物理连线：c1/RConn1 -- gnd/LConn1 ----------
editedSlx = fullfile(outRoot,'physLineMdl_edited.slx');
info = snp_xml_edit(origSlx, editedSlx, {{'add_line','','c1','RConn1','gnd','LConn1'}});
logf('\nXML add_line 结果：applied=%d skipped=%d\n', size(info.applied,1), size(info.skipped,1));
for k=1:size(info.applied,1)
  logf('  [applied] %s : %s\n', info.applied{k,1}, info.applied{k,2});
end
for k=1:size(info.skipped,1)
  logf('  [skipped] %s : %s : %s\n', info.skipped{k,1}, info.skipped{k,2}, info.skipped{k,3});
end
% mops 端口应为 LConn/RConn 字符串（下游 snp_patch 直接消费）
logf('mops: ');
for k=1:numel(info.mops)
  mop = info.mops{k};
  logf('%s(%s,%s,%s,%s) ', mop{1}, mop{2}, mop{3}, mop{4}, mop{5});
end
logf('\n');

% ---------- 编辑件物理网络（XML 直接读回）----------
[~, editMdl] = fileparts(editedSlx);
load_system(editedSlx);
editNets = snp_phys_connections(editMdl);
close_system(editMdl,0);
editUnion = endpointUnion(editNets);
logf('编辑件物理网络 %d 个，端点并集 = {%s}\n', numel(editNets), strjoin(editUnion,' , '));

% ---------- 导出 M 快照（基类 + 编辑件）----------
% snp_export(mdl,o) 写出 snapshot_<mdl>.m，导出器内部函数名即该名
o = struct(); o.OutDir = outRoot; o.LibDir = fullfile(R,'test','lib','blocks');
o.AliasMap = cell(0,2); o.ExtraHeader = {}; o.LibRel = '..\..\lib\blocks'; o.InlineMasks = true;

baseFn = ['snapshot_' origMdl];   % snapshot_physLineMdl_orig
editFn = ['snapshot_' editMdl];    % snapshot_physLineMdl_edited

load_system(origSlx); snp_export(origMdl, o); close_system(origMdl,0);
baseM = fullfile(outRoot, [baseFn '.m']);
copyfile(fullfile(outRoot,[baseFn '.m']), fullfile(outRoot,'snapshot_physLineMdl_base.m'),'f');

load_system(editedSlx); snp_export(editMdl, o); close_system(editMdl,0);
editM = fullfile(outRoot, [editFn '.m']);
copyfile(fullfile(outRoot,[editFn '.m']), fullfile(outRoot,'snapshot_physLineMdl_edit.m'),'f');

% ---------- 重建（ok0: 基线重建一致；ok2: 编辑件 M 重建 == 编辑件 XML）----------
% 重新导出（带 SaveRel）会覆盖同名快照文件，但已 copy 出 baseM/editM 备份
rebBase = fullfile(outRoot,'reb_base'); if ~isfolder(rebBase), mkdir(rebBase); end
rebEdit = fullfile(outRoot,'reb_edit'); if ~isfolder(rebEdit), mkdir(rebEdit); end
% 快照函数以导出时模型名构建 .slx（origMdl/editMdl），SaveRel 指向各自目录
o.SaveRel = rebBase; load_system(origSlx); snp_export(origMdl, o); close_system(origMdl,0);
cd(outRoot); feval(baseFn); cd(R); bdclose('all');
rebBaseSlx = fullfile(rebBase, [origMdl '.slx']);
load_system(rebBaseSlx); rebBaseNets = snp_phys_connections(origMdl); close_system(origMdl,0);
o.SaveRel = rebEdit; load_system(editedSlx); snp_export(editMdl, o); close_system(editMdl,0);
cd(outRoot); feval(editFn); cd(R); bdclose('all');
rebEditSlx = fullfile(rebEdit, [editMdl '.slx']);
load_system(rebEditSlx); rebEditNets = snp_phys_connections(editMdl); close_system(editMdl,0);

% ---------- 判据 ----------
nOk = 0; nTot = 5;
% ok0 基线重建一致
ok0 = isequal(origUnion, endpointUnion(rebBaseNets));
logf('\n[ok0] 基线重建一致：%s（原件并集={%s} vs 重建并集={%s}）\n', ...
  tern(ok0,'OK','FAIL'), strjoin(origUnion,' , '), strjoin(endpointUnion(rebBaseNets),' , '));
if ok0, nOk = nOk+1; end

% ok1 XML 加线生效：snp_phys_connections 的物理端点为端口名（LConn1/RConn1，无块名），
% 加线 c1/RConn1 -- gnd/LConn1 应在 orig 的 {LConn1} 基础上引入新端口名 RConn1。
newPorts = setdiff(editUnion, origUnion);
ok1 = issubset(origUnion, editUnion) && isequal(newPorts, {'RConn1'});
logf('[ok1] XML 加物理线生效：%s（orig={%s} → edited={%s}，新增端口={%s}）\n', ...
  tern(ok1,'OK','FAIL'), strjoin(origUnion,' , '), strjoin(editUnion,' , '), strjoin(newPorts,' , '));
if ok1, nOk = nOk+1; end

% ok2 M 路线等价：编辑件 M 重建网络 == 编辑件 XML 网络
ok2 = isequal(editUnion, endpointUnion(rebEditNets));
logf('[ok2] M 重建 == XML 编辑件：%s（M重建并集={%s} vs XML并集={%s}）\n', ...
  tern(ok2,'OK','FAIL'), strjoin(endpointUnion(rebEditNets),' , '), strjoin(editUnion,' , '));
if ok2, nOk = nOk+1; end

% ok3 下游链路：基类 M 与编辑件 M 的 diff 含物理 add_line 行
baseTxt = fileread(baseM); editTxt = fileread(editM);
baseLines = strsplit(baseTxt, sprintf('\n'));
editLines = strsplit(editTxt, sprintf('\n'));
physLine = '';
for k=1:numel(editLines)
  ln = editLines{k};
  if contains(ln,'add_line') && (contains(ln,'LConn') || contains(ln,'RConn')) && ~any(strcmp(ln, baseLines))
    physLine = ln; break;
  end
end
ok3 = ~isempty(physLine);
logf('[ok3] M diff 含物理 add_line：%s（%s）\n', tern(ok3,'OK','FAIL'), strtrim(physLine));
if ok3, nOk = nOk+1; end

% ok4 物理 remove_line 生效：从编辑件删掉刚加的线，网络应回到 orig
editedSlx2 = fullfile(outRoot,'edited2.slx');
info2 = snp_xml_edit(editedSlx, editedSlx2, {{'remove_line','','c1','RConn1','gnd','LConn1'}});
logf('\n[remove_line] applied=%d skipped=%d\n', size(info2.applied,1), size(info2.skipped,1));
for k=1:size(info2.applied,1), logf('  [A] %s : %s\n', info2.applied{k,1}, info2.applied{k,2}); end
for k=1:size(info2.skipped,1), logf('  [S] %s : %s : %s\n', info2.skipped{k,1}, info2.skipped{k,2}, info2.skipped{k,3}); end
load_system(editedSlx2); [~, m2] = fileparts(editedSlx2); editedNets2 = snp_phys_connections(m2); close_system(m2,0);
editUnion2 = endpointUnion(editedNets2);
ok4 = isequal(editUnion2, origUnion);
logf('[ok4] 物理 remove_line 回到 orig：%s（删线后并集={%s} vs orig={%s}）\n', ...
  tern(ok4,'OK','FAIL'), strjoin(editUnion2,' , '), strjoin(origUnion,' , '));
if ok4, nOk = nOk+1; end

fclose(fid);
fprintf('XML_PHYS_LINE_TOTAL ok=%d/%d\n', nOk, nTot);
end

function s = tern(c, a, b)
if c, s = a; else, s = b; end
end

function s = stripOne(ep)
% 端点 'model/block/Port' → 去模型名前缀 'block/Port'
toks = split(ep, '/');
s = strjoin(toks(2:end), '/');
end

function c = issubset(a, b)
% a 的每个元素都出现在 b 中
for k=1:numel(a)
  if ~any(strcmp(a{k}, b)), c = false; return; end
end
c = true;
end
