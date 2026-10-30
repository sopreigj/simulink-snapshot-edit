function info = snp_xml_edit(srcSlx, dstSlx, ops, varargin)
%SNP_XML_EDIT  直接改 .slx 内部 XML（块参数 + 结构）并重打包出新的 .slx
%
%  .slx 是 OPC(zip) 包：块、连线、参数全在 simulink/systems/system_*.xml 里。
%  本工具按"模型内块路径"定位到 XML 里的块元素，改它的参数或结构，再按原
%  条目顺序重打包成新的 .slx。
%
%  为什么值得做（与 snp_export 路线互补，不是替代）：
%    · 改 XML 不需要知道块型的库路径——add_block 才需要。未知块型照样能改。
%    · 改 XML 不需要重建模型——未列白的参数、Stateflow、Simscape 物理连接
%      全部原样保留（字节级不动其余部分）。
%    · 代价：产物是"改过的 .slx"，不是"能重建的 M"。跨版本可移植性与逐字节
%      新鲜度判据要靠 snp_export 路线兜底。
%
%  操作（ops 的每个元素是一条操作）
%    {'set_param',   块路径, 参数名, 新值}
%    {'add_block',   父路径, 块型, 块名, 参数cell}  参数cell={{'Gain','3.5'},...}，可空
%    {'remove_block',块路径}
%    {'add_line',    父路径, 源块名, 源端口, 目的块名, 目的端口}
%    {'remove_line', 父路径, 源块名, 源端口, 目的块名, 目的端口}
%      源/目的端口：普通信号用端口号（'1'）；Simscape 物理端口用 'LConn1'/'RConn1'
%      （XML 里写为 #lconn:N / #rconn:N，<Line LineType="Connection">，不扇出）
%    简写 {块路径, 参数名, 新值} 等价于 {'set_param', 块路径, 参数名, 新值}
%
%    父路径：'' 表示模型顶层；'Plant' 表示名为 Plant 的子系统。块路径用模型内
%    路径（与 get_param 一致），如 'g1'、'ToyLibRef/tm'。
%
%  改什么不碰：坐标与走线（布局）——那是展示属性，由 Simulink 自动排列负责，
%      人机协作不需要 agent 写几何（D5）。
%
%  连线的 XML 形态（实测）：一个目的地时直接 <P Name="Dst">；多个目的地时全部
%      放在 <Branch> 里（与 Simulink 自己写出来的形态一致）。本工具写回时保持
%      这个规范形态。
%
%  可选名值参数：'Verbose', true（打印每条操作的结果）
%
%  返回 info：
%    .applied  {动词, 目标, 说明}
%    .skipped  {动词, 目标, 原因}
%    .mops     与本次操作等价的 M 侧操作（供回灌用；格式见各操作实现）
%
%  依赖：MATLAB 自带 Java（java.util.zip）。MATLAB 以 -nojvm 启动时不可用。
opts = struct('Verbose', false);
if mod(numel(varargin), 2) ~= 0
  error('snp_xml_edit:badOpts', '可选参数必须成对出现');
end
for k = 1:2:numel(varargin)
  opts.(varargin{k}) = varargin{k+1};
end
if nargin < 3 || isempty(ops)
  error('snp_xml_edit:noOps', 'ops 不能为空');
end
if ~isfile(srcSlx)
  error('snp_xml_edit:noSrc', '源模型不存在: %s', srcSlx);
end

tmp = tempname;
mkdir(tmp);
exDir = fullfile(tmp, 'ex');
cleanup = onCleanup(@() rmdir(tmp, 's')); %#ok<NASGU>
unzip(srcSlx, exDir);

