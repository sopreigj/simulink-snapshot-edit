%% snp_patch.m — 快照局部编辑 API（simulink-snapshot-edit）
%
%  以程序化方式修改 snapshot_*.m 中指定块/线/连接——只动目标那几行，
%  文件中其他内容（其他块、位置、布线）逐字节不变。
%
%  用法
%    % 1) 块参数（既有）
%    snp_patch(file, block, 'Param1', value1, 'Param2', value2, ...)
%    snp_patch(file, block, 'Position', [x y x2 y2])
%
%    % 2) 改线：改某条 add_line 的走线点（Points 行存在则替换，不存在则补）
%    snp_patch(file, 'line', 'src/1', 'dst/1', 'Parent', 'm', 'Points', [x y; x2 y2])
%
%    % 3) 增块（顶层 Parent='m'）：插在 lines 分节之前
%    snp_patch(file, 'add_block', 'Name', 'NewConst', ...
%              'Source', 'simulink/Sources/Constant', 'Position', [100 100 130 130], ...
%              'Value', '42')
%
%    % 4) 删块：删除该块的 add_block 行
%    snp_patch(file, 'remove_block', 'NewConst')
%
%    % 5) 批量（表驱动）：ops 为 struct 数组，每项 {op, args}
%    ops(1) = struct('op', 'SpeedPI',  'args', {{'Ilim', '30'}});
%    ops(2) = struct('op', 'add_block','args', {{'Name','C1','Source', ...
%                  'simulink/Sources/Constant','Position',[100 100 130 130]}});
%    snp_patch(file, 'batch', ops)
%
%  参数
%    file   快照 .m 路径
%    block  块名（快照内 [m '/<block>'] 的 <block>，可含子系统路径，如 'InvAvg/gBC'）
%           或保留动词 'line' / 'add_block' / 'remove_block' / 'batch'
%
%  行为
%    - 块定位：add_block(... [m '/block'] ...); 整行（生成的快照每块一行）；
%    - 已有参数：替换其值；新参数：在行尾 ');' 前追加；Position 就地替换；
%    - 改线：定位 add_line(parent, 'src', 'dst', ...) 行，Points 行紧随其后则
%      替换其矩阵值，否则在该行后补 try/set_param/catch 行（与导出器同款写法）；
  %    - 增块：在 % ---- lines ---- 分节标记前插入 add_block 行；
  %    - 删块：删 add_block 行，并清理指向该块的悬空连线（同名前缀块
%      不误删）；MATLAB Function 块拒绝删（chart 脚本段会悬空）；
%    - 找不到目标 / 多处语义冲突 → 报错，不写文件。
%
%  边界（当前实现有意收窄，够用再扩）
%    - add_block 只支持顶层 Parent='m'；子系统内部加块请先展开位再 patch；
%    - 参数值字符类边界（2026-10-29 实测精确化，A 组矩阵）：
%      · 逗号：旧值含逗号曾使正则截断留半个值（工具层 bug，已修——引号串
%        完整吃、无引号字面仍排除逗号）；另 Simulink 语义层 Gain 等数值参数
%        本就不接受含逗号字面；
%      · 引号：需在值中转义（'it''s'）；
%      · 括号：实测可完整往返——写进快照、重建回读生效（语义按表达式求值，
%        如 '(3)' 回读 Gain=(3)）——旧措辞"括号也不行"过严。
%    - remove_block 现已清理 lines 分节里指向被删块的悬空连线（strip_
%      dangling_lines，按末段块名+parent 路径一致性判）；MATLAB Function
%      块仍拒绝删（chart 脚本段会悬空）。

function snp_patch(file, block, varargin)
  verbs = {'line', 'add_block', 'remove_block', 'add_line', 'remove_line', 'batch'};
  if any(strcmp(block, verbs))
    feval(['patch_' block], file, varargin{:});
    return;
  end
  assert(nargin >= 3, 'snp_patch: 需要至少一个 参数/值 对');
  patch_block_params(file, block, varargin{:});
