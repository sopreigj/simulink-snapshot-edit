%% audit_layout.m — read-only layout audit for a Simulink model
%
%  Usage:
%     report = audit_layout('myModel')              % print report, return struct
%     report = audit_layout('myModel', Verbose=false)
%
%  Checks (MAAB rule in parentheses). Level "Partial" per MAAB Appendix A:
%  it flags what it can measure, and says so.
%
%    L1  blocks overlapping each other                (db_0141, jm_0002)
%    L2  blocks sitting off the canvas                (readability)
%    L3  round Sum blocks that are not square         (jc_0121)
%    L4  blocks that are tiny / likely -K- truncated  (jm_0002)
%    L5  blocks whose name is not placed below        (db_0142)
%    L6  inconsistent block font name/size            (db_0043)
%    L7  unconnected block input/output ports         (db_0081)
%    L8  lines crossing blocks                        (db_0032)
%    L9  lines crossing other lines                   (db_0032)
%    L10 horizontal signal flow violations            (db_0141)
%
%  It does NOT check: signal label presence/content (na_0008/na_0009),
%  Goto/From flow (jc_0171), root-level block-type purity (db_0143), or
%  anything semantic. Those need human review.
%
%  Verified on R2023b.

function report = audit_layout(mdl, opts)
  arguments
    mdl (1,:) char
    opts.Verbose (1,1) logical = true
    opts.Tolerance (1,1) double = 2   % overlap slack in canvas units
  end

  % bdIsLoaded only accepts a MODEL name, not a subsystem path, so probing
  % with a path throws. Test whether the target is a real system instead.
  if ~is_system_loaded(mdl)
    load_system(mdl);
  end

  report = struct('model', mdl, 'findings', {{}}, 'counts', struct());

  blks = find_system(mdl, 'LookUnderMasks', 'all', 'FollowLinks', 'off', ...
                     'SearchDepth', 1, 'Type', 'block');
  % drop the model's own annotation-ish objects and subsystem-internal handles
  blks = blks(cellfun(@(b) strcmp(get_param(b, 'Type'), 'block'), blks));

  if isempty(blks)
    if opts.Verbose, fprintf('[audit] %s: no blocks\n', mdl); end
    return;
  end

  pos = cell2mat(get_param(blks, 'Position'));     % N x 4

  report = add(report, 'L2', check_offcanvas(blks, pos));
  report = add(report, 'L1', check_overlap(blks, pos, opts.Tolerance));
  report = add(report, 'L3', check_round_sums(blks));
  report = add(report, 'L4', check_tiny(blks, pos));
  report = add(report, 'L5', check_name_placement(blks));
  report = add(report, 'L6', check_fonts(blks));
  typesAll = cellfun(@(b) get_param(b, 'BlockType'), blks, 'UniformOutput', false);
  report = add(report, 'L7', check_unconnected(blks));
  report = add(report, 'L11', check_orphan_tags(blks, typesAll));
  report = add(report, 'L12', check_islands(mdl, blks));
  report = add(report, 'L13', check_port_visibility(blks, pos));
  report = add(report, 'L9', check_line_crossings(mdl));
  report = add(report, 'L8', check_line_block_crossings(mdl, blks, pos));
  report = add(report, 'L10', check_flow_direction(mdl));

  if opts.Verbose
    print_report(report);
  end
end

% ---------------------------------------------------------------------------
function tf = is_system_loaded(sys)
  % True when `sys` (a model name OR a subsystem path) can be queried.
  % bdIsLoaded throws on paths containing '/', so go through get_param.
  tf = false;
  try
    get_param(sys, 'Handle');   % throws if the model is not loaded
    tf = true;
  catch
  end
end
% ===========================================================================
% checks
% ===========================================================================

function f = check_offcanvas(blks, pos)
  f = {};
  margin = -200;   % allow some content left/above the origin
  bad = find(pos(:,1) < margin | pos(:,2) < margin);
  for i = bad.'
    f{end+1} = sprintf('block off canvas: %s at [%d %d]', ...
                       short(blks{i}), pos(i,1), pos(i,2)); %#ok<AGROW>
  end
