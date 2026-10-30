%% verify_collab.m — 人机协作场景矩阵验证（simulink-snapshot-edit）
%
%  沉淀并拓展人机协作的实测覆盖（原散在 scratch 探针）：
%    C1 人改参数 + agent 注释保留        C5 仿真中 pull 提醒（snp:simRunning）
%    C2 人加/删块 pull                   C6 merge3 正交合并（两侧改不同块）
%    C3 pull 后重建 功能级等价           C7 merge3 同块冲突 theirs 优先（模型=唯一真相）
%    C4 dirty 提醒（snp:dirtyUnsaved）   C8 merge3 删 vs 改 删优先并进冲突清单
%
%  输出末行：COLLAB_TOTAL ok=N/N fails=N；日志落 scratch/dbg_collab.txt。

function verify_collab()
  here = fileparts(mfilename('fullpath'));
  root = here;
  while ~exist(fullfile(root, 'src', 'snp_export.m'), 'file') && ~strcmp(root, fileparts(root))
    root = fileparts(root);
  end
  addpath(fullfile(root, 'src'));
  addpath(here);   % verify_fidelity.m
  scr = fullfile(root, 'test', 'scratch');
  if ~isfolder(scr), mkdir(scr); end
  dbg = fullfile(scr, 'dbg_collab.txt');
  if isfile(dbg), delete(dbg); end

  say(dbg, '=== verify_collab 人机协作场景矩阵 (R%s) ===', version('-release'));

  nOk = 0; nTot = 0;
  cases = {@c1, @c2, @c3, @c4, @c5, @c6, @c7, @c8};
  names = {'C1 人改参数+注释保留', 'C2 人加/删块pull', 'C3 pull后重建等价', ...
           'C4 dirty提醒', 'C5 仿真中提醒', 'C6 merge3正交', 'C7 merge3冲突', 'C8 merge3删vs改'};
  for i = 1:numel(cases)
    try
      ok = cases{i}(root, dbg);
    catch err
      say(dbg, '%s 异常: %s @%s', names{i}, err.message, err.stack(1).name);
      ok = false;
    end
    nTot = nTot + 1;
    if ok, nOk = nOk + 1; end
    say(dbg, '%s -> %s', names{i}, tf(ok));
  end

  say(dbg, 'COLLAB_TOTAL ok=%d/%d fails=%d', nOk, nTot, nTot - nOk);
end

%% ---------- 通用 helper ----------

function say(dbg, varargin)
% 双写：屏幕 + scratch 日志（T53：方括号拼接不用 +）
  line = [sprintf(varargin{:}) newline];
  fprintf('%s', line);
  fid = fopen(dbg, 'a', 'n', 'UTF-8');
  fprintf(fid, '%s', line);
  fclose(fid);
end

function s = tf(ok), if ok, s = 'PASS'; else, s = 'FAIL'; end, end

function d = setupDir(nm)
% 独立 tempname 工作目录 + addpath（pull 的 load_system 按模型名找）
  d = tempname; mkdir(d); addpath(d);
  try, if bdIsLoaded(nm), close_system(nm, 0); end, catch, end
end

function r = catchWarn(fn)
% 取 pull/export 的 snp:* warning id（T59 后运行时提醒）
  lastwarn('');
  rep = [];
  try, rep = fn(); catch err, rep = struct('error', err.message); end
  [~, mid] = lastwarn();
  r = struct('id', mid, 'rep', rep);
end

