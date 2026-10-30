%% snp_merge3.m — 快照三路合并（人机并发合并，协作三缺口的最后一块）
%
% WHY：snp_pull 只是两路（旧快照 + 新导出），覆盖"人先改 agent 后回流"的串行
% 场景；人与 agent **并发**改动同一模型时需要三路（base 共同祖先 / ours agent 侧
% / theirs 人侧）。M 快照是强结构化纯文本（节边界明确、块行有唯一键 rel），
% 因此合并不做通用 diff3 的行级 LCS，而做**键级合并**——远比自由文本可靠
% （按节边界与块行唯一键 rel 对齐，不做整行 LCS）。
%
% 两条路径：
%   1) 内置键级合并（默认）：按节/块名对齐，参数级正交自动合并——M 快照是
%      强结构化文本，键级合并远比行级 diff3 可靠
%   2) git fast path（opts.UseGit=true）：`git merge-file --diff3` 拿合并文本，
%      冲突区按裁决表处理（默认 theirs 优先——模型=唯一真相）。注意：行级
%      diff3 对"相邻行双方各改一处"会产生假冲突区（无块语义），故非默认
%
% 用法
%   rep = snp_merge3(baseFile, oursFile, theirsFile, outFile)
%   rep = snp_merge3(..., opts)  opts.UseGit（默认 false）/ opts.TheirsPriority（默认 true）
%
% rep 字段：
%   .nMerged      自动合并条目数（无冲突）
%   .nConflict    冲突条目数
%   .nOursKept    ours 侧改动被保留数
%   .nTheirsKept  theirs 侧改动被保留数
%   .conflictList 冲突键（块名/行键）cell
%   .strategy     实际使用的路径（'git' / 'builtin'）
%   .notes        说明行
%
% 裁决表（与设计文档一致）：
%   双方改同一键且不同     → 冲突 → theirs（可被 opts.TheirsPriority=false 翻转）
%   一方删键另一方改该键   → 冲突 → 删优先（结构性意图强于参数意图）
%   双方加同名键内容不同   → 冲突 → theirs + 报警
%   其余（单方改/正交）    → 自动合并
function rep = snp_merge3(baseFile, oursFile, theirsFile, outFile, opts)
  if nargin < 5, opts = struct(); end
  if ~isfield(opts, 'UseGit'), opts.UseGit = false; end
  if ~isfield(opts, 'TheirsPriority'), opts.TheirsPriority = true; end
  rep = struct('nMerged', 0, 'nConflict', 0, 'nOursKept', 0, 'nTheirsKept', 0, ...
    'strategy', '', 'notes', {{}});
  rep.conflictList = cell(1, 0);

  baseTxt = fileread(baseFile);
  oursTxt = fileread(oursFile);
  theirsTxt = fileread(theirsFile);

  useGit = opts.UseGit && git_available(rep);
  if useGit
    try
      [outTxt, rep] = merge_via_git(baseTxt, oursTxt, theirsTxt, opts, rep);
      rep.strategy = 'git';
      if isempty(outTxt)
        useGit = false;
        rep.notes{end+1} = 'git 路径失败，退化为内置键级合并'; %#ok<AGROW>
      end
    catch e
      useGit = false;
      rep.notes{end+1} = ['git 路径异常: ' strrep(e.message, sprintf('\n'), ' ')]; %#ok<AGROW>
    end
  end
  if ~useGit
    [outTxt, rep] = merge_builtin(baseTxt, oursTxt, theirsTxt, opts, rep);
    rep.strategy = 'builtin';
  end

  fid = fopen(outFile, 'w', 'n', 'UTF-8');
  fprintf(fid, '%s', outTxt);
  fclose(fid);
  % T58：conflictList 出口统一成裸块名（内部键是 [m '/X'] 路径形态，消费方期望裸名）
  rep.conflictList = strip_lead_slash(rep.conflictList);
  rep.notes{end+1} = sprintf('合并写出: %s', outFile); %#ok<AGROW>
