function verify_phys_coverage()
% Simscape 覆盖面验证：把物理连接导出/重建覆盖面从"纯电阻网络"
% 扩展到更多物理块型，并验证 masked 子系统内部物理网络（expand_masked 路径）。
%
%  场景 A：顶层多块型网络 —— Resistor + Capacitor + Inductor +
%          Electrical Reference(Gnd)，验证电容/电感等无换行块型的 BlockType
%          导出与物理网络重建一致（受控源等含内嵌换行块名是另一类坑，
%          隔离用例另测）。
%  场景 B：masked 子系统内部物理网络（R+C+L+Gnd），验证 expand_masked 路径
%          （snp_phys_connections(maskedPath)）能把子系统内部物理线一并导出重建。
%  场景 C：PMIOPort 物理端口块型（Boundary/Solver Configuration 段的内建块）——
%          验证该块型经 snp_block_source('PMIOPort') → add_block('built-in/PMIOPort')
%          的 M 重建路径可用，且作为物理网络中的一个节点被 snp_phys_connections
%          捕获、重建一致。PMIOPort 只暴露单个物理端口 RConn1（非 LConn/RConn 两端），
%          故作为物理网络的中间节点验证（实测事实）。
%
%  判据：原件 vs 重建件的物理网络集合（按端点名归一化）一致即 OK；新块型
%  BlockType 一致即 OK。场景 C 的库路径若未发现则跳过并记录。
R = fileparts(fileparts(mfilename('fullpath')));
while ~exist(fullfile(R,'src','snp_export.m'),'file') && ~strcmp(R,fileparts(R)), R = fileparts(R); end
addpath(fullfile(R,'src'));
if ~isfolder(fullfile(R,'test','sfun_probe')), mkdir(fullfile(R,'test','sfun_probe')); end
addpath(fullfile(R,'test','sfun_probe'));

log = fullfile(R,'test','scratch','dbg_phys_cov.txt');
if ~isfolder(fileparts(log)), mkdir(fileparts(log)); end
fid = fopen(log,'w');
fprintf(fid,'=== Simscape 覆盖面验证（②）===\n');

keyOf = @(net) strjoin(sort(net),'|');
netsEq = @(oa,na) isequal(sort(cellfun(keyOf,oa,'UniformOutput',false)), ...
                           sort(cellfun(keyOf,na,'UniformOutput',false)));

% ---------- 发现 Physical Port 块路径（场景 C 用）----------
% PMIOPort 是 Simulink 内建块（add_block('built-in/PMIOPort',…)），fl_lib 里
% 没有该块型（fl_lib 的 "Physical Signals" 是 PS 信号库，非电气物理端口）。
% 直接走共享表 snp_block_source（D6：库路径知识只有 add_block 需要）。
physSrc = snp_block_source('PMIOPort');
if isempty(physSrc)
  fprintf(fid,'发现 Physical Port 路径失败（snp_block_source 无 PMIOPort）\n');
else
  fprintf(fid,'发现 Physical Port 路径：%s\n', physSrc);
end

nPass=0; nFail=0; nSkip=0;

% ---------- 公共导出配置（三场景共享）----------
outDir = fullfile(R,'test','scratch','phys_cov_out'); if ~isfolder(outDir), mkdir(outDir); end
o = struct(); o.OutDir = outDir; o.LibDir = fullfile(R,'test','lib','blocks'); o.AliasMap = cell(0,2);
o.ExtraHeader = {}; o.LibRel = '..\..\lib\blocks'; o.InlineMasks = true;

% ---------- 场景 A：顶层多块型网络（R+C+L+Gnd）----------
fprintf(fid,'\n== 场景 A：顶层 R+C+L+Gnd ==\n');
try
close_system('covA',0);
new_system('covA');
add_block('fl_lib/Electrical/Electrical Elements/Resistor','covA/r1','Position',[100 100 140 140]);
add_block('fl_lib/Electrical/Electrical Elements/Capacitor','covA/c1','Position',[220 100 260 140]);
add_block('fl_lib/Electrical/Electrical Elements/Inductor','covA/l1','Position',[340 100 380 140]);
add_block('fl_lib/Electrical/Electrical Elements/Electrical Reference','covA/gnd','Position',[340 240 380 280]);
add_line('covA','r1/LConn1','c1/LConn1');
add_line('covA','c1/RConn1','l1/LConn1');
add_line('covA','l1/RConn1','gnd/LConn1');
save_system('covA', fullfile(R,'test','scratch','covA.slx'));
oa = snp_phys_connections('covA');
fprintf(fid,'  原件网络 %d 个：%s\n', numel(oa), strjoin(cellfun(keyOf,oa,'UniformOutput',false),' | '));
rebA = fullfile(outDir,'rebA'); if ~isfolder(rebA), mkdir(rebA); end
o.SaveRel = rebA;
close_system('covA',0); load_system(fullfile(R,'test','scratch','covA.slx'));
snp_export('covA', o);
close_system('covA',0);
cd(outDir); feval('snapshot_covA'); cd(R);
load_system(fullfile(rebA,'covA.slx'));
na = snp_phys_connections('covA');
fprintf(fid,'  重建网络 %d 个：%s\n', numel(na), strjoin(cellfun(keyOf,na,'UniformOutput',false),' | '));
if netsEq(oa,na)
  fprintf(fid,'  OK  顶层多块型物理网络一致\n'); nPass = nPass+1;
else
  fprintf(fid,'  FAIL 不同\n'); nFail = nFail+1;
end
close_system('covA',0);
catch ME
  fprintf(fid,'  场景 A ERR %s\n', ME.message(1:min(180,end))); nFail = nFail+1; cd(R);
  try, close_system('covA',0); catch, end
