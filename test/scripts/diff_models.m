function diff_models(modelName, pathA, pathB)
% 结构深对比：两个模型文件逐个子系统比块集合与连线集合
%
%  用途：重建件与原件的差异定位——先说清"哪里不同"，再决定怎么修。
%  判据：块集合（按名排序）与连线集合（按 "src:port->dst:port" 排序）完全一致。
%
%  用法：diff_models('ToyBasic', '<原件路径>', '<重建件路径>')
nm = modelName;

try, close_system(nm, 0); catch, end
load_system(pathA);
A = collect_model(nm);
try, close_system(nm, 0); catch, end
load_system(pathB);
B = collect_model(nm);
try, close_system(nm, 0); catch, end

fprintf('子系统数：原件 %d，重建 %d\n', numel(A), numel(B));
nDiff = 0;
for k = 1:numel(A)
  j = find(strcmp({B.path}, A(k).path), 1);
  if isempty(j)
    fprintf('%s : 重建件里没有这个子系统\n', A(k).path); nDiff = nDiff + 1; continue;
  end
  if ~isequal(A(k).blks, B(j).blks)
    fprintf('%s : 块集合不同\n   原: %s\n   新: %s\n', A(k).path, ...
      strjoin(A(k).blks, ','), strjoin(B(j).blks, ','));
    nDiff = nDiff + 1;
  end
  if ~isequal(A(k).lines, B(j).lines)
    fprintf('%s : 连线不同（%d vs %d）\n', A(k).path, numel(A(k).lines), numel(B(j).lines));
    d1 = setdiff(A(k).lines, B(j).lines);
    d2 = setdiff(B(j).lines, A(k).lines);
    for q = 1:min(8, numel(d1)), fprintf('     仅原件有: %s\n', d1{q}); end
    for q = 1:min(8, numel(d2)), fprintf('     仅重建有: %s\n', d2{q}); end
    nDiff = nDiff + 1;
  end
end
fprintf('== 子系统差异数 %d ==\n', nDiff);
end

function out = collect_model(mdl)
out = struct('path', {}, 'blks', {}, 'lines', {});
% 全深度：每个块（含嵌套）都作为一个"容器"单独比内部
subs = find_system(mdl, 'LookUnderMasks', 'all', 'Type', 'block');
n = 0;
for k = 1:numel(subs)
  s = subs{k};
  if isempty(strfind(s, '/')), continue; end
  b = find_system(s, 'LookUnderMasks', 'all', 'SearchDepth', 1, 'Type', 'block');
  nm = {};
  for j = 1:numel(b), nm{end+1} = get_param(b{j}, 'Name'); end %#ok<AGROW>
  l = find_system(s, 'FindAll', 'on', 'LookUnderMasks', 'all', 'SearchDepth', 1, 'Type', 'line');
  ls = {};
  for j = 1:numel(l)
    try
      sb = get_param(get_param(l(j), 'SrcBlockHandle'), 'Name');
      sp = get_param(get_param(l(j), 'SrcPortHandle'), 'PortNumber');
      dh = get_param(l(j), 'DstPortHandle'); dh = dh(dh > 0);
      for q = 1:numel(dh)
        ls{end+1} = sprintf('%s:%d->%s:%d', sb, sp, ...
          get_param(get_param(dh(q), 'Parent'), 'Name'), get_param(dh(q), 'PortNumber')); %#ok<AGROW>
      end
    catch
    end
  end
  ls = sort(ls);
  n = n + 1;
  out(n).path = s; out(n).blks = sort(nm); out(n).lines = ls;
end
end