end

%% ==================== git fast path ====================

function tf = git_available(rep)
  tf = false;
  try
    [st, ~] = system('git --version');
    tf = (st == 0);
  catch
  end
  if ~tf, rep.notes{end+1} = 'git 不可用，使用内置键级合并'; end %#ok<AGROW>
end

function [outTxt, rep] = merge_via_git(baseTxt, oursTxt, theirsTxt, opts, rep)
  outTxt = '';
  % 行尾统一：snp_export 快照在 Windows text 模式下写 CRLF，而文本编辑产物常是 LF；
  % 不统一会让 git merge-file 把整节判成一个冲突区
  NL = sprintf('\n');
  baseTxt = strrep(baseTxt, sprintf('\r\n'), NL);
  oursTxt = strrep(oursTxt, sprintf('\r\n'), NL);
  theirsTxt = strrep(theirsTxt, sprintf('\r\n'), NL);
  d = tempname; mkdir(d);
  bf = fullfile(d, 'base.m'); of = fullfile(d, 'ours.m'); tf2 = fullfile(d, 'theirs.m');
  write_text(bf, baseTxt); write_text(of, oursTxt); write_text(tf2, theirsTxt);
  % -p 输出到 stdout（不写回 ours）；--diff3 冲突区含 base 段
  cmd = sprintf('git merge-file -p --diff3 "%s" "%s" "%s"', of, bf, tf2);
  [st, mergedTxt] = system(cmd);
  if st > 1
    rep.notes{end+1} = sprintf('git merge-file 失败 status=%d', st); %#ok<AGROW>
    return;
  end
  if st == 0
    outTxt = mergedTxt;
    rep.notes{end+1} = 'git: 干净合并（无冲突区）'; %#ok<AGROW>
    rep = annotate_clean(baseTxt, oursTxt, theirsTxt, rep);
    return;
  end
  % st == 1：有冲突区 → 解析标记并在 M 语义层裁决
  [outTxt, rep] = resolve_git_conflicts(mergedTxt, opts, rep);
end

function write_text(f, txt)
  fid = fopen(f, 'w', 'n', 'UTF-8');
  fprintf(fid, '%s', txt);
  fclose(fid);
end

function [outTxt, rep] = resolve_git_conflicts(mergedTxt, opts, rep)
  raw = strsplit(mergedTxt, {'\r\n', '\n'}, 'CollapseDelimiters', true);
  out = cell(1, 0);          % 水平拼接：统一 1×N
  state = 0;                 % 0 正文 1 ours 2 base 3 theirs
  oursC = cell(1, 0); baseC = cell(1, 0); theirsC = cell(1, 0);
  for i = 1:numel(raw)
    L = raw{i};
    t = strtrim(L);
    if startsWith(t, '<<<<<<<')
      state = 1; oursC = cell(1, 0); baseC = cell(1, 0); theirsC = cell(1, 0);
      continue;
    elseif startsWith(t, '|||||||')
      state = 2; continue;
    elseif strcmp(t, '=======')
      state = 3; continue;
    elseif startsWith(t, '>>>>>>>')
      keep = theirsC; side = 'theirs';
      if ~opts.TheirsPriority, keep = oursC; side = 'ours'; end
      out = [out, keep]; %#ok<AGROW>
      rep.nConflict = rep.nConflict + 1;
      key = conflict_key([oursC, theirsC]);
      rep.conflictList{end+1} = key; %#ok<AGROW>
      kk = strip_lead_slash({key});  % T58：notes 也用裸块名（出口统一）
      rep.notes{end+1} = sprintf('冲突 %s → 取 %s', kk{1}, side); %#ok<AGROW>
      state = 0;
      continue;
    end
    switch state
      case 0, out = [out, {L}]; %#ok<AGROW>
      case 1, oursC = [oursC, {L}]; %#ok<AGROW>
      case 2, baseC = [baseC, {L}]; %#ok<AGROW>
      case 3, theirsC = [theirsC, {L}]; %#ok<AGROW>
    end
  end
  outTxt = sprintf('%s\n', strjoin(out, sprintf('\n')));
