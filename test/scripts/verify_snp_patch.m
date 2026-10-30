function verify_snp_patch()
% snp_patch 五路能力验证：块参数 / 改线 Points / 增块 / 删块 / 批量
%
%  流程（全部落 tempdir，不动仓库资产）：每场景独立 export 一份 ToyBasic
%  快照到临时目录 → 在临时副本上打 patch → 跑快照重建 → 对重建件断言。
%  判据：get_param 值 / 结构存在性，个别场景用「重建件复导出文本」判 Points。
%
%  输出：scratch/dbg_snp_patch.txt；末行打印 SNP_PATCH_TOTAL ok=<n>/<m>
R = fileparts(fileparts(mfilename('fullpath'))); while ~exist(fullfile(R,'src','snp_export.m'),'file') && ~strcmp(R,fileparts(R)), R = fileparts(R); end
addpath(fullfile(R, 'src'));
logPath = fullfile(R, 'test', 'scratch', 'dbg_snp_patch.txt');
if ~isfolder(fileparts(logPath)), mkdir(fileparts(logPath)); end
fid = fopen(logPath, 'w');

nm = 'ToyBasic';
nOk = 0; nTot = 0; fails = {};

% ---- 场景工具：导出一份新快照到独立临时目录 ----
function [dirA, snap] = fresh()
  d = tempname; mkdir(d);
  o = struct(); o.OutDir = d; o.LibDir = fullfile(R, 'test', 'lib', 'blocks');
  o.AliasMap = cell(0, 2); o.ExtraHeader = {}; o.LibRel = '..\lib\blocks';
  o.InlineMasks = true; o.SaveRel = d;
  try, close_system(nm, 0); catch, end
  load_system(fullfile(R, 'test', 'models', [nm '.slx']));
  snp_export(nm, o); close_system(nm, 0);
  dirA = d; snap = fullfile(d, ['snapshot_' nm '.m']);
end

% ---- 跑快照重建，返回 .slx 路径 ----
function mdl = rebuild(dirA)
  cd(dirA); feval(['snapshot_' nm]); cd(R);
  mdl = fullfile(dirA, [nm '.slx']);
end

% ---- 断言记账 ----
function check(cond, tag)
  nTot = nTot + 1;
  if cond
    nOk = nOk + 1;
    fprintf(fid, 'PASS %s\n', tag);
  else
    fprintf(fid, 'FAIL %s\n', tag);
    fails{end+1} = tag;
  end
end

% ================= S1 块参数 =================
try
  [d1, s1] = fresh();
  snp_patch(s1, 'g1', 'Gain', '5');
  m = rebuild(d1);
  load_system(m);
  check(strcmp(get_param([nm '/g1'], 'Gain'), '5'), 'S1 param Gain=5');
  close_system(nm, 0);
  rmdir(d1, 's');
catch ME
  nTot = nTot + 1; fails{end+1} = 'S1';
  fprintf(fid, 'ERR  S1 %s\n', ME.message(1:min(160, end)));
  try, close_system(nm, 0); catch, end
  cd(R);
end

% ================= S2 改线 Points =================
% 注：新走线必须锚在真实端口路由上——Simulink 对远离端点的 Points 既不抛错也
% 不生效（静默忽略，T15），所以先从重建模型读出原路由，再取 [起点;中点弯折;终点]。
try
  [d2, s2] = fresh();
  txt = fileread(s2);
  tk = regexp(txt, 'lnH = add_line\(m, ''([^'']+)'', ''([^'']+)''', 'tokens', 'once');
  assert(~isempty(tk), 'no top-level add_line found');
  % 先重建一次，读原线的实际路由（endpoints 锚定，Simulink 才会接受新 Points）
  m = rebuild(d2);
  load_system(m);
  blk = extractBefore(tk{1}, '/');
  ph = get_param([nm '/' blk], 'PortHandles');
  lh = get_param(ph.Outport(1), 'Line');
  pts0 = get_param(lh, 'Points');
  close_system(nm, 0);
  assert(size(pts0, 1) >= 2, 'line has no polyline points');
  newPts = [pts0(1, :); round(mean(pts0, 1)) + [0 80]; pts0(end, :)];
  snp_patch(s2, 'line', tk{1}, tk{2}, 'Points', newPts);
  m = rebuild(d2);
  load_system(m);
  ph = get_param([nm '/' blk], 'PortHandles');
  lh = get_param(ph.Outport(1), 'Line');
  ptsNow = get_param(lh, 'Points');
  close_system(nm, 0);
  % 模型级判据：新走线真实生效（抓住 T15 式静默忽略）
  % Simulink 规范化可能插入附加顶点（实测终点前插入一点），判据=新点全部出现
  inModel = size(ptsNow, 1) >= size(newPts, 1) && all(ismember(round(newPts), round(ptsNow), 'rows'));
  check(inModel, sprintf('S2 line Points applied %s -> %s', tk{1}, tk{2}));
  % 文本级判据：重建件复导出的快照里应有同一 Points 矩阵
  d2b = tempname; mkdir(d2b);
  oB = struct(); oB.OutDir = d2b; oB.LibDir = fullfile(R, 'test', 'lib', 'blocks');
  oB.AliasMap = cell(0, 2); oB.ExtraHeader = {}; oB.LibRel = '..\lib\blocks';
  oB.InlineMasks = true; oB.SaveRel = d2b;
  load_system(m); snp_export(nm, oB); close_system(nm, 0);
  t2 = fileread(fullfile(d2b, ['snapshot_' nm '.m']));
  i2 = strfind(t2, sprintf('add_line(m, ''%s'', ''%s''', tk{1}, tk{2}));
  seg = t2(i2(1):i2(1) + 600);
  pm = regexp(seg, 'set_param\(lnH, ''Points'', (\[[^\]]*\])', 'tokens', 'once');
  inText = ~isempty(pm) && all(ismember(round(newPts), round(str2num(pm{1})), 'rows'));
  check(inText, sprintf('S2 re-export contains Points %s -> %s', tk{1}, tk{2}));
  rmdir(d2, 's'); rmdir(d2b, 's');
