%% legend_collect.m — 收集某层可见的缩写候选（不写注释）
%
%  缩写候选来源：Goto/From 标签、Inport/Outport 名、Scope 名、
%  To Workspace 变量名、信号线名。不含常量值和块类型名。
%
%  用法：abbr = legend_collect('myModel')
%
function abbr = legend_collect(sys)
  if nargin < 1, error('用法: abbr = legend_collect(sys)'); end
  if ~is_loaded(sys)
    load_system(sys);
  end
  raw = {};

  blks = find_system(sys, 'SearchDepth', 1, 'Type', 'block');
  if isempty(blks)
    abbr = {};
    return
  end
  types = cellfun(@(b) get_param(b, 'BlockType'), blks, 'UniformOutput', false);

  for i = 1:numel(blks)
    bt = types{i};
    try
      if strcmp(bt, 'Goto') || strcmp(bt, 'From')
        raw{end+1} = get_param(blks{i}, 'GotoTag'); %#ok<AGROW>
      elseif strcmp(bt, 'Inport') || strcmp(bt, 'Outport')
        raw{end+1} = get_param(blks{i}, 'Name'); %#ok<AGROW>
      elseif strcmp(bt, 'Scope')
        raw{end+1} = get_param(blks{i}, 'Name'); %#ok<AGROW>
      elseif strcmp(bt, 'ToWorkspace')
        raw{end+1} = get_param(blks{i}, 'VariableName'); %#ok<AGROW>
      end
    catch
    end
  end

  lns = find_system(sys, 'FindAll', 'on', 'SearchDepth', 1, 'Type', 'line');
  for i = 1:numel(lns)
    try
      nm = get_param(lns(i), 'Name');
      if ischar(nm) && ~isempty(nm)
        raw{end+1} = nm; %#ok<AGROW>
      end
    catch
    end
  end

  junk = {'in', 'out', 'In1', 'Out1', 'SC', 'in1', 'out1'};
  keep = {};
  for i = 1:numel(raw)
    s = strtrim(raw{i});
    if isempty(s) || numel(s) > 12
      continue
    end
    if any(strcmp(s, junk))
      continue
    end
    if looks_like_abbrev(s)
      keep{end+1} = s; %#ok<AGROW>
    end
  end
  abbr = unique(keep);
end

function tf = looks_like_abbrev(s)
  % 含非 ASCII（希腊/中文）、含下划线、或短且含大写 -> 视为缩写
  tf = false;
  if any(double(s) > 127)
    tf = true;
    return
  end
  if any(s == '_')
    tf = true;
    return
  end
  hasUpper = any(upper(s) == s & ~ismember(upper(s), '0123456789'));
  if numel(s) <= 4 && hasUpper
    tf = true;
  end
end

function tf = is_loaded(sys)
  tf = false;
  try
    get_param(sys, 'Handle');
    tf = true;
  catch
  end
end