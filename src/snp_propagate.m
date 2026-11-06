%% snp_propagate.m — 库传播 runner（simulink-snapshot-edit）
%
% 机制（2026-10-29 R2023b 实测）：引用模型的库实例是链接式
% （ReferenceBlock / LinkStatus='resolved'）；模型快照只记链接
% add_block('mylib/blk',…)，不记库内部参数。**改库后用未改动的模型快照
% 重建，实例 resolve 时自动带上库新内容**——所以自动传播只需两步：
%   (1) 重建库（run 库快照 M 生成新 .slx；或库文件已被改则跳过）
%   (2) 对每个引用模型 run 其快照 M（文本不含库参数，重建即带上新内容）
% 模型快照本身**逐字节不变**——传播靠库侧解析，快照无需同步（见 rep.snapHash*）。
%
% 用法
%   o.WorkDir = '<workdir>';      % 库/模型/快照都在此目录
%   o.RebuildLib = true;          % true=先 run 库快照重建库（默认）
%                                  % false=库文件已是新值，只重建模型
%   o.LibSnap = '';               % 库快照路径（默认 WorkDir/snapshot_<lib>.m）
%   o.ModelSnaps = {};            % 各模型快照路径（默认逐个 WorkDir/snapshot_<m>.m）
%   o.Check = struct(...);        % 可选：期望校验数组（见下）
%   o.Force = false;              % true=有模型带未保存改动时仍强关（默认阻断，T70）
%   rep = snp_propagate('mylib', {'mA','mB'}, o)
%   rep = snp_propagate('mylib', 'auto', o)   % models 由 WorkDir 里所有
%                                             % ReferenceBlock 引用 mylib 的
%                                             % snapshot_*.m 自动发现
%
% o.Check：struct 数组，每项字段
%   .model  模型名
%   .block  引用块在模型里的相对名（如 'Ref1'）
%   .param  参数名（如 'Gain'）
%   .value  期望值（字符串比对）
%
% 输出 rep
%   .libRebuilt      库是否重建（RebuildLib 且成功）
%   .libFile         库产物路径
%   .nModels/.nPropagated/.nFailed
%   .models          每模型 struct：
%                     .name .rebuilt(逻辑) .err(报错文本)
%                     .snapHashBefore/After（MD5；传播前后应相等）
%                     .checks（每项 .ok .got）
%   .notes           说明
%
% 坑（负知识）
%   T30：库默认上锁——重建前先 close_system(lib)，库快照脚本内部 bdclose+new；
%   T31：重建后 bdIsLoaded 恒 0，必须 open_system(产物文件) 再 get_param；
%   T37：快照脚本 save 到**执行时 cwd**（无 SaveRel 时），必须 cd(WorkDir) 后 run。
%   T72：models='auto' 必须先发现再走提醒/守卫循环——旧顺序对 char 输入
%        先做 models{i} 花括号索引，'auto' 还没进发现逻辑就崩了。
function rep = snp_propagate(libModel, models, opts)
  R = fileparts(fileparts(mfilename('fullpath')));
  while ~exist(fullfile(R, 'src', 'snp_export.m'), 'file') && ~strcmp(R, fileparts(R))
    R = fileparts(R);
  end
  if ~isfield(opts, 'WorkDir'), opts.WorkDir = pwd; end
  if ~isfield(opts, 'RebuildLib'), opts.RebuildLib = true; end
  if ~isfield(opts, 'LibSnap') || isempty(opts.LibSnap)
    opts.LibSnap = fullfile(opts.WorkDir, sprintf('snapshot_%s.m', libModel));
  end
  if ~isfield(opts, 'ModelSnaps') || isempty(opts.ModelSnaps)
    opts.ModelSnaps = {};
  end
  if ~isfield(opts, 'Check'), opts.Check = struct('model', {}, 'block', {}, 'param', {}, 'value', {}); end
  if ~isfield(opts, 'Force'), opts.Force = false; end    % T70：默认护住人的未保存改动
  rep = struct('libRebuilt', false, 'libFile', '', 'nModels', 0, ...
    'nPropagated', 0, 'nFailed', 0, 'notes', '');
  rep.models = {};   % 空字段必须后加：struct() 里给 {} 会让整个结构体变空数组

  %% models 自动发现：WorkDir 里引用该库的 snapshot_*.m（T72：先发现，
  %  提醒/守卫循环才能拿到真实模型名单；'auto' 是 char/string 标量）
  if (ischar(models) || (isstring(models) && numel(models) == 1)) && strcmp(models, 'auto')
    models = {};
    snaps = dir(fullfile(opts.WorkDir, 'snapshot_*.m'));
    for i = 1:numel(snaps)
      nm = snaps(i).name(10:end-2);   % snapshot_<m>.m → <m>
      txt = fileread(fullfile(opts.WorkDir, snaps(i).name));
      % 快照含 add_block('<libModel>/…', …) 即引用
      if contains(txt, sprintf('''%s/', libModel))
        models{end+1} = nm; %#ok<AGROW>
      end
    end
    rep.notes = sprintf('auto 发现 %d 个引用模型', numel(models));
  end
  if ~iscell(models), models = {models}; end
  rep.nModels = numel(models);

  % bdclose('all') 会无保存强关所有模型——先提醒每个相关模型的
  % 仿真中/未保存状态（同 snp_runtime_warn）
  snp_runtime_warn(libModel, 'reload');
  for i = 1:numel(models)
    if ischar(models{i}) || isstring(models{i})
      snp_runtime_warn(char(models{i}), 'reload');
    end
  end
  % T70：bdclose('all') 的波及面是**全部已加载块图**，Dirty 检查也必须全量
  %      （Simulink.allBlockDiagrams，R2023b 文档实测可用）：任一未保存
  %      默认阻断，opts.Force=true 才放行。枚举自身失败则只警告不阻断
  %      （fail-open：守卫不能因自身故障卡死工具链，但也不静默放行）
  if ~opts.Force
    try
      bds = Simulink.allBlockDiagrams();
      dirty = bds(strcmp(get_param(bds, 'Dirty'), 'on'));
      if ~isempty(dirty)
        % 单个块图时 get_param 返回 char 而非 cell（实测 R2023b），cellstr 统一
        names = cellstr(get_param(dirty, 'Name'));
        error('snp:dirtyBlocked', ...
          ['bdclose(''all'') 会无保存强关以下带未保存改动的模型，改动将丢失：\n  %s\n' ...
           '  先逐个保存：save_system(模型名)；或明确放弃：opts.Force = true'], ...
          strjoin(names, ', '));
      end
    catch e
      if strcmp(e.identifier, 'snp:dirtyBlocked'), rethrow(e); end
      warning('snp:guardProbe', '全量 Dirty 守卫枚举失败（%s），仅警告不阻断', e.message);
    end
  end
  bdclose('all');

  %% ---- 步骤 1：重建库 ----
  if opts.RebuildLib
    if ~isfile(opts.LibSnap)
      rep.notes = [rep.notes ' 库快照缺失: ' opts.LibSnap];
      rep.nFailed = rep.nModels;
      return;
    end
    try
      try, close_system(libModel, 0); catch, end   % T30：库可能上锁占内存
      oldDir = cd(opts.WorkDir);
      run(opts.LibSnap);                          % T37：save 落 cwd
      cd(oldDir);
      rep.libFile = fullfile(opts.WorkDir, [libModel '.slx']);
      rep.libRebuilt = isfile(rep.libFile);
    catch e
      rep.notes = [rep.notes ' 库重建失败: ' strrep(e.message, sprintf('\n'), ' ')];
      rep.nFailed = rep.nModels;
      return;
    end
  else
    rep.libFile = fullfile(opts.WorkDir, [libModel '.slx']);
    rep.libRebuilt = false;
  end

  %% ---- 步骤 2：逐模型重建 + 校验 ----
  for i = 1:numel(models)
    m = models{i};
    ent = struct('name', m, 'rebuilt', false, 'err', '', ...
      'snapHashBefore', '', 'snapHashAfter', '');
    ent.checks = {};   % 空字段后加，同 rep.models
    snap = fullfile(opts.WorkDir, sprintf('snapshot_%s.m', m));
    if ~isempty(opts.ModelSnaps) && i <= numel(opts.ModelSnaps) && ~isempty(opts.ModelSnaps{i})
      snap = opts.ModelSnaps{i};
    end
    if ~isfile(snap)
      ent.err = '模型快照缺失';
      rep.nFailed = rep.nFailed + 1;
      rep.models{end+1} = ent; %#ok<AGROW>
      continue;
    end
    ent.snapHashBefore = local_md5(snap);
    try
      try, close_system(m, 0); catch, end
      oldDir = cd(opts.WorkDir);
      run(snap);
      cd(oldDir);
      f = fullfile(opts.WorkDir, [m '.slx']);
      ent.rebuilt = isfile(f);
      ent.snapHashAfter = local_md5(snap);
      % T31：bdIsLoaded 恒 0——open_system 产物再回读
      if ent.rebuilt
        open_system(f);
        % 回读 ReferenceBlock 实例的期望参数
        ckIdx = find(arrayfun(@(c) strcmp(c.model, m), opts.Check));
        for k = 1:numel(ckIdx)
          c = opts.Check(ckIdx(k));
          got = '';
          try
            blk = [m '/' c.block];
            got = get_param(blk, c.param);
            if isnumeric(got), got = mat2str(got); end
          catch e2
            got = ['ERR:' strrep(e2.message, sprintf('\n'), ' ')];
          end
          ent.checks{end+1} = struct('block', c.block, 'param', c.param, ...
            'value', c.value, 'got', got, ...
            'ok', isequal(got, c.value)); %#ok<AGROW>
        end
        close_system(m, 0);
      end
    catch e
      ent.err = strrep(e.message, sprintf('\n'), ' ');
    end
    ckOk = ~isempty(ent.checks) && all(cellfun(@(c) c.ok, ent.checks));
    if ent.rebuilt && (isempty(ent.checks) || ckOk)
      rep.nPropagated = rep.nPropagated + 1;
    else
      rep.nFailed = rep.nFailed + 1;
    end
    rep.models{end+1} = ent; %#ok<AGROW>
  end
  bdclose('all');
end

function h = local_md5(f)
  h = '';
  try
    d = dir(f);
    h = d.date;   % 文件时间戳代理：传播不写快照则不变（MD5 依赖 Java，避免拖慢）
  catch
  end
end