catch ME
  nTot = nTot + 1; fails{end+1} = 'S2';
  fprintf(fid, 'ERR  S2 %s\n', ME.message(1:min(160, end)));
  try, close_system(nm, 0); catch, end
  cd(R);
end

% ================= S3 增块 =================
try
  [d3, s3] = fresh();
  snp_patch(s3, 'add_block', 'Name', 'SnPTestConst', ...
    'Source', 'simulink/Sources/Constant', 'Position', [2000 2000 2060 2030], ...
    'Value', '42');
  m = rebuild(d3);
  load_system(m);
  b = find_system(nm, 'SearchDepth', 1, 'Name', 'SnPTestConst');
  check(~isempty(b) && strcmp(get_param([nm '/SnPTestConst'], 'Value'), '42'), ...
    'S3 add_block SnPTestConst=42');
  close_system(nm, 0);
  rmdir(d3, 's');
catch ME
  nTot = nTot + 1; fails{end+1} = 'S3';
  fprintf(fid, 'ERR  S3 %s\n', ME.message(1:min(160, end)));
  try, close_system(nm, 0); catch, end
  cd(R);
end

% ================= S4 删块 =================
try
  [d4, s4] = fresh();
  snp_patch(s4, 'add_block', 'Name', 'SnPTestConst', ...
    'Source', 'simulink/Sources/Constant', 'Position', [2000 2000 2060 2030]);
  snp_patch(s4, 'remove_block', 'SnPTestConst');
  m = rebuild(d4);
  load_system(m);
  check(isempty(find_system(nm, 'SearchDepth', 1, 'Name', 'SnPTestConst')), ...
    'S4 remove_block SnPTestConst gone');
  close_system(nm, 0);
  rmdir(d4, 's');
catch ME
  nTot = nTot + 1; fails{end+1} = 'S4';
  fprintf(fid, 'ERR  S4 %s\n', ME.message(1:min(160, end)));
  try, close_system(nm, 0); catch, end
  cd(R);
end

% ================= S5 批量（表驱动） =================
try
  [d5, s5] = fresh();
  ops = struct('op', {}, 'args', {});
  ops(1) = struct('op', 'g1', 'args', {{'Gain', '5'}});
  ops(2) = struct('op', 'add_block', 'args', {{'Name', 'SnPBatConst', ...
    'Source', 'simulink/Sources/Constant', 'Position', [2000 2100 2060 2130], ...
    'Value', '7'}});
  snp_patch(s5, 'batch', ops);
  m = rebuild(d5);
  load_system(m);
  ok1 = strcmp(get_param([nm '/g1'], 'Gain'), '5');
  ok2 = ~isempty(find_system(nm, 'SearchDepth', 1, 'Name', 'SnPBatConst'));
  check(ok1 && ok2, 'S5 batch param+add_block');
  close_system(nm, 0);
  rmdir(d5, 's');
catch ME
  nTot = nTot + 1; fails{end+1} = 'S5';
  fprintf(fid, 'ERR  S5 %s\n', ME.message(1:min(160, end)));
  try, close_system(nm, 0); catch, end
  cd(R);
end

fprintf(fid, '\n=== SNP_PATCH_TOTAL ok=%d/%d fails=%d ===\n', nOk, nTot, numel(fails));
if ~isempty(fails)
  fprintf(fid, 'failed: %s\n', strjoin(fails, ', '));
end
fclose(fid);
fprintf('SNP_PATCH_TOTAL ok=%d/%d fails=%d\n', nOk, nTot, numel(fails));
end

