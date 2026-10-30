%% fit_block_text.m — 把块拉伸到完全显示其图标内容所需的最小尺寸
%
%  为什么需要：R2023b 没有 resizeBlocksToFitContent（R2026b 才有）。
%  Constant / Gain / Goto / From / DataStoreRead/Write 等在图标上显示文本，
%  块太窄就退化成 "-K-" 占位符，这是 jm_0002（Mandatory）的违反。
%
%  做法：用无界面的 text 对象量出文本在给定字体下的像素宽，
%  加上图标内边距，得到需要的块宽；块高保持至少能容纳一行字。
%
%  用法：
%     fit_block_text(blk)            % 单个块
%     fit_block_text(blks)           % cell 数组
%     n = fit_block_text(mdl)        % 整个系统（递归，返回调整个数）
%
%  Verified on R2023b.

function n = fit_block_text(targets)
  if nargin < 1, error('用法: fit_block_text(blockOrCellOrModel)'); end

  if ischar(targets) && ~contains(targets, '/')
    % 模型名：递归处理所有层
    blks = find_system(targets, 'LookUnderMasks','all','FollowLinks','off', ...
                       'Type','block');
  elseif ischar(targets)
    blks = {targets};
  else
    blks = targets;
  end

  n = 0;
  for i = 1:numel(blks)
    if fit_one(blks{i}), n = n + 1; end
  end
end

% ---------------------------------------------------------------------------
function changed = fit_one(blk)
  changed = false;
  try
    bt = get_param(blk, 'BlockType');
  catch
    return;
  end

  txt = icon_text(blk, bt);
  if isempty(txt), return; end

  % 多行文本取最长一行
  lines = strsplit(txt, newline);
  widest = 0;
  for k = 1:numel(lines)
    widest = max(widest, text_width(lines{k}, blk));
  end
  if widest <= 0, return; end

  % 图标内边距：左右各 8，再留 4 给端口刻度
  needW = widest + 20;

  % 行高决定最小高度
  fsz = font_size(blk);
  lineH = line_height(fsz);
  needH = numel(lines) * lineH + 10;

  p0 = get_param(blk, 'Position');
  w = p0(3) - p0(1);
  h = p0(4) - p0(2);

  % 只放大不缩小；保持左上角略动以维持中心
  if w >= needW && h >= needH, return; end
  cx = (p0(1) + p0(3)) / 2;
  cy = (p0(2) + p0(4)) / 2;
  newW = max(w, needW);
  newH = max(h, needH);
  p = round([cx-newW/2, cy-newH/2, cx+newW/2, cy+newH/2]);
  try
    set_param(blk, 'Position', p);
    changed = true;
  catch
  end
end

% ---------------------------------------------------------------------------
function txt = icon_text(blk, bt)
  % 返回该块在图标上显示的文本；不显示的块返回 ''
  txt = '';
  switch bt
    case 'Gain'
      txt = get_param(blk, 'Gain');
    case 'Constant'
      txt = get_param(blk, 'Value');
    case {'Goto','From'}
      txt = get_param(blk, 'GotoTag');
    case 'DataStoreRead'
      txt = get_param(blk, 'DataStoreName');
    case 'DataStoreWrite'
      txt = get_param(blk, 'DataStoreName');
    case 'SubSystem'
      % 带 mask 的子系统显示说明；取首行
      try
        if strcmp(get_param(blk,'Mask'),'on')
          txt = get_param(blk, 'MaskDisplay');
          % MaskDisplay 是 disp('...') 形式，抽出引号内内容
          q = regexp(txt, '''([^'']*)''', 'tokens');
          if ~isempty(q), txt = q{1}{1}; else, txt = ''; end
        end
      catch
        txt = '';
      end
    otherwise
      % Sum / Product 等符号块不需要按文本加宽
      txt = '';
  end
  if ischar(txt), txt = strtrim(txt); end
  if iscell(txt), txt = ''; end
end

% ---------------------------------------------------------------------------
function w = text_width(s, blk)
  % 用无界面 text 对象量文本像素宽（R2023b 可用，避免手写经验系数）
  if isempty(s), w = 0; return; end
  persistent figH
  if isempty(figH) || ~ishandle(figH)
    figH = figure('Visible','off','HandleVisibility','off');
  end
  try
    t = text(0, 0, s, 'Parent', ax_of(figH), ...
             'FontName', font_name(blk), 'FontSize', font_size(blk), ...
             'Units', 'pixels');
    e = get(t, 'Extent');
    delete(t);
    w = e(3);
  catch
    % 退化：按字符数估（CJK 算两倍宽）
    w = est_width(s, font_size(blk));
  end
end

function ax = ax_of(figH)
  ax = get(figH, 'CurrentAxes');
  if isempty(ax), ax = axes('Parent', figH, 'Visible','off'); end
end

function w = est_width(s, fsz)
  % 粗略估计：ASCII 约 0.55*fsz，CJK 约 1.0*fsz
  w = 0;
  for k = 1:numel(s)
    if double(s(k)) > 127, w = w + fsz; else, w = w + 0.55*fsz; end
  end
end

function nm = font_name(blk)
  nm = 'Helvetica';
  try
    f = get_param(blk, 'FontName');
    if ischar(f) && ~isempty(f) && ~strcmp(f,'auto'), nm = f; end
  catch
  end
end

function fs = font_size(blk)
  fs = 10;
  try
    v = get_param(blk, 'FontSize');
    if isnumeric(v) && isscalar(v) && ~isempty(v) && v > 0, fs = v; end
  catch
  end
end

function h = line_height(fs)
  h = round(fs * 1.5);
end