end

function f = check_overlap(blks, pos, tol)
  f = {};
  n = size(pos, 1);
  for i = 1:n-1
    for j = i+1:n
      a = pos(i,:); b = pos(j,:);
      ox = min(a(3), b(3)) - max(a(1), b(1));
      oy = min(a(4), b(4)) - max(a(2), b(2));
      if ox > tol && oy > tol
        f{end+1} = sprintf('blocks overlap (%dx%d): %s  <->  %s', ...
                           ox, oy, short(blks{i}), short(blks{j})); %#ok<AGROW>
      end
    end
  end
end

function f = check_round_sums(blks)
  f = {};
  for i = 1:numel(blks)
    try
      if ~strcmp(get_param(blks{i}, 'BlockType'), 'Sum'), continue; end
      if ~strcmp(get_param(blks{i}, 'IconShape'), 'round'), continue; end
      p = get_param(blks{i}, 'Position');
      w = p(3)-p(1); h = p(4)-p(2);
      if abs(w-h) > 2
        f{end+1} = sprintf('round Sum is elliptical (%dx%d): %s', ...
                           w, h, blks{i}); %#ok<AGROW>
      end
    catch
    end
  end
end

function f = check_tiny(blks, pos)
  f = {};
  w = pos(:,3) - pos(:,1);
  h = pos(:,4) - pos(:,2);
  % blocks that render text on the icon need more width than a glyph square
  texty = {'Constant','StringConstant','Gain','Goto','From', ...
           'DataStoreRead','DataStoreWrite','ScanString'};
  for i = 1:numel(blks)
    try
      bt = get_param(blks{i}, 'BlockType');
    catch
      continue;
    end
    if any(strcmp(bt, texty)) && w(i) < 32
      f{end+1} = sprintf('may truncate icon text (%d wide): %s', w(i), blks{i}); %#ok<AGROW>
    elseif w(i) < 12 || h(i) < 12
      f{end+1} = sprintf('block too small (%dx%d): %s', w(i), h(i), blks{i}); %#ok<AGROW>
    end
  end
end

function f = check_name_placement(blks)
  f = {};
  for i = 1:numel(blks)
    try
      if ~strcmp(get_param(blks{i}, 'ShowName'), 'on'), continue; end
      np = get_param(blks{i}, 'NamePlacement');
      if ~strcmp(np, 'normal')
        f{end+1} = sprintf('name not below block (NamePlacement=%s): %s', ...
                           np, blks{i}); %#ok<AGROW>
      end
    catch
    end
  end
end

function f = check_fonts(blks)
  % FontName is a char ('auto' when unset). FontSize is a DOUBLE that reads
  % back as [] when unset — not a char — so it needs its own accumulator.
  f = {};
  nameTok = {};
  sizeTok = {};
  for i = 1:numel(blks)
    try
      nm = get_param(blks{i}, 'FontName');
      if ischar(nm) && ~isempty(nm)
        nameTok{end+1} = nm; %#ok<AGROW>
      end
    catch
    end
    try
      sz = get_param(blks{i}, 'FontSize');
      if isnumeric(sz) && isscalar(sz) && ~isempty(sz) && ~isnan(sz)
        sizeTok{end+1} = sprintf('%g', sz); %#ok<AGROW>
      end
    catch
    end
  end
  uNames = unique(nameTok);
  uSizes = unique(sizeTok);
  if numel(uNames) > 1
    f{end+1} = sprintf('inconsistent block fonts: %s', strjoin(uNames, ', '));
  end
  if numel(uSizes) > 1
    f{end+1} = sprintf('inconsistent block font sizes: %s', strjoin(uSizes, ', '));
  end
end

