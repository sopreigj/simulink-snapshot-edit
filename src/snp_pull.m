%% snp_pull.m — 增量反编译合并器：把模型里的（人类）变更最小化地合并回快照
% （simulink-snapshot-edit）
%
%  目标（双向最大保留）：
%    agent 方向（已有）：快照是 LLM 产出的代码（含分节注释/块注释），agent 改几行
%      → run → 模型更新。注释天然保留。
%    人类方向（本函数）：人类在 GUI 改模型（参数/位置/加块删块）→ snp_pull 把
%      变更合并回快照——**LLM 写的手写区（分节注释/块上方注释/辅助行）全部保留**，
%      只按块名对齐增删改语句，报告差异清单。
%
%  用法
%    rep = snp_pull('MyModel', 'snapshot_MyModel.m', opts);
%    rep.nAdd / nDel / nChg / nNoteKept —— 新增块/删除块/变更块/保留注释数
%
%  合并算法（按节）：
%    - 节标题与手写内容（非语句行）一律保留旧快照的；
%    - 块节：旧 token 流（注释/语句交替）逐 token 走：注释→保留；语句（块 X）：
%        模型仍有 X → 换新语句（注释不动）；模型无 X → 删语句留注释并标记；
%        模型新增块 → 追加到块节末尾并标记 [new]；
%    - chart Script 行（rtc.…）作为所属块的附属行随块走；
%    - 其余节（lines/annotations/config/ws）：文本相同则保留旧（含注释），
%      不同则换新文本（报告变化）。

function rep = snp_pull(mdl, snapFile, opts)
  if nargin < 3, opts = struct; end
  if ~isfield(opts, 'LibDir'), opts.LibDir = ''; end
  if ~isfield(opts, 'AliasMap'), opts.AliasMap = cell(0,2); end
  addpath(fileparts(which('snp_export')));
  % 强制从磁盘重载：MATLAB 可能残留同名已加载模型（shadow），
  % 不重载会读到旧内容——pull 的前提是"磁盘上的模型即人类刚改的"
  % 重载前提醒：仿真中/未保存改动都会在下面的无保存强关里出事（T59 同族）
  snp_runtime_warn(mdl, 'reload');
  try, close_system(mdl, 0); catch, end
  try, bdclose(mdl); catch, end
  load_system(mdl);

  % 1) 从当前模型导出"新快照"到临时目录
  tmpDir = tempname; mkdir(tmpDir);
  o2 = opts; o2.OutDir = tmpDir; o2.ExtraHeader = {};
  snp_export(mdl, o2);
  tmp = fullfile(tmpDir, ['snapshot_' mdl '.m']);
  newTxt = fileread(tmp);
  oldTxt = fileread(snapFile);
  delete(tmp);

  rep = struct('nAdd',0,'nDel',0,'nChg',0,'nNoteKept',0,'detail',{{}});

  % 2) 节切分：%% ---- <title> ---- 为节边界
  oldSecs = split_sections(oldTxt);
  newSecs = split_sections(newTxt);

  out = oldSecs.header;                    % 函数头+到第一节前的内容
  for i = 1:numel(oldSecs.titles)
    title = oldSecs.titles{i};
    oldBody = oldSecs.bodies{i};
    j = find(cellfun(@(t) strcmp(t, title) || (contains(t, title) && numel(title) > 3) || (contains(title, t) && numel(t) > 3), newSecs.titles), 1);
    if isempty(j)                            % 节在新模型里没了：保留旧并标记
      out = [out sec_text(title, oldBody)]; %#ok<AGROW>
      rep.detail{end+1} = ['节保留（新模型无此节）: ' title]; %#ok<AGROW>
      continue;
    end
    newBody = newSecs.bodies{j};
    if contains(title, 'blocks') && contains(newSecs.titles{j}, 'blocks')
      [body, r] = merge_blocks(oldBody, newBody);
      rep.nAdd = rep.nAdd + r.nAdd;
      rep.nDel = rep.nDel + r.nDel;
      rep.nChg = rep.nChg + r.nChg;
      rep.nNoteKept = rep.nNoteKept + r.nNoteKept;
      rep.detail = [rep.detail r.detail]; %#ok<AGROW>
    else
      % 其余节：行级保留——旧行顺序/注释不动，只删消失的、换变更的、追加新的
      [body, nKeep, nChg, nDel, nAdd] = merge_lines(oldBody, newBody);
      rep.nNoteKept = rep.nNoteKept + nKeep;
      rep.nChg = rep.nChg + nChg;
      rep.nDel = rep.nDel + nDel;
      rep.nAdd = rep.nAdd + nAdd;
      if nChg || nDel || nAdd
        rep.detail{end+1} = sprintf('节 %s: %d 变更 / %d 删 / %d 增', title, nChg, nDel, nAdd); %#ok<AGROW>
      end
    end
    out = [out sec_text(title, body)]; %#ok<AGROW>
  end

  % 3) 新模型多出的节（罕见）追加
  for j = 1:numel(newSecs.titles)
    if ~any(strcmp(oldSecs.titles, newSecs.titles{j}))
      out = [out sec_text(newSecs.titles{j}, newSecs.bodies{j})]; %#ok<AGROW>
      rep.detail{end+1} = ['节新增: ' newSecs.titles{j}]; %#ok<AGROW>
    end
  end

  fid = fopen(snapFile, 'w'); fwrite(fid, out); fclose(fid);
  fprintf('PULL %s: +%d 块 / -%d 块 / ~%d 变更 / %d 条注释保留\n', ...
    mdl, rep.nAdd, rep.nDel, rep.nChg, rep.nNoteKept);
  for i = 1:min(numel(rep.detail), 10)
    fprintf('  %s\n', rep.detail{i});
  end
