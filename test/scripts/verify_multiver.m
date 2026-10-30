function verify_multiver()
% 多版本兼容性测试驱动：在当前 MATLAB 版本下运行全套验证，
% 结果按版本号归档到 test/scripts/multiver/<release>/，供跨版本对比。
%
% 运行（每个版本一次；各套件日志路径固定，不同版本必须**顺序**跑）：
%   matlab -batch "cd('<repo>/test/scripts'); verify_multiver"
%
% 产物（test/scripts/multiver/<release>/）：
%   env.txt      version / Simulink / Stateflow 版本信息
%   snapshots/   全部资产（1 库 + 4 模型）的本版本快照导出（跨版本 diff 素材）
%   export.txt   快照导出汇总
%   rebuild.txt  verify_rebuild_all 结果（结构保真）
%   special.txt  verify_special_blocks 结果
%   behavior.txt verify_behavior 结果（行为等价）
%   roundtrip.txt test_roundtrip 结果（双向保留）
here = fileparts(mfilename('fullpath'));
R = here; while ~exist(fullfile(R,'src','snp_export.m'),'file') && ~strcmp(R,fileparts(R)), R = fileparts(R); end
addpath(fullfile(R, 'src'));
addpath(here);

rel = version('-release');
outRoot = fullfile(here, 'multiver', rel);
if isfolder(outRoot), rmdir(outRoot, 's'); end
mkdir(outRoot);
% 下游套件（verify_rebuild_all/verify_behavior/verify_special_blocks/
% test_roundtrip→verify_fidelity）内部的 snp_export 调用没有 opts 通道，
% 经环境变量统一放行版本断言
setenv('SNP_ALLOW_UNTESTED', '1');
fprintf('MULTIVER release=%s out=%s\n', rel, outRoot);

% ---- 环境信息 ----
fid = fopen(fullfile(outRoot, 'env.txt'), 'w');
fprintf(fid, 'release=%s\n', rel);
fprintf(fid, 'version=%s\n', strtrim(version));
v = ver('simulink');
if ~isempty(v), fprintf(fid, 'simulink=%s (%s)\n', v.Version, v.Release); end
v = ver('stateflow');
if ~isempty(v), fprintf(fid, 'stateflow=%s (%s)\n', v.Version, v.Release); end
fclose(fid);

% ---- 快照导出（跨版本 diff 素材；三个版本用完全相同的导出配置，
%      含绝对路径行在内都必须逐字节可比）----
snapDir = fullfile(outRoot, 'snapshots');
mkdir(snapDir);
libs = dir(fullfile(R, 'test', 'lib', 'blocks', '*.slx'));
models = dir(fullfile(R, 'test', 'models', '*.slx'));
fid = fopen(fullfile(outRoot, 'export.txt'), 'w');
nExp = 0; nExpTot = numel(libs) + numel(models);
for pass_ = 1:2
  if pass_ == 1
    list = libs;  subdir = fullfile(R, 'test', 'lib', 'blocks');
  else
    list = models; subdir = fullfile(R, 'test', 'models');
  end
  for i = 1:numel(list)
    nm = list(i).name(1:end-4);
    try, close_system(nm, 0); catch, end
    try
      o = struct(); o.OutDir = snapDir; o.LibDir = fullfile(R, 'test', 'lib', 'blocks');
      o.AliasMap = cell(0, 2); o.ExtraHeader = {};
      o.LibRel = '..\..\..\..\test\lib\blocks';   % 快照在 test/scripts/multiver/<rel>/snapshots，上 4 级到根再进 test
      o.InlineMasks = true;
      o.SaveRel = fullfile(outRoot, 'rebuilt');
      o.AllowUntestedVersion = true;
      load_system(fullfile(subdir, list(i).name));
      snp_export(nm, o); close_system(nm, 0);
      nExp = nExp + 1;
      fprintf(fid, 'OK   %s\n', nm);
    catch ME
      fprintf(fid, 'FAIL %s: %s\n', nm, ME.message);
      try, close_system(nm, 0); catch, end
    end
  end
end
fprintf(fid, '=== EXPORT ok=%d/%d ===\n', nExp, nExpTot);
fclose(fid);
fprintf('MULTIVER_EXPORT ok=%d/%d\n', nExp, nExpTot);

% ---- 全套验证（各套件日志落固定路径，跑完即归档副本）----
run_suite('verify_rebuild_all',    'dbg_rebuild.txt',  outRoot, 'rebuild.txt');
run_suite('verify_special_blocks', 'dbg_special.txt',  outRoot, 'special.txt');
run_suite('verify_behavior',       'dbg_behavior.txt', outRoot, 'behavior.txt');
try
  rt = evalc('test_roundtrip');
  fid = fopen(fullfile(outRoot, 'roundtrip.txt'), 'w');
  fwrite(fid, rt); fclose(fid);
  disp(rt);
catch ME
  fid = fopen(fullfile(outRoot, 'roundtrip.txt'), 'w');
  fprintf(fid, 'ROUNDTRIP ERR: %s\n', ME.message);
  fclose(fid);
end
fprintf('MULTIVER_DONE release=%s\n', rel);
end

function run_suite(name, logName, outRoot, dstName)
% 跑一个验证套件，把它的固定路径日志归档到本版本目录
% 套件日志写在 test/scratch/；
% 套件前 bdclose 清状态（C/D 子代理发现顺序执行时上一阶段残留会污染）；
% catch 的错误写进归档（原版只 fprintf，中文 GBK 乱码会吞掉原因）
try
  bdclose('all');
  feval(name);
catch ME
  msg = sprintf('%s ERR: %s\nstack:\n', name, ME.message);
  st = ME.stack;
  for i = 1:numel(st)
    msg = sprintf('%s  %s (L%d)\n', msg, st(i).name, st(i).line);
  end
  fid = fopen(fullfile(outRoot, dstName), 'w', 'n', 'UTF-8');
  fwrite(fid, msg); fclose(fid);
  fprintf('%s ERR: %s\n', name, strrep(ME.message, sprintf('\n'), ' '));
  return;
end
here = fileparts(mfilename('fullpath'));
R = here; while ~exist(fullfile(R,'src','snp_export.m'),'file') && ~strcmp(R,fileparts(R)), R = fileparts(R); end
src = fullfile(R, 'test', 'scratch', logName);
if isfile(src)
  copyfile(src, fullfile(outRoot, dstName));
else
  fid = fopen(fullfile(outRoot, dstName), 'w');
  fprintf(fid, 'no log produced\n');
  fclose(fid);
end
end