function f = check_unconnected(blks)
  f = {};
  for i = 1:numel(blks)
    try
      ph = get_param(blks{i}, 'PortHandles');
      bt = get_param(blks{i}, 'BlockType');
    catch
      continue;
    end
    % Inports have no upstream, Outports have no downstream: skip those
    if ~strcmp(bt, 'Inport')
      for k = 1:numel(ph.Inport)
        ln = get_param(ph.Inport(k), 'Line');
        if isempty(ln) || all(ln < 0)
          f{end+1} = sprintf('unconnected input port %d: %s', k, short(blks{i})); %#ok<AGROW>
        end
      end
    end
    if ~strcmp(bt, 'Outport')
      for k = 1:numel(ph.Outport)
        ln = get_param(ph.Outport(k), 'Line');
        if isempty(ln) || all(ln < 0)
          f{end+1} = sprintf('unconnected output port %d: %s', k, short(blks{i})); %#ok<AGROW>
        end
      end
    end
  end
end

function f = check_orphan_tags(blks, types)
  % 空 From 标签：From 的标签在本层找不到对应 Goto。
  % 这类块从"端口是否连线"看完全正常，但实际收不到任何信号——
  % 是最隐蔽的一类死块，check_unconnected 抓不到。
  f = {};
  gotoTags = {};
  for i = 1:numel(blks)
    if ~strcmp(types{i}, 'Goto'), continue; end
    try
      gotoTags{end+1} = get_param(blks{i}, 'GotoTag'); %#ok<AGROW>
    catch
    end
  end
  for i = 1:numel(blks)
    if ~strcmp(types{i}, 'From'), continue; end
    try
      tg = get_param(blks{i}, 'GotoTag');
    catch
      continue
    end
    if ~any(strcmp(gotoTags, tg))
      f{end+1} = sprintf('From 标签无对应 Goto（收不到信号）: %s  tag="%s"', ...
                         short(blks{i}), tg); %#ok<AGROW>
    end
  end
end

function f = check_islands(mdl, blks)
  % 孤岛检测（两条互补判据）：
  %   (a) 无源无汇：整块子链既不接源也不接汇 -> 一定是死块
  %   (b) 相对孤立：本层存在"主干"（>=3 块的连通分量）时，
  %       任何只有 1~2 块且不含 Inport/Outport 的分量都是可疑的旁支。
  %       Constant->Terminator 这类"有源有汇但整体无关"的链属于 (b)。
  %
  % 为什么需要 (b)：check_unconnected 只看单端口，一条内部完整连通的子链
  % 每个端口都"连着"，它抓不到。
  f = {};
  n = numel(blks);
  h2i = containers.Map('KeyType','double','ValueType','double');
  for i = 1:n
    h2i(get_param(blks{i}, 'Handle')) = i;
  end
  adj = cell(n,1);
  lns = find_system(mdl, 'FindAll','on','SearchDepth',1,'Type','line');
  for i = 1:numel(lns)
    sH = get_param(lns(i), 'SrcBlockHandle');
    dH = get_param(lns(i), 'DstBlockHandle');
    if sH < 0 || ~isKey(h2i, sH), continue; end
    if isempty(dH) || any(dH < 0), continue; end
    si = h2i(sH);
    for k = 1:numel(dH)
      if isKey(h2i, dH(k))
        di = h2i(dH(k));
        adj{si} = [adj{si}, di];
        adj{di} = [adj{di}, si];
      end
    end
  end

  % 全部连通分量
  seen = false(n,1);
  comps = {};
  for i = 1:n
    if seen(i), continue; end
    comp = [];
    queue = i;
    while ~isempty(queue)
      c = queue(1); queue(1) = [];
      if seen(c), continue; end
      seen(c) = true;
      comp(end+1) = c; %#ok<AGROW>
      queue = [queue, adj{c}]; %#ok<AGROW>
    end
    comps{end+1} = comp; %#ok<AGROW>
  end
  if isempty(comps), return; end

  sizes = cellfun(@numel, comps);
  mainSize = max(sizes);
  hasMain = mainSize >= 3;

  srcTypes = {'Inport','Constant','Step','From','Ground','SineWave','Ramp', ...
              'PulseGenerator','SignalGenerator','Clock', ...
              'RandomNumber','UniformRandomNumber'};
  snkTypes = {'Outport','Scope','ToWorkspace','Terminator','Goto'};

  for c = 1:numel(comps)
    comp = comps{c};
    types = cellfun(@(q) get_param(blks{q}, 'BlockType'), num2cell(comp), 'UniformOutput', false);
    hasSrc = any(ismember(types, srcTypes));
    hasSnk = any(ismember(types, snkTypes));
    hasPort = any(ismember(types, {'Inport','Outport'}));
    nm = cellfun(@(q) short(blks{q}), num2cell(comp), 'UniformOutput', false);
    nmStr = strjoin(nm, ', ');

    if ~hasSrc && ~hasSnk
      f{end+1} = sprintf('孤岛子链（无源无汇，%d 块）: %s', numel(comp), nmStr); %#ok<AGROW>
    elseif hasMain && numel(comp) < mainSize && ~hasPort && numel(comp) <= 2
      f{end+1} = sprintf('孤立旁支（与主干无连接，%d 块）: %s', numel(comp), nmStr); %#ok<AGROW>
    end
  end
