function verify_special_blocks()
% 特殊块型特性测试：Data Store / Bus / Model Reference / 真 S-Function / 变体子系统
%
%  做法：造一个含这些块的探针模型 → snp_export → 跑快照重建 → 逐块核对
%  （原件里每个块，重建件里必须存在且 BlockType 一致）。
%  判据：缺失或类型不符即 FAIL；全部通过才 PASS。
%
%  已知限制（照实记录，不掩盖）：
%  · Model Reference：被引用模型必须在 MATLAB 路径上（工具不复制它）
%  · 变体子系统：只保留当前激活分支，变体切换机制不保留
R = fileparts(fileparts(mfilename('fullpath'))); while ~exist(fullfile(R,'src','snp_export.m'),'file') && ~strcmp(R,fileparts(R)), R = fileparts(R); end
addpath(fullfile(R, 'src'));
if ~isfolder(fullfile(R, 'test', 'sfun_probe')), mkdir(fullfile(R, 'test', 'sfun_probe')); end
addpath(fullfile(R, 'test', 'sfun_probe'));

logPath = fullfile(R, 'test', 'scratch', 'dbg_special.txt');
if ~isfolder(fileparts(logPath)), mkdir(fileparts(logPath)); end
fid = fopen(logPath, 'w');

% ---------- 1. 造探针模型 ----------
try, close_system('probeFeat', 0); catch, end
try, close_system('probeRef', 0); catch, end
new_system('probeRef');
add_block('simulink/Sources/Constant', 'probeRef/c', 'Position', [10 10 40 30]);
add_block('simulink/Sinks/Out1', 'probeRef/o', 'Position', [100 10 130 30]);
add_line('probeRef', 'c/1', 'o/1');
save_system('probeRef', fullfile(R, 'test', 'scratch', 'probeRef.slx'));

new_system('probeFeat');
add_block('simulink/Signal Routing/Data Store Memory', 'probeFeat/dsm', 'Position', [10 100 60 130]);
add_block('simulink/Signal Routing/Data Store Read', 'probeFeat/dsr', 'Position', [100 100 150 130]);
add_block('simulink/Signal Routing/Data Store Write', 'probeFeat/dsw', 'Position', [200 100 250 130]);
add_block('simulink/Signal Routing/Bus Creator', 'probeFeat/bus', 'Position', [10 180 60 210]);
add_block('simulink/Signal Routing/Bus Selector', 'probeFeat/busel', 'Position', [100 180 150 210]);
add_block('simulink/Ports & Subsystems/Model', 'probeFeat/mref', 'Position', [300 180 400 210], ...
  'ModelName', 'probeRef');
% 真 S-Function（自定义 .m）：S-Function 块只接受 1 级 S-Function 签名
sfm = [ ...
  'function [sys,x0,str,ts] = probe_sfun(t,x,u,flag)' newline ...
  'switch flag' newline ...
  '  case 0' newline ...
  '    sys = [0 0 1 1 0 0 0]; x0 = []; str = []; ts = [];' newline ...
  '  case 3' newline ...
  '    sys = 2*u;' newline ...
  '  case {1,2,4,9}' newline ...
  '    sys = [];' newline ...
  '  case 0' newline ...
  '    sys = [];' newline ...
  '  otherwise' newline ...
  '    sys = [];' newline ...
  'end' newline];
f2 = fopen(fullfile(R, 'test', 'sfun_probe', 'probe_sfun.m'), 'w'); fprintf(f2, '%s', sfm); fclose(f2);
add_block('simulink/User-Defined Functions/S-Function', 'probeFeat/sfun', 'Position', [120 260 200 300], ...
  'FunctionName', 'probe_sfun');