end

%% ---------- 节切分 ----------
function S = split_sections(txt)
  S.header = ''; S.titles = {}; S.bodies = {};
  lines = strsplit(txt, sprintf('\n'));
  cur = 1; S.header = lines{1};
  for i = 2:numel(lines)
    L = lines{i};
    m = regexp(L, '^\s*%+ ---- (.+) ----', 'tokens', 'once');
    if ~isempty(m)
      cur = cur + 1;
      S.titles{cur-1} = m{1}; %#ok<AGROW>
      S.bodies{cur-1} = {};  %#ok<AGROW>
    else
      if cur == 1
        S.header = [S.header sprintf('\n') L]; %#ok<AGROW>
      else
        S.bodies{cur-1}{end+1} = L; %#ok<AGROW>
      end
    end
  end
end

function t = sec_text(title, body)
  t = sprintf('\n  %% ---- %s ----\n', title);
  if iscell(body) && ~isempty(body)
    t = [t strjoin(body, sprintf('\n')) sprintf('\n')]; %#ok<AGROW>
  end
end

%% ---------- 通用节行级合并（线/注解/ws/config）：保序+注释全留 ----------
%  旧行逐行走：注释/空行→原样保留；语句→在新集合有（文本同）则保留旧文本，
%  有但文本不同→换新；没有→删（注释留）；新集合多出的→追加到末尾。
function [body, nKeep, nChg, nDel, nAdd] = merge_lines(oldBody, newBody)
  nKeep = 0; nChg = 0; nDel = 0; nAdd = 0;
  newStmts = newBody(~cellfun(@(s) isempty(strtrim(s)) || startsWith(strtrim(s), '%'), newBody));
  used = false(1, numel(newStmts));
  body = {};
  for i = 1:numel(oldBody)
    L = oldBody{i};
    if isempty(strtrim(L)) || startsWith(strtrim(L), '%')
      body{end+1} = L; if ~isempty(strtrim(L)), nKeep = nKeep + 1; end %#ok<AGROW>
      continue;
    end
    hit = find(strcmp(newStmts, L) & ~used, 1);
    if ~isempty(hit)
      used(hit) = true;
      body{end+1} = L; %#ok<AGROW>
    else
      hit2 = find(~used, 1);   % 同槽位不同文本：换新（取未用的第一条近似配对）
      if ~isempty(hit2) && ~isempty(newStmts)
        used(hit2) = true; nChg = nChg + 1; %#ok<AGROW>
        body{end+1} = newStmts{hit2}; %#ok<AGROW>
      else
        nDel = nDel + 1; %#ok<AGROW>   % 删语句（注释保留）
      end
    end
  end
  for k = find(~used)
    body{end+1} = ['  % [new from model] ' newStmts{k}]; %#ok<AGROW>
    body{end+1} = newStmts{k}; %#ok<AGROW>
    nAdd = nAdd + 1; %#ok<AGROW>
  end