end

function key = conflict_key(lines)
  % 从冲突行提取块名（[m '/X']）有序去重拼接，分号分隔（多块时 'A; B'，
  % 不用斜杠连接——子系统路径本身含 /，斜杠拼接会把 A/B 读成子路径）；
  % 否则用 add_line 的端口对，否则前导 40 字符
  segs = cell(1, 0);
  for i = 1:numel(lines)
    tok = regexp(strtrim(lines{i}), "\[m '/([^']+)'\]", 'tokens', 'once');
    if ~isempty(tok)
      seg = tok{1};
      if ~any(strcmp(segs, seg)), segs{end+1} = seg; end %#ok<AGROW>
    end
  end
  key = strjoin(segs, '; ');
  if isempty(key)
    for i = 1:numel(lines)
      tok = regexp(strtrim(lines{i}), "'([^|]+)\|\s*([^']+)'\s*,", 'tokens', 'once');
      if ~isempty(tok), key = ['line:' tok{1} '|' tok{2}]; return; end
    end
  end
  if isempty(key) && ~isempty(lines)
    key = ['txt:' lines{1}(1:min(40, numel(lines{1})))];
  end
end

function rep = annotate_clean(baseTxt, oursTxt, theirsTxt, rep)
  % git 干净合并时补键级统计
  b = block_keys(baseTxt); o = block_keys(oursTxt); t = block_keys(theirsTxt);
  chO = setdiff(o, b); chT = setdiff(t, b);
  rep.nOursKept = numel(chO); rep.nTheirsKept = numel(chT);
  rep.nMerged = numel(chO) + numel(chT);
end

function ks = block_keys(txt)
  ks = regexp(txt, "\[m '/([^']+)'\]", 'tokens');
  ks = cellfun(@(c) c{1}, ks, 'UniformOutput', false);
end

%% ==================== 内置键级三路合并（fallback / 语义口径）====================

function [outTxt, rep] = merge_builtin(baseTxt, oursTxt, theirsTxt, opts, rep)
  B = parse_snap(baseTxt); O = parse_snap(oursTxt); T = parse_snap(theirsTxt);
  kinds = {'header', 'config', 'callback', 'ws', 'blocks', 'lines', 'annotations', 'tail'};
  out = cell(1, 0);
  nConflict = 0; nMerged = 0; nO = 0; nT = 0; confs = cell(1, 0);
  for k = 1:numel(kinds)
    kd = kinds{k};
    bs = get_section(B, kd); os = get_section(O, kd); ts = get_section(T, kd);
    if isempty(bs) && isempty(os) && isempty(ts), continue; end
    % 节标记行（% ---- X ----）三份通常相同，前置保留（key_map 会跳过注释）
    markers = cell(1, 0);
    for q = 1:numel(bs)
      if ~isempty(regexp(strtrim(bs{q}), '^%+\s*----', 'once')), markers = [markers, {bs{q}}]; end
    end
    if strcmp(kd, 'blocks') || strcmp(kd, 'lines')
      [merged, r] = merge_keyed(bs, os, ts, opts);
      merged = [markers, merged];
    else
      merged = [markers, merge_lines(bs, os, ts)];
      r = empty_r();
      if strcmp(kd, 'header')
        % T57：三方快照函数名不同时，header 节会保留多条 function 声明
        % → 合并文件非法。只保留第一条 + notes 报警（真实工作流三方本就同名）
        fnIdx = find(cellfun(@(L) ...
          ~isempty(regexp(strtrim(L), '^function\s', 'once')), merged));
        if numel(fnIdx) > 1
          firstFn = strtrim(merged{fnIdx(1)});
          merged(setdiff(fnIdx, fnIdx(1))) = [];
          rep.notes{end+1} = sprintf( ...
            'header 检测到 %d 条 function 声明（三方快照函数名不同？），只保留第一条: %s', ...
            numel(fnIdx), firstFn);  %#ok<AGROW>
        end
      end
    end
    out = [out, merged]; %#ok<AGROW>
    nMerged = nMerged + r.nMerged; nConflict = nConflict + r.nConflict;
    nO = nO + r.nOursKept; nT = nT + r.nTheirsKept; confs = [confs, r.conflictList]; %#ok<AGROW>
  end
  rep.nMerged = rep.nMerged + nMerged;
  rep.nConflict = rep.nConflict + nConflict;
  rep.nOursKept = rep.nOursKept + nO;
  rep.nTheirsKept = rep.nTheirsKept + nT;
  rep.conflictList = [rep.conflictList, confs];
  outTxt = sprintf('%s\n', strjoin(out, sprintf('\n')));