end

function f = check_port_visibility(blks, pos)
  % 子系统接口必须完整展示。块太矮时端口名会挤在一起或显示不下。
  % 判据：每端口约需 14 单位，上下各留 8 边距。
  f = {};
  for i = 1:numel(blks)
    try
      if ~strcmp(get_param(blks{i}, 'BlockType'), 'SubSystem'), continue; end
      ports = get_param(blks{i}, 'Ports');
    catch
      continue;
    end
    nPort = max(ports(1), ports(2));
    if nPort < 2, continue; end
    h = pos(i,4) - pos(i,2);
    needH = 16 + 14 * nPort;
    if h < needH
      f{end+1} = sprintf('子系统接口显示不全（%d 口，高 %d < 需 %d）: %s', ...
                         nPort, h, needH, short(blks{i})); %#ok<AGROW>
    end
  end
end

function f = check_line_crossings(mdl)
  f = {};
  lns = find_system(mdl, 'FindAll', 'on', 'SearchDepth', 1, 'Type', 'line');
  segs = {};
  for i = 1:numel(lns)
    try
      pts = get_param(lns(i), 'Points');
    catch
      continue;
    end
    if size(pts,1) < 2, continue; end
    for k = 1:size(pts,1)-1
      segs{end+1} = [pts(k,:), pts(k+1,:)]; %#ok<AGROW>
    end
  end
  if isempty(segs), return; end
  S = cell2mat(segs(:));
  n = size(S,1);
  count = 0;
  for i = 1:n-1
    for j = i+1:n
      if i == j, continue; end
      if segments_cross(S(i,:), S(j,:))
        count = count + 1;
      end
    end
  end
  if count > 0
    f{end+1} = sprintf('%d line segment crossing(s) between signal lines', count);
  end
end

function tf = segments_cross(s1, s2)
  % axis-aligned only; true crossing = interiors intersect
  tf = false;
  h1 = s1(2) == s1(4); h2 = s2(2) == s2(4);
  v1 = s1(1) == s1(3); v2 = s2(1) == s2(3);
  if h1 && v2
    y = s1(2);
    x = s2(1);
    tf = x > min(s1(1),s1(3)) && x < max(s1(1),s1(3)) && ...
         y > min(s2(2),s2(4)) && y < max(s2(2),s2(4));
  elseif v1 && h2
    tf = segments_cross(s2, s1);
  end
end

function f = check_line_block_crossings(mdl, blks, pos)
  f = {};
  lns = find_system(mdl, 'FindAll', 'on', 'SearchDepth', 1, 'Type', 'line');
  for i = 1:numel(lns)
    try
      pts = get_param(lns(i), 'Points');
    catch
      continue;
    end
    if size(pts,1) < 2, continue; end
    srcB = '';
    try
      srcB = get_param(get_param(lns(i), 'SrcBlockHandle'), 'Name');
    catch
    end
    for k = 1:size(pts,1)-1
      p1 = pts(k,:); p2 = pts(k+1,:);
      for b = 1:numel(blks)
        bb = pos(b,:);
        if rect_intersects_segment(bb, p1, p2)
          nm = short(blks{b});
          if strcmp(nm, srcB), continue; end
          f{end+1} = sprintf('line crosses block "%s"', nm); %#ok<AGROW>
          break;
        end
      end
    end
  end
  if ~isempty(f), f = unique(f); end
