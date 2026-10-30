%% build_toy_models.m
%  程序化构建 4 个玩具模型（公开面资产，无宿主业务语义）。
%
%  覆盖本工具机制的四种形态：
%    ToyBasic  纯内置块（Constant+Gain+Scope+画布注释）——基础导出
%    ToyLibRef 引用 ToyLib 四块——库链接/传播/mask 实例
%    ToyChart  独立 Stateflow chart（On/Off 两状态）——chart 结构化导出
%    ToyPhys   Simscape 物理网络（R+C+L+Gnd 物理串联）——物理连接
%
%  运行：matlab -batch "addpath('test/models'); build_toy_models()"

function build_toy_models()
  % src-锚定环：脚本随目录深度变化时自纠正（-batch 下 mfilename 不可靠，T62 同族）
  R = fileparts(fileparts(mfilename('fullpath')));
  while ~exist(fullfile(R, 'src', 'snp_export.m'), 'file') && ~strcmp(R, fileparts(R))
    R = fileparts(R);
  end
  addpath(fullfile(R, 'src'));
  addpath(fullfile(R, 'test', 'lib'));
  bdclose('all');   % 清理上次失败残留的脏模型
  outDir = fullfile(R, 'test', 'models');   % 模型 .slx 落点
  libFile = fullfile(R, 'test', 'lib', 'blocks', 'ToyLib.slx');
  load_system(libFile);   % 库链接实例需要库已加载

  %% ToyBasic
  nm = 'ToyBasic';
  try, close_system(nm, 0); catch, end
  new_system(nm);
  add_block('simulink/Sources/Constant', [nm '/c1'], 'Position', [40 40 80 70]);
  add_block('simulink/Math Operations/Gain', [nm '/g1'], 'Gain', '2', 'Position', [140 40 200 70]);
  add_block('simulink/Sinks/Scope', [nm '/sc1'], 'Position', [260 40 310 70]);
  add_line(nm, 'c1/1', 'g1/1');
  add_line(nm, 'g1/1', 'sc1/1');
  % 画布注释：导出器支持（T54 的替代方案），API 失败则跳过并报告
  annOk = false;
  try
    add_annotation(nm, '玩具模型：基础导出覆盖', [350 40 500 80]);
    annOk = true;
  catch
  end
  save_system(nm, fullfile(outDir, [nm '.slx']));
  close_system(nm, 0);
  fprintf('%s ok (annotation=%d)\n', nm, annOk);

  %% ToyLibRef：引用 ToyLib 4 块
  nm = 'ToyLibRef';
  try, close_system(nm, 0); catch, end
  new_system(nm);
  add_block('simulink/Sources/Constant', [nm '/c1'], 'Position', [40 40 80 70]);
  add_block('ToyLib/ToyGain', [nm '/tg'], 'Position', [140 40 200 80]);
  add_block('ToyLib/ToyInner', [nm '/ti'], 'Position', [260 40 320 80]);
  add_block('ToyLib/ToyLimited', [nm '/tl'], 'Position', [380 40 440 80]);
  add_block('ToyLib/ToyMasked', [nm '/tm'], 'Position', [500 40 560 80], 'Kp', '5');
  add_block('simulink/Sinks/Out1', [nm '/y1'], 'Position', [640 40 690 60]);
  add_line(nm, 'c1/1', 'tg/1');
  add_line(nm, 'tg/1', 'ti/1');
  add_line(nm, 'ti/1', 'tl/1');
  add_line(nm, 'tl/1', 'tm/1');
  add_line(nm, 'tm/1', 'y1/1');
  save_system(nm, fullfile(outDir, [nm '.slx']));
  close_system(nm, 0);
  fprintf('%s ok\n', nm);

  %% ToyChart：独立 Stateflow chart（On/Off）
  nm = 'ToyChart';
  try, close_system(nm, 0); catch, end
  new_system(nm);
  add_block('sflib/Chart', [nm '/c1'], 'Position', [100 100 300 260]);
  % sfroot 不能链式调用（"不支持函数调用语法"）——先赋变量
  rt = sfroot;
  ch = rt.find('-isa', 'Stateflow.Chart', '-and', 'Path', [nm '/c1']);
  sOn = Stateflow.State(ch);
  sOn.Name = 'On'; sOn.Position = [30 20 90 60];
  sOff = Stateflow.State(ch);
  sOff.Name = 'Off'; sOff.Position = [30 120 90 60];
  t = Stateflow.Transition(ch);
  t.Source = sOn; t.Destination = sOff; t.LabelString = 'timeout';
  save_system(nm, fullfile(outDir, [nm '.slx']));
  close_system(nm, 0);
  fprintf('%s ok\n', nm);

  %% ToyPhys：R+C+L+Gnd 物理串联（姿势同 verify_phys_coverage）
  nm = 'ToyPhys';
  try, close_system(nm, 0); catch, end
  new_system(nm);
  add_block('fl_lib/Electrical/Electrical Elements/Resistor', [nm '/r1'], 'Position', [60 60 100 100]);
  add_block('fl_lib/Electrical/Electrical Elements/Capacitor', [nm '/c1'], 'Position', [180 60 220 100]);
  add_block('fl_lib/Electrical/Electrical Elements/Inductor', [nm '/l1'], 'Position', [300 60 340 100]);
  add_block('fl_lib/Electrical/Electrical Elements/Electrical Reference', [nm '/gnd'], 'Position', [300 180 340 220]);
  add_line(nm, 'r1/LConn1', 'c1/LConn1');
  add_line(nm, 'c1/RConn1', 'l1/LConn1');
  add_line(nm, 'l1/RConn1', 'gnd/LConn1');
  save_system(nm, fullfile(outDir, [nm '.slx']));
  close_system(nm, 0);
  fprintf('%s ok\n', nm);
end
