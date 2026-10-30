function nets = snp_phys_connections(container)
% 收集 container 直接子级块之间的物理（Simscape）连接，按**网络**分组返回。
%
%  返回 M×1 cell，每个元素是一个网络：{n×1 cell of 端点字符串}，
%  端点形如 'r1/RConn1'、'gnd/LConn1'。网络内端点按字符串排序（可比对）。
%
%  为什么不能用端口号：物理端口没有"端口序号"语义，get_param(port,'PortNumber')
%  对它们一律返回 1；add_line 传 '<块>/1' 报"Simulink 对象名称无效"（T5）。
%  为什么不用 find_system(Type='line')：T 型物理网络里分支线只有一端落在端口上，
%  按线枚举会丢端口（实测 3 端口网络只看到 1 条完整边，T14）。
%
%  为什么按网络而不是按配对返回：PortConnectivity 给出的是同一网络的**完全图**
%  （3 端口网络 → 3 条两两配对）。照配对逐条 add_line 会在第三个端口报
%  "第二个端口已有信号线连接"——一个端口只能被作为目标连一次。重建必须每个
%  网络连一棵星形生成树（n-1 条边），Simscape 自会归并成同一网络（T14）。
nets = {};
try
  % 容器自身若是 masked 子系统（expand_masked 路径正是这样调用），必须
  % LookUnderMasks='all' 才能看到其内部块——否则 find_system 只返回容器
  % 自身，物理连接归零（静默丢网络，T24 类缺陷）。顶层调用容器是模型、
  % 非 masked，用 'none'；SearchDepth=1 保证不递归进更深层的 masked 子级，
  % 因此不会与 expand_masked 对子级的单独处理重复导出。
  lumat = 'none';
  try
    if strcmp(get_param(container, 'Mask'), 'on'), lumat = 'all'; end
  catch
  end
  blks = find_system(container, 'SearchDepth', 1, 'LookUnderMasks', lumat, ...
    'FollowLinks', 'off', 'Type', 'block');
  blks = setdiff(blks, {container});  % 排除容器自身（其外部端口非内部物理端点）
catch
  return;
end
edges = {};   % 两两配对（已去重）
seen = {};
for i = 1:numel(blks)
  try
    pc = get_param(blks{i}, 'PortConnectivity');
    ownName = get_param(blks{i}, 'Name');
  catch
    continue;
  end
  for k = 1:numel(pc)
    try
      tnm = pc(k).Type;
    catch
      continue;
    end
    if isempty(tnm) || isempty(regexp(tnm, '^[LR]Conn\d+$', 'once')), continue; end
    peers = [];
    for f = {'DstPort', 'SrcPort'}
      try
        v = pc(k).(f{1});
        if ~isempty(v), peers = [peers, v(:)']; end %#ok<AGROW>
      catch
      end
    end
    for q = 1:numel(peers)
      ph = peers(q);
      if ph <= 0, continue; end
      try
        pblk = get_param(get_param(ph, 'Parent'), 'Name');
        pnm = phys_port_name(ph);
      catch
        continue;
      end
      if isempty(pblk) || isempty(pnm), continue; end
      a = sprintf('%s/%s', ownName, tnm);
      b = sprintf('%s/%s', pblk, pnm);
      key = strjoin(sort({a, b}), '>');
      if any(strcmp(seen, key)), continue; end
      seen{end+1} = key; %#ok<AGROW>
      edges{end+1} = {a, b}; %#ok<AGROW>
    end
  end
end
% 连通分量 = 物理网络（并查集，端点用字符串做键）
parent = containers.Map('KeyType', 'char', 'ValueType', 'char');
findRoot = @(x) x;  %#ok<NASGU>
for i = 1:numel(edges)
  for j = 1:2
    e = edges{i}{j};
    if ~isKey(parent, e), parent(e) = e; end
  end
  ra = root_of(parent, edges{i}{1});
  rb = root_of(parent, edges{i}{2});
  if ~strcmp(ra, rb), parent(rb) = ra; end
end
groups = containers.Map('KeyType', 'char', 'ValueType', 'any');
ks = parent.keys;
for i = 1:numel(ks)
  r = root_of(parent, ks{i});
  if ~isKey(groups, r), groups(r) = {}; end
  g = groups(r); g{end+1} = ks{i}; groups(r) = g;
end
gs = groups.values;
for i = 1:numel(gs)
  if numel(gs{i}) >= 2
    nets{end+1} = sort(gs{i}); %#ok<AGROW>
  end
end
end

function r = root_of(parent, x)
r = x;
while true
  p = parent(r);
  if strcmp(p, r), break; end
  r = p;
end
end

function nm = phys_port_name(ph)
% 端口句柄 → add_line 的端口名。物理端口取 PortHandles.LConn/RConn 的序号，
% 普通端口回落为端口号字符串。
nm = '';
par = get_param(ph, 'Parent');
try
  phs = get_param(par, 'PortHandles');
catch
  return;
end
if isfield(phs, 'LConn')
  idx = find(phs.LConn == ph, 1);
  if ~isempty(idx), nm = sprintf('LConn%d', idx); return; end
end
if isfield(phs, 'RConn')
  idx = find(phs.RConn == ph, 1);
  if ~isempty(idx), nm = sprintf('RConn%d', idx); return; end
end
try
  nm = sprintf('%d', get_param(ph, 'PortNumber'));
catch
  nm = '';
end
end
