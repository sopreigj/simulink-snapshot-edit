function rep = snp_collab_check(model, varargin)
%snp_collab_check  人机协作守卫：检测"谁动过模型" + 双线产物功能等价
%
% 背景：XML 原地编辑（D4 ①）与 M 快照重建（D4 ②）双线并行，需要判据确认两条
% 路线产物**功能等价**，并在人类经 GUI 改动模型时给出明确信号。用 Simulink
% 官方两个层次的校验和（R2023b 文档实测，2026-10-29）：
%   · Simulink.getFileChecksum(file)     MD5，文件级——文件内容变它就变
%     （移动一个块也会变；用于"人类是否动过此文件"）
%   · Simulink.BlockDiagram.getChecksum  128 位，功能级——功能不变它不变
%     （移动块不变，改参数变；用于"双线产物是否功能等价"）
% 两者刻意分开：文件级管"谁动过"，功能级管"改没改坏"。
%
% 用法：
%   rep = snp_collab_check('Model')                  % 单模型：报两个校验和
%   rep = snp_collab_check('ModelA', 'Compare', 'ModelB')  % 双模型功能等价判据
%   rep = snp_collab_check('Model', 'BaselineFile', 'x.slx') % 与磁盘文件比文件级
%
% 输出 rep 字段：
%   .fileChecksum    文件级 MD5（char）；模型未存盘或路径不可得时为 ''
%   .funcChecksum    功能级 128 位（[4x1 uint32]）；获取失败为 []
%   .funcEqual       （Compare 模式）三态：1=相同 / 0=不同 / -1=不可判定
%   .fileEqual       （BaselineFile 模式）三态：1=一致 / 0=不同 / -1=不可判定
%   .notes           说明（供上层的判断依据）
%
% T71 三态化（外部只读审查证实的假成功）：两侧 getChecksum 都失败时
%   isequal([],[])=true，会被误报"功能等价"。校验和不可得（模型未存盘 /
%   编译失败 / 读取异常）是**不可判定**，不是"相同"——不可判定不得视为
%   通过。消费者必须先排除 -1 再用真值（与 verify_collab C3 的 -1 哨兵
%   实践一致：那里早已因假阴性弃用裸 funcEqual）。
%
% 边界：本函数只**度量**不改模型。BlockDiagram.getChecksum 会编译模型
% （文档明示），故在 -batch 里调用可能较慢——这是官方行为，不是缺陷。

  p = inputParser;
  addRequired(p, 'model', @ischar);
  addParameter(p, 'Compare', '', @ischar);
  addParameter(p, 'BaselineFile', '', @ischar);
  parse(p, model, varargin{:});
  o = p.Results;

  rep = struct('fileChecksum', '', 'funcChecksum', [], ...
               'funcEqual', [], 'fileEqual', [], 'notes', '');

  % --- 载入目标模型 ---
  if ~bdIsLoaded(model)
    load_system(model);
  end
  % 文件级：要求磁盘路径（R2023b 用 get_param('FileName')，无 bdGetPath）
  f = '';
  try, f = get_param(model, 'FileName'); catch, end
  if ~isempty(f) && isfile(f)
    rep.fileChecksum = Simulink.getFileChecksum(f);
  else
    rep.notes = '模型未存盘或路径不可得，文件级校验和留空';
  end

  % --- 功能级 ---
  rep.funcChecksum = localFuncChecksum(model);

  % --- Compare：两模型功能等价（T71 三态）---
  if ~isempty(o.Compare)
    if ~bdIsLoaded(o.Compare), load_system(o.Compare); end
    c2 = localFuncChecksum(o.Compare);
    if isempty(rep.funcChecksum) || isempty(c2)
      rep.funcEqual = -1;
      rep.notes = [rep.notes ' 功能等价不可判定（功能级校验和获取失败，不得视为通过）'];
    elseif isequal(rep.funcChecksum, c2)
      rep.funcEqual = 1;
      rep.notes = [rep.notes ' 功能等价（BlockDiagram 校验和一致）'];
    else
      rep.funcEqual = 0;
      rep.notes = [rep.notes ' 功能不同（BlockDiagram 校验和不一致）'];
    end
  end

  % --- BaselineFile：与磁盘基线比文件级（T71 三态）---
  if ~isempty(o.BaselineFile) && isfile(o.BaselineFile)
    if isempty(rep.fileChecksum)
      rep.fileEqual = -1;
      rep.notes = [rep.notes ' 文件级与基线不可判定（模型未存盘，无文件级校验和）'];
    else
      b = '';
      try, b = Simulink.getFileChecksum(o.BaselineFile); catch, end
      if isempty(b)
        rep.fileEqual = -1;
        rep.notes = [rep.notes ' 文件级与基线不可判定（基线文件校验和读取失败）'];
      elseif strcmp(rep.fileChecksum, b)
        rep.fileEqual = 1;
        rep.notes = [rep.notes ' 文件级与基线一致'];
      else
        rep.fileEqual = 0;
        rep.notes = [rep.notes ' 文件级与基线不同（人类动过或重新保存过）'];
      end
    end
  end
end

%% 取功能级校验和（统一错误兜底，编译失败不致命）
% R2023b 签名：[checksum, details] = getChecksum(model)——第一个输出就是
% 4x1 uint32 校验和；ContentsChecksum 等字段在第二个输出 details 里。
% （首版误用单输出再取 .ContentsChecksum.Value，报"此类型不支持点索引"）
function c = localFuncChecksum(m)
  c = [];
  try
    [c, ~] = Simulink.BlockDiagram.getChecksum(m);
  catch
    c = [];
  end
end
