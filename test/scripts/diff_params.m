function diff_params(modelName, pathA, pathB)
% 全参数比对：两个模型逐块比所有可写对话框参数
%
%  用途：结构（块/线）一致但仿真报错时，差异一定在参数里——本工具直接指出
%  第一个不一致的块与参数名。
%
%  用法：diff_params('ToyBasic', '<原件路径>', '<重建件路径>')
nm = modelName;

try, close_system(nm, 0); catch, end
load_system(pathA);
A = grab(nm);
try, close_system(nm, 0); catch, end
load_system(pathB);
B = grab(nm);
try, close_system(nm, 0); catch, end

fprintf('块数：原件 %d，重建 %d\n', numel(A), numel(B));
nDiff = 0;
bp = cell(size(B)); for k = 1:numel(B), bp{k} = B(k).path; end
for k = 1:numel(A)
  j = find(strcmp(bp, A(k).path), 1);
  if isempty(j)
    fprintf('%s : 重建件缺此块\n', A(k).path); nDiff = nDiff + 1; continue;
  end
  common = intersect(A(k).name, B(j).name);
  for q = 1:numel(common)
    p = common{q};
    va = A(k).val.(p); vb = B(j).val.(p);
    if ~isequaln(va, vb)
      fprintf('%s : 参数 ''%s'' 不同\n   原: %s\n   新: %s\n', A(k).path, p, ...
        num2str_any(va), num2str_any(vb));
      nDiff = nDiff + 1;
    end
  end
end
fprintf('== 参数差异数 %d ==\n', nDiff);
end

function s = num2str_any(v)
if ischar(v), s = v;
elseif isnumeric(v) || islogical(v), s = mat2str(v);
else, s = sprintf('<%s>', class(v));
end
end

function out = grab(mdl)
out = struct('path', {}, 'name', {}, 'val', {});
blks = find_system(mdl, 'LookUnderMasks', 'all', 'FollowLinks', 'off', 'Type', 'block');
n = 0;
for k = 1:numel(blks)
  b = blks{k};
  try
    dps = get_param(b, 'DialogParameters');
  catch
    continue;
  end
  if isempty(dps), continue; end
  fn = fieldnames(dps);
  vals = struct();
  keep = {};
  for j = 1:numel(fn)
    p = fn{j};
    at = '';
    try, at = dps.(p).Attributes; catch, end
    if (iscell(at) && any(strcmp('read-only', at))) || (ischar(at) && contains(at, 'read-only'))
      continue;
    end
    try
      v = get_param(b, p);
      if ischar(v) || isnumeric(v) || islogical(v)
        vals.(p) = v; keep{end+1} = p; %#ok<AGROW>
      end
    catch
    end
  end
  n = n + 1;
  out(n).path = b; out(n).name = keep; out(n).val = vals;
end
end