info = struct('applied', {cell(0, 3)}, 'skipped', {cell(0, 3)}, 'mops', {{}});
for k = 1:numel(ops)
  op = normalizeOp(ops{k});
  verb = op{1};
  try
    switch verb
      case 'set_param'
        info = doSetParam(exDir, info, op);
      case 'add_block'
        info = doAddBlock(exDir, info, op);
      case 'remove_block'
        info = doRemoveBlock(exDir, info, op);
      case 'add_line'
        info = doAddLine(exDir, info, op);
      case 'remove_line'
        info = doRemoveLine(exDir, info, op);
      otherwise
        error('snp_xml_edit:badVerb', '未知操作 %s', verb);
    end
  catch ME
    info.skipped(end+1, :) = {verb, opDetail(op), ME.message};
    if opts.Verbose, fprintf('  [skip] %s : %s\n', verb, ME.message); end
  end
end

repackZip(srcSlx, dstSlx, exDir);
end

% ===========================================================================
%  操作实现
% ===========================================================================
function info = doSetParam(exDir, info, op)
blkPath = char(op{2}); pname = char(op{3}); newVal = char(op{4});
[found, file, blockXml] = locateBlock(exDir, blkPath);
if ~found
  info.skipped(end+1, :) = {'set_param', blkPath, '未找到块'};
  return;
end
pat = sprintf('<P Name="%s">([^<]*)</P>', pname);
m = regexp(blockXml, pat, 'tokens', 'once');
if isempty(m)
  info.skipped(end+1, :) = {'set_param', blkPath, sprintf('该块无参数 %s', pname)};
  return;
end
oldRaw = m{1};
% regexp(...,'tokens') 只给捕获组，不含整段匹配（m{0} 不存在）；
% 整段按模式形状重建即可，模式是确定的。
newBlock = strrep(blockXml, sprintf('<P Name="%s">%s</P>', pname, oldRaw), ...
  sprintf('<P Name="%s">%s</P>', pname, xmlEscape(newVal)));
txt = fileread(file);
if isempty(strfind(txt, blockXml)) %#ok<STREMP>
  error('snp_xml_edit:stale', 'XML 片段定位失败（%s / %s）', blkPath, pname);
end
writeText(file, strrep(txt, blockXml, newBlock));
info.applied(end+1, :) = {'set_param', blkPath, sprintf('%s: %s -> %s', pname, oldRaw, newVal)};
info.mops{end+1} = {blkPath, pname, newVal};
end

function info = doAddBlock(exDir, info, op)
parentPath = char(op{2}); blkType = char(op{3}); blkName = char(op{4});
params = {};
if numel(op) >= 5 && ~isempty(op{5}), params = op{5}; end
file = systemFileForPath(exDir, parentPath);
txt = fileread(file);
if ~isempty(findBlockInText(txt, blkName))
  error('已存在同名块 %s', blkName);
end
sid = allocSid(exDir);
z = allocZOrder(txt);
pos = [100 100 130 120];
body = sprintf('  <P Name="Position">[%d, %d, %d, %d]</P>\n', pos(1), pos(2), pos(3), pos(4));
body = sprintf('%s  <P Name="ZOrder">%d</P>\n', body, z);
for k = 1:numel(params)
  p = params{k};
  if iscell(p) && numel(p) >= 2
    nm = char(p{1}); vl = char(p{2});
  else
    nm = char(p); vl = '';
  end
  body = sprintf('%s  <P Name="%s">%s</P>\n', body, xmlEscape(nm), xmlEscape(vl));
end
el = sprintf('<Block BlockType="%s" Name="%s" SID="%s">\n%s</Block>\n', ...
  xmlEscape(blkType), xmlEscape(blkName), sid, body);
% 插入位置必须是 blocks 段末尾（最后一个 </Block> 之后）：
% 原文件顺序是 Block → Line → Annotation，Simulink 载入器按文档顺序解析——
% 若新块放在 </System> 前（Annotation/Line 之后），引用它的 Line 会指向一个
% "尚未定义"的块，分支被静默丢弃（2026-10-28 实测）。
p = strfind(txt, '</Block>');
if ~isempty(p)
  insertPos = p(end) + numel('</Block>');
  writeText(file, [txt(1:insertPos) sprintf('\n%s', el) txt(insertPos+1:end)]);
