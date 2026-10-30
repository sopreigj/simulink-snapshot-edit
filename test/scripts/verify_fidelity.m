%% verify_fidelity.m — 保真度验证器：导出→重建→结构 diff（simulink-snapshot-edit）
%
%  对任意模型证明快照的"彻底一致"：采集原模型结构指纹 → 导出快照 → 用快照
%  重建模型 → 再次采集 → 逐对象对比（块名/类型/位置、线连接对、信号标签、
%  ws 变量值、模型级参数、回调、注解）。输出 diff 明细与计数；验证后恢复原文件。
%
%  用法
%    r = verify_fidelity('MyModel', opts)   % opts 同 snp_export（LibDir/AliasMap…）
%    r.diff==0 即结构彻底一致。
%
%  设计要点：对比用"同一模型名的两次内存采集"，回避同名 slx 无法并存加载
%  的 Simulink 限制。库实例内部不参与 diff（实例=库整体复制）；分支折线
%  形状不参与 diff（连接关系参与）。

function r = verify_fidelity(mdl, opts)
  if nargin < 2, opts = struct; end
  R0 = fileparts(fileparts(mfilename('fullpath'))); while ~exist(fullfile(R0,'src','snp_export.m'),'file') && ~strcmp(R0,fileparts(R0)), R0 = fileparts(R0); end
  if ~isfield(opts, 'OutDir'), opts.OutDir = fullfile(R0, 'test', 'scratch', 'fidelity_tmp'); end
  if ~isfolder(opts.OutDir), mkdir(opts.OutDir); end
  addpath(fileparts(which('snp_export')));
  if ~bdIsLoaded(mdl), load_system(mdl); end

  % 1) 原模型备份（copyfile 不触碰 Simulink 状态，避免 save-as 重名切换）+ 采集 S1
  bak = fullfile(opts.OutDir, sprintf('%s_bak_%d.slx', mdl, randi(1e9)));
  src = which(mdl);
  if isempty(src), src = fullfile(pwd, [mdl '.slx']); end
  copyfile(src, bak, 'f');
  S1 = collect(mdl);
  close_system(mdl, 0);

  % 2) 导出 + 用快照重建（导出到独立临时目录，绝不覆盖用户手写的 snap 文件）
  tmpDir = fullfile(opts.OutDir, 'verify_gen');
  if ~isfolder(tmpDir), mkdir(tmpDir); end
  o3 = opts; o3.OutDir = tmpDir;
  snp_export(mdl, o3);
  snap = fullfile(tmpDir, ['snapshot_' mdl '.m']);
  oldDir = pwd;
  cd(opts.OutDir);
  try
    run(snap);
  catch ME
    cd(oldDir);
    r.diff = inf; r.detail = {['SNAPSHOT BUILD FAILED: ' ME.message]};
    restore(mdl, bak); return;
  end
  cd(oldDir);

  % 3) 重建后采集 S2 并对比（先清除 new_system shadow 留下的同名幽灵模型）
  try, close_system(mdl, 0); catch, end
  bdclose('new Simulink model');   %#ok<BDSCI> 兜底
  load_system(mdl);
  S2 = collect(mdl);
  close_system(mdl, 0);
  [r.diff, r.detail] = diffstruct(S1, S2);

  % 4) 恢复原模型
  restore(mdl, bak);

  if r.diff == 0
    fprintf('FIDELITY OK: %s 结构彻底一致（块/线/信号标签/ws/配置/回调/注解）\n', mdl);
  else
    fprintf('FIDELITY DIFF=%d:\n', r.diff);
    for i = 1:min(numel(r.detail), 10), fprintf('  - %s\n', r.detail{i}); end
  end
end

