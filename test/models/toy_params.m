%% toy_params.m
%  玩具参数（公开面示例数据，无业务语义）。
%
%  与玩具资产的关系：build_toylib / build_toy_models 里的数值刻意保持
%  与本文件一致——改这里后重跑两个 build 脚本即可再生资产。
%  真实项目里同位置的文件是自己的领域参数，本仓库公开面只用玩具值。

function p = toy_params()
  p = struct();
  p.toyGain   = 2;     % ToyBasic 的 g1 / ToyGain 的 g
  p.toyInner1 = 2;     % ToyInner 内部 g1
  p.toyInner2 = 3;     % ToyInner 内部 g2
  p.toyKp     = 5;     % ToyMasked 的 Kp（ToyLibRef 实例改写值）
  p.toyLimit  = 1;     % ToyLimited 的 UpperLimit
end