end

%% ---------- 动词 1：改线（Points 走线点） ----------
function patch_line(file, src, dst, varargin)
  parent = 'm';
  pts = [];
  i = 1;
  while i <= numel(varargin)
    switch varargin{i}
      case 'Parent',  parent = varargin{i+1}; i = i + 2;
      case 'Points',  pts    = varargin{i+1}; i = i + 2;
      otherwise, error('snp_patch(line): 未知选项 %s', varargin{i});
    end
  end
  assert(~isempty(pts), 'snp_patch(line): 必须给 ''Points''');
  if strcmp(parent, 'm')
    parentText = 'm';
  else
    parentText = sprintf('[m ''/%s'']', parent);
  end
  txt = fileread(file);
  % needle 结尾带 dst 的闭引号，避免 'd/1' 误配 'd/12'
  needle = sprintf('add_line(%s, ''%s'', ''%s''', parentText, src, dst);
  idx = strfind(txt, needle);
  if isempty(idx)
    error('snp_patch: 快照 %s 中找不到连线 %s → %s（parent=%s）', file, src, dst, parent);
  end
  [lineStart, lineEnd, line] = line_at(txt, idx(1));
  if ~contains(line, 'lnH =')
    error('snp_patch: 匹配处不是 lnH = add_line 行（%s → %s）', src, dst);
  end
  newPtsLine = sprintf('  try, set_param(lnH, ''Points'', %s); catch, end', mat2str(pts, 17));
  % Points 行约定紧随 add_line 行（导出器写法）；找下一行判断
  rest = txt(lineEnd+2:end);
  nl = find(rest == sprintf('\n'), 1, 'first');
  if isempty(nl), nextLine = rest; else, nextLine = rest(1:nl-1); end
  if startsWith(strtrim(nextLine), 'try, set_param(lnH, ''Points''')
    % 替换已有 Points 行的矩阵值
    eol = lineEnd + 1 + numel(nextLine);
    txt = [txt(1:lineEnd+1) newPtsLine txt(eol+1:end)];
  else
    txt = [txt(1:lineEnd) sprintf('\n') newPtsLine txt(lineEnd+1:end)];
  end
  write_back(file, txt);
  fprintf('PATCHED line %s -> %s @ %s\n', src, dst, file);
end

%% ---------- 动词 2：增块 ----------
function patch_add_block(file, varargin)
  name = ''; src = ''; pos = [100 100 160 140]; parent = 'm';
  extra = {};
  i = 1;
  while i <= numel(varargin)
    switch varargin{i}
      case 'Name',     name   = varargin{i+1}; i = i + 2;
      case 'Source',   src    = varargin{i+1}; i = i + 2;
      case 'Position', pos    = varargin{i+1}; i = i + 2;
      case 'Parent',   parent = varargin{i+1}; i = i + 2;
      otherwise, extra{end+1} = varargin{i}; extra{end+1} = varargin{i+1}; i = i + 2; %#ok<AGROW>
    end
  end
  assert(~isempty(name) && ~isempty(src), 'snp_patch(add_block): 必须给 Name 与 Source');
  assert(strcmp(parent, 'm'), 'snp_patch(add_block): 当前只支持顶层 Parent=''m''');
  txt = fileread(file);
  assert(isempty(strfind(txt, sprintf('[m ''/%s''', name))), ...
    'snp_patch(add_block): 快照中已存在块 %s', name);
  seg = sprintf('  add_block(%s, [m ''/%s''], ''Position'', %s', ...
    mval(src), name, mat2str(pos, 17));
  for k = 1:2:numel(extra)
    seg = [seg sprintf(', ''%s'', %s', extra{k}, mval_local(extra{k+1}))]; %#ok<AGROW>
  end
  seg = [seg sprintf(');\n')];
  % 插在 % ---- lines ---- 分节标记之前，保证 add_block 全部先于 add_line 执行
  marker = strfind(txt, sprintf('\n  %% ---- lines'));
  assert(~isempty(marker), 'snp_patch(add_block): 快照缺少 lines 分节标记，无法定位插入点');
  at = marker(1);
  txt = [txt(1:at) sprintf('\n') seg txt(at+1:end)];
  write_back(file, txt);
  fprintf('PATCHED add_block %s @ %s\n', name, file);
