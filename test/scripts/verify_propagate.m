%% verify_propagate.m — 库传播验证（simulink-snapshot-edit）
%
%  补 snp_propagate 的测试覆盖（外部只读审查证实为零覆盖，T72 修复后补建）：
%    P1 手改库文件 → RebuildLib=false → 引用实例带上新库参数
%    P2 'auto' 发现名单（T72：'auto' 必须先发现再进守卫循环，char 输入不再崩）
%    P3 Dirty 默认阻断 + Force 放行（T70：bdclose('all') 会丢弃未保存改动）
%    P4 改库快照（agent 路线）→ RebuildLib=true → 整链重建带新值
%
%  输出末行：PROPAGATE_TOTAL ok=N/N fails=N；日志落 scratch/dbg_propagate.txt。

function verify_propagate()
  here = fileparts(mfilename('fullpath'));
  root = here;
  while ~exist(fullfile(root, 'src', 'snp_export.m'), 'file') && ~strcmp(root, fileparts(root))
    root = fileparts(root);
  end
  addpath(fullfile(root, 'src'));
  addpath(fullfile(root, 'test', 'lib'));   % lib_build 建库助手
  scr = fullfile(root, 'test', 'scratch');
  if ~isfolder(scr), mkdir(scr); end
  dbg = fullfile(scr, 'dbg_propagate.txt');
  if isfile(dbg), delete(dbg); end

  say(dbg, '=== verify_propagate 库传播 (R%s) ===', version('-release'));

  nOk = 0; nTot = 0;
  cases = {@p1, @p2, @p3, @p4};
  names = {'P1 手改库文件传播', 'P2 auto发现名单', 'P3 Dirty阻断+Force', 'P4 改库快照传播'};
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

  say(dbg, 'PROPAGATE_TOTAL ok=%d/%d fails=%d', nOk, nTot, nTot - nOk);
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

function d = setupCase(libNm, refMdls, plainMdls)
% 独立 tempname 工作目录：建玩具库（子系统 TG：u→y，内部 Gain=g）+
% 若干引用模型（R1 是库实例）+ 若干无引用模型，再导出全部快照——
% 构成 snp_propagate 的标准工作区形态（WorkDir 内 库/模型/快照 同层）。
  here = fileparts(mfilename('fullpath'));
  root = here;
  while ~exist(fullfile(root, 'src', 'snp_export.m'), 'file') && ~strcmp(root, fileparts(root))
    root = fileparts(root);
  end
  addpath(fullfile(root, 'src'));
  addpath(fullfile(root, 'test', 'lib'));

  d = tempname; mkdir(d); addpath(d);   % snp_export/load_system 按裸名找模型，工作目录须挂 PATH
  try, if bdIsLoaded(libNm), close_system(libNm, 0); end, catch, end

  % 库（T55：new_system 第二参数保 Library 类型，否则引用实例得内联副本）
  lib_build.reset(libNm);
  lib_build.subsystem(libNm, 'TG', {'u'}, {'y'});
  lib_build.gain([libNm '/TG'], 'g', '2');
  lib_build.line([libNm '/TG'], 'u/1', 'g/1');
  lib_build.line([libNm '/TG'], 'g/1', 'y/1');
  save_system(libNm, fullfile(d, [libNm '.slx']));
  close_system(libNm, 0);

  load_system(fullfile(d, [libNm '.slx']));   % add_block 引用需库已加载
  for i = 1:numel(refMdls)
    try, if bdIsLoaded(refMdls{i}), close_system(refMdls{i}, 0); end, catch, end
    new_system(refMdls{i});
    add_block([libNm '/TG'], [refMdls{i} '/R1']);
    save_system(refMdls{i}, fullfile(d, [refMdls{i} '.slx']));
    close_system(refMdls{i}, 0);
  end
  for i = 1:numel(plainMdls)
    try, if bdIsLoaded(plainMdls{i}), close_system(plainMdls{i}, 0); end, catch, end
    new_system(plainMdls{i});
    add_block('simulink/Sources/Constant', [plainMdls{i} '/C1'], 'Position', [40 40 80 70]);
    add_block('simulink/Sinks/Out1', [plainMdls{i} '/O1'], 'Position', [200 40 240 70]);
    add_line(plainMdls{i}, 'C1/1', 'O1/1', 'autorouting', 'off');
    save_system(plainMdls{i}, fullfile(d, [plainMdls{i} '.slx']));
    close_system(plainMdls{i}, 0);
  end

  % 快照：库 + 全部模型（propagate 的发现/重建都按 WorkDir/snapshot_<m>.m）
  o = struct(); o.OutDir = d;
  snp_export(libNm, o);
  for i = 1:numel(refMdls), snp_export(refMdls{i}, o); end
  for i = 1:numel(plainMdls), snp_export(plainMdls{i}, o); end
  try, close_system(libNm, 0); catch, end