function snap = buildSnap(d, nm, gain, hasSub)
% pull 场景夹具：建玩具模型 → snp_export 导出真实格式快照 → 注入 agent 注释。
% 用导出格式而非手写：pull 的节匹配针对导出格式，手写快照会误判（T61）
  try, if bdIsLoaded(nm), close_system(nm, 0); end, catch, end
  new_system(nm);
  add_block('simulink/Sources/Constant', [nm '/C1'], 'Position', [40 40 80 70]);
  add_block('simulink/Math Operations/Gain', [nm '/G1'], 'Position', [150 40 210 60], 'Gain', gain);
  add_block('simulink/Sinks/Scope', [nm '/Sc'], 'Position', [260 40 320 70]);
  add_line(nm, 'C1/1', 'G1/1', 'autorouting', 'off');
  add_line(nm, 'G1/1', 'Sc/1', 'autorouting', 'off');
  if hasSub
    add_block('built-in/SubSystem', [nm '/Sub1'], 'Position', [40 200 130 260]);
  end
  save_system(nm, fullfile(d, [nm '.slx']));
  close_system(nm, 0);

  o = struct(); o.OutDir = d;
  snp_export(nm, o);
  snap = fullfile(d, sprintf('snapshot_%s.m', nm));
  txt = fileread(snap);
  % 注入 agent 注释（pull 的手写区保留所保护的对象）：
  % 头部工作流注释后 + blocks 节标记后（G1 块行上方）
  hdrLine = '% Local-edit workflow: edit only the lines of the block you need.';
  blkMark = '  % ---- blocks (positions & full parameters preserved) ----';
  if contains(txt, hdrLine)
    txt = strrep(txt, hdrLine, [hdrLine newline '% agent 备注：人机协作夹具，注释由 agent 注入']);
  end
  if contains(txt, blkMark)
    txt = strrep(txt, blkMark, [blkMark newline '  % 增益：agent 的放大级（G1）']);
  end
  fid = fopen(snap, 'w', 'n', 'UTF-8');
  fprintf(fid, '%s', txt);
  fclose(fid);
end

function writeTri(d, nm, g1, g2, hasSub)
% merge3 三方夹具：函数名=模型名（T57），节标记 % ---- blocks ----
  L = {
    sprintf('function %s()', nm);
    sprintf('  if bdIsLoaded(''%s''), close_system(''%s'', 0); end', nm, nm);
    sprintf('  new_system(''%s''); m = ''%s'';', nm, nm);
    '  % ---- blocks ----';
    sprintf('  add_block(''simulink/Math Operations/Gain'', [m ''/G1''], ''Gain'', ''%s'');', g1);
    sprintf('  add_block(''simulink/Math Operations/Gain'', [m ''/G2''], ''Gain'', ''%s'');', g2);
  };
  if hasSub
    L = [L; { '  add_block(''built-in/SubSystem'', [m ''/Sub1''], ''Position'', [40 200 130 260]);' }];
  end
  L = [L; {
    sprintf('  save_system(m, fullfile(pwd, ''%s.slx''));', nm);
    '  close_system(m, 0);';
    'end'
  }];
  txt = strjoin(L, newline);
  fid = fopen(fullfile(d, sprintf('%s.m', nm)), 'w', 'n', 'UTF-8');
  fprintf(fid, '%s', txt);
  fclose(fid);
end

function runSnap(here, d, snap, nm)
% 重建姿势同 verify_fidelity：先 load 锚定 PATH 名字解析，再 close 后 run。
% run 后重新 load 供 get_param/find_system 读取（快照末尾会 close）
  try, if bdIsLoaded(nm), close_system(nm, 0); end, catch, end
  try, load_system(nm); close_system(nm, 0); catch, end
  cd(d); run(snap); cd(here);
  try, load_system(nm); catch, end
end

function bs = blockNames(nm)
% 顶层块名集合（含子系统）
  bs = find_system(nm, 'SearchDepth', 1, 'Type', 'block');
  bs = cellfun(@(p) regexp(p, '^.*/(.+)$', 'tokens'), bs, 'UniformOutput', false);
  bs = cellfun(@(t) t{1}{1}, bs, 'UniformOutput', false);
  bs = sort(bs);
end