end

%% ---------- 块节合并 ----------
function [body, r] = merge_blocks(oldBody, newBody)
  r = struct('nAdd',0,'nDel',0,'nChg',0,'nNoteKept',0,'detail',{{}});
  % 新模型：块名 → 语句组（add_block 行 + 紧跟的附属行：rtc 行 / chart 内容组）
  % 附属行边界（T42 chart 回流修复）：rtc 行，或 % ---- chart X 内容 ---- 与
  % 其配对的 % ---- chart X end ---- 之间的行（含两端标记）
  newMap = containers.Map('KeyType','char','ValueType','any');
  i = 1; N = numel(newBody);
  while i <= N
    L = newBody{i};
    bn = block_name(L);
    if ~isempty(bn)
      grp = {L}; i = i + 1;
      while i <= N && is_affix_line(newBody, i)
        grp{end+1} = newBody{i}; i = i + 1; %#ok<AGROW>
      end
      newMap(bn) = grp;
    else
      i = i + 1;
    end
  end
  % 旧快照逐 token 走
  body = {}; i = 1; M = numel(oldBody);
  while i <= M
    L = oldBody{i};
    bn = block_name(L);
    if isempty(bn)
      if ~isempty(strtrim(L)), r.nNoteKept = r.nNoteKept + 1; end
      body{end+1} = L; i = i + 1; %#ok<AGROW>
    else
      grp = {L}; i = i + 1;
      while i <= M && is_affix_line(oldBody, i)
        grp{end+1} = oldBody{i}; i = i + 1; %#ok<AGROW>
      end
      if newMap.isKey(bn)
        ng = newMap(bn);
        if ~isequal(grp, ng)
          r.nChg = r.nChg + 1; %#ok<AGROW>
          r.detail{end+1} = ['块变更: ' bn]; %#ok<AGROW>
        end
        body = [body ng]; %#ok<AGROW>
        newMap.remove(bn);
      else
        r.nDel = r.nDel + 1; %#ok<AGROW>
        r.detail{end+1} = ['块已删（注释保留）: ' bn]; %#ok<AGROW>
        % 删语句、保留其上注释（上一 token 已入 body）
      end
    end
  end
  % 新模型新增块追加
  if ~isempty(newMap.keys)
    ks = newMap.keys;
    for k = 1:numel(ks)
      body{end+1} = ['  % [new from model] ' ks{k}]; %#ok<AGROW>
      body = [body newMap(ks{k})]; %#ok<AGROW>
      r.nAdd = r.nAdd + 1; %#ok<AGROW>
      r.detail{end+1} = ['块新增: ' ks{k}]; %#ok<AGROW>
    end
  end
end

%% 从 add_block 行提取块名（[m '/NAME']）
function bn = block_name(L)
  bn = '';
  if ~contains(L, 'add_block'), return; end
  tok = regexp(L, "\[m '/([^']+)'\]", 'tokens', 'once');
  if ~isempty(tok), bn = tok{1}; end
end

%% 块附属行判定（T42 chart 回流修复）
%  附属 = MATLAB Function 的 rtc 行（既有），或 chart 内容组：
%  % ---- chart X 内容（Stateflow 结构化导出）---- 与配对的
%  % ---- chart X end ---- 之间的行（含两端标记）。
%  组内判定用"chart 内容标记之后、end 标记之前"的前向扫描，无需全局状态。
function tf = is_affix_line(body, i)
  L = body{i};
  if contains(L, 'rtc'), tf = true; return; end
  if startsWith(strtrim(L), '% ---- chart') && contains(L, '内容'), tf = true; return; end
  if startsWith(strtrim(L), '% ---- chart') && contains(L, 'end ----'), tf = true; return; end
  % 组内行：向前找最近的 chart 标记，若是"内容"开头且未遇 end，则属组内
  j = i - 1;
  while j >= 1
    P = strtrim(body{j});
    if startsWith(P, '% ---- chart') && contains(P, 'end ----'), tf = false; return; end
    if startsWith(P, '% ---- chart') && contains(P, '内容'), tf = true; return; end
    j = j - 1;
  end
  tf = false;
end
