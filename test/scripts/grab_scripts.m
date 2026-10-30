function out = grab_scripts()
% 收集模型里所有 MATLAB Function 块（chart）的 Script 与 Data 接口
out = struct('path', {}, 'script', {}, 'data', {});
blks = find_system(bdroot, 'LookUnderMasks', 'all', 'FollowLinks', 'off', 'Type', 'block');
n = 0;
for k = 1:numel(blks)
  b = blks{k};
  % MATLAB Function 块：BlockType 显示 SubSystem/S-Function，靠 chart 判定
  ch = sfroot().find('-isa', 'Stateflow.EMChart', '-and', 'Path', b);
  if isempty(ch), continue; end
  sc = '';
  try, sc = ch(1).Script; catch, end
  if ~ischar(sc) || isempty(sc), continue; end
  d = {};
  dd = ch(1).find('-isa', 'Stateflow.Data');
  for j = 1:numel(dd)
    d{end+1} = sprintf('%s:%s', dd(j).Name, dd(j).Scope); %#ok<AGROW>
  end
  n = n + 1;
  out(n).path = b; out(n).script = sc; out(n).data = d;
end
end
