%% lib_build.m
%  程序化构建 Simulink 库块的公共助手
%
%  为什么需要这个文件：
%    无 GUI 环境下所有库块都必须用 add_block/add_line/set_param 生成。
%    若每个生成器各写一遍建块、接线、封装的代码，就会出现
%    "这个块的端口朝左、那个朝右""这个 mask 有说明、那个没有"这类不一致，
%    而它们恰恰是 D7（自解释）要消灭的东西。所以把模式收在这里，只写一次。
%
%  典型用法：
%    lib_build.reset('MyLib');
%    lib_build.subsystem('MyLib','Clark',{'ia','ib','ic'},{'alpha','beta'});
%    ... 在子系统内加块、接线 ...
%    lib_build.mask('MyLib/Clark','transform','Clark 变换（幅值不变）', ...
%                   struct('Name','abc','Type','edit','Value','[1 1 1]'));
%    lib_build.save('MyLib', 'lib/MyLib.slx');

classdef lib_build < handle
  methods (Static)

    function reset(libName)
      % 新建库；若已存在先关闭丢弃，保证每次生成都是干净起点
      if bdIsLoaded(libName)
        close_system(libName, 0);
      end
      new_system(libName, 'Library');
      open_system(libName);   % 无头环境下也需要 open 才能操作部分属性
    end

    function h = subsystem(libPath, name, inNames, outNames)
      % 建一个空子系统并直接按给定名字建好出入端口
      full = [libPath '/' name];
      add_block('simulink/Ports & Subsystems/Subsystem', full);
      Simulink.SubSystem.deleteContents(full);
      for i = 1:numel(inNames)
        add_block('simulink/Sources/In1', [full '/' inNames{i}], ...
                  'Position', [20, 40+(i-1)*60, 50, 54+(i-1)*60]);
      end
      for i = 1:numel(outNames)
        add_block('simulink/Sinks/Out1', [full '/' outNames{i}], ...
                  'Position', [400, 40+(i-1)*60, 430, 54+(i-1)*60]);
      end
      h = full;
    end

    function blk = gain(parent, name, val, pos)
      % 增益块；val 用字符串以支持表达式（避免浮点写死）
      if nargin < 4, pos = []; end
      blk = [parent '/' name];
      add_block('simulink/Math Operations/Gain', blk, 'Gain', num2str(val));
      if ~isempty(pos), set_param(blk, 'Position', pos); end
    end

    function blk = sum2(parent, name, signs, pos)
      % 加法块；signs 如 '+-' 或 '++'
      if nargin < 4, pos = []; end
      blk = [parent '/' name];
      add_block('simulink/Math Operations/Sum', blk, 'Inputs', signs);
      if ~isempty(pos), set_param(blk, 'Position', pos); end
    end

    function blk = product(parent, name, nIn, pos)
      if nargin < 4, pos = []; end
      blk = [parent '/' name];
      % nIn 可以是数字（输入个数）或字符串（如 '*/' 表示第一口乘第二口除）
      if isnumeric(nIn), nIn = num2str(nIn); end
      add_block('simulink/Math Operations/Product', blk, 'Inputs', nIn);
      if ~isempty(pos), set_param(blk, 'Position', pos); end
    end

    function blk = rounding(parent, name, op, pos)
      % 取整函数块；op 取 'floor' | 'ceil' | 'round' | 'fix'
      if nargin < 4, pos = []; end
      blk = [parent '/' name];
      add_block('simulink/Math Operations/Rounding Function', blk, 'Operator', op);
      if ~isempty(pos), set_param(blk, 'Position', pos); end
    end

    function blk = minmax(parent, name, fcn, nIn, pos)
      % 最值块；fcn 取 'min' | 'max'
      if nargin < 5, pos = []; end
      blk = [parent '/' name];
      add_block('simulink/Math Operations/MinMax', blk, 'Function', fcn, 'Inputs', num2str(nIn));
      if ~isempty(pos), set_param(blk, 'Position', pos); end
    end

    function blk = multiportSwitch(parent, name, nData, pos)
      % 多路开关：数据口 1..nData，控制口 nData+1（1 基选择，out = data[ctrl]）
      if nargin < 4, pos = []; end
      blk = [parent '/' name];
      add_block('simulink/Signal Routing/Multiport Switch', blk, 'Inputs', num2str(nData));
      if ~isempty(pos), set_param(blk, 'Position', pos); end
    end

    function blk = constant(parent, name, val, pos)
      if nargin < 4, pos = []; end
      blk = [parent '/' name];
      add_block('simulink/Sources/Constant', blk, 'Value', num2str(val));
      if ~isempty(pos), set_param(blk, 'Position', pos); end
    end

    function blk = trig(parent, name, op, pos)
      % 三角函数块；op 取 'sin' | 'cos' | 'atan2'
      if nargin < 4, pos = []; end
      blk = [parent '/' name];
      switch lower(op)
        case 'atan2'
          add_block('simulink/Math Operations/Trigonometric Function', blk, ...
                    'Operator', 'atan2');
        otherwise
          add_block('simulink/Math Operations/Trigonometric Function', blk, ...
                    'Operator', op);
      end
      if ~isempty(pos), set_param(blk, 'Position', pos); end
    end

    function blk = unitDelay(parent, name, Ts, pos)
      % 单位延迟；Ts 为字符串或数值，'-1' 表示继承
      if nargin < 4, pos = []; end
      blk = [parent '/' name];
      add_block('simulink/Discrete/Unit Delay', blk, 'SampleTime', num2str(Ts));
      if ~isempty(pos), set_param(blk, 'Position', pos); end
    end

    function blk = relational(parent, name, op, pos)
      % 关系运算；op 取 '>' | '<' | '>=' | '<=' | '==' | '~='
      if nargin < 4, pos = []; end
      blk = [parent '/' name];
      add_block('simulink/Logic and Bit Operations/Relational Operator', blk, ...
                'Operator', op);
      if ~isempty(pos), set_param(blk, 'Position', pos); end
    end

    function blk = mathFcn(parent, name, op, pos)
      % 数学函数块；op 取 'mod' | 'rem' | 'exp' | 'log' 等。
      % 注意：'abs' 不是 Math Function 的 Operator，是独立块——用 lib_build.abs。
      % 二元运算（mod/rem）自动出现第二输入口，由调用方接 Constant。
      if nargin < 4, pos = []; end
      blk = [parent '/' name];
      add_block('simulink/Math Operations/Math Function', blk, 'Operator', op);
      if ~isempty(pos), set_param(blk, 'Position', pos); end
    end

    function blk = absBlk(parent, name, pos)
      % 绝对值块（simulink/Math Operations/Abs）
      if nargin < 3, pos = []; end
      blk = [parent '/' name];
      add_block('simulink/Math Operations/Abs', blk);
      if ~isempty(pos), set_param(blk, 'Position', pos); end
    end

    function blk = switch3(parent, name, pos)
      % 三路 Switch：in1/in3 为数据，in2 为控制（>=0.5 通 in1）
      if nargin < 3, pos = []; end
      blk = [parent '/' name];
      add_block('simulink/Signal Routing/Switch', blk, ...
                'Criteria', 'u2 >= Threshold', 'Threshold', '0.5');
      if ~isempty(pos), set_param(blk, 'Position', pos); end
    end

    function blk = integrator(parent, name, pos)
      if nargin < 3, pos = []; end
      blk = [parent '/' name];
      add_block('simulink/Continuous/Integrator', blk);
      if ~isempty(pos), set_param(blk, 'Position', pos); end
    end

    function blk = matlabFcn(parent, name, code, nIn, pos)
      % MATLAB Function 块；无头环境下同样可写代码
      if nargin < 5, pos = []; end
      blk = [parent '/' name];
      add_block('simulink/User-Defined Functions/MATLAB Function', blk);
      % 修改函数体必须通过 Stateflow API
      rt = sfroot;
      ch = rt.find('-isa', 'Stateflow.EMChart', '-and', 'Path', blk);
      if isempty(ch)
        error('lib_build:noChart', '未能定位 %s 的 Stateflow 图表', blk);
      end
      ch.Script = code;
      if ~isempty(pos), set_param(blk, 'Position', pos); end
    end

    function line(libPath, src, dst)
      % 接线；src/dst 形如 'Blk/1'，相对 libPath 解析。
      %
      % add_line 三个参数 (bd, srcSpec, dstSpec)：
      %   bd      必须是**发生接线的那个系统本身**，如 'MyLib/SomeSub';
      %   srcSpec 是相对 bd 的块/端口写法，如 'in1/1'。
      % 实测排错过程（踩坑记录，保留备查）：
      %   add_line(libPath, [libPath '/in1/1'], ...)         -> InvSimulinkObjectName
      %   add_line(父库名, 'SomeSub/in1/1', ...)             -> AddLinePortNotInSystem
      %   只有 add_line(libPath, 'ia/1', ...) 成立。
      add_line(libPath, src, dst, 'autorouting', 'on');
    end

    function ph = portHandle(bd, spec, dir)
      % 把 'Blk/2' 解析成端口句柄。spec 是**相对 bd 的**块名。
      %
      % 为什么写成 static 方法而不是文件级局部函数：
      % 实测在 classdef 里从 static 方法调用同名局部函数会报
      % Simulink:Commands:TooFewInputArgs（参数个数对不上），
      % 定位成本很高且难复现。收进 methods 里就没有这个问题。
      idx = find(spec == '/', 1, 'last');
      if isempty(idx)
        error('lib_build:badPort', '端口写法应为 "Block/portindex"，收到 "%s"', spec);
      end
      fullPath = [bd '/' spec(1:idx-1)];
      portIdx  = str2double(spec(idx+1:end));
      if isnan(portIdx)
        error('lib_build:badPort', '端口序号非法：%s', spec);
      end

      % 字段名是 'Inport'（小写 p），不是 'InputPort'
      phs = get_param(fullPath, 'PortHandles');
      switch lower(dir)
        case 'in',  ports = phs.Inport;
        case 'out', ports = phs.Outport;
        otherwise,  error('lib_build:badDir', 'dir 只能是 in 或 out，收到 %s', dir);
      end
      if isempty(ports) || portIdx < 1 || portIdx > numel(ports)
        error('lib_build:noPort', '%s 没有第 %d 个 %s 端口（共 %d 个）', ...
              fullPath, portIdx, dir, numel(ports));
      end
      ph = ports(portIdx);
    end
    function mask(blk, cls, description, params)
      % 封装：功能类着色 + 中文一行说明 + 具名参数暴露（D7）
      %
      % params 为 struct 数组，每项需含 Name / Type（edit|checkbox|popup）
      % 以及可选 Value / Prompt。
      pal = lib_palette();

      if nargin < 4, params = struct([]); end

      set_param(blk, ...
        'Mask', 'on', ...
        'MaskType',                 cls, ...
        'MaskDescription',          description, ...
        'BackgroundColor',          pal.func(cls), ...
        'ForegroundColor',          pal.fg);

      if ~isempty(params)
        % 顺序很关键：MaskDisplay 里引用了参数名，必须先让 MaskVariables 就位，
        % 否则报 "输入变量 'K' 无法识别"。
        set_param(blk, 'MaskVariables',   buildMaskVars(params));
        set_param(blk, 'MaskPrompts',     {params.Prompt});
        set_param(blk, 'MaskStyleString', buildMaskStyles(params));
        set_param(blk, 'MaskValues',      {params.Value});
        set_param(blk, 'MaskDisplay',     buildMaskDisplay(cls, description, params));
      else
        set_param(blk, 'MaskDisplay',     buildMaskDisplay(cls, description, params));
      end
    end

    function inst = instantiate(parent, moduleName, instName, pos)
      % 把库模块的**副本**装进 parent（D2 的复制式装配）。
      %
      % 前提：源模块已加载（[<模块名>/<模块名>] 存在）；未加载则自动从
      % lib/blocks/<模块名>.slx 加载。源是模型而非库，add_block 即复制内容，
      % 副本带源模块内部的一切（含指纹注释）。
      %
      % 返回实例路径；实例的 mask 参数由调用方用 set_param 按名设置
      % （如 set_param(inst,'Kp','2*zeta*wn/k')——表达式在父级 mask 工作区求值）。
      if nargin < 4, pos = []; end
      src = [moduleName '/' moduleName];
      % 预检不能用 find_system（对未加载模型直接抛 SystemNotLoaded），
      % 用 bdIsLoaded 判断模型是否已加载，未加载则从文件加载。
      if ~bdIsLoaded(moduleName)
        blkFile = fullfile(fileparts(mfilename('fullpath')), 'blocks', [moduleName '.slx']);
        load_system(blkFile);
      end
      inst = [parent '/' instName];
      add_block(src, inst);
      if ~isempty(pos), set_param(inst, 'Position', pos); end
    end

    function save(libName, outFile)
      % 存盘并关闭（不留加载态，避免影响后续构建）
      parent = fileparts(outFile);
      if ~isempty(parent) && ~isfolder(parent)
        mkdir(parent);
      end
      save_system(libName, outFile);
      close_system(libName, 0);
    end
  end