%% ---------- C1 人改参数 + 注释保留 ----------
function ok = c1(root, dbg)
  here = fileparts(mfilename('fullpath'));
  nm = 'cbC1'; d = setupDir(nm);
  snap = buildSnap(d, nm, '2', false);
  runSnap(here, d, snap, nm);

  % 人：改 G1 增益 2→7 并存盘
  load_system(nm);
  set_param([nm '/G1'], 'Gain', '7');
  save_system(nm); close_system(nm, 0);

  o = struct(); o.OutDir = d;
  rep = snp_pull(nm, snap, o);
  noteG1 = contains(fileread(snap), '% 增益：agent 的放大级');
  noteHdr = contains(fileread(snap), '% agent 备注');
  say(dbg, '  nChg=%d nNoteKept=%d 注释G1=%d 头注释=%d', rep.nChg, rep.nNoteKept, noteG1, noteHdr);

  % pull 后重建应等价且 G1=7
  runSnap(here, d, snap, nm);
  r = verify_fidelity(nm, o);
  ok = rep.nChg >= 1 && rep.nNoteKept > 0 && noteG1 && noteHdr && r.diff == 0;
  try, close_system(nm, 0); catch, end
end

%% ---------- C2 人加/删块 pull ----------
function ok = c2(root, dbg)
  here = fileparts(mfilename('fullpath'));
  nm = 'cbC2'; d = setupDir(nm);
  snap = buildSnap(d, nm, '2', true);   % 含 Sub1
  runSnap(here, d, snap, nm);

  % 人：删 Sub1、加 G3
  load_system(nm);
  delete_block([nm '/Sub1']);
  add_block('simulink/Math Operations/Gain', [nm '/G3'], 'Gain', '9');
  save_system(nm); close_system(nm, 0);

  o = struct(); o.OutDir = d;
  rep = snp_pull(nm, snap, o);
  say(dbg, '  nAdd=%d nDel=%d nChg=%d', rep.nAdd, rep.nDel, rep.nChg);

  % 重建后块集合：G3 在、Sub1 不在
  runSnap(here, d, snap, nm);
  bs = blockNames(nm);
  hasG3 = any(strcmp(bs, 'G3'));
  noSub = ~any(strcmp(bs, 'Sub1'));
  say(dbg, '  块集合=[%s] G3在=%d Sub1不在=%d', strjoin(bs, ','), hasG3, noSub);
  ok = rep.nAdd >= 1 && rep.nDel >= 1 && hasG3 && noSub;
  try, close_system(nm, 0); catch, end
end

%% ---------- C3 pull 后重建 逐参数等价 ----------
function ok = c3(root, dbg)
% T48：功能级 funcEqual 假阴性常见，判据用逐参数比对 + verify_fidelity；
% 功能级校验和仅作分叉参考记录
  here = fileparts(mfilename('fullpath'));
  nm = 'cbC3'; d = setupDir(nm);
  snap = buildSnap(d, nm, '3', false);
  runSnap(here, d, snap, nm);

  % 人：G1 3→8 存盘
  load_system(nm);
  set_param([nm '/G1'], 'Gain', '8');
  save_system(nm, fullfile(d, [nm '.slx']));
  close_system(nm, 0);

  o = struct(); o.OutDir = d;
  rep = snp_pull(nm, snap, o);
  runSnap(here, d, snap, nm);   % pull 后快照重建 nm

  v = get_param([nm '/G1'], 'Gain');
  bs = blockNames(nm);
  r = verify_fidelity(nm, o);
  try
    cc = snp_collab_check(nm, 'Compare', nm);   % 自比=0 无意义，仅探测可用性
  catch
    cc = struct('funcEqual', -1);
  end
  say(dbg, '  pull.nChg=%d 重建G1=%s 块集=[%s] fidelity.diff=%d', ...
    rep.nChg, v, strjoin(bs, ','), r.diff);
  ok = rep.nChg >= 1 && strcmp(v, '8') && numel(bs) == 3 && r.diff == 0;
  try, close_system(nm, 0); catch, end
end