%% ---------- 结构指纹采集 ----------
function S = collect(mdl)
  % mdl 可为已加载模型名或 .slx 文件路径
  if ~bdIsLoaded(mdl)
    [~, nm] = fileparts(mdl);
    if ~isempty(nm), mdl = nm; end
    load_system(mdl);
  end
  S.blocks = struct('name', {}, 'type', {}, 'pos', {});
  bs = find_system(mdl, 'LookUnderMasks', 'none', 'FollowLinks', 'off', 'Type', 'block');
  for i = 1:numel(bs)
    rel = strrep(bs{i}, [mdl '/'], '');
    if isempty(rel), continue; end   % 根
    try
      S.blocks(end+1) = struct('name', rel, 'type', get_param(bs{i}, 'BlockType'), ...
        'pos', get_param(bs{i}, 'Position')); %#ok<AGROW>
    catch
    end
  end
  [S.blocks.name] = S.blocks.name;   % 保持顺序
  % 线连接对 + 信号标签
  S.conns = {}; S.sigs = {};
  lines = find_system(mdl, 'FindAll', 'on', 'LookUnderMasks', 'none', 'FollowLinks', 'off', 'Type', 'line');
  for i = 1:numel(lines)
    try
      srcH = get_param(lines(i), 'SrcPortHandle');
      if srcH <= 0, continue; end
      dstH = get_param(lines(i), 'DstPortHandle');
      sn = get_param(lines(i), 'Name');
      for k = 1:numel(dstH)
        if dstH(k) <= 0, continue; end
        s = sprintf('%s/%d>%s/%d', get_param(get_param(lines(i), 'SrcBlockHandle'), 'Name'), ...
          get_param(srcH, 'PortNumber'), get_param(get_param(dstH(k), 'Parent'), 'Name'), ...
          get_param(dstH(k), 'PortNumber'));
        S.conns{end+1} = s; %#ok<AGROW>
        if ischar(sn) && ~isempty(sn), S.sigs{end+1} = [s ' ' sn]; end %#ok<AGROW>
      end
    catch
    end
  end
  S.conns = sort(S.conns); S.sigs = sort(S.sigs);
  % Model Workspace
  ws = get_param(mdl, 'ModelWorkspace');
  v = ws.whos;
  S.wsNames = sort({v.name});
  S.wsVals = {};
  for i = 1:numel(S.wsNames)
    try, S.wsVals{end+1} = ws.getVariable(S.wsNames{i}); catch, S.wsVals{end+1} = []; end %#ok<AGROW>
  end
  % 模型级参数 + 回调
  mps = {'SolverType','SolverName','FixedStep','StartTime','StopTime', ...
    'DefaultBlockFontName','DefaultBlockFontSize','ScreenColor','Description', ...
    'PreLoadFcn','InitFcn','StartFcn','StopFcn','CloseFcn','SaveFcn','DeleteFcn', ...
    'SaveTime','TimeSaveName','SaveOutput','OutputSaveName','SaveFormat','DeviceType'};
  S.mp = mps;
  S.mpVals = cell(1, numel(mps));
  for i = 1:numel(mps)
    try, S.mpVals{i} = get_param(mdl, mps{i}); catch, S.mpVals{i} = '<missing>'; end
  end
  % 顶层注解（文本+位置）
  S.anns = {}; S.annPos = {};
  anns = find_system(mdl, 'FindAll', 'on', 'SearchDepth', 1, 'Type', 'annotation');
  for i = 1:numel(anns)
    try
      if ~strcmp(get_param(anns(i), 'Parent'), mdl), continue; end
      S.anns{end+1} = get_param(anns(i), 'Name'); %#ok<AGROW>
      S.annPos{end+1} = get_param(anns(i), 'Position'); %#ok<AGROW>
    catch
    end
  end
  S.anns = sort(S.anns);
end

%% ---------- 指纹对比 ----------
function [n, detail] = diffstruct(A, B)
  detail = {};
  % 块（按名对齐比较）
  nmA = {A.blocks.name}; nmB = {B.blocks.name};
  if ~isequal(sort(nmA), sort(nmB))
    detail{end+1} = sprintf('块集合不同: 仅原 [%s] / 仅新 [%s]', ...
      strjoin(setdiff(nmA, nmB), ' '), strjoin(setdiff(nmB, nmA), ' ')); %#ok<AGROW>
  end
  for i = 1:numel(A.blocks)
    j = find(strcmp(nmB, A.blocks(i).name), 1);
    if isempty(j), continue; end
    if ~strcmp(A.blocks(i).type, B.blocks(j).type)
      detail{end+1} = sprintf('块 %s 类型不同 %s vs %s', A.blocks(i).name, A.blocks(i).type, B.blocks(j).type); %#ok<AGROW>
    elseif ~isequal(A.blocks(i).pos, B.blocks(j).pos)
      detail{end+1} = sprintf('块 %s Position 不同', A.blocks(i).name); %#ok<AGROW>
    end
  end
  % 线/信号
  if ~isequal(A.conns, B.conns)
    detail{end+1} = sprintf('线连接对不同: 仅原 %d / 仅新 %d', ...
      numel(setdiff(A.conns, B.conns)), numel(setdiff(B.conns, A.conns))); %#ok<AGROW>
  end
  if ~isequal(A.sigs, B.sigs)
    detail{end+1} = '信号标签不同'; %#ok<AGROW>
  end
  % ws
  if ~isequal(A.wsNames, B.wsNames)
    detail{end+1} = sprintf('ws 变量集合不同: [%s]', strjoin(setdiff(A.wsNames, B.wsNames), ' ')); %#ok<AGROW>
  else
    for i = 1:numel(A.wsVals)
      if ~isequal(A.wsVals{i}, B.wsVals{i})
        detail{end+1} = sprintf('ws 变量 %s 值不同', A.wsNames{i}); %#ok<AGROW>
      end
    end
  end
  % 模型参数
  for i = 1:numel(A.mp)
    if ~isequal(A.mpVals{i}, B.mpVals{i})
      detail{end+1} = sprintf('模型参数 %s 不同', A.mp{i}); %#ok<AGROW>
    end
  end
  % 注解（多行文本逐字节比）
  if ~isequal(A.anns, B.anns)
    detail{end+1} = sprintf('注解文本不同: 原 %d 条 / 新 %d 条', numel(A.anns), numel(B.anns)); %#ok<AGROW>
  end
  n = numel(detail);
end

%% ---------- 恢复原模型文件（带重试——Windows 文件占用句柄释放有延迟）----------
function restore(mdl, bak)
  dest = which(mdl);
  if isempty(dest), dest = fullfile(pwd, [mdl '.slx']); end
  try, close_system(mdl, 0); catch, end
  for k = 1:5
    try
      copyfile(bak, dest, 'f');
      return;
    catch
      pause(1);
    end
  end
  warning('verify_fidelity: restore 失败（文件持续被占用）：%s', dest);
end