end

function r = empty_r()
  % 不能用 struct('conflictList', cell(1,0))——非标量 cell 值会把 struct 广播成 1×0
  r = struct('nMerged', 0, 'nConflict', 0, 'nOursKept', 0, 'nTheirsKept', 0);
  r.conflictList = cell(1, 0);
end

%% ---------- 快照解析：节 + 键化条目 ----------

function S = parse_snap(txt)
  lines = strsplit(txt, {'\r\n', '\n'}, 'CollapseDelimiters', true);
  S = struct('kind', {}, 'title', {}, 'lines', {});
  cur = cell(1, 0); curKind = 'header'; curTitle = '';
  for i = 1:numel(lines)
    L = lines{i};
    m = regexp(strtrim(L), '^%+\s*----\s*(.*?)\s*----\s*$', 'tokens', 'once');
    if ~isempty(m)
      S = push_section(S, curKind, curTitle, cur);
      curTitle = m{1}; curKind = kind_of(curTitle); cur = {L};
    else
      cur = [cur, {L}]; %#ok<AGROW>
    end
  end
  S = push_section(S, curKind, curTitle, cur);
end

function S = push_section(S, kind, title, lines)
  if isempty(lines), return; end
  S(end+1).kind = kind;
  S(end).title = title;
  S(end).lines = lines;
end

function kd = kind_of(title)
  t = lower(title);
  if contains(t, 'block'), kd = 'blocks';
  elseif contains(t, 'line'), kd = 'lines';
  elseif contains(t, 'annotation'), kd = 'annotations';
  elseif contains(t, 'workspace'), kd = 'ws';
  elseif contains(t, 'callback'), kd = 'callback';
  elseif contains(t, 'solver') || contains(t, 'config'), kd = 'config';
  else, kd = 'tail';
  end
end

function sec = get_section(S, kind)
  sec = cell(1, 0);
  for i = 1:numel(S)
    if strcmp(S(i).kind, kind), sec = [sec, S(i).lines]; end %#ok<AGROW>
  end
end

%% ---------- 键级三路（blocks / lines 节）----------

function [out, r] = merge_keyed(bs, os, ts, opts)
  r = empty_r();
  [bMap, bOrd] = key_map(bs);
  [oMap, oOrd] = key_map(os);
  [tMap, tOrd] = key_map(ts);
  keys = ordered_union(bOrd, oOrd, tOrd);
  out = cell(1, 0);
  for i = 1:numel(keys)
    k = keys{i};
    b = []; o = []; t = [];
    if bMap.isKey(k), b = bMap(k); end
    if oMap.isKey(k), o = oMap(k); end
    if tMap.isKey(k), t = tMap(k); end
    [grp, act, key2] = decide(k, b, o, t, opts);
    switch act
      case 'merged'
        out = [out, grp]; r.nMerged = r.nMerged + 1; %#ok<AGROW>
      case 'ours'
        out = [out, grp]; r.nOursKept = r.nOursKept + 1; %#ok<AGROW>
      case 'theirs'
        out = [out, grp]; r.nTheirsKept = r.nTheirsKept + 1; %#ok<AGROW>
      case 'conflict_theirs'
        out = [out, grp]; r.nConflict = r.nConflict + 1; %#ok<AGROW>
        r.conflictList{end+1} = key2; r.nTheirsKept = r.nTheirsKept + 1; %#ok<AGROW>
      case 'conflict_ours'
        out = [out, grp]; r.nConflict = r.nConflict + 1; %#ok<AGROW>
        r.conflictList{end+1} = key2; r.nOursKept = r.nOursKept + 1; %#ok<AGROW>
      case 'deleted_conflict'
        % 删优先：不输出该键，但入冲突清单（结构性意图强于参数意图）
        r.nConflict = r.nConflict + 1;
        r.conflictList{end+1} = key2;
      case 'deleted'
        % 干净删除：不输出
    end
  end
