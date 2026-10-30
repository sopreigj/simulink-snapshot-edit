function verify_snapshots_fresh()
% 校验仓库内 snapshots/ 与**当前导出器**的输出一致（快照是否过期）。
%
%  为什么需要：verify_rebuild_all 每次都现导到 tempdir，从不读已提交的
%  snapshots/——所以导出器改过之后，仓库里的快照可能整体过期而所有测试仍全绿。
%  实测发现过一次：快照还停留在 char("...") 的 chart 写法（早期导出器
%  的缺陷形态），且缺 chart 参数与接口断言，说明它们很久没重新生成。
%
%  判据：现导一份到 tempdir，与 snapshots/snapshot_<名>.m 文本逐字节相同。
%  输出：scratch/dbg_fresh.txt；末行 FRESH_TOTAL ok=<n>/<m>
R = fileparts(fileparts(mfilename('fullpath'))); while ~exist(fullfile(R,'src','snp_export.m'),'file') && ~strcmp(R,fileparts(R)), R = fileparts(R); end
addpath(fullfile(R, 'src'));
logPath = fullfile(R, 'test', 'scratch', 'dbg_fresh.txt');
if ~isfolder(fileparts(logPath)), mkdir(fileparts(logPath)); end
fid = fopen(logPath, 'w');

libs = dir(fullfile(R, 'test', 'lib', 'blocks', '*.slx'));
models = dir(fullfile(R, 'test', 'models', '*.slx'));
nOk = 0; nTot = 0; stale = {};
for pass_ = 1:2
  if pass_ == 1
    list = libs; srcDir = fullfile(R, 'test', 'lib', 'blocks'); saveRel = '..\lib\blocks';
  else
    list = models; srcDir = fullfile(R, 'test', 'models'); saveRel = '..\models';
  end
  for i = 1:numel(list)
    nm = list(i).name(1:end-4);
    nTot = nTot + 1;
    tmpDir = tempname; mkdir(tmpDir);
    try, close_system(nm, 0); catch, end
    try
      o = struct(); o.OutDir = tmpDir; o.LibDir = fullfile(R, 'test', 'lib', 'blocks');
      o.AliasMap = cell(0, 2); o.ExtraHeader = {};
      o.LibRel = '..\lib\blocks'; o.SaveRel = saveRel;
      o.InlineMasks = true;
      load_system(fullfile(srcDir, list(i).name));
      snp_export(nm, o);
      close_system(nm, 0);
      a = fileread(fullfile(tmpDir, ['snapshot_' nm '.m']));
      committed = fullfile(R, 'test', 'snapshots', ['snapshot_' nm '.m']);
      if ~isfile(committed)
        fprintf(fid, '%-22s : MISSING（仓库里没有这个快照）\n', nm);
        stale{end+1} = nm; %#ok<AGROW>
      else
        b = fileread(committed);
        if strcmp(a, b)
          fprintf(fid, '%-22s : FRESH\n', nm);
          nOk = nOk + 1;
        else
          la = strsplit(a, sprintf('\n')); lb = strsplit(b, sprintf('\n'));
          d = -1;
          for k = 1:min(numel(la), numel(lb))
            if ~strcmp(la{k}, lb{k}), d = k; break; end
          end
          fprintf(fid, '%-22s : STALE first@%d 现导=%d 行 仓库=%d 行\n', ...
            nm, d, numel(la), numel(lb));
          if d > 0
            fprintf(fid, '   现导: %s\n', la{d}(1:min(150, end)));
            fprintf(fid, '   仓库: %s\n', lb{d}(1:min(150, end)));
          end
          stale{end+1} = nm; %#ok<AGROW>
        end
      end
    catch ME
      fprintf(fid, '%-22s : ERR %s\n', nm, ME.message(1:min(140, end)));
      stale{end+1} = nm; %#ok<AGROW>
      try, close_system(nm, 0); catch, end
    end
    rmdir(tmpDir, 's');
  end
end
fprintf(fid, '\n=== FRESH_TOTAL ok=%d/%d stale=%d ===\n', nOk, nTot, numel(stale));
if ~isempty(stale), fprintf(fid, 'stale: %s\n', strjoin(stale, ', ')); end
fclose(fid);
fprintf('FRESH_TOTAL ok=%d/%d stale=%d\n', nOk, nTot, numel(stale));
end

