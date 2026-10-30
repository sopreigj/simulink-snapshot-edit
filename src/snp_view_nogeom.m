function out = snp_view_nogeom(snapshotFile, varargin)
%snp_view_nogeom 把 M 快照里的几何行剔除，给"读模型"用（不是给重建用）
%
% 用途：第三级编辑路线——agent/人只需要读懂模型的结构与参数，不需要块位置与走线。
% 实测（2026-10-29，25 份快照）：几何行（含 'Position' 或 'Points'）占总行数 35.1%
% （4364/12427），剔除后可读性显著提升。
%
% 重要：本函数只产出**读视图**，绝不替代 M 快照本身——M 里的 Position/Points 是
% 逐字节可重建所必需（D5）。简单模型上视图也许能碰巧 run 通，但**重建不保证**：
% 视图供阅读/agent 筛选用，重建请用原始 M。
%
% 输入：
%   snapshotFile  快照 .m 路径
%   可选 'OutFile'  写出的文件路径；不写则只返回字符串
% 输出：
%   out   去几何后的快照文本（char）
%
% 判据：几何行指 add_block(...'Position',...) 与 add_line(...'Points',...) 中的
%       几何参数对；整行保留，只删该参数对，故行数不变、结构不乱。

  p = inputParser;
  addRequired(p, 'snapshotFile', @ischar);
  addParameter(p, 'OutFile', '', @ischar);
  parse(p, snapshotFile, varargin{:});

  txt = fileread(p.Results.snapshotFile);
  lines = strsplit(txt, sprintf('\n'))';

  % 删几何参数对：'Position', <值>  与  'Points', <值>
  % 值可能是 [x y w h] 形式的向量字面量（不含逗号嵌套），也可能跨到行尾。
  % 两类来源：① add_block/add_line 的几何参数；② 注解（Note）的放置
  %   set_param(nb,'Position',[...]) 与 dp = get_param(nb,'Position') ——同样是几何。
  patPos   = '''Position''\s*,\s*\[[^\]]*\]';
  patPts   = '''Points''\s*,\s*\[[^\]]*\](?:\s*;\s*\[[^\]]*\])*';
  for i = 1:numel(lines)
    l = lines{i};
    % 注解放置整行剔除（dp = get_param(nb,'Position'); 与 set_param(nb,'Position',[...]);）
    if ~isempty(regexp(l, '^\s*dp\s*=\s*get_param\([^,]+,\s*''Position''\)\s*;\s*$', 'once'))
      lines{i} = ''; continue;
    end
    if ~isempty(regexp(l, '^\s*set_param\([^,]+,\s*''Position''\s*,[^;]*\);\s*$', 'once'))
      lines{i} = ''; continue;
    end
    l = regexprep(l, patPts, '');
    l = regexprep(l, patPos, '');
    % 清理删参后残留的多余逗号/空格：', ,' -> ',' ，行尾 ',)' -> ')'
    l = regexprep(l, ',\s*,', ',');
    l = regexprep(l, ',\s*\)', ')');
    lines{i} = l;
  end
  % 注解块本身（built-in/Note）保留——它是模型内容；只丢它的位置。

  out = strjoin(lines, sprintf('\n'));
  if ~isempty(p.Results.OutFile)
    fid = fopen(p.Results.OutFile, 'w', 'n', 'UTF-8');
    fwrite(fid, out, 'char');
    fclose(fid);
  end
end
