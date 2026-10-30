function verify_cross_version()
% 跨版本可跑性：把仓库里 snapshots/ 的快照（基线版本导出）在**当前** MATLAB
% 版本下重建，判据「快照 → 重建 → 再导出 → 与仓库快照文本一致」。
%
%  与 verify_rebuild_all 的区别：那个从 models/ 现导一份再重建（验证导出器），
%  这个从**仓库里已提交的快照**出发（验证产物能否在别的版本上跑起来）。
%  两者互补：前者管生成，后者管消费。
%
%  沙箱：快照复制到 <tmp>/snapshots、库块复制到 <tmp>/lib/blocks，
%  快照按自身相对路径把模型存进 <tmp>/models —— 绝不碰仓库源资产。
%
%  输出：scratch/dbg_cross.txt；末行 CROSS_TOTAL ok=<n>/<m> release=<rel>
R = fileparts(fileparts(mfilename('fullpath'))); while ~exist(fullfile(R,'src','snp_export.m'),'file') && ~strcmp(R,fileparts(R)), R = fileparts(R); end
addpath(fullfile(R, 'src'));
% 本脚本的用途就是在**非基线版本**上跑，导出调用的版本断言必须放行
setenv('SNP_ALLOW_UNTESTED', '1');
logPath = fullfile(R, 'test', 'scratch', 'dbg_cross.txt');
if ~isfolder(fileparts(logPath)), mkdir(fileparts(logPath)); end
fid = fopen(logPath, 'w');
fprintf(fid, 'release=%s version=%s\n', version('-release'), strtrim(version));

% 排除路径相关行（同 verify_rebuild_all 的判据）
pat = ['(?m)^.*(load_system\(fullfile|if ~bdIsLoaded|tmp_save|snpDir|snpOut|' ...
       'movefile|mkdir\(snpOut|addpath\(fullfile).*$'];

libs = dir(fullfile(R, 'test', 'lib', 'blocks', '*.slx'));
models = dir(fullfile(R, 'test', 'models', '*.slx'));
nOk = 0; nTot = 0; fails = {};
% 沙箱：库块供快照 addpath + 库链接解析
sb = tempname; mkdir(sb);
mkdir(fullfile(sb, 'snapshots')); mkdir(fullfile(sb, 'models')); mkdir(fullfile(sb, 'lib', 'blocks'));
for i = 1:numel(libs)
  copyfile(fullfile(R, 'test', 'lib', 'blocks', libs(i).name), fullfile(sb, 'lib', 'blocks', libs(i).name));
end
addpath(fullfile(sb, 'lib', 'blocks'));
addpath(fullfile(sb, 'snapshots'));

for pass_ = 1:2
  if pass_ == 1, list = libs;   kind = 'LIB';
  else,          list = models; kind = 'MODEL';
  end
  for i = 1:numel(list)
    nm = list(i).name(1:end-4);
    nTot = nTot + 1;
    snapCommitted = fullfile(R, 'test', 'snapshots', ['snapshot_' nm '.m']);
    if ~isfile(snapCommitted)
      fprintf(fid, '%s %-20s: MISSING 仓库无快照\n', kind, nm);
      fails{end+1} = nm; %#ok<AGROW>
      continue;
    end
    snapSb = fullfile(sb, 'snapshots', ['snapshot_' nm '.m']);
    copyfile(snapCommitted, snapSb);
    outDir = tempname; mkdir(outDir);
    try
      try, close_system(nm, 0); catch, end
      cd(fullfile(sb, 'snapshots'));
      feval(['snapshot_' nm]);          % ← 被试：基线版本导出的快照在本版本 run
      cd(R);
      % 重建件落点：库快照 → <sb>/lib/blocks，模型快照 → <sb>/models
      if pass_ == 1, mdlPath = fullfile(sb, 'lib', 'blocks', [nm '.slx']);
      else,          mdlPath = fullfile(sb, 'models', [nm '.slx']);
      end
      if ~isfile(mdlPath)
        fprintf(fid, '%s %-20s: NORUN 快照 run 后没产出模型\n', kind, nm);
        fails{end+1} = nm; %#ok<AGROW>
        continue;
      end
      load_system(mdlPath);
      o = struct(); o.OutDir = outDir; o.LibDir = fullfile(R, 'test', 'lib', 'blocks');
      o.AliasMap = cell(0, 2); o.ExtraHeader = {}; o.LibRel = '..\lib\blocks';
      o.InlineMasks = true; o.SaveRel = '..\models';
      snp_export(nm, o); close_system(nm, 0);
      a = fileread(fullfile(outDir, ['snapshot_' nm '.m']));
      b = fileread(snapCommitted);
      ra = regexprep(a, pat, ''); rb = regexprep(b, pat, '');
      if strcmp(ra, rb)
        fprintf(fid, '%s %-20s: CROSS IDENTICAL\n', kind, nm);
        nOk = nOk + 1;
      else
        la = strsplit(ra, sprintf('\n')); lb = strsplit(rb, sprintf('\n'));
        d = -1;
        for k = 1:min(numel(la), numel(lb))
          if ~strcmp(la{k}, lb{k}), d = k; break; end
        end
        fprintf(fid, '%s %-20s: CROSS DIFF first@%d\n', kind, nm, d);
        if d > 0
          fprintf(fid, '   重建后导出: %s\n', la{d}(1:min(150, end)));
          fprintf(fid, '   仓库快照  : %s\n', lb{d}(1:min(150, end)));
        end
        fails{end+1} = nm; %#ok<AGROW>
      end
    catch ME
      fprintf(fid, '%s %-20s: CROSS ERR %s\n', kind, nm, ME.message(1:min(150, end)));
      fails{end+1} = nm; %#ok<AGROW>
      cd(R);
      try, close_system(nm, 0); catch, end
    end
    rmdir(outDir, 's');
  end
end
rmdir(sb, 's');
fprintf(fid, '\n=== CROSS_TOTAL ok=%d/%d fails=%d release=%s ===\n', ...
  nOk, nTot, numel(fails), version('-release'));
if ~isempty(fails), fprintf(fid, 'failed: %s\n', strjoin(fails, ', ')); end
fclose(fid);
fprintf('CROSS_TOTAL ok=%d/%d fails=%d release=%s\n', nOk, nTot, numel(fails), version('-release'));
end