end

function [grp, act, key] = decide(~, b, o, t, opts)
  % 冲突键先算：各 return 分支都会带上正确 key（末尾的兜底不可达）
  key = '';
  if ~isempty(o), key = conflict_key(o); end
  if isempty(key) && ~isempty(t), key = conflict_key(t); end
  if isempty(key), key = 'unknown'; end
  ob = ~isempty(b); oo = ~isempty(o); ot = ~isempty(t);
  if oo && ot && isequal(o, t)
    act = 'merged'; grp = o; return;
  end
  if ob
    if oo && ot
      if isequal(o, b), act = 'theirs'; grp = t; return; end
      if isequal(t, b), act = 'ours'; grp = o; return; end
      % 双方都改且不同 → 冲突（模型=唯一真相 → 默认 theirs）
      if opts.TheirsPriority, act = 'conflict_theirs'; grp = t;
      else, act = 'conflict_ours'; grp = o; end
      return;
    end
    if oo && ~ot   % theirs 删
      if isequal(o, b), act = 'deleted'; grp = {}; return; end
      act = 'deleted_conflict'; grp = {}; return;   % 一方删一方改 → 删优先+冲突
    end
    if ot && ~oo   % ours 删
      if isequal(t, b), act = 'deleted'; grp = {}; return; end
      act = 'deleted_conflict'; grp = {}; return;
    end
    act = 'deleted'; grp = {}; return;  % 双方都删
  else
    if oo && ot && ~isequal(o, t)
      if opts.TheirsPriority, act = 'conflict_theirs'; grp = t;
      else, act = 'conflict_ours'; grp = o; end
      return;  % 双方加同名不同内容
    end
    if oo, act = 'ours'; grp = o; return; end
    if ot, act = 'theirs'; grp = t; return; end
    act = 'merged'; grp = {};
  end
end

function [map, order] = key_map(lines)
  % 把节内行拆成"键 → 行组"：块以 add_block 行为头（含其附属行）；
  % lines 节以 add_line 的 'src','dst' 为键；其余非注释行以内容归一化为键
  map = containers.Map('KeyType', 'char', 'ValueType', 'any');
  order = cell(1, 0);
  n = numel(lines);
  i = 1;
  while i <= n
    L = lines{i};
    if is_blank_or_comment(L)
      i = i + 1; continue;
    end
    key = '';
    if startsWith(strtrim(L), 'add_block(')
      key = extract_rel(L);
    elseif startsWith(strtrim(L), 'add_line(')
      key = extract_line_key(L);
    else
      key = ['raw:' regexprep(strtrim(L), '\s+', ' ')];
    end
    grp = {L}; i = i + 1;
    if startsWith(strtrim(L), 'add_block(')
      while i <= n && is_affix(lines, i)
        grp = [grp, {lines{i}}]; i = i + 1; %#ok<AGROW>
      end
    end
    map(key) = grp;
    order = [order, {key}]; %#ok<AGROW>
  end
end

function tf = is_blank_or_comment(L)
  t = strtrim(L);
  tf = isempty(t) || t(1) == '%';
end