%% ---------- C4 dirty 提醒（人改完不存盘）----------
function ok = c4(root, dbg)
  here = fileparts(mfilename('fullpath'));
  nm = 'cbC4'; d = setupDir(nm);
  snap = buildSnap(d, nm, '2', false);
  runSnap(here, d, snap, nm);

  % 人：改 G1 不存盘（dirty=on）
  load_system(nm);
  set_param([nm '/G1'], 'Gain', '9');
  o = struct(); o.OutDir = d;
  w = catchWarn(@() snp_pull(nm, snap, o));
  say(dbg, '  dirty拉 pull warnId=[%s] dirty=%s', w.id, get_param(nm, 'Dirty'));
  warnHit = strcmp(w.id, 'snp:dirtyUnsaved');

  % 收尾：重做改动并存盘 → 再 pull 应无 dirty 提醒且正常合并
  load_system(nm);
  set_param([nm '/G1'], 'Gain', '9');
  save_system(nm); close_system(nm, 0);
  w2 = catchWarn(@() snp_pull(nm, snap, o));
  rep = w2.rep;
  cleanPull = ~strcmp(w2.id, 'snp:dirtyUnsaved') && isfield(rep, 'nChg') && rep.nChg >= 1;
  say(dbg, '  存盘后pull warnId=[%s] nChg=%d', w2.id, ...
    0 + isfield(rep, 'nChg') * rep.nChg);
  ok = warnHit && cleanPull;
  try, close_system(nm, 0); catch, end
end

%% ---------- C5 仿真中 pull 提醒 ----------
function ok = c5(root, dbg)
  here = fileparts(mfilename('fullpath'));
  nm = 'cbC5'; d = setupDir(nm);
  snap = buildSnap(d, nm, '2', false);
  runSnap(here, d, snap, nm);
  load_system(nm);
  set_param(nm, 'StopTime', '1');
  save_system(nm);
  sim(nm);   % 预热编译：-batch 下首次 start 需先完成一次编译
  set_param(nm, 'StopTime', '3');
  save_system(nm);          % 保证磁盘最新（排除 dirty 干扰）
  set_param(nm, 'SimulationCommand', 'start');
  t0 = tic;
  while strcmp(get_param(nm, 'SimulationStatus'), 'stopped') && toc(t0) < 15
    pause(0.3);
  end
  st = get_param(nm, 'SimulationStatus');
  o = struct(); o.OutDir = d;
  w = catchWarn(@() snp_pull(nm, snap, o));
  say(dbg, '  status=%s pull warnId=[%s]', st, w.id);
  ok = strcmp(st, 'running') && strcmp(w.id, 'snp:simRunning');
  % 收尾：停仿真再关（不留进程）
  try, set_param(nm, 'SimulationCommand', 'stop'); catch, end
  pause(0.4);
  try, close_system(nm, 0); catch, end
  try, bdclose(nm); catch, end
end

%% ---------- C6 merge3 正交合并 ----------
function ok = c6(root, dbg)
  here = fileparts(mfilename('fullpath'));
  nm = 'cbC6';
  db = setupDir(nm); do = setupDir(nm); dt = setupDir(nm); dm = setupDir(nm);
  writeTri(db, nm, '1', '2', false);
  writeTri(do, nm, '10', '2', false);   % ours 改 G1
  writeTri(dt, nm, '1', '20', false);   % theirs 改 G2
  rep = snp_merge3(fullfile(db, sprintf('%s.m', nm)), ...
    fullfile(do, sprintf('%s.m', nm)), fullfile(dt, sprintf('%s.m', nm)), ...
    fullfile(dm, sprintf('%s.m', nm)));
  merged = fullfile(dm, sprintf('%s.m', nm));
  say(dbg, '  nMerged=%d nConflict=%d strategy=%s', rep.nMerged, rep.nConflict, rep.strategy);
  % 合并件重建：G1=10（ours）且 G2=20（theirs）
  runSnap(here, dm, merged, nm);
  v1 = get_param([nm '/G1'], 'Gain');
  v2 = get_param([nm '/G2'], 'Gain');
  say(dbg, '  重建 G1=%s G2=%s', v1, v2);
  ok = rep.nConflict == 0 && strcmp(v1, '10') && strcmp(v2, '20');
  try, close_system(nm, 0); catch, end
