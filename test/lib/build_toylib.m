%% build_toylib.m
%  程序化构建玩具库 ToyLib（公开面资产，无宿主业务语义）。
%
%  为什么需要自定义库：库链接（ReferenceBlock）/库传播（snp_propagate）
%  /mask 参数导出等机制都需要一个项目自己的库——内置库的块是内联拷贝，
%  不会形成链接实例（T55）。
%
%  4 个玩具块覆盖四种结构形态：
%    ToyGain   普通库子块（无 mask，内部一个 Gain）
%    ToyLimited 带 saturation 限幅参数的库子块（参数多样性）
%    ToyMasked mask 过的子块（Simulink.Mask 两参数 Kp/Ki，内部 Gain 用 Kp）
%    ToyInner  含内部连线的普通子块（g1→g2 串联——测 T56 内部线 parentRel）
%
%  运行：matlab -batch "addpath('lib'); build_toylib()"

function build_toylib()
  here = fileparts(mfilename('fullpath'));
  addpath(here);
  outDir = fullfile(here, 'blocks');
  if ~isfolder(outDir), mkdir(outDir); end
  outFile = fullfile(outDir, 'ToyLib.slx');

  libName = 'ToyLib';
  if bdIsLoaded(libName), close_system(libName, 0); end
  if isfile(outFile), delete(outFile); end

  % T55：建库必须 new_system(name, 'Library')
  new_system(libName, 'Library');
  open_system(libName);

  %% ToyGain：普通库子块（in u → out y，内部 Gain=2，无 mask）
  lib_build.subsystem(libName, 'ToyGain', {'u'}, {'y'});
  lib_build.gain([libName '/ToyGain'], 'g', '2');
  lib_build.line([libName '/ToyGain'], 'u/1', 'g/1');
  lib_build.line([libName '/ToyGain'], 'g/1', 'y/1');

  %% ToyLimited：内部 Gain → Saturation，mask 暴露限幅参数
  lib_build.subsystem(libName, 'ToyLimited', {'u'}, {'y'});
  add_block('simulink/Discontinuities/Saturation', [libName '/ToyLimited/sat']);
  lib_build.gain([libName '/ToyLimited'], 'g', '1');
  lib_build.line([libName '/ToyLimited'], 'u/1', 'g/1');
  lib_build.line([libName '/ToyLimited'], 'g/1', 'sat/1');
  lib_build.line([libName '/ToyLimited'], 'sat/1', 'y/1');
  lib_build.mask([libName '/ToyLimited'], 'signal', ...
    '玩具限幅：输入乘增益后限幅', ...
    struct('Name', 'UpperLimit', 'Type', 'edit', 'Value', '1', ...
           'Prompt', '上限'));

  %% ToyMasked：Simulink.Mask 两参数，内部 Gain 用 mask 参数 Kp
  lib_build.subsystem(libName, 'ToyMasked', {'u'}, {'y'});
  lib_build.gain([libName '/ToyMasked'], 'g', 'Kp');
  lib_build.line([libName '/ToyMasked'], 'u/1', 'g/1');
  lib_build.line([libName '/ToyMasked'], 'g/1', 'y/1');
  lib_build.mask([libName '/ToyMasked'], 'control', ...
    '玩具掩码：Kp 增益 + Ki 备用', ...
    struct('Name', 'Kp', 'Type', 'edit', 'Value', '2', 'Prompt', '比例增益'));

  %% ToyInner：含内部连线的普通子块（T56 的覆盖目标，必须有内部线）
  lib_build.subsystem(libName, 'ToyInner', {'u'}, {'y'});
  lib_build.gain([libName '/ToyInner'], 'g1', '2');
  lib_build.gain([libName '/ToyInner'], 'g2', '3');
  lib_build.line([libName '/ToyInner'], 'u/1', 'g1/1');
  lib_build.line([libName '/ToyInner'], 'g1/1', 'g2/1');
  lib_build.line([libName '/ToyInner'], 'g2/1', 'y/1');

  save_system(libName, outFile);
  close_system(libName, 0);
  fprintf('ToyLib 已写出: %s\n', outFile);
end