function tf = is_affix(lines, i)
  % 块附属行：rtc 行 / chart 内容标记组 / mask 行（复用 snp_pull 语义）
  L = lines{i};
  if contains(L, 'rtc'), tf = true; return; end
  t = strtrim(L);
  if startsWith(t, '% ---- chart') && (contains(t, '内容') || contains(t, 'end ----'))
    tf = true; return;
  end
  if contains(L, 'Simulink.Mask.create') || contains(L, '.addParameter('), tf = true; return; end
  if contains(L, 'Stateflow.State(') || contains(L, 'Stateflow.Transition('), tf = true; return; end
  % chart 组内行：向前找最近的 chart 标记（未遇 end 即组内）
  j = i - 1;
  while j >= 1
    P = strtrim(lines{j});
    if startsWith(P, '% ---- chart') && contains(P, 'end ----'), tf = false; return; end
    if startsWith(P, '% ---- chart') && contains(P, '内容'), tf = true; return; end
    if startsWith(strtrim(lines{j}), 'add_block') || startsWith(strtrim(lines{j}), 'add_line')
      tf = false; return;
    end
    j = j - 1;
  end
  tf = false;
end

function rel = extract_rel(L)
  tok = regexp(L, "\[m '/([^']+)'\]", 'tokens', 'once');
  if isempty(tok), rel = ''; else, rel = tok{1}; end
end

function key = extract_line_key(L)
  tok = regexp(L, "'([^']+)'\s*,\s*'([^']+)'", 'tokens', 'once');
  if isempty(tok), key = ''; else, key = ['line:' tok{1} '|' tok{2}]; end
end

function keys = ordered_union(a, b, c)
  keys = a;
  for i = 1:numel(b), if ~any(strcmp(keys, b{i})), keys = [keys, {b{i}}]; end, end %#ok<AGROW>
  for i = 1:numel(c), if ~any(strcmp(keys, c{i})), keys = [keys, {c{i}}]; end, end %#ok<AGROW>
end

%% ---------- 非键节（config/ws/annotations/callback/tail）：行级三路 ----------

function merged = merge_lines(bs, os, ts)
  % 保留顺序的行级三路：ours==base 取 theirs；theirs==base 取 ours；都变取 theirs
  b = normalized(bs); o = normalized(os); t = normalized(ts);
  keys = ordered_union(b.keys, o.keys, t.keys);
  merged = cell(1, 0);
  for i = 1:numel(keys)
    k = keys{i};
    hasB = b.map.isKey(k); hasO = o.map.isKey(k); hasT = t.map.isKey(k);
    if hasO && hasT, keep = o.map(k);
    elseif hasT, keep = t.map(k);
    elseif hasO, keep = o.map(k);
    else, keep = b.map(k);
    end
    if hasB && hasO && hasT && ~isequal(o.map(k), b.map(k)) && ~isequal(t.map(k), b.map(k))
      keep = t.map(k);  % 双方都改 → theirs
    end
    if ~isempty(keep), merged = [merged, keep]; end %#ok<AGROW>
  end
end

function S = normalized(lines)
  S.map = containers.Map('KeyType', 'char', 'ValueType', 'any');
  S.keys = cell(1, 0);
  for i = 1:numel(lines)
    if is_blank_or_comment(lines{i}), continue; end
    k = regexprep(strtrim(lines{i}), '\s+', ' ');
    if ~S.map.isKey(k), S.map(k) = lines{i}; S.keys = [S.keys, {k}]; end %#ok<AGROW>
  end
end

function c = strip_lead_slash(c)
  % T58：conflictList 出口统一成裸块名。内部键是 [m '/X'] 路径形态（带前导 /），
  % 消费方期望裸块名——只剥前导一个 /，保留块名内部的子系统路径斜杠（Sub/Blk）
  for i = 1:numel(c)
    s = c{i};
    if numel(s) > 1 && s(1) == '/', c{i} = s(2:end); end
  end
end