else
  idx = lastSystemClose(txt);
  writeText(file, [txt(1:idx-1) el txt(idx:end)]);
end
info.applied(end+1, :) = {'add_block', blkName, sprintf('%s (SID=%s, parent=%s)', blkType, sid, parentPath)};
info.mops{end+1} = {'add_block', parentPath, blkType, blkName, params, pos};
end

function info = doRemoveBlock(exDir, info, op)
blkPath = char(op{2});
[found, file, blockXml] = locateBlock(exDir, blkPath);
if ~found
  info.skipped(end+1, :) = {'remove_block', blkPath, '未找到块'};
  return;
end
sid = regexp(blockXml, 'SID="([^"]*)"', 'tokens', 'once');
txt = fileread(file);
% 先统计引用该 SID 的连线（XML 侧一并删除；M 侧回灌时 snp_patch 的
% remove_block 自带 strip_dangling_lines 清悬空 add_line——S3 修复后
% 不再需要remove_line mop，否则双重清线：remove_block 已把线删掉，
% 随后的 remove_line 找不到连线抛错）。
segs = strsplit(strrep(blkPath, '\', '/'), '/');
if numel(segs) > 1, parentPath = strjoin(segs(1:end-1), '/'); else, parentPath = ''; end
nTouched = numel(lines_touching_mops(txt, sid{1}, parentPath));
txt = strrep(txt, blockXml, '');
% 引用该 SID 的连线一并删掉（Src 或 Dst 里出现它）
txt = removeLinesReferencing(txt, sid{1});
writeText(file, txt);
info.applied(end+1, :) = {'remove_block', blkPath, sprintf('SID=%s，%d 条相关连线一并清理', sid{1}, nTouched)};
info.mops{end+1} = {'remove_block', blkPath};
end

function mops = lines_touching_mops(txt, sid, parentPath)
% 返回引用 sid 的连线对应的 remove_line mops（端点块名在当前文件内解析）
mops = {};
% SID → Name 映射（从开始标签取）
blocks = regexp(txt, '<Block[^>]*>', 'match');
sid2name = containers.Map('KeyType', 'char', 'ValueType', 'char');
for b = 1:numel(blocks)
  ms = regexp(blocks{b}, 'SID="([^"]*)"', 'tokens', 'once');
  mn = regexp(blocks{b}, 'Name="([^"]*)"', 'tokens', 'once');
  if ~isempty(ms) && ~isempty(mn)
    sid2name(ms{1}) = mn{1};
  end
end
lines = regexp(txt, '<Line[^>]*>[\s\S]*?</Line>', 'match');
for k = 1:numel(lines)
  if isempty(strfind(lines{k}, [sid '#out:'])) && isempty(strfind(lines{k}, [sid '#in:'])) %#ok<STREMP>
    continue;
  end
  [srcRef, dsts] = parseLine(lines{k});
  [sSid, sPort] = split_ref(srcRef);
  if isempty(sSid) || ~isKey(sid2name, sSid), continue; end
  for d = 1:numel(dsts)
    [dSid, dPort] = split_ref(dsts{d});
    if isempty(dSid) || ~isKey(sid2name, dSid), continue; end
    mops{end+1} = {'remove_line', parentPath, sid2name(sSid), sPort, sid2name(dSid), dPort}; %#ok<AGROW>
  end
end
end

function [sid, port] = split_ref(ref)
% '13#out:1' → sid='13', port='1'；物理端口（#lconn:/#rconn:）返回空
m = regexp(ref, '(\d+)#(?:out|in):(\d+)', 'tokens', 'once');
if isempty(m)
  sid = ''; port = '';
else
  sid = m{1}; port = m{2};
end
end
function s = portStr(p)
% 端口参数归一：数字→'N'；字符（'LConn1'/'RConn1'/'1'）原样
if ischar(p), s = p; else, s = num2str(p); end
end
function c = is_phys_port(p)
% 'LConn1'/'RConn1' 为物理端口名；普通信号端口号（'1'）为 false
c = ~isempty(regexp(p, '^[LR]Conn\d+$', 'once'));
end
function r = physRef(sid, port)
% 物理端口 'LConn1' → '1#lconn:1'（XML 里就是 #lconn:N / #rconn:N）
m = regexp(port, '^([LR])Conn(\d+)$', 'tokens', 'once');
if isempty(m), error('snp_xml_edit:badPhysPort', '非法物理端口名 %s', port); end
r = sprintf('%s#%sconn:%s', sid, lower(m{1}), m{2});
end
function info = doAddLine(exDir, info, op)
parentPath = char(op{2});
srcName = char(op{3}); srcPort = portStr(op{4});
dstName = char(op{5}); dstPort = portStr(op{6});
file = systemFileForPath(exDir, parentPath);
txt = fileread(file);
srcSid = requireSid(txt, srcName);
dstSid = requireSid(txt, dstName);
srcPhys = is_phys_port(srcPort); dstPhys = is_phys_port(dstPort);
if srcPhys, srcRef = physRef(srcSid, srcPort);
else,       srcRef = sprintf('%s#out:%s', srcSid, srcPort); end
if dstPhys, dstRef = physRef(dstSid, dstPort);
else,       dstRef = sprintf('%s#in:%s', dstSid, dstPort); end
z = allocZOrder(txt);
if srcPhys || dstPhys
  % 物理连接：星形生成树逐对连，每条独立 <Line LineType="Connection">，无扇出
  if ~isempty(strfind(txt, sprintf('<P Name="Dst">%s</P>', dstRef)))
    error('物理连线 %s -> %s 已存在', srcRef, dstRef);
  end
  el = sprintf(['<Line LineType="Connection">\n  <P Name="ZOrder">%d</P>\n' ...
    '  <P Name="Src">%s</P>\n  <P Name="Dst">%s</P>\n</Line>\n'], z, srcRef, dstRef);
  idx = lastSystemClose(txt);
  writeText(file, [txt(1:idx-1) el txt(idx:end)]);
else
  if ~isempty(strfind(txt, sprintf('<P Name="Dst">%s</P>', dstRef)))
    error('连线 %s -> %s 已存在', srcRef, dstRef);
  end
  [lStart, lEnd, lineXml] = findLineBySrc(txt, srcRef);
  if isempty(lineXml)
    el = sprintf(['<Line>\n  <P Name="ZOrder">%d</P>\n  <P Name="Src">%s</P>\n' ...
      '  <P Name="Dst">%s</P>\n</Line>\n'], z, srcRef, dstRef);
    idx = lastSystemClose(txt);
    writeText(file, [txt(1:idx-1) el txt(idx:end)]);
  else
    newLine = addDestinationToLine(lineXml, dstRef, z);
    writeText(file, [txt(1:lStart-1) newLine txt(lEnd+1:end)]);
  end
end
info.applied(end+1, :) = {'add_line', sprintf('%s -> %s', srcRef, dstRef), sprintf('parent=%s', parentPath)};
info.mops{end+1} = {'add_line', parentPath, srcName, srcPort, dstName, dstPort};
end

function info = doRemoveLine(exDir, info, op)
parentPath = char(op{2});
srcName = char(op{3}); srcPort = portStr(op{4});
dstName = char(op{5}); dstPort = portStr(op{6});
file = systemFileForPath(exDir, parentPath);
txt = fileread(file);
srcSid = requireSid(txt, srcName);
dstSid = requireSid(txt, dstName);
srcPhys = is_phys_port(srcPort); dstPhys = is_phys_port(dstPort);
if srcPhys, srcRef = physRef(srcSid, srcPort);
else,       srcRef = sprintf('%s#out:%s', srcSid, srcPort); end
if dstPhys, dstRef = physRef(dstSid, dstPort);
else,       dstRef = sprintf('%s#in:%s', dstSid, dstPort); end
[lStart, lEnd, lineXml] = findLineBySrc(txt, srcRef);
if isempty(lineXml)
  error('找不到源为 %s 的连线', srcRef);
end
newLine = removeDestinationFromLine(lineXml, dstRef);
if isempty(newLine)
  writeText(file, [txt(1:lStart-1) txt(lEnd+1:end)]);
else
  writeText(file, [txt(1:lStart-1) newLine txt(lEnd+1:end)]);
end
info.applied(end+1, :) = {'remove_line', sprintf('%s -> %s', srcRef, dstRef), sprintf('parent=%s', parentPath)};
info.mops{end+1} = {'remove_line', parentPath, srcName, srcPort, dstName, dstPort};
end

% ===========================================================================
%  XML 元素操作
% ===========================================================================
function newLine = addDestinationToLine(lineXml, dstRef, z)
% 给一条线加一个目的地：解析出 src 与全部目的地，按 Simulink 规范形态重建
% （地面真相实测：Src 后有 <P Name="Points">[0, 0]</P>；Branch 不带 Points）
[srcRef, dsts] = parseLine(lineXml);
dsts{end+1} = dstRef;
newLine = buildLine(srcRef, dsts, z);
end

function newLine = removeDestinationFromLine(lineXml, dstRef)
% 移除一个目的地；0 个 → 删整条线；1 个 → 回到"直接 Dst"形态
[srcRef, dsts] = parseLine(lineXml);
keep = {};
for k = 1:numel(dsts)
  if ~strcmp(dsts{k}, dstRef), keep{end+1} = dsts{k}; end %#ok<AGROW>
end
newLine = buildLine(srcRef, keep, 0);
end

function [srcRef, dsts] = parseLine(lineXml)
% 解析线的 src 与全部目的地（直接 Dst + Branch 里的 Dst）
srcM = regexp(lineXml, '<P Name="Src">([^<]*)</P>', 'tokens', 'once');
if isempty(srcM)
  error('线元素缺少 Src');
end
srcRef = srcM{1};
d = regexp(lineXml, '<P Name="Dst">([^<]*)</P>', 'tokens');
dsts = {};
for k = 1:numel(d)
  dsts{end+1} = d{k}{1}; %#ok<AGROW>
end
end

function newLine = buildLine(srcRef, dsts, zBase)
% 按 Simulink 规范形态构建线元素：
%   0 目的地 → ''（删线）；1 目的地 → 直接 <P Name="Dst">；N>1 → 全在 <Branch>
if isempty(dsts)
  newLine = '';
  return;
end
if numel(dsts) == 1
  newLine = sprintf(['<Line>\n  <P Name="ZOrder">%d</P>\n  <P Name="Src">%s</P>\n' ...
    '  <P Name="Dst">%s</P>\n</Line>\n'], zBase, srcRef, dsts{1});
  return;
end
parts = sprintf(['<Line>\n  <P Name="ZOrder">%d</P>\n  <P Name="Src">%s</P>\n' ...
  '  <P Name="Points">[0, 0]</P>\n'], zBase, srcRef);
for k = 1:numel(dsts)
  parts = sprintf('%s  <Branch>\n    <P Name="ZOrder">%d</P>\n    <P Name="Dst">%s</P>\n  </Branch>\n', ...
    parts, zBase + k, dsts{k});
end
newLine = sprintf('%s</Line>\n', parts);
end
function txt = removeLinesReferencing(txt, sid)
pat = '<Line[^>]*>[\s\S]*?</Line>';
ms = regexp(txt, pat, 'match');
for k = 1:numel(ms)
  if ~isempty(strfind(ms{k}, sprintf('%s#out:', sid))) || ...
     ~isempty(strfind(ms{k}, sprintf('%s#in:', sid)))
    txt = strrep(txt, ms{k}, '');
  end
end
end

function [lStart, lEnd, lineXml] = findLineBySrc(txt, srcRef)
lStart = 0; lEnd = 0; lineXml = '';
ms = regexp(txt, '<Line[^>]*>[\s\S]*?</Line>', 'match');
starts = regexp(txt, '<Line[^>]*>', 'start');
for k = 1:numel(ms)
  if ~isempty(strfind(ms{k}, sprintf('<P Name="Src">%s</P>', srcRef)))
    lStart = starts(k);
    lEnd = lStart + numel(ms{k}) - 1;
    lineXml = ms{k};
    return;
  end
end
end

function sid = requireSid(txt, blkName)
el = findBlockInText(txt, blkName);
if isempty(el)
  error('找不到块 %s', blkName);
end
m = regexp(el, 'SID="([^"]*)"', 'tokens', 'once');
sid = m{1};
end

% ===========================================================================
%  定位与工具
% ===========================================================================
function op = normalizeOp(op)
% 归一化成 {verb, ...}；支持 {块路径, 参数名, 新值} 的简写
if ~iscell(op), error('snp_xml_edit:badOp', '每条操作必须是 cell'); end
if numel(op) < 2, error('snp_xml_edit:badOp', '操作至少要有 2 个元素'); end
verbs = {'set_param', 'add_block', 'remove_block', 'add_line', 'remove_line'};
first = char(op{1});
if any(strcmp(first, verbs))
  op = op(:)';
  return;
end
if numel(op) < 3, error('snp_xml_edit:badOp', '操作元素不足'); end
op = [{'set_param'}, op(:)'];
end

function s = opDetail(op)
if numel(op) >= 2, s = char(op{2}); else, s = ''; end
end

function idx = lastSystemClose(txt)
pos = strfind(txt, '</System>');
if isempty(pos), error('找不到 </System> 收尾'); end
idx = pos(end);
end

function file = systemFileForPath(exDir, parentPath)
% 父路径 → 该子系统所在的 XML 文件（'' = 模型顶层）
sysDir = fullfile(exDir, 'simulink', 'systems');
file = fullfile(sysDir, 'system_root.xml');
segs = strsplit(strrep(char(parentPath), '\', '/'), '/');
segs = segs(~cellfun(@isempty, segs));
for k = 1:numel(segs)
  txt = fileread(file);
  el = findBlockInText(txt, segs{k});
  if isempty(el)
    error('找不到子系统 %s', segs{k});
  end
  rf = regexp(el, '<System\s+Ref="([^"]+)"', 'tokens', 'once');
  if isempty(rf)
    error('%s 不是子系统（没有 <System Ref>）', segs{k});
  end
  file = fullfile(sysDir, rf{1});
  if ~isfile(file)
    if isfile([file '.xml']), file = [file '.xml'];
    else, error('子系统 %s 指向的文件不存在: %s', segs{k}, rf{1}); end
  end
end
end

function [found, file, blockXml] = locateBlock(exDir, blkPath)
% 按模型内路径逐级下沉：system_root.xml -> 子系统 Ref 指向的 system_*.xml
% 返回的 file 是 XML 文件的完整路径（调用方直接拿去读写）。
found = false; file = ''; blockXml = '';
segs = strsplit(strrep(char(blkPath), '\', '/'), '/');
segs = segs(~cellfun(@isempty, segs));
sysDir = fullfile(exDir, 'simulink', 'systems');
file = fullfile(sysDir, 'system_root.xml');
if ~isfile(file)
  error('snp_xml_edit:noRoot', '包内找不到 system_root.xml');
end
for k = 1:numel(segs)
  txt = fileread(file);
  [blockXml, refFile] = findBlockInText(txt, segs{k});
  if isempty(blockXml)
    return;
  end
  if k == numel(segs)
    found = true;
    return;
  end
  if isempty(refFile)
    error('snp_xml_edit:path', '路径 %s 中 %s 不是子系统，无法继续向下定位', ...
      char(blkPath), segs{k});
  end
  file = fullfile(sysDir, refFile);
  if ~isfile(file)
    if isfile([file '.xml']), file = [file '.xml'];
    else, error('snp_xml_edit:noRef', '子系统 %s 指向的文件不存在: %s', segs{k}, refFile); end
  end
end
end

function [blockXml, refFile] = findBlockInText(txt, blkName)
% 在一个 system XML 里找名为 blkName 的块；顺带取它内部的 <System Ref="..."/>
blockXml = ''; refFile = '';
% 块元素跨多行（MATLAB 的 . 默认能匹配换行）。
% 注意：不要用 \b 字边界——实测 MATLAB 的 regexp 里 '<Block\b' 匹配数为 0。
ms = regexp(txt, '<Block[^>]*>.*?</Block>', 'match');
for k = 1:numel(ms)
  el = ms{k};
  % 名字只从**开始标签**里取：块内部还有 <P Name="..."> 之类的子元素，
  % 直接在整段里搜 Name=" 会误命中（如 <P Name="Name">）。
  openTag = regexp(el, '^<Block[^>]*>', 'match', 'once');
  nm = regexp(openTag, 'Name="([^"]*)"', 'tokens', 'once');
  if isempty(nm) || ~strcmp(nm{1}, blkName)
    continue;
  end
  blockXml = el;
  rf = regexp(el, '<System\s+Ref="([^"]+)"', 'tokens', 'once');
  if ~isempty(rf)
    refFile = rf{1};
  end
  return;
end
end

function sid = allocSid(exDir)
% 分配一个全模型唯一的 SID
sysDir = fullfile(exDir, 'simulink', 'systems');
files = dir(fullfile(sysDir, 'system_*.xml'));
maxSid = 0;
for k = 1:numel(files)
  txt = fileread(fullfile(sysDir, files(k).name));
  ids = regexp(txt, 'SID="(\d+)"', 'tokens');
  for q = 1:numel(ids)
    v = str2double(ids{q}{1});
    if v > maxSid, maxSid = v; end
  end
end
sid = sprintf('%d', maxSid + 1);
end

function z = allocZOrder(txt)
ids = regexp(txt, '<P Name="ZOrder">(\d+)</P>', 'tokens');
m = 0;
for q = 1:numel(ids)
  v = str2double(ids{q}{1});
  if v > m, m = v; end
end
z = m + 1;
end

function writeText(file, txt)
fid = fopen(file, 'w'); fwrite(fid, txt, 'char'); fclose(fid);
end

function names = zipEntryNames(zipPath)
zin = java.util.zip.ZipFile(java.io.File(zipPath));
it = zin.entries();
names = {};
while it.hasMoreElements()
  ent = it.nextElement();
  names{end+1} = char(ent.getName()); %#ok<AGROW>
end
zin.close();
end

function repackZip(srcZip, dstZip, exDir)
% 按原包的条目顺序重打包；内容一律从磁盘按字节取（二进制也原样保留）
[parentDir, ~, ~] = fileparts(dstZip);
if ~isempty(parentDir) && ~isfolder(parentDir)
  mkdir(parentDir);
end
names = zipEntryNames(srcZip);
zout = java.util.zip.ZipOutputStream(java.io.FileOutputStream(dstZip));
zout.setLevel(9);
for k = 1:numel(names)
  nm = names{k};
  zout.putNextEntry(java.util.zip.ZipEntry(nm));
  if ~endsWith(nm, '/')
    p = fullfile(exDir, strrep(nm, '/', filesep));
    f = fopen(p, 'r');
    if f < 0
      error('snp_xml_edit:missingEntry', '重打包时缺少条目 %s', nm);
    end
    data = fread(f, Inf, '*int8');
    fclose(f);
    if ~isempty(data)
      zout.write(data);
    end
  end
  zout.closeEntry();
end
zout.close();
end

function s = xmlEscape(s)
s = strrep(s, '&', '&amp;');
s = strrep(s, '<', '&lt;');
s = strrep(s, '>', '&gt;');
s = strrep(s, '"', '&quot;');
end