end

%% ---------- 动词 3：删块 ----------
function patch_remove_block(file, name)
  txt = fileread(file);
  needle = sprintf('[m ''/%s''', name);
  idx = strfind(txt, needle);
  if isempty(idx)
    error('snp_patch: 快照 %s 中找不到块 %s', file, name);
  end
  [lineStart, lineEnd, line] = line_at(txt, idx(1));
  if ~startsWith(strtrim(line), 'add_block')
    error('snp_patch: %s 匹配处不是 add_block 行（块 %s）', file, name);
  end
  if contains(line, 'MATLAB Function')
    error('snp_patch(remove_block): %s 是 MATLAB Function 块，chart 脚本段会悬空，拒绝删除', name);
  end
  delStart = lineStart;
  txt = [txt(1:delStart) txt(lineEnd+1:end)];
  % 清理 lines 分节里指向该块的悬空 add_line（连带的 Points 行一并删）——
  % 不清的话重建报"无效端口"（A 组 4a 实测）。按"末段块名 + parent 路径
  % 一致性"精确判：同名前缀块（G2 vs G2x）与不同 parent 下的同名块不误删
  txt = strip_dangling_lines(txt, name);
  write_back(file, txt);
  fprintf('PATCHED remove_block %s @ %s\n', name, file);
end

%% 删除指向被删块的悬空 add_line 行（及其紧随的 Points 行）
function txt = strip_dangling_lines(txt, name)
  parts = strsplit(name, '/');
  leaf = parts{end};
  parentPath = strjoin(parts(1:end-1), '/');
  lines = regexp(txt, '\r?\n', 'split');
  out = cell(1, numel(lines));
  j = 0; i = 1;
  while i <= numel(lines)
    L = lines{i};
    if startsWith(strtrim(L), 'lnH = add_line(') && is_dangling(L, leaf, parentPath)
      if i + 1 <= numel(lines) && ...
          startsWith(strtrim(lines{i+1}), 'try, set_param(lnH, ''Points''')
        i = i + 2;
      else
        i = i + 1;
      end
    else
      j = j + 1; out{j} = L; i = i + 1; %#ok<AGROW>
    end
  end
  txt = strjoin(out(1:j), sprintf('\n'));
end

function tf = is_dangling(L, leaf, parentPath)
  tf = false;
  % 捕获完整端口串（'G1/1' 或嵌套 'Sub/G2/1'），块名=最后一个 / 之前的部分；
  % 正则无法区分块名内 / 与端口分隔 /，故先取整串再在 MATLAB 里切
  tok = regexp(L, 'lnH = add_line\(([^,]+), ''([^'']*?)'', ''([^'']*?)''', 'tokens');
  if isempty(tok), return; end
  parTxt = strtrim(tok{1}{1});
  srcB = port_block(tok{1}{2});
  dstB = port_block(tok{1}{3});
  if ~strcmp(srcB, leaf) && ~strcmp(dstB, leaf), return; end
  if isempty(parentPath)
    tf = strcmp(parTxt, 'm');
  else
    tf = strcmp(parTxt, sprintf('[m ''/%s'']', parentPath));
  end
end

function b = port_block(port)
  k = find(port == '/', 1, 'last');
  if isempty(k), b = port; else, b = port(1:k-1); end
end

%% ---------- 动词 4：批量（表驱动） ----------
function patch_batch(file, ops)
  assert(isstruct(ops) && ~isempty(ops), 'snp_patch(batch): ops 必须是非空 struct 数组');
  for k = 1:numel(ops)
    assert(isfield(ops(k), 'op') && isfield(ops(k), 'args'), ...
      'snp_patch(batch): 第 %d 项缺少 op/args 字段', k);
    snp_patch(file, ops(k).op, ops(k).args{:});
  end
