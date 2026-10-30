%% annotate_legend.m — 每层放置"缩写词表"注释
%
%  为什么：模型里满是一眼看不出来的缩写（θe、we、ua、TH、WE……）。
%  每个看到该层的人都得猜一遍。规范要求：顶层或每个子系统放一个词表注释，
%  列出该层可见缩写的全称与含义。
%
%  用法：
%     abbr = legend_collect(mdl)                    % 只看不写
%     annotate_legend(mdl)                          % 只列缩写，含义留 TODO
%     annotate_legend(mdl, 'Meanings', struct( ...
%        'we','电角速度 electrical angular speed', ...
%        'TH','电角度 electrical angle'))
%
%  位置：该层左上角（x=30, y=20），宽高自适应行数。
%  已存在则覆盖，不会重复堆叠（用 Tag 定位，不靠显示文本匹配）。
%
%  Verified on R2023b.

function annotate_legend(sys, opts)
  arguments
    sys  (1,:) char
    opts.Meanings struct = struct()
    opts.Title    (1,:) char = '缩写词表 Abbreviations'
    opts.Verbose  (1,1) logical = true
  end

  if ~is_loaded(sys)
    load_system(sys);
  end

  abbr = legend_collect(sys);
  if isempty(abbr)
    if opts.Verbose
      fprintf('[legend] %s: 未发现缩写\n', sys);
    end
    return
  end

  % ---- 组装文本：每行 "缩写 = 含义" ----
  lines = cell(1, numel(abbr));
  nTodo = 0;
  for i = 1:numel(abbr)
    a = abbr{i};
    if isfield(opts.Meanings, a)
      lines{i} = sprintf('%s = %s', a, opts.Meanings.(a));
    else
      lines{i} = sprintf('%s = TODO', a);
      nTodo = nTodo + 1;
    end
  end

  % ---- 写成注释（句柄 + get_param/set_param）----
  h = find_or_create_legend(sys);
  set_param(h, 'Name', strjoin([{opts.Title}, lines], newline));

  % 尺寸：宽度取最长行，高度按行数
  lh = 16;                                   % 每行像素高
  w  = max(cellfun(@numel, lines)) * 7 + 40;  % 每字符约 7 px
  hh = (numel(abbr) + 1) * lh + 12;
  % FixedWidth/FixedHeight 必须**先于** Position 设置，
  % 否则 Position 只被当成最小值，实际尺寸会缩回贴合文本
  set_param(h, 'FixedWidth',  'on');
  set_param(h, 'FixedHeight', 'on');
  set_param(h, 'Position', [30, 20, 30 + w, 20 + hh]);

  % 样式：浅底细字，不抢主结构
  try
    set_param(h, 'FontSize', '9');
    set_param(h, 'FontName', 'Helvetica');
  catch
  end

  if opts.Verbose
    fprintf('[legend] %s: %d 个缩写（%d 个待补）\n', sys, numel(abbr), nTodo);
    for i = 1:numel(abbr)
      if ~isfield(opts.Meanings, abbr{i})
        fprintf('          TODO: %s\n', abbr{i});
      end
    end
  end
end



% ---------------------------------------------------------------------------
function h = find_or_create_legend(sys)
  % 返回词表注释的**句柄**，不是 Simulink.Annotation 对象。
  % 用 Tag 定位；没有再建。句柄配合 get_param/set_param 用，
  % 比 Annotation 对象可靠——后者无法从已有句柄反构
  % （实测 Simulink.Annotation(mdl, name) 拿不到既有注释）。
  existing = find_system(sys, 'FindAll', 'on', 'Type', 'annotation');
  for i = 1:numel(existing)
    try
      if strcmp(get_param(existing(i), 'Tag'), 'ABBR_LEGEND')
        h = existing(i);
        return
      end
    catch
    end
  end
  a = Simulink.Annotation([sys '/__abbr_legend__']);
  try
    a.Tag = 'ABBR_LEGEND';
  catch
  end
  h = a.Handle;
end

function tf = is_loaded(sys)
  tf = false;
  try
    get_param(sys, 'Handle');
    tf = true;
  catch
  end
end
