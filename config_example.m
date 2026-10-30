function cfg = config_example()
%CONFIG_EXAMPLE 示例配置——示例孪生（§1.7）。
%
%  本项目所有"随机器/环境变化"的值都经 snp_config() 集中读取：
%    cfg = snp_config();        % 优先 config_local.m（gitignore，本机真值），
%                               % 缺失时回落本文件。
%
%  新机器用法：**复制本文件为 config_local.m 并改成本机的值**。
%  config_local.m 已加入 .gitignore，不会入库（公开面只见本示例）。

cfg = struct();

% --- 运行环境 ---
% MATLAB 可执行文件：从命令行/外部调度 verify 脚本与跨版本测试时用。
% `<matlab-bin>` 是占位符——按你的安装路径替换（如 D:\...\matlab.exe）。
cfg.MatlabBin = '<matlab-bin>';
% 目标版本：snp_export 版本断言的基线（非该版本会要求 AllowUntestedVersion）
cfg.TargetRelease = 'R2023b';

% --- 资产目录（相对仓库根；示例资产统一在 test/ 下） ---
cfg.LibDir = fullfile('test', 'lib', 'blocks');   % 自定义库目录
cfg.ModelsDir = fullfile('test', 'models');       % 演示模型目录
cfg.SnapDir = fullfile('test', 'snapshots');      % 快照输出目录

% --- 导出参数默认值（opts 缺省时） ---
% AliasMap：块名→库名别名映射（个别块与库不同名时才需要；默认空）
cfg.AliasMap = cell(0, 2);
% ExtraHeader：快照头部的额外注入行（项目定制信息；默认空）
cfg.ExtraHeader = {};
% 默认输出目录：验证/诊断产物统一落套件运行时目录（.gitignore，不污染公开面）
cfg.OutDir = fullfile('test', 'scratch');

end