end

%% ---------- C7 merge3 同块冲突（theirs 优先）----------
function ok = c7(root, dbg)
  here = fileparts(mfilename('fullpath'));
  nm = 'cbC7';
  db = setupDir(nm); do = setupDir(nm); dt = setupDir(nm); dm = setupDir(nm);
  writeTri(db, nm, '1', '2', false);
  writeTri(do, nm, '10', '2', false);   % ours G1=10
  writeTri(dt, nm, '30', '2', false);   % theirs G1=30
  rep = snp_merge3(fullfile(db, sprintf('%s.m', nm)), ...
    fullfile(do, sprintf('%s.m', nm)), fullfile(dt, sprintf('%s.m', nm)), ...
    fullfile(dm, sprintf('%s.m', nm)));
  merged = fullfile(dm, sprintf('%s.m', nm));
  cl = rep.conflictList;
  cl0 = ''; if ~isempty(cl), cl0 = cl{1}; end
  noSlash = ~isempty(cl) && cl{1}(1) ~= '/';
  say(dbg, '  nConflict=%d list0=[%s] 无前导斜杠=%d', rep.nConflict, cl0, noSlash);
  runSnap(here, dm, merged, nm);
  v1 = get_param([nm '/G1'], 'Gain');
  say(dbg, '  重建 G1=%s（theirs 优先）', v1);
  ok = rep.nConflict == 1 && noSlash && strcmp(v1, '30');
  try, close_system(nm, 0); catch, end
end

%% ---------- C8 merge3 删 vs 改（删优先）----------
function ok = c8(root, dbg)
  here = fileparts(mfilename('fullpath'));
  nm = 'cbC8';
  db = setupDir(nm); do = setupDir(nm); dt = setupDir(nm); dm = setupDir(nm);
  writeTri(db, nm, '1', '2', true);     % base: G1+G2+Sub1
  % ours：删 G1——写一个不含 G1 的三方件
  L = {
    sprintf('function %s()', nm);
    sprintf('  if bdIsLoaded(''%s''), close_system(''%s'', 0); end', nm, nm);
    sprintf('  new_system(''%s''); m = ''%s'';', nm, nm);
    '  % ---- blocks ----';
    sprintf('  add_block(''simulink/Math Operations/Gain'', [m ''/G2''], ''Gain'', ''%s'');', '2');
    '  add_block(''built-in/SubSystem'', [m ''/Sub1''], ''Position'', [40 200 130 260]);';
    sprintf('  save_system(m, fullfile(pwd, ''%s.slx''));', nm);
    '  close_system(m, 0);';
    'end'
  };
  fid = fopen(fullfile(do, sprintf('%s.m', nm)), 'w', 'n', 'UTF-8');
  fprintf(fid, '%s', strjoin(L, newline));
  fclose(fid);
  writeTri(dt, nm, '8', '2', true);     % theirs 改 G1=8
  rep = snp_merge3(fullfile(db, sprintf('%s.m', nm)), ...
    fullfile(do, sprintf('%s.m', nm)), fullfile(dt, sprintf('%s.m', nm)), ...
    fullfile(dm, sprintf('%s.m', nm)));
  merged = fullfile(dm, sprintf('%s.m', nm));
  runSnap(here, dm, merged, nm);
  bs = blockNames(nm);
  noG1 = ~any(strcmp(bs, 'G1'));
  say(dbg, '  nConflict=%d 块集合=[%s] G1不在=%d', rep.nConflict, strjoin(bs, ','), noG1);
  ok = noG1 && rep.nConflict >= 1;
  try, close_system(nm, 0); catch, end
end