% 变体子系统（只能加 Subsystem 分支）
try
  add_block('simulink/Ports & Subsystems/Variant Subsystem', 'probeFeat/vs', 'Position', [300 260 400 320]);
  add_block('built-in/Subsystem', 'probeFeat/vs/br1', 'Position', [10 10 80 50]);
  add_block('simulink/Sources/Constant', 'probeFeat/vs/br1/Const', 'Position', [10 10 40 30]);
  add_block('simulink/Sinks/Terminator', 'probeFeat/vs/br1/Term', 'Position', [120 10 140 30]);
  add_line('probeFeat/vs/br1', 'Const/1', 'Term/1');
catch ME
  fprintf(fid, '变体子系统搭建失败: %s\n', ME.message(1:min(100,end)));
end
save_system('probeFeat', fullfile(R, 'test', 'scratch', 'probeFeat.slx'));

% ---------- 2. 记录原件块清单（重建前取，重建后原件会被同名件顶替）----------
origBlks = find_system('probeFeat', 'LookUnderMasks', 'all', 'FollowLinks', 'off', 'Type', 'block');
fprintf(fid, '原件块数 %d\n', numel(origBlks));
origRel = cell(numel(origBlks), 1);
origBT = cell(numel(origBlks), 1);
origSkip = false(numel(origBlks), 1);
for i = 1:numel(origBlks)
  origRel{i} = strrep(origBlks{i}, ['probeFeat' '/'], '');
  origBT{i} = get_param(origBlks{i}, 'BlockType');
  origSkip(i) = is_variant_auto_port(origBlks{i});
end
close_system('probeFeat', 0);

% ---------- 3. 导出 → 重建 ----------
outDir = fullfile(R, 'test', 'scratch', 'special_out');
rebuiltDir = fullfile(outDir, 'rebuilt');
if ~isfolder(outDir), mkdir(outDir); end
if ~isfolder(rebuiltDir), mkdir(rebuiltDir); end
o = struct(); o.OutDir = outDir; o.LibDir = fullfile(R, 'test', 'lib', 'blocks');
o.AliasMap = cell(0, 2); o.ExtraHeader = {}; o.LibRel = '..\..\lib\blocks';
o.InlineMasks = true; o.SaveRel = rebuiltDir;
try
  load_system(fullfile(R, 'test', 'scratch', 'probeFeat.slx'));
  snp_export('probeFeat', o);
  close_system('probeFeat', 0);
  cd(outDir); feval('snapshot_probeFeat'); cd(R);
  % 快照脚本末尾保存并关闭了模型——重新加载重建件再做核对
  load_system(fullfile(rebuiltDir, 'probeFeat.slx'));
catch ME
  fprintf(fid, '重建 ERR: %s\n', ME.message(1:min(180,end)));
  fclose(fid); return;
end

% ---------- 4. 逐块核对 ----------
newBlks = find_system('probeFeat', 'LookUnderMasks', 'all', 'FollowLinks', 'off', 'Type', 'block');
nPass = 0; nFail = 0; nSkip = 0;
fprintf(fid, '\n== 逐块核对 ==\n');
for i = 1:numel(origRel)
  rel = origRel{i};
  bt = origBT{i};
  % 变体容器的自动端口（In1/Out1）属于变体机制，代码形态不保留——不参与核对
  if origSkip(i)
    fprintf(fid, '  %-28s : 跳过（变体容器自动端口，代码形态不保留）\n', rel);
    nSkip = nSkip + 1; continue;
  end
  if any(strcmp(newBlks, ['probeFeat' '/' rel]))
    nbt = get_param(['probeFeat' '/' rel], 'BlockType');
    if strcmp(bt, nbt)
      fprintf(fid, '  %-28s : OK  (%s)\n', rel, bt); nPass = nPass + 1;
    else
      fprintf(fid, '  %-28s : FAIL 类型不同 %s -> %s\n', rel, bt, nbt); nFail = nFail + 1;
    end
  else
    fprintf(fid, '  %-28s : FAIL 重建件缺失 (%s)\n', rel, bt); nFail = nFail + 1;
  end
end
% ---------- 5. 物理连接（Simscape）：端口名 LConn/RConn + T 型分支 ----------
fprintf(fid, '\n== 物理连接（Simscape）==\n');
physPass = 0; physFail = 0;
if isempty(ver('simscape'))
  fprintf(fid, '\n== 物理连接（Simscape）==\n  跳过（本机未安装 Simscape）\n');
