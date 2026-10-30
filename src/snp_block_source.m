function src = snp_block_source(blockType)
%SNP_BLOCK_SOURCE  块型（BlockType）→ 库路径（add_block 用的源路径）
%
%  为什么单独成文件：库路径是 Simulink **API 侧**的知识——只有 add_block 这条
%  命令需要它。模型文件本身不需要：.slx 内部 XML 里普通块只记 BlockType，
%  Simulink 载入时自己解析（2026-10-28 实测：只写 BlockType="Gain"、不带任何
%  库路径的新块，能被正常识别、参数可读回、连线成立，模型仿真与原件逐信号
%  相同 max|diff|=0）。因此：
%    · XML 原地编辑（增删块、改参数）——用不到本函数；
%    · M 快照路线（add_block）与将来的 XML→M 回灌——必须用它。
%  两条路线共用这一份表，不要再复制第二份（一个概念一个名字）。
%
%  覆盖度（2026-10-29 实测）：
%    ① 本项目 25 模型/库用到 30 种 BlockType，逐一实测覆盖（D3：文档名≠BlockType）；
%    ② Detailed 线 8 模型新增 7 种（8b2a632）；
%    ③ probe_lib_coverage 枚举 R2023b 'simulink' 核心库 502 块 / 163 种
%    BlockType，表外 119 种逐一 add_block 实测收录——除 SubSystem（容器，
%    expand_masked/rb 处理）与 S-Function（snp_export 的 S-Function 特判分支）两个
%    设计性例外外，'simulink' 库全覆盖。
%    ④ 工具箱库穷举（T38 双发现机制：slblocks().OpenFcn 得 52 顶层库 +
%    physmod/**/library/*.slx 得 278 子库）：四 subagent 并行 T24 实测，
%    收录 33 种新块型（SimEvents 实体系、nesl_utility Simscape 工具系、
%    FMU/Reciprocal/Reference/Observer 等）。未入表的结构性端口块见 T39
%    （Fault*/StateControl 必须位于特定子系统内，不能裸 add_block）。
%    有 rb 的块导出时优先走 rb（L148），表条目是无 rb 时的回退（T40）。
%  路径换行约定：库名含真 char(10)（如 'Math⏎Operations'，T28），表中记为字面
%  \n，函数返回前还原成真 char(10)。
%
%  未收录的块型返回 ''，调用方据此走特殊路径或跳过。
bt = char(blockType);
switch bt
  case 'Constant',            src = 'simulink/Sources/Constant';
  case 'Step',                src = 'simulink/Sources/Step';
  case 'Ramp',                src = 'simulink/Sources/Ramp';
  case 'Sin',                 src = 'simulink/Sources/Sine Wave';
  case 'SineWave',            src = 'simulink/Sources/Sine Wave';
  case 'Gain',                src = 'simulink/Math Operations/Gain';
  case 'Sum',                 src = 'simulink/Math Operations/Sum';
  case 'Product',             src = 'simulink/Math Operations/Product';
  case 'Math',                src = 'simulink/Math Operations/Math Function';
  case 'Trigonometry',        src = 'simulink/Math Operations/Trigonometric Function';
  case 'Saturate',            src = 'simulink/Discontinuities/Saturation';
  case 'UnitDelay',           src = 'simulink/Discrete/Unit Delay';
  case 'DiscreteTransferFcn', src = 'simulink/Discrete/Discrete Transfer Fcn';
  case 'Integrator',          src = 'simulink/Continuous/Integrator';
  case 'Mux',                 src = 'simulink/Signal Routing/Mux';
  case 'MultiPortSwitch',     src = 'simulink/Signal Routing/Multiport Switch';
  case 'From',                src = 'simulink/Signal Routing/From';
  case 'Goto',                src = 'simulink/Signal Routing/Goto';
  case 'Scope',               src = 'simulink/Sinks/Scope';
  case 'ToWorkspace',         src = 'simulink/Sinks/To Workspace';
  case 'Terminator',          src = 'simulink/Sinks/Terminator';
  case 'DigitalClock',        src = 'simulink/Sources/Digital Clock';
  case 'Inport',              src = 'simulink/Sources/In1';
  case 'Outport',             src = 'simulink/Sinks/Out1';
  % 库/断链副本内部出现的块型（R2023b add_block 实测路径，2026-10-23）
  case 'Abs',                 src = 'simulink/Math Operations/Abs';
  case 'MinMax',              src = 'simulink/Math Operations/MinMax';
  case 'RelationalOperator',  src = 'simulink/Logic and Bit Operations/Relational Operator';
  case 'Rounding',            src = 'simulink/Math Operations/Rounding Function';
  case 'Switch',              src = 'simulink/Signal Routing/Switch';
  case 'Demux',               src = 'simulink/Signal Routing/Demux';
  case 'DataStoreMemory',     src = 'simulink/Signal Routing/Data Store Memory';
  case 'DataStoreRead',       src = 'simulink/Signal Routing/Data Store Read';
  case 'DataStoreWrite',      src = 'simulink/Signal Routing/Data Store Write';
  case 'BusCreator',          src = 'simulink/Signal Routing/Bus Creator';
  case 'BusSelector',         src = 'simulink/Signal Routing/Bus Selector';
  case 'ModelReference',      src = 'simulink/Ports & Subsystems/Model';
  case 'S-Function',          src = '';  % MATLAB Function 块由 chart 脚本判定
  % Simscape 物理端口：跨子系统边界传播物理连接。fl_lib 里无此块型（fl_lib 的
  % "Physical Signals" 是 PS 信号库，非电气物理端口）；它是 Simulink 内建块，
  % 2026-10-28 实测 add_block('built-in/PMIOPort',…) 可用且 BlockType=='PMIOPort'。
  case 'PMIOPort',           src = 'built-in/PMIOPort';
  % ---- Detailed 线（早期大规模验证实测，2026-10-29；该资产已移出仓库）----
  % 这 7 种是原 25 模型之外的缺口（8 个 Detailed 模型共 144 块）。每种都在 R2023b
  % 里 add_block 真建过并回读 BlockType 确认一致（T24 判据），不是凭文档名猜的
  % （文档名≠BlockType，见 D3）。S-Function 不在此列：它由 snp_export 第 185 行
  % 按 chart 脚本判定真假，不在本表硬给路径。
  case 'Clock',              src = 'simulink/Sources/Clock';
  case 'DataTypeConversion', src = 'simulink/Signal Attributes/Data Type Conversion';
  case 'Delay',              src = 'simulink/Discrete/Delay';
  case 'Fcn',                src = 'simulink/User-Defined Functions/Fcn';
  case 'Logic',              src = 'simulink/Logic and Bit Operations/Logical Operator';
  case 'Selector',           src = 'simulink/Signal Routing/Selector';
  case 'ZeroOrderHold',      src = 'simulink/Discrete/Zero-Order Hold';
  % ---- 全库覆盖（2026-10-29，probe_lib_coverage 枚举 R2023b 'simulink' 核心库
  % 502 块 / 163 种 BlockType；表外 119 种逐一 add_block 实测 + 回读 BlockType
  % 一致，T24 判据全过）。至此 'simulink' 库除 SubSystem/S-Function（设计性
  % 不在表：前者由 expand_masked/rb 处理，后者由 snp_export 第 185 行特判）外
  % 全覆盖。其它工具箱库（Simscape 的 fl_lib/ee_lib 等）的物理块走 rb 链接，
  % 不经本表。
  % 路径换行约定：库名含真 char(10)（如 'Math⏎Operations'，T28 现象），表中
  % 记为字面 \n（单引号串内是反斜杠+n 两字符），函数返回前统一还原成真
  % char(10)。空格版 add_block 仅抽测 1 例成功，换行版是 119 例逐一全验证，
  % 故存换行版。
  case 'ASCIIToString',              src = 'simulink/String/ASCII to String';
  case 'AlgebraicConstraint',        src = 'simulink/Math\nOperations/Algebraic Constraint';
  case 'ArithShift',                 src = 'simulink/Logic and Bit\nOperations/Shift\nArithmetic';
  case 'Assertion',                  src = 'simulink/Model\nVerification/Assertion';
  case 'Assignment',                 src = 'simulink/Math\nOperations/Assignment';
  case 'Backlash',                   src = 'simulink/Discontinuities/Backlash';
  case 'Bias',                       src = 'simulink/Math\nOperations/Bias';
  case 'BusAssignment',              src = 'simulink/Signal\nRouting/Bus\nAssignment';
  case 'BusToVector',                src = 'simulink/Signal\nAttributes/Bus to Vector';
  case 'CCaller',                    src = 'simulink/User-Defined\nFunctions/C Caller';
  case 'CFunction',                  src = 'simulink/User-Defined\nFunctions/C Function';
  case 'CombinatorialLogic',         src = 'simulink/Logic and Bit\nOperations/Combinatorial \nLogic';
  case 'ComplexToMagnitudeAngle',    src = 'simulink/Math\nOperations/Complex to\nMagnitude-Angle';
  case 'ComplexToRealImag',          src = 'simulink/Math\nOperations/Complex to\nReal-Imag';
  case 'ComposeString',              src = 'simulink/String/Compose String';
  case 'Concatenate',                src = 'simulink/Commonly\nUsed Blocks/Vector\nConcatenate';
  case 'DataTypeDuplicate',          src = 'simulink/Signal\nAttributes/Data Type\nDuplicate';
  case 'DeadZone',                   src = 'simulink/Discontinuities/Dead Zone';
  case 'Derivative',                 src = 'simulink/Continuous/Derivative';
  case 'DescriptorStateSpace',       src = 'simulink/Continuous/Descriptor State-Space';
  case 'DiscreteFilter',             src = 'simulink/Discrete/Discrete Filter';
  case 'DiscreteFir',                src = 'simulink/Discrete/Discrete FIR Filter';
  case 'DiscreteIntegrator',         src = 'simulink/Commonly\nUsed Blocks/Discrete-Time\nIntegrator';
  case 'DiscretePulseGenerator',     src = 'simulink/Quick Insert/Sources/Continuous\nPulse Generator';
  case 'DiscreteStateSpace',         src = 'simulink/Discrete/Discrete State-Space';
  case 'DiscreteZeroPole',           src = 'simulink/Discrete/Discrete\nZero-Pole';
  case 'Display',                    src = 'simulink/Sinks/Display';
  case 'DotProduct',                 src = 'simulink/Math\nOperations/Dot Product';
  case 'EnablePort',                 src = 'simulink/Ports &\nSubsystems/Enable';
  case 'EntityTransportDelay',       src = 'simulink/Continuous/Entity\nTransport Delay';
  case 'Find',                       src = 'simulink/Math\nOperations/Find Nonzero\nElements';
  case 'FirstOrderHold',             src = 'simulink/Continuous/First Order Hold';
  case 'FloatExtractBits',           src = 'simulink/Logic and Bit\nOperations/Float Extract Bits';
  case 'FromFile',                   src = 'simulink/Sources/From File';
  case 'FromSpreadsheet',            src = 'simulink/Sources/From Spreadsheet';
  case 'FromWorkspace',              src = 'simulink/Sources/From\nWorkspace';
  case 'FunctionCallFeedbackLatch',  src = 'simulink/Ports &\nSubsystems/Function-Call\nFeedback Latch';
  case 'FunctionCallSplit',          src = 'simulink/Ports &\nSubsystems/Function-Call\nSplit';
  case 'FunctionCaller',             src = 'simulink/User-Defined\nFunctions/Function Caller';
  case 'GotoTagVisibility',          src = 'simulink/Signal\nRouting/Goto Tag\nVisibility';
  case 'Ground',                     src = 'simulink/Commonly\nUsed Blocks/Ground';
  case 'HitCross',                   src = 'simulink/Discontinuities/Hit \nCrossing';
  case 'HitScheduler',               src = 'simulink/Messages\n& Events/Hit Scheduler';
  case 'IdentityMatrix',             src = 'simulink/Matrix\nOperations/IdentityMatrix';
  case 'If',                         src = 'simulink/Ports &\nSubsystems/If';
  case 'InitialCondition',           src = 'simulink/Signal\nAttributes/IC';
  case 'Interpolation_n-D',          src = 'simulink/Lookup\nTables/Interpolation\nUsing Prelookup';
  case 'IsHermitian',                src = 'simulink/Matrix\nOperations/IsHermitian';
  case 'IsSymmetric',                src = 'simulink/Matrix\nOperations/IsSymmetric';
  case 'IsTriangular',               src = 'simulink/Matrix\nOperations/IsTriangular';
  case 'LookupNDDirect',             src = 'simulink/Lookup\nTables/Direct Lookup\nTable (n-D)';
  case 'Lookup_n-D',                 src = 'simulink/Lookup\nTables/1-D Lookup\nTable';
  case 'M-S-Function',               src = 'simulink/User-Defined\nFunctions/Level-2 MATLAB\nS-Function';
  case 'MATLABFcn',                  src = 'simulink/User-Defined\nFunctions/Interpreted MATLAB\nFunction';
  case 'MATLABSystem',               src = 'simulink/User-Defined\nFunctions/MATLAB System';
  case 'MagnitudeAngleToComplex',    src = 'simulink/Math\nOperations/Magnitude-Angle\nto Complex';
  case 'ManualSwitch',               src = 'simulink/Signal\nRouting/Manual Switch';
  case 'Memory',                     src = 'simulink/Discrete/Memory';
  case 'Merge',                      src = 'simulink/Signal\nRouting/Merge';
  case 'MessageMerge',               src = 'simulink/Messages\n& Events/Message Merge';
  case 'MessageViewer',              src = 'simulink/Messages\n& Events/Sequence Viewer';
  case 'ParameterWriter',            src = 'simulink/Signal\nRouting/Parameter Writer';
  case 'PermuteDimensions',          src = 'simulink/Math\nOperations/Permute\nDimensions';
  case 'Playback',                   src = 'simulink/Sources/Playback';
  case 'Polyval',                    src = 'simulink/Math\nOperations/Polynomial';
  case 'PreLookup',                  src = 'simulink/Lookup\nTables/Prelookup';
  case 'Probe',                      src = 'simulink/Quick Insert/Signal\nAttributes/Probe Complexity';
  case 'PropagationDelay',           src = 'simulink/Discrete/Propagation Delay';
  case 'Quantizer',                  src = 'simulink/Discontinuities/Quantizer';
  case 'Queue',                      src = 'simulink/Messages\n& Events/Queue';
  case 'RandomNumber',               src = 'simulink/Sources/Random\nNumber';
  case 'RateLimiter',                src = 'simulink/Discontinuities/Rate Limiter';
  case 'RateTransition',             src = 'simulink/Signal\nAttributes/Rate Transition';
  case 'RealImagToComplex',          src = 'simulink/Math\nOperations/Real-Imag to\nComplex';
  case 'Receive',                    src = 'simulink/Messages\n& Events/Receive';
  case 'Record',                     src = 'simulink/Sinks/Record';
  case 'Relay',                      src = 'simulink/Discontinuities/Relay';
  case 'Reshape',                    src = 'simulink/Math\nOperations/Reshape';
  case 'SampleTimeMath',             src = 'simulink/Math\nOperations/Weighted\nSample Time\nMath';
  case 'ScanString',                 src = 'simulink/String/Scan String';
  case 'SecondOrderIntegrator',      src = 'simulink/Continuous/Integrator,\nSecond-Order';
  case 'Send',                       src = 'simulink/Messages\n& Events/Send';
  case 'SignalConversion',           src = 'simulink/Quick Insert/Signal\nAttributes/Signal Copy';
  case 'SignalGenerator',            src = 'simulink/Quick Insert/Sources/Sawtooth\nGenerator';
  case 'SignalSpecification',        src = 'simulink/Signal\nAttributes/Signal Specification';
  case 'Signum',                     src = 'simulink/Math\nOperations/Sign';
  case 'Sqrt',                       src = 'simulink/Math\nOperations/Reciprocal\nSqrt';
  case 'Squeeze',                    src = 'simulink/Math\nOperations/Squeeze';
  case 'StateReader',                src = 'simulink/Signal\nRouting/State Reader';
  case 'StateSpace',                 src = 'simulink/Continuous/State-Space';
  case 'StateWriter',                src = 'simulink/Signal\nRouting/State Writer';
  case 'Stop',                       src = 'simulink/Sinks/Stop Simulation';
  case 'StringCompare',              src = 'simulink/String/String Compare';
  case 'StringConcatenate',          src = 'simulink/String/String Concatenate';
  case 'StringConstant',             src = 'simulink/String/String Constant';
  case 'StringContains',             src = 'simulink/String/String Contains';
  case 'StringCount',                src = 'simulink/String/String Count';
  case 'StringFind',                 src = 'simulink/String/String Find';
  case 'StringLength',               src = 'simulink/String/String Length';
  case 'StringToASCII',              src = 'simulink/String/String to ASCII';
  case 'StringToEnum',               src = 'simulink/String/String to Enum';
  case 'Substring',                  src = 'simulink/String/Substring';
  case 'SwitchCase',                 src = 'simulink/Ports &\nSubsystems/Switch Case';
  case 'ToFile',                     src = 'simulink/Sinks/To File';
  case 'ToString',                   src = 'simulink/String/To String';
  case 'TransferFcn',                src = 'simulink/Continuous/Transfer Fcn';
  case 'TransportDelay',             src = 'simulink/Continuous/Transport\nDelay';
  case 'TriggerPort',                src = 'simulink/Ports &\nSubsystems/Trigger';
  case 'TwoWayConnection',           src = 'simulink/Signal\nRouting/Two-Way\nConnection';
  case 'UnaryMinus',                 src = 'simulink/Math\nOperations/Unary Minus';
  case 'UniformRandomNumber',        src = 'simulink/Sources/Uniform Random\nNumber';
  case 'UnitConfiguration',          src = 'simulink/Ports &\nSubsystems/Unit System Configuration';
  case 'UnitConversion',             src = 'simulink/Signal\nAttributes/Unit Conversion';
  case 'VariablePulseGenerator',     src = 'simulink/Discontinuities/Variable Pulse Generator';
  case 'VariableTransportDelay',     src = 'simulink/Continuous/Variable\nTime Delay';
  case 'VariantSink',                src = 'simulink/Signal\nRouting/Manual\nVariant Sink';
  case 'VariantSource',              src = 'simulink/Signal\nRouting/Manual\nVariant Source';
  case 'Width',                      src = 'simulink/Signal\nAttributes/Width';
  case 'ZeroPole',                   src = 'simulink/Continuous/Zero-Pole';
  % ---- 工具箱库（2026-10-29，四 subagent 并行实测，T38 双发现机制）----
  % 来源：slblocks().OpenFcn 发现 52 顶层库（A/B/C/D 组并行实测）+ physmod
  % **/library/*.slx 发现 278 子库（Simscape Lib 系 + sps*Model 实测）。
  % 全部经 T24 判据（add_block + 回读 BlockType 一致）。路径换行同核心库约定
  % （字面 \n，返回前 strrep 还原）。
  % 未入表的结构性端口块（T39）：FaultInport/FaultOutport/StateControl——
  % 它们必须位于特定子系统内、不能裸 add_block，M 线重建由父系统随之生成。
case 'FindEntity',                 src = 'sldelib/Entity Find';
case 'SimscapeBlock',              src = 'fl_lib/Electrical/Electrical Elements/Capacitor';
case 'FloatTypecast',              src = 'hdlsllib/HDL Floating Point\nOperations/Float Typecast';
case 'VariantPMConnector',         src = 'nesl_utility/Variant Connector';
case 'SimscapeBus',                src = 'nesl_utility/Simscape Bus';
case 'EntityResourcePool',         src = 'sldelib/Resource Pool';
case 'EntityResourceReleaser',     src = 'sldelib/Resource\nReleaser';
case 'EntityStore',                src = 'sldelib/Entity Store';
case 'Reciprocal',                 src = 'simulink_extras/Additional Math/HDL Reciprocal';
case 'Reference',                  src = 'serdesTopLevel/Datapath Blocks/Automatic Gain Control';
case 'EntityGate',                 src = 'sldelib/Entity Gate';
case 'EntityTerminator',           src = 'sldelib/Entity Terminator';
case 'PMComponent',                src = 'sps_lib/Passives/Mutual Inductance';
case 'EntityReplicator',           src = 'sldelib/Entity Replicator';
case 'EntityBatchCreator',         src = 'sldelib/Entity Batch\nCreator';
case 'CompositeEntityCreator',     src = 'sldelib/Composite Entity\nCreator';
case 'FMU',                        src = 'simulink_extras/FMU Import/FMU';
case 'ObserverPort',               src = 'sltestlib/ObserverPort';
case 'ObserverReference',          src = 'sltestlib/Observer';
case 'EntityInputSwitch',          src = 'sldelib/Entity\nInput Switch';
case 'SpectrumAnalyzer',           src = 'nesl_utility/Spectrum\nAnalyzer';
case 'EntityOutputSwitch',         src = 'sldelib/Entity\nOutput Switch';
case 'SimscapeComponentBlock',     src = 'nesl_utility/Simscape\nComponent';
case 'AsynchronousTaskSpecification', src = 'rtwlib/Asynchronous/Asynchronous Task\nSpecification';
case 'EntityResourceAcquirer',     src = 'sldelib/Resource\nAcquirer';
case 'ConnectionLabel',            src = 'nesl_utility/Connection Label';
case 'EntityMulticast',            src = 'sldelib/Entity Multicast';
case 'CompositeEntitySplitter',    src = 'sldelib/Composite Entity\nSplitter';
case 'SimscapeProbe',              src = 'nesl_utility/Probe';
case 'MATLABDiscreteEventSystem',  src = 'sldelib/Conveyor System';
case 'EntityServer',               src = 'sldelib/Entity Server';
case 'EntityGenerator',            src = 'sldelib/Entity Generator';
case 'EntityBatchSplitter',        src = 'sldelib/Entity Batch\nSplitter';
  % ---- A 线补充：Fixed-Point Designer 查表块（2023b library/ 目录约定，T24 实测）----
  case 'Lookup',                  src = 'fixpt_megmalib/Parameter and\nConstant/Parameter1D\nIndex';
  case 'Lookup2D',                src = 'fixpt_megmalib/Parameter and\nConstant/Parameter2D\nIndex';
  % X1/X2 线实测新增（R2025a/R2026a 穷举唯一新块型，nesl_utility/Array Connection）：
  % 2023b 无此 BlockType（模型不含该块型时本条不触发，零副作用；T40 同理）
  case 'SimscapeArrayConnection', src = 'nesl_utility/Array Connection';
  otherwise,                  src = '';
end

% 字面 \n 还原成真 char(10)（T28：add_block 需要真换行）。
% 已有条目均无反斜杠，此处对它们是 no-op。
if ischar(src) && contains(src, '\n')
  src = strrep(src, '\n', sprintf('\n'));
end
end