end

%% ---------- 块参数（既有行为） ----------
function patch_block_params(file, block, varargin)
  txt = fileread(file);
  % 快照中每块一行：add_block('...', [m '/<block>'], ...);
  needle = sprintf('[m ''/%s''', block);
  idx = strfind(txt, needle);
  if isempty(idx)
    error('snp_patch: 快照 %s 中找不到块 %s', file, block);
  end
  % 行首（最近的前置换行）与行尾（最近的后续换行）
  lineStart = find(txt(1:idx(1)) == sprintf('\n'), 1, 'last');
  if isempty(lineStart), lineStart = 0; end
  lineEnd = find(txt(idx(1):end) == sprintf('\n'), 1, 'first');
  if isempty(lineEnd)
    lineEnd = numel(txt);
  else
    lineEnd = idx(1) + lineEnd - 2;
  end
  line = txt(lineStart+1:lineEnd);
  if ~startsWith(strtrim(line), 'add_block')
    error('snp_patch: %s 匹配处不是 add_block 行（块 %s）', file, block);
  end

  for i = 1:2:numel(varargin)
    key = varargin{i};
    val = varargin{i+1};
    lit = mval_local(val);
    if strcmp(key, 'Position')
      % 位置就地替换
      if contains(line, '''Position''')
        line = regexprep(line, '''Position'', \[[^\]]*\]', ...
          sprintf('''Position'', %s', mat2str(val)), 'once');
      else
        line = insert_before_close(line, sprintf(', ''Position'', %s', mat2str(val)));
      end
    else
      % 参数对：已有则替换，否则行尾追加
      pat = sprintf(', ''%s'', ', key);
      if contains(line, pat)
        % 替换该参数的值：', 'Key', <old>  ->  ', 'Key', <new>
        % 旧值两种形态：引号字符串（内部可含逗号）或无引号字面（数值/矩阵）。
        % 旧正则 [^',)]* 在旧值含逗号处截断，留下半个值导致语法破碎——
        % 引号形态用 ''[^']*'' 完整吃掉，无引号形态仍排除逗号（无引号逗号
        % 是参数分隔符）
        oldValPat = sprintf(', ''%s'', (''[^'']*''|['',)\\n]*)', key);
        line = regexprep(line, oldValPat, ...
                         sprintf(', ''%s'', %s', key, stripq(lit)), 'once');
      else
        line = insert_before_close(line, sprintf(', ''%s'', %s', key, stripq(lit)));
      end
    end
  end

  txt = [txt(1:lineStart) line sprintf('\n') txt(lineEnd+1:end)];
  write_back(file, txt);
  fprintf('PATCHED %s @ %s\n', block, file);
end

%% ---------- 动词 5：增连线 ----------
function patch_add_line(file, parent, src, srcPort, dst, dstPort)
  txt = fileread(file);
  if isempty(parent) || strcmp(parent, 'm'), parentText = 'm';
  else, parentText = sprintf('[m ''/%s'']', parent); end
  needle = sprintf('add_line(%s, ''%s/%s'', ''%s/%s''', parentText, ...
    char(src), char(srcPort), char(dst), char(dstPort));
  assert(isempty(strfind(txt, needle)), 'snp_patch(add_line): 连线已存在：%s', needle); %#ok<STREMP>
  % 行形如：lnH = add_line(m, 'src/1', 'dst/1', 'autorouting', 'off');
  % 不附 Points 行——重建时让 Simulink 自动布线（D5 不写几何）。
  seg = sprintf('  lnH = %s, ''autorouting'', ''off'');\n', needle);
  idxs = strfind(txt, sprintf('\n  lnH = add_line'));
  assert(~isempty(idxs), 'snp_patch(add_line): 快照中没有 add_line 行可作锚点');
  at = idxs(end);
  nl = find(txt(at:end) == sprintf('\n'), 1, 'first');
  insertAt = at + nl - 1;
  txt = [txt(1:insertAt) seg txt(insertAt+1:end)];
  write_back(file, txt);
  fprintf('PATCHED add_line %s/%s -> %s/%s @ %s\n', char(src), char(srcPort), char(dst), char(dstPort), file);
end

%% ---------- 动词 6：删连线 ----------
function patch_remove_line(file, parent, src, srcPort, dst, dstPort)
  txt = fileread(file);
  if isempty(parent) || strcmp(parent, 'm'), parentText = 'm';
  else, parentText = sprintf('[m ''/%s'']', parent); end
  needle = sprintf('add_line(%s, ''%s/%s'', ''%s/%s''', parentText, ...
    char(src), char(srcPort), char(dst), char(dstPort));
  idx = strfind(txt, needle);
  if isempty(idx)
    error('snp_patch: 快照 %s 中找不到连线 %s', file, needle);
  end
  [lineStart, lineEnd, line] = line_at(txt, idx(1));
  if ~contains(line, 'lnH = add_line')
    error('snp_patch: %s 匹配处不是 add_line 行', file);
  end
  delEnd = lineEnd;
  % 伴随的 Points 行（紧随其后的 try, set_param(lnH, 'Points',...)）一并删
  [~, pEnd, pLine] = line_at(txt, lineEnd + 2);
  if startsWith(strtrim(pLine), 'try, set_param(lnH, ''Points''')
    delEnd = pEnd;
  end
  txt = [txt(1:lineStart) txt(delEnd+1:end)];
  write_back(file, txt);
  fprintf('PATCHED remove_line %s/%s -> %s/%s @ %s\n', char(src), char(srcPort), char(dst), char(dstPort), file);
end
%% ---------- 共用工具 ----------

%% 定位 needle 所在整行，返回 [行首换行下标, 行尾换行下标, 行内容]
function [lineStart, lineEnd, line] = line_at(txt, idx)
  lineStart = find(txt(1:idx) == sprintf('\n'), 1, 'last');
  if isempty(lineStart), lineStart = 0; end
  lineEnd = find(txt(idx:end) == sprintf('\n'), 1, 'first');
  if isempty(lineEnd)
    lineEnd = numel(txt);
  else
    lineEnd = idx + lineEnd - 2;
  end
  line = txt(lineStart+1:lineEnd);
end

%% 写回文件
function write_back(file, txt)
  fid = fopen(file, 'w'); assert(fid > 0, 'cannot write %s', file);
  fwrite(fid, txt); fclose(fid);
end

%% 在 ');' 前插入
function line = insert_before_close(line, frag)
  k = strfind(line, ');');
  assert(~isempty(k), 'snp_patch: add_block 行缺少 ); 结尾');
  line = [line(1:k(end)-1) frag line(k(end):end)];
end

%% 字面量去掉外层引号（参数行内的值片段不带引号包裹）
function s = stripq(lit)
  % mval 已产出合法字面量；保持原样即可（单/双引号包裹都是 set_param 可用形式）
  s = lit;
end

%% 字面量（与 snp_export.m 的 mval 保持一致；本地函数不跨文件）
function s = mval_local(v)
  s = mval(v);
end

function s = mval(v)
  if ischar(v)
    if contains(v, sprintf('\n')) || contains(v, '"')
      w = strrep(v, '\', '\\');
      w = strrep(w, '"', '\"');
      w = strrep(w, sprintf('\n'), '\n');
      s = ['"' w '"'];
    else
      s = ['''' strrep(v, '''', '''''') ''''];
    end
  elseif islogical(v)
    if v, s = '''on'''; else, s = '''off'''; end
  elseif isnumeric(v)
    if isscalar(v), s = num2str(v, 17); else, s = mat2str(v, 17); end
  else
    s = '''''';
  end
end