else
try
  try, close_system('probePhys', 0); catch, end
  new_system('probePhys');
  add_block('fl_lib/Electrical/Electrical Elements/Resistor', 'probePhys/r1', 'Position', [100 100 140 140]);
  add_block('fl_lib/Electrical/Electrical Elements/Resistor', 'probePhys/r2', 'Position', [300 100 340 140]);
  add_block('fl_lib/Electrical/Electrical Elements/Electrical Reference', 'probePhys/gnd', 'Position', [200 240 240 280]);
  add_line('probePhys', 'r1/LConn1', 'r2/LConn1');
  add_line('probePhys', 'r1/RConn1', 'r2/RConn1');
  add_line('probePhys', 'r2/RConn1', 'gnd/LConn1');   % 3 端口网络（T 型分支）
  origCons = snp_phys_connections('probePhys');
  fprintf(fid, '  原件：物理网络 %d 个（端点 %d 个）\n', numel(origCons), ...
    sum(cellfun(@numel, origCons)));
  oP = struct(); oP.OutDir = outDir; oP.LibDir = fullfile(R, 'test', 'lib', 'blocks');
  oP.AliasMap = cell(0, 2); oP.ExtraHeader = {}; oP.LibRel = '..\..\lib\blocks';
  oP.InlineMasks = true; oP.SaveRel = rebuiltDir;
  snp_export('probePhys', oP);
  close_system('probePhys', 0);
  cd(outDir); feval('snapshot_probePhys'); cd(R);
  load_system(fullfile(rebuiltDir, 'probePhys.slx'));
  newCons = snp_phys_connections('probePhys');
  fprintf(fid, '  重建件：物理网络 %d 个（端点 %d 个）\n', numel(newCons), ...
    sum(cellfun(@numel, newCons)));
  % 网络按端点集合归一化后比对（网络内顺序无意义）
  keyOf = @(net) strjoin(sort(net), '|');
  ko = sort(cellfun(keyOf, origCons, 'UniformOutput', false));
  kn = sort(cellfun(keyOf, newCons, 'UniformOutput', false));
  if isequal(ko, kn)
    fprintf(fid, '  %-28s : OK  物理网络一致\n', 'Simscape 物理连接');
    physPass = physPass + numel(ko);
  else
    fprintf(fid, '  %-28s : FAIL 物理网络不同\n', 'Simscape 物理连接');
    fprintf(fid, '    原件: %s\n', strjoin(ko, ' | '));
    fprintf(fid, '    重建: %s\n', strjoin(kn, ' | '));
    physFail = physFail + 1;
  end
  close_system('probePhys', 0);
catch ME
  fprintf(fid, '  Simscape 物理连接 : ERR %s\n', ME.message(1:min(160,end)));
  physFail = physFail + 1;
  cd(R);
  try, close_system('probePhys', 0); catch, end
end
end

fprintf(fid, '\n== 特殊块型特性测试：PASS=%d FAIL=%d 跳过=%d ==\n', nPass, nFail, nSkip);
fprintf(fid, '== 物理连接检查：PASS=%d 条 FAIL=%d ==\n', physPass, physFail);
fclose(fid);
close_system('probeFeat', 0); close_system('probeRef', 0);
fprintf('SPECIAL_DONE pass=%d fail=%d skip=%d physPass=%d physFail=%d\n', nPass, nFail, nSkip, physPass, physFail);
end

function tf = is_variant_auto_port(blk)
% 变体容器的自动端口：父容器是变体子系统，且块名形如 In<N>/Out<N>
  tf = false;
  try
    nm = get_param(blk, 'Name');
    if isempty(regexp(nm, '^(In|Out)\d+$', 'once')), return; end
    p = get_param(blk, 'Parent');
    if ~strcmp(get_param(p, 'Variant'), 'on'), return; end
    tf = true;
  catch
  end
end

