function export_all_snapshots()
% 重新生成仓库内 snapshots/ 下的全部快照（仓库全部资产：1 库 + 4 模型）。
%
%  为什么需要它：此前 snapshots/ 是手工逐个导出的，没有再生入口——改导出器
%  之后无法一致地刷新全部产物（哪几个重新导过、用的什么配置，全靠记忆）。
%
%  导出配置（与已提交快照里写的一致）：
%    LibRel  = '..\lib\blocks'     快照里 addpath 的库目录（相对快照文件）
%    SaveRel = 库 → '..\lib\blocks'，模型 → '..\models'
%    InlineMasks = true            mask 子系统展开为普通子系统导出内部结构
%
%  **只写 snapshots/**：不运行快照、不覆盖 lib/ 与 models/ 的源资产。
%
%  输出：末行打印 SNAPSHOTS_TOTAL ok=<n>/<m>
R = fileparts(fileparts(mfilename('fullpath'))); while ~exist(fullfile(R,'src','snp_export.m'),'file') && ~strcmp(R,fileparts(R)), R = fileparts(R); end  % -batch 下 mfilename('fullpath') 不可靠，须向上锚定
addpath(fullfile(R, 'src'));
snapDir = fullfile(R, 'test', 'snapshots');

libs = dir(fullfile(R, 'test', 'lib', 'blocks', '*.slx'));
models = dir(fullfile(R, 'test', 'models', '*.slx'));
nOk = 0; nTot = 0; fails = {};
for pass_ = 1:2
  if pass_ == 1
    list = libs; srcDir = fullfile(R, 'test', 'lib', 'blocks'); saveRel = '..\lib\blocks';
  else
    list = models; srcDir = fullfile(R, 'test', 'models'); saveRel = '..\models';
  end
  for i = 1:numel(list)
    nm = list(i).name(1:end-4);
    nTot = nTot + 1;
    try, close_system(nm, 0); catch, end
    try
      o = struct();
      o.OutDir = snapDir; o.LibDir = fullfile(R, 'test', 'lib', 'blocks');
      o.AliasMap = cell(0, 2); o.ExtraHeader = {};
      o.LibRel = '..\lib\blocks'; o.SaveRel = saveRel;
      o.InlineMasks = true;
      load_system(fullfile(srcDir, list(i).name));
      snp_export(nm, o);
      close_system(nm, 0);
      nOk = nOk + 1;
      fprintf('OK   %s\n', nm);
    catch ME
      fprintf('FAIL %s: %s\n', nm, ME.message(1:min(160, end)));
      fails{end+1} = nm; %#ok<AGROW>
      try, close_system(nm, 0); catch, end
    end
  end
end
fprintf('SNAPSHOTS_TOTAL ok=%d/%d fails=%d\n', nOk, nTot, numel(fails));
if ~isempty(fails), fprintf('failed: %s\n', strjoin(fails, ', ')); end
end
