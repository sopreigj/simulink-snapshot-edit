%% lib_fingerprint.m
%  模块指纹：给"复制进 release 的副本"提供可校验的身份
%
%  为什么需要它：
%    D2 的装配方式是「库里验证 → 复制进 release 模型 → 接线」。
%    复制之后，副本与库源**立刻脱钩**——
%    改了源头，副本不会跟着变，于是又会出现旧模型里那种
%    "同一个块在一个模型里是一个参数、在另一个里是不一致的旧版本"。
%    指纹让这种漂移变成**可检测的失败**，而不是靠人记住。
%
%  设计：
%    指纹 = 模块名 + 版本号 + 结构哈希
%    结构哈希内容 = 所有子块(类型/名字/关键参数) + 所有连线的(源,目标) 的稳定序列化
%    刻意**不含位置信息**：挪动块的位置不算改动，不该触发过期。
%
%  存放位置：
%    写在模块子系统块的自定义参数 Fingerprint 上（set_param 的任意属性会被存盘）。
%    release 副本复制过去时自带该属性，校验脚本逐块比对。

classdef lib_fingerprint
  methods (Static)

    function s = compute(blkPath, ver)
      % 计算指纹字符串。ver 为模块版本号（如 '1.0'）。
      if nargin < 2, ver = '1.0'; end

      items = collectItems(blkPath, 0);

      items = sort(items);
      blob  = strjoin(items, newline);

      % 用一个稳定的 32 位十六进制摘要（java.security 在 MATLAB 里可用）
      md = java.security.MessageDigest.getInstance('MD5');
      hash = typecast(md.digest(double(blob)), 'uint8');
      hex  = lower(reshape(dec2hex(hash, 2)', 1, []));

      % 格式必须能作为 Constant 的 Value 求值：只允许字母数字与下划线，
      % 不能含 @ # 等会破坏 MATLAB 表达式的字符。
      s = sprintf('FP_%s_v%s_%s', fileName(blkPath), strrep(ver,'.','_'), hex(1:16));
    end

    function stamp(blkPath, fp)
      % 指纹存在子系统内的一个**注释（Simulink.Annotation）**里。
      %
      % 先后试错并否决的载体（全部实测）：
      %   (1) masked subsystem 任意属性名      -> ParamUnknown
      %   (2) masked subsystem 的 UserData      -> mask 拦截，读回 double 0，不报错
      %   (3) 普通块 UserData                   -> save_system 后丢失，重载读到空
      %   (4) Constant 的 Value                 -> 存得住读得回，但**仿真时被求值**
      %                                            （未定义变量报错）
      %   (5) built-in/Note + add_block         -> InvSimulinkObjectName（注释不是块）
      %   (6) Simulink.Annotation              -> 任意文本、随模型存盘、不参与仿真  ✓
      %
      % 约定：子系统内**第一个文本以 FP_ 开头的注释**即指纹。
      a = findAnnotation(blkPath);
      if isempty(a)
        ann = Simulink.Annotation(blkPath, fp);
        try
          ann.Position = [5 5];
          ann.FontSize = 8;
        catch
        end
      else
        % a 是 find_system 返回的句柄数值，不能点号赋值
        set_param(a, 'Text', fp);
      end
    end

    function fp = read(blkPath)
      % 读回指纹；找不到或格式不符返回空串
      fp = '';
      a = findAnnotation(blkPath);
      if isempty(a)
        return;
      end
      % find_system 返回的是**句柄数值**，不是 Simulink.Annotation 对象，
      % 因此不能用 a.Text 取文本，必须用 get_param。
      v = strtrim(char(string(get_param(a, 'Text'))));
      if startsWith(v, 'FP_')
        fp = v;
      end
    end
  end
end

%% ---------- 局部函数 ----------

function s = relName(full, root)
  if strcmp(full, root)
    s = '.';
  else
    s = strrep(full, [root '/'], '');
  end
end

function n = portNum(h)
  try
    n = get_param(h, 'PortNumber');
    if iscell(n), n = n{1}; end
  catch
    n = -1;
  end
end

function v = keyParam(p, bt)
  % 只取对行为有影响的参数；位置/颜色/字体不算
  switch bt
    case 'Gain',      v = getp(p, 'Gain');
    case 'Constant',  v = getp(p, 'Value');
    case 'Sum',       v = getp(p, 'Inputs');
    case 'Product',   v = getp(p, 'Inputs');
    case 'Trigonometric Function', v = getp(p, 'Operator');
    case 'Fcn',       v = getp(p, 'Expr');
    case 'Relational Operator', v = getp(p, 'Operator');
    case 'Math',      v = getp(p, 'Operator');
    case 'Switch',    v = [getp(p, 'Criteria') '|' getp(p, 'Threshold')];
    case 'Unit Delay',v = getp(p, 'SampleTime');
    case 'Inport',    v = getp(p, 'Port');
    case 'Outport',   v = getp(p, 'Port');
    otherwise,        v = '';
  end
end

function v = getp(p, name)
  try
    v = get_param(p, name);
    if iscell(v), v = v{1}; end
    v = char(string(v));
  catch
    v = '';
  end
end

function s = fileName(p)
  [~, s] = fileparts(p);
end

function tf = blockExists(p)
  % 判断块是否存在（含 masked 子系统内部的块）。
  %
  % 踩坑记录：
  %   find_system(p, 'SearchDepth', 0)                  -> 对 masked 内部不可见
  %   find_system(p, 'LookUnderMasks','all','SearchDepth',0) -> 报 FindSystemNoBlock
  %   getSimulinkBlockHandle(p)                          -> 对不存在的路径返回自动句柄，
  %                                                          **永远 > 0**，会误判
  % 可靠做法：用 get_param 试读一个必定存在的属性，捕获异常即不存在。
  try
    get_param(p, 'BlockType');
    tf = true;
  catch
    tf = false;
  end
end

function items = collectItems(blkPath, depth)
  % 递归收集块的结构项（块/线/mask 值），子系统副本的内容并入父指纹。
  % MAXDEPTH 防意外深递归：PLL -> VCO -> WrapAngle 实际需要 3 层。
  MAXDEPTH = 4;
  items = {};

  inner = find_system(blkPath, 'LookUnderMasks', 'all', ...
                      'FollowLinks', 'on', 'SearchDepth', 1, 'Type', 'Block');
  for i = 1:numel(inner)
    p = inner{i};
    if strcmp(p, blkPath), continue; end
    nm = relName(p, blkPath);
    if strcmp(nm, 'Fingerprint'), continue; end
    bt  = get_param(p, 'BlockType');
    val = keyParam(p, bt);
    items{end+1} = sprintf('B|%s|%s|%s', bt, nm, val); %#ok<AGROW>
    % 子系统副本：递归并入其内容与实例 mask 值
    % （改了 PI_discrete.slx 内部，所有装配它的父模块指纹都会变）
    if strcmp(bt, 'SubSystem') && depth < MAXDEPTH
      try
        if strcmp(get_param(p, 'Mask'), 'on')
          mv = get_param(p, 'MaskValues');
          if iscell(mv), mv = strjoin(mv, ','); end
          items{end+1} = sprintf('S|%s|M|%s', nm, char(string(mv))); %#ok<AGROW>
        end
      catch
      end
      sub = collectItems(p, depth + 1);
      for k = 1:numel(sub)
        items{end+1} = sprintf('S|%s|%s', nm, sub{k}); %#ok<AGROW>
      end
    end
  end

  lines = find_system(blkPath, 'LookUnderMasks', 'all', ...
                      'FollowLinks', 'on', 'FindAll', 'on', 'Type', 'Line');
  for i = 1:numel(lines)
    L = lines(i);
    sb = get_param(L, 'SrcBlockHandle');
    db = get_param(L, 'DstBlockHandle');
    sp = get_param(L, 'SrcPortHandle');
    dp = get_param(L, 'DstPortHandle');
    if sb <= 0 || isempty(db) || db(1) <= 0, continue; end
    items{end+1} = sprintf('L|%s|%d|%s|%d', ...
      relName(getfullname(sb), blkPath), portNum(sp), ...
      relName(getfullname(db(1)), blkPath), portNum(dp(1))); %#ok<AGROW>
  end

  % 本层 mask 参数值（实例值不同则指纹不同——PLL 里 PI 实例 Kp 是表达式）
  try
    if strcmp(get_param(blkPath, 'Mask'), 'on')
      mv = get_param(blkPath, 'MaskValues');
      if iscell(mv), mv = strjoin(mv, ','); end
      items{end+1} = sprintf('M|%s', char(string(mv))); %#ok<AGROW>
    end
  catch
  end
end

function a = findAnnotation(blkPath)
  % 返回子系统内文本以 FP_ 开头的第一个注释；没有则返回空
  a = [];
  try
    % 必须带 LookUnderMasks='all'：子系统被 mask 之后，内部注释对 find_system
    % 默认不可见，会误判为「没有指纹」而返回空串。
    anns = find_system(blkPath, 'LookUnderMasks', 'all', ...
                             'FindAll', 'on', 'Type', 'annotation');
  catch
    return;
  end
  for i = 1:numel(anns)
    t = get_param(anns(i), 'Text');
    if iscell(t), t = t{1}; end
    if startsWith(strtrim(char(string(t))), 'FP_')
      a = anns(i);
      return;
    end
  end
end