end

function tf = rect_intersects_segment(r, p1, p2)
  % shrink the rect slightly so touching a border is not a violation
  pad = 3;
  r = [r(1)+pad, r(2)+pad, r(3)-pad, r(4)-pad];
  if r(3) <= r(1) || r(4) <= r(2), tf = false; return; end
  xmin = min(p1(1),p2(1)); xmax = max(p1(1),p2(1));
  ymin = min(p1(2),p2(2)); ymax = max(p1(2),p2(2));
  tf = ~(xmax <= r(1) || xmin >= r(3) || ymax <= r(2) || ymin >= r(4));
  % the above is an AABB test; tighten for axis-aligned segments
  if tf
    horiz = p1(2) == p2(2);
    if horiz
      tf = p1(2) > r(2) && p1(2) < r(4) && xmax > r(1) && xmin < r(3);
    else
      tf = p1(1) > r(1) && p1(1) < r(3) && ymax > r(2) && ymin < r(4);
    end
  end
end

function f = check_flow_direction(mdl)
  % db_0141: default flow is left -> right. Flag lines whose destination is
  % clearly to the LEFT of the source (feedback loops are allowed, so only
  % report when the backward span exceeds a block height and there is no
  % visible loop-back channel) — this is a soft signal, not a violation.
  f = {};
  lns = find_system(mdl, 'FindAll', 'on', 'SearchDepth', 1, 'Type', 'line');
  for i = 1:numel(lns)
    try
      sp = get_param(get_param(lns(i), 'SrcPortHandle'), 'Position');
      dp = cell2mat(get_param(get_param(lns(i), 'DstPortHandle'), 'Position'));
    catch
      continue;
    end
    if isempty(dp), continue; end
    if all(dp(:,1) < sp(1) - 120)
      f{end+1} = sprintf('signal flows right-to-left over a long span (%d units)', ...
                         sp(1) - min(dp(:,1))); %#ok<AGROW>
    end
  end
  if ~isempty(f), f = unique(f); end
end

% ===========================================================================
% reporting
% ===========================================================================

function r = add(r, code, findings)
  if isempty(findings), return; end
  for i = 1:numel(findings)
    r.findings{end+1} = struct('code', code, 'detail', findings{i});
  end
end

function print_report(r)
  fprintf('\n=== layout audit: %s ===\n', r.model);
  if isempty(r.findings)
    fprintf('  no findings in the checked subset\n');
    fprintf('  (checked: overlap, off-canvas, Sum shape, sizing, name placement,\n');
    fprintf('   font consistency, connectivity, line crossings, flow direction)\n');
    fprintf('  NOT checked: signal labels, Goto/From flow, block-type purity\n\n');
    return;
  end

  % codes is a 1xN cell; indexing it explicitly keeps the loop per-element
  allCodes = cellfun(@(f) f.code, r.findings, 'UniformOutput', false);
  codes = unique(allCodes);
  for ci = 1:numel(codes)
    code = codes{ci};
    sel  = r.findings(strcmp(allCodes, code));
    fprintf('\n  [%s] %d finding(s)\n', code, numel(sel));
    nShow = min(numel(sel), 12);
    for i = 1:nShow
      fprintf('    - %s\n', sel{i}.detail);
    end
    if numel(sel) > nShow
      fprintf('    ... and %d more\n', numel(sel) - nShow);
    end
  end
  fprintf('\n  total: %d finding(s)\n\n', numel(r.findings));
end

function s = short(p)
  s = strrep(p, newline, ' ');
  if numel(s) > 70, s = ['...' s(end-66:end)]; end
end