end

function closeAll(names)
  for i = 1:numel(names)
    try, if bdIsLoaded(names{i}), close_system(names{i}, 0); end, catch, end
  end
end

%% ---------- P1 手改库文件 → 传播 ----------
function ok = p1(root, dbg)
  libNm = 'pgL1'; mdl = 'pgM1';
  d = setupCase(libNm, {mdl}, {});

  % 库已是新值：直接改库文件内部 Gain 2→7（RebuildLib=false 路线）
  load_system(fullfile(d, [libNm '.slx']));
  set_param(libNm, 'Lock', 'off');   % 库载入后默认上锁（T30），改库内块先解锁
  set_param([libNm '/TG/g'], 'Gain', '7');
  save_system(libNm);
  close_system(libNm, 0);

  opts = struct(); opts.WorkDir = d; opts.RebuildLib = false;
  opts.Check = struct('model', mdl, 'block', 'R1/g', 'param', 'Gain', 'value', '7');
  rep = snp_propagate(libNm, {mdl}, opts);

  m1 = rep.models{1};
  got = ''; if ~isempty(m1.checks), got = m1.checks{1}.got; end
  say(dbg, '  nPropagated=%d nFailed=%d libRebuilt=%d got=%s 快照哈希不变=%d', ...
      rep.nPropagated, rep.nFailed, rep.libRebuilt, got, ...
      strcmp(m1.snapHashBefore, m1.snapHashAfter));
  ok = rep.nModels == 1 && rep.nPropagated == 1 && rep.nFailed == 0 && ...
       ~rep.libRebuilt && ~isempty(m1.checks) && m1.checks{1}.ok && ...
       strcmp(m1.snapHashBefore, m1.snapHashAfter);
  closeAll({libNm, mdl});
end

%% ---------- P2 'auto' 发现名单（T72）----------
function ok = p2(root, dbg)
  libNm = 'pgL2';
  d = setupCase(libNm, {'pgA'}, {'pgB'});

  opts = struct(); opts.WorkDir = d;
  rep = snp_propagate(libNm, 'auto', opts);
  names = cellfun(@(e) e.name, rep.models, 'UniformOutput', false);
  say(dbg, '  notes=[%s] nModels=%d 发现=[%s] nFailed=%d', ...
      rep.notes, rep.nModels, strjoin(names, ','), rep.nFailed);

  % 同一调用用 string 标量 "auto" 也应等价（T72 顺带覆盖）
  rep2 = snp_propagate(libNm, "auto", opts);
  names2 = cellfun(@(e) e.name, rep2.models, 'UniformOutput', false);
  sameNames = numel(names) == numel(names2) && all(strcmp(names, names2));
  say(dbg, '  string形式 发现=[%s] 名单一致=%d', strjoin(names2, ','), 0 + sameNames);

  ok = rep.nModels == 1 && numel(names) == 1 && strcmp(names{1}, 'pgA') && ...
       rep.nFailed == 0 && rep2.nFailed == 0 && sameNames;
  closeAll({libNm, 'pgA', 'pgB'});
end

