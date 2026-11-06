function st = snp_runtime_warn(mdl, op)
%SNP_RUNTIME_WARN Simulink 运行时状态提醒（内部函数，无 tool-api 条目）。
%
% 在无保存强关 / 磁盘重载模型之前检查两项 Simulink 运行时特性，
% 命中时发 warning（不阻断执行；可用 warning('off','snp:simRunning')
% 等标准机制静默）：
%
%   1. 仿真运行中（SimulationStatus ~= 'stopped'）：
%      官方明确"仿真运行中不能改模型结构"；bdclose/close_system 会
%      中断正在运行的仿真。
%   2. 未保存的 GUI 改动（Dirty = 'on'）：
%      GUI 改动只存在 MATLAB 内存（标题栏星号），close_system(mdl,0)
%      这类无保存强关会把它**直接丢弃**——pull/propagate 正是这么做的，
%      所以它们必须在强关前提醒人先 save_system。
%
% T70 起**同时返回结构化状态**（仍不阻断，阻断由调用方决策）：
%   st.simRunning  仿真是否在跑
%   st.dirty       是否有未保存 GUI 改动（op='reload' 时才查）
% snp_pull / snp_propagate 据此做"默认阻断 + opts.Force=true 放行"——
% "会丢数据"必须由明确意图推翻，不能默认通过。模型未加载时两项均 false。
%
% 用法：
%   snp_runtime_warn('MyModel', 'reload')   % 要无保存强关+磁盘重载：两项都查
%   snp_runtime_warn('MyModel', 'read')     % 只读模型（导出）：只查仿真中
%   st = snp_runtime_warn('MyModel','reload');  % 取结构化状态做阻断决策
%
% 模型未加载时无提醒（内存里没有就没有可丢的东西）。

st = struct('simRunning', false, 'dirty', false);
if ~bdIsLoaded(mdl), return; end
try
  simst = get_param(mdl, 'SimulationStatus');
catch
  return;   % 极少数情况下模型在内存但参数不可读：不阻塞主流程
end

if ~strcmp(simst, 'stopped')
  st.simRunning = true;
  warning('snp:simRunning', sprintf( ...
    ['[snp] 模型 ''%s'' 正在仿真中（SimulationStatus=%s）。\n' ...
     '  仿真运行中不能改结构，继续会中断仿真——请先停：\n' ...
     '  set_param(''%s'', ''SimulationCommand'', ''stop'')'], mdl, simst, mdl));
end

if strcmp(op, 'reload') && strcmp(get_param(mdl, 'Dirty'), 'on')
  st.dirty = true;
  warning('snp:dirtyUnsaved', sprintf( ...
    ['[snp] 模型 ''%s'' 有未保存的 GUI 改动（Dirty=on，标题栏星号）。\n' ...
     '  GUI 改动只存于 MATLAB 内存，下一步会从磁盘重载并丢弃未保存内容——\n' ...
     '  请先保存：save_system(''%s'')'], mdl, mdl));
end