end

%% ---------- mask 字符串拼装 ----------

function s = buildMaskVars(params)
  % MaskVariables 必须是 "name=@N" 的配对形式，用分号分隔。
  % 只写 "K,Ts" 会被 Simulink **静默丢弃**并替换成 Parameter1/Parameter2——
  % 不报错，但参数名全丢，MaskDisplay 里引用 K 时才会报错。这是实测踩到的。
  parts = cell(1, numel(params));
  for i = 1:numel(params)
    parts{i} = sprintf('%s=@%d', params(i).Name, i);
  end
  s = strjoin(parts, ';');
end

function s = buildMaskStyles(params)
  % R2023b 实测：MaskStyleString 用**逗号**分隔多个参数。
  % 'edit|edit' 与 'edit;edit' 都报 Simulink:Masking:UnrecognizedStyle。
  % popup 类型在风格串里仍写作 popup，候选项通过 MaskPrompts 的括号提供。
  parts = cell(1, numel(params));
  for i = 1:numel(params)
    p = params(i);
    switch lower(p.Type)
      case 'edit',     parts{i} = 'edit';
      case 'checkbox', parts{i} = 'checkbox';
      case 'popup',    parts{i} = 'popup';
      otherwise,       error('lib_build:badType', '未知参数类型 %s', p.Type);
    end
  end
  s = strjoin(parts, ',');
end

function s = buildMaskDisplay(cls, description, params)
  % 模块对外（图标）只显示简洁名称 = 说明的冒号前短名（"Clark 变换"、"SVPWM"）。
  % 详细说明写在模块点进去的内部（子系统顶部注释，polish_annotations.m 放置）
  % 与 MaskDescription（双击参数框可见）——用户 2026-10-22 最终指示。
  short = description;
  nl = strfind(short, newline);
  if ~isempty(nl), short = short(1:nl(1)-1); end
  for sep = ['：', ':']
    idx = strfind(short, sep);
    if ~isempty(idx), short = short(1:idx(1)-1); break; end
  end
  short = strtrim(short);
  if numel(short) > 12, short = [short(1:11) '…']; end
  s = sprintf('disp(''%s'');', escapeQuotes(short));
end

function s = escapeQuotes(s)
  s = strrep(s, '''', '''''');
end