%% ---------- P3 Dirty 默认阻断 + Force 放行（T70）----------
function ok = p3(root, dbg)
  libNm = 'pgL3'; mdl = 'pgC';
  d = setupCase(libNm, {mdl}, {});
  % 库带未保存改动（Dirty=on，不入盘）——bdclose('all') 会丢弃它
  load_system(fullfile(d, [libNm '.slx']));
  set_param(libNm, 'Lock', 'off');   % 库载入后默认上锁（T30）
  set_param([libNm '/TG/g'], 'Gain', '9');

  opts = struct(); opts.WorkDir = d;
  errId = '';
  try
    snp_propagate(libNm, {mdl}, opts);
  catch err
    errId = err.identifier;
  end
  say(dbg, '  默认 errId=[%s]（期望 snp:dirtyBlocked）', errId);
  blocked = strcmp(errId, 'snp:dirtyBlocked');
  % 库仍在内存且仍是未保存状态（阻断没有副作用）
  stillDirty = bdIsLoaded(libNm) && strcmp(get_param(libNm, 'Dirty'), 'on');

  % Force=true=明确放弃未保存改动 → 放行，整链重建照常
  oF = opts; oF.Force = true;
  rep = struct('nPropagated', 0, 'nFailed', -1);
  try
    rep = snp_propagate(libNm, {mdl}, oF);
  catch err
    say(dbg, '  Force 异常: %s', err.message);
  end
  say(dbg, '  Force nPropagated=%d nFailed=%d 库未存脏=%d', ...
      rep.nPropagated, rep.nFailed, 0 + stillDirty);

  % 重建后库与实例都应回到快照值 2（未保存的 9 被放弃）
  v = ''; v2 = '';
  try
    load_system(fullfile(d, [libNm '.slx']));
    v = get_param([libNm '/TG/g'], 'Gain');
  catch, end
  try
    load_system(fullfile(d, [mdl '.slx']));
    v2 = get_param([mdl '/R1/g'], 'Gain');
  catch, end
  say(dbg, '  库Gain=%s 实例Gain=%s（期望 2/2）', v, v2);

  ok = blocked && stillDirty && rep.nFailed == 0 && rep.nPropagated == 1 && ...
       strcmp(v, '2') && strcmp(v2, '2');
  closeAll({libNm, mdl});
end

%% ---------- P4 改库快照（agent 路线）→ 整链重建 ----------
function ok = p4(root, dbg)
  libNm = 'pgL4'; mdl = 'pgD';
  d = setupCase(libNm, {mdl}, {});

  % agent 路线：直接改库快照里 TG 内部 Gain 的字面值 2→7
  snapLib = fullfile(d, sprintf('snapshot_%s.m', libNm));
  txt = fileread(snapLib);
  L = strsplit(txt, newline);
  hit = false;
  for i = 1:numel(L)
    if contains(L{i}, '/g''') && contains(L{i}, '''Gain''')
      L{i} = regexprep(L{i}, '''Gain'', ''[^'']*''', sprintf('''Gain'', ''7'''));
      hit = true;
    end
  end
  fid = fopen(snapLib, 'w', 'n', 'UTF-8');
  fprintf(fid, '%s', strjoin(L, newline));
  fclose(fid);

  opts = struct(); opts.WorkDir = d;
  opts.Check = struct('model', mdl, 'block', 'R1/g', 'param', 'Gain', 'value', '7');
  rep = snp_propagate(libNm, {mdl}, opts);

  m1 = rep.models{1};
  got = ''; if ~isempty(m1.checks), got = m1.checks{1}.got; end
  say(dbg, '  快照命中=%d libRebuilt=%d nPropagated=%d nFailed=%d got=%s', ...
      0 + hit, rep.libRebuilt, rep.nPropagated, rep.nFailed, got);
  ok = hit && rep.libRebuilt && rep.nPropagated == 1 && rep.nFailed == 0 && ...
       ~isempty(m1.checks) && m1.checks{1}.ok;
  closeAll({libNm, mdl});
end