end

% ---------- 场景 B：masked 子系统内部网络（expand_masked）----------
fprintf(fid,'\n== 场景 B：masked 子系统内部 R+C+L+Gnd ==\n');
try
close_system('covB',0);
new_system('covB');
add_block('simulink/Ports & Subsystems/Subsystem','covB/sub','Position',[100 100 400 400],'Mask','on');
add_block('fl_lib/Electrical/Electrical Elements/Resistor','covB/sub/r1','Position',[40 40 80 80]);
add_block('fl_lib/Electrical/Electrical Elements/Capacitor','covB/sub/c1','Position',[160 40 200 80]);
add_block('fl_lib/Electrical/Electrical Elements/Inductor','covB/sub/l1','Position',[280 40 320 80]);
add_block('fl_lib/Electrical/Electrical Elements/Electrical Reference','covB/sub/gnd','Position',[160 200 200 240]);
add_line('covB/sub','r1/LConn1','c1/LConn1');
add_line('covB/sub','c1/RConn1','l1/LConn1');
add_line('covB/sub','l1/RConn1','gnd/LConn1');
save_system('covB', fullfile(R,'test','scratch','covB.slx'));
ob = snp_phys_connections('covB/sub');
fprintf(fid,'  原件子系统内网络 %d 个：%s\n', numel(ob), strjoin(cellfun(keyOf,ob,'UniformOutput',false),' | '));
rebB = fullfile(outDir,'rebB'); if ~isfolder(rebB), mkdir(rebB); end
o.SaveRel = rebB;
close_system('covB',0); load_system(fullfile(R,'test','scratch','covB.slx'));
snp_export('covB', o);
close_system('covB',0);
cd(outDir); feval('snapshot_covB'); cd(R);
load_system(fullfile(rebB,'covB.slx'));
nb = snp_phys_connections('covB/sub');
fprintf(fid,'  重建子系统内网络 %d 个：%s\n', numel(nb), strjoin(cellfun(keyOf,nb,'UniformOutput',false),' | '));
if netsEq(ob,nb)
  fprintf(fid,'  OK  子系统内部物理网络一致（expand_masked 路径）\n'); nPass = nPass+1;
else
  fprintf(fid,'  FAIL 不同\n'); nFail = nFail+1;
end
close_system('covB',0);
catch ME
  fprintf(fid,'  场景 B ERR %s\n', ME.message(1:min(180,end))); nFail = nFail+1; cd(R);
  try, close_system('covB',0); catch, end
end

% ---------- 场景 C：PMIOPort 物理端口块型（built-in）----------
fprintf(fid,'\n== 场景 C：PMIOPort 物理端口块型 ==\n');
if isempty(physSrc)
  fprintf(fid,'  跳过（snp_block_source 无 PMIOPort）\n'); nSkip = nSkip+1;
else
  try
  close_system('covC',0);
  new_system('covC');
  % PMIOPort 只暴露单个物理端口 RConn1（已知事实 2026-10-28 探针），作为物理
  % 网络中的一个节点：R1 -- port -- Gnd，验证该块型经 M 重建路径可用且被捕获。
  add_block('fl_lib/Electrical/Electrical Elements/Resistor','covC/r1','Position',[100 100 140 140]);
  add_block(physSrc,'covC/port','Position',[220 100 260 140]);
  add_block('fl_lib/Electrical/Electrical Elements/Electrical Reference','covC/gnd','Position',[340 100 380 140]);
  add_line('covC','r1/RConn1','port/RConn1');
  add_line('covC','port/RConn1','gnd/LConn1');
  save_system('covC', fullfile(R,'test','scratch','covC.slx'));
  % 块型一致性判据：重建件里 port 的 BlockType 必须是 PMIOPort
  oc = snp_phys_connections('covC');
  fprintf(fid,'  原件网络 %d 个：%s\n', numel(oc), strjoin(cellfun(keyOf,oc,'UniformOutput',false),' | '));
  rebC = fullfile(outDir,'rebC'); if ~isfolder(rebC), mkdir(rebC); end
  o.SaveRel = rebC;
  close_system('covC',0); load_system(fullfile(R,'test','scratch','covC.slx'));
  snp_export('covC', o);
  close_system('covC',0);
  cd(outDir); feval('snapshot_covC'); cd(R);
  load_system(fullfile(rebC,'covC.slx'));
  nc = snp_phys_connections('covC');
  btC = get_param('covC/port','BlockType');
  fprintf(fid,'  重建网络 %d 个：%s（port BlockType=%s）\n', numel(nc), ...
    strjoin(cellfun(keyOf,nc,'UniformOutput',false),' | '), btC);
  if netsEq(oc,nc) && strcmp(btC,'PMIOPort')
    fprintf(fid,'  OK  PMIOPort 块型重建 + 物理网络一致\n'); nPass = nPass+1;
  else
    fprintf(fid,'  FAIL 不同（网络%s / 块型%s）\n', ...
      iffstr(netsEq(oc,nc),'一致','异'), btC); nFail = nFail+1;
  end
  close_system('covC',0);
  catch ME
    fprintf(fid,'  场景 C ERR %s\n', ME.message(1:min(180,end))); nFail = nFail+1; cd(R);
    try, close_system('covC',0); catch, end
  end
end

fprintf(fid,'\n== Simscape 覆盖面验证：PASS=%d FAIL=%d 跳过=%d ==\n', nPass, nFail, nSkip);
fclose(fid);
fprintf('PHYS_COV_DONE pass=%d fail=%d skip=%d\n', nPass, nFail, nSkip);
end

function s = iffstr(c, a, b)
if c, s = a; else, s = b; end
end
