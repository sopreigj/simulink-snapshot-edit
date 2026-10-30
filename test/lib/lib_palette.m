%% lib_palette.m
%  共用模块库的**唯一调色板定义**（D7：固定调色板）
%
%  为什么单独成文件而不散落在各生成器里：
%    颜色一旦分散，就会出现"同一个 Clark 在两个库里是两种蓝"，
%    读者对颜色的记忆失效，调色板就从"自解释"退化成噪音。
%    所有生成器与校验器都只能从这里取色。
%
%  用法：
%    pal = lib_palette();
%    pal.func('transform')      % -> 'lightBlue'
%    pal.label('transform')     % -> '坐标变换'

function pal = lib_palette()

  % 功能类 -> 背景色。
  % 注意：Simulink 具名颜色只有 black/white/red/green/blue/cyan/magenta/
  % yellow/gray/lightBlue/orange/lightGreen/darkGreen 这几个；
  % 'lightYellow'/'lightMagenta'/'lightGray' 不存在（实测报 BadSetParamValue），
  % 浅色一律用 RGB 向量字符串表达。
  bg = struct( ...
    'transform',   'lightBlue',    ...  % 坐标变换：Clark / Park / 反变换
    'estimator',   '[1 1 0.8]',    ...  % 观测与估计：PLL / SMO / LDO / DSO（浅黄）
    'control',     '[0.5 1 0.5]',  ...  % 控制环：PI（R2023b 无 lightGreen 具名色，实测）
    'modulation',  '[1 0.75 1]',   ...  % 调制与功率级：SVPWM / 逆变器（浅紫）
    'signal',      'orange',       ...  % 信号处理：BPF / LPF / 解调
    'measure',     'gray',         ...  % 测量与工况：转矩 / 转速给定 / 负载
    'machine',     'darkGreen',    ...  % 电机本体
    'aux',         'white'         ...  % 辅助：常量 / 复用 / 显示
  );

  % 功能类 -> 中文标签（写进 mask 的一行说明里，D9：release 全中文）
  label = struct( ...
    'transform',   '坐标变换', ...
    'estimator',   '观测与估计', ...
    'control',     '控制环', ...
    'modulation',  '调制与功率', ...
    'signal',      '信号处理', ...
    'measure',     '测量与工况', ...
    'machine',     '电机本体', ...
    'aux',         '辅助' ...
  );

  % 前景色统一用深色，保证在任何浅色背景上都可读
  pal.fg          = 'black';
  pal.background  = bg;
  pal.label       = label;

  pal.func = @(cls) getfield_safe(bg, cls);
  pal.name = @(cls) getfield_safe(label, cls);
  pal.canonical = @canonicalColor;
end

function name = canonicalColor(colorStr)
  % 返回 Simulink 对给定颜色设定的**规范名**。
  %
  % 为什么需要：set_param(bg,'[1 1 0.8]') 后 get_param 读回的是 'paleyellow'——
  % Simulink 会把 RGB 向量规范化/注册为具名颜色，字符串形式的比较会误判。
  % 校验脚本比较颜色时，一律拿设定值过一遍本函数再比。
  persistent cache
  if isempty(cache), cache = containers.Map(); end
  if isKey(cache, colorStr)
    name = cache(colorStr);
    return;
  end
  m = 'palprobe_tmp';
  if bdIsLoaded(m), close_system(m, 0); end
  new_system(m);
  add_block('simulink/Sources/Constant', [m '/C']);
  set_param([m '/C'], 'BackgroundColor', colorStr);
  name = get_param([m '/C'], 'BackgroundColor');
  close_system(m, 0);
  cache(colorStr) = name;
end

function v = getfield_safe(s, f)
  if isfield(s, f)
    v = s.(f);
  else
    error('lib_palette:unknownClass', ...
          '未知功能类 "%s"，可用类：%s', f, strjoin(fieldnames(s)', ', '));
  end
end
