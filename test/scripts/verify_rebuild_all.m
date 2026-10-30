function verify_rebuild_all()
% 重建保真全量检查：仓库全部资产（1 库 + 4 模型），逐项「导出 → 重建 → 再导出 → 文本 diff」
%
%  判据：对重建结果再导出的快照，与原件快照**逐字节相同**（diff=0）。
%  为什么要再导出一次：直接比 .slx 二进制没有意义（zip 时间戳/元数据会变），
%  而"重建件再导出的代码"才是模型语义的直接表达。
%
%  关键：**输出全部落在临时目录**，绝不覆盖仓库里的 models/ 与 lib/blocks/
%  （覆盖过一次，源资产被重建件顶替，git status 出现 25 个假变更）。
%
%  输出：scratch/dbg_rebuild.txt；末行打印 REBUILD_TOTAL ok=<n>/<m>
R = fileparts(fileparts(mfilename('fullpath'))); while ~exist(fullfile(R,'src','snp_export.m'),'file') && ~strcmp(R,fileparts(R)), R = fileparts(R); end
addpath(fullfile(R, 'src'));
logPath = fullfile(R, 'test', 'scratch', 'dbg_rebuild.txt');
if ~isfolder(fileparts(logPath)), mkdir(fileparts(logPath)); end
fid = fopen(logPath, 'w');

% diff 时要排除的路径相关行（每次导出的落盘目录不同）
pat = ['(?m)^.*(load_system\(fullfile|if ~bdIsLoaded|tmp_save|snpDir|snpOut|' ...
       'movefile|mkdir\(snpOut|addpath\(fullfile).*$'];

libs = dir(fullfile(R, 'test', 'lib', 'blocks', '*.slx'));
models = dir(fullfile(R, 'test', 'models', '*.slx'));
nOk = 0; nTot = 0; fails = {};

for pass_ = 1:2
  if pass_ == 1
    list = libs;   kind = 'LIB';   subdir = 'test\lib\blocks';
  else
    list = models; kind = 'MODEL'; subdir = 'test\models';
  end
  for i = 1:numel(list)
    nm = list(i).name(1:end-4);
    nTot = nTot + 1;
    % 每次用独立临时目录：原快照（对照）→ 重建件快照（被测）
    dirA = tempname; mkdir(dirA);
    dirB = tempname; mkdir(dirB);
    try
      % LibRel 用绝对路径：临时快照落 tempname 根（无仓库的层级关系），
      % 相对 LibRel 会把 '..\lib\blocks' 相对 temp 根解析而加载不到库
      % （库引用模型 ToyLibRef 实测）；绝对路径只用于即弃的验证快照，
      % 仓库正式快照仍用相对
      oA = struct(); oA.OutDir = dirA; oA.LibDir = fullfile(R, 'test', 'lib', 'blocks');
      oA.AliasMap = cell(0, 2); oA.ExtraHeader = {};
      oA.LibRel = fullfile(R, 'test', 'lib', 'blocks');
      oA.InlineMasks = true; oA.SaveRel = dirA;
      oB = oA; oB.OutDir = dirB; oB.SaveRel = dirB;

      try, close_system(nm, 0); catch, end
      load_system(fullfile(R, subdir, list(i).name));
      snp_export(nm, oA); close_system(nm, 0);

      % 跑快照 → 重建模型（落在 dirA，因为快照的 SaveRel=dirA），
      % 再对重建件导出 → dirB 的快照（被测）
      cd(dirA); feval(['snapshot_' nm]); cd(R);
      load_system(fullfile(dirA, [nm '.slx']));
      snp_export(nm, oB); close_system(nm, 0);

      a = fileread(fullfile(dirA, ['snapshot_' nm '.m']));
      b = fileread(fullfile(dirB, ['snapshot_' nm '.m']));
      ra = regexprep(a, pat, ''); rb = regexprep(b, pat, '');
      if strcmp(ra, rb)
        fprintf(fid, '%s %-20s: REBUILD IDENTICAL\n', kind, nm);
        nOk = nOk + 1;
      else
        la = strsplit(ra, sprintf('\n')); lb = strsplit(rb, sprintf('\n'));
        d = -1;
        for k = 1:min(numel(la), numel(lb))
          if ~strcmp(la{k}, lb{k}), d = k; break; end
        end
        fprintf(fid, '%s %-20s: DIFF first@%d A=%d B=%d\n', kind, nm, d, numel(la), numel(lb));
        fprintf(fid, '   A: %s\n', la{max(1, min(d, end))}(1:min(160, end)));
        fprintf(fid, '   B: %s\n', lb{max(1, min(d, end))}(1:min(160, end)));
        fails{end+1} = nm;
      end
    catch ME
      fprintf(fid, '%s %-20s: ERR %s\n', kind, nm, ME.message(1:min(160, end)));
      fails{end+1} = nm;
      cd(R);
      try, close_system(nm, 0); catch, end
    end
    rmdir(dirA, 's'); rmdir(dirB, 's');
  end
end

fprintf(fid, '\n=== REBUILD_TOTAL ok=%d/%d fails=%d ===\n', nOk, nTot, numel(fails));
if ~isempty(fails)
  fprintf(fid, 'failed: %s\n', strjoin(fails, ', '));
end
fclose(fid);
fprintf('REBUILD_TOTAL ok=%d/%d fails=%d\n', nOk, nTot, numel(fails));
end

