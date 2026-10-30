function cfg = snp_config()
%SNP_CONFIG 读取本机配置：优先 config_local.m（已 gitignore），回落 config_example.m。
%
%  用法：
%    cfg = snp_config();
%    matlabBin = cfg.MatlabBin;      % MATLAB 可执行路径
%    o.LibDir = cfg.LibDir;          % 传给 snp_export 的库目录
%
%  设计：所有随机器/环境变化的值集中在根目录两个配置文件之一：
%    config_local.m   = 本机真值（不入库，从 config_example.m 复制改值）
%    config_example.m = 示例孪生（入库，公开面唯一的配置样本，占位值）
%  新克隆的机器没有 config_local.m，本函数自动回落到示例——开箱可用
%  但 MatlabBin 等需按示例头注释替换。
%
%  若 config_local.m 定义了本函数未列的字段，原样透传（允许本机扩展）。

% 锚定仓库根：which 返回绝对路径（-batch 下 mfilename('fullpath') 可能返回
% 空或相对路径，实测不可靠——T62）；fileparts 两次 = src 的上级 = 仓库根
thisFn = which('snp_config');
if isempty(thisFn), thisFn = [mfilename('fullpath') '.m']; end
R = fileparts(fileparts(thisFn));
% 仓库根须在 path 上——config_local/config_example 是函数文件，
% MATLAB 的函数解析只查 path 与 cwd（只有 src 在 path 时根上的配置不可解析）。
% 用精确条目比较：contains(path,R) 会把"子目录在 path"误判为"R 在 path"（前缀子串）
ps = split(path, pathsep);
if ~any(strcmp(ps, R)), addpath(R); end
localFn = fullfile(R, 'config_local.m');
if isfile(localFn)
  cfg = config_local();
else
  cfg = config_example();
end

end
