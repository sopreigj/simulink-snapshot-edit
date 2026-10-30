function info = snp_sync_m(srcSlx, mFile, ops, varargin)
%SNP_SYNC_M  第二级编辑路线：把 .slx 的 XML 编辑回灌进 M 快照
%
%  流程：snp_xml_edit 在 .slx 包内 XML 上做编辑（产出编辑件 + 等价的 M 侧操作
%  info.mops），再把 mops 经 snp_patch 应用到 M 快照——M 与 .slx 双向一致，
%  无需人工比对。M 快照仍是跨版本/可逐字节验证的兜底真相。
%
%  块型→库路径的转换用共享表 snp_block_source（库路径是 API 侧知识，
%  M 侧的 add_block 需要它，XML 侧不需要）。
%
%  用法：
%    info = snp_sync_m(srcSlx, mFile, {'ToyLibRef/tm', 'Kp', '7'});
%    info = snp_sync_m(srcSlx, mFile, {{'add_block', '', 'Gain', 'G1', {{'Gain', '2'}}}, ...
%                       {'add_line', '', 'g1', 1, 'G1', 1}});
%
%  名值参数：'DstSlx', <path>   编辑件落盘位置（默认临时文件，用后自删由调用方定）
%
%  返回 info：同 snp_xml_edit，另含 .dstSlx（编辑件路径）。
dstSlx = fullfile(tempdir, ['snp_sync_' char(java.util.UUID.randomUUID().toString()) '.slx']);
for k = 1:2:numel(varargin)
  if strcmp(varargin{k}, 'DstSlx'), dstSlx = varargin{k+1}; end
end

info = snp_xml_edit(srcSlx, dstSlx, ops);
apply_mops(mFile, info.mops);
info.dstSlx = dstSlx;
end

% ---------------------------------------------------------------------------
function apply_mops(mFile, mops)
for k = 1:numel(mops)
  op = mops{k};
  verb = op{1};
  switch verb
    case 'add_block'
      parentPath = op{2}; blkType = op{3}; blkName = op{4};
      params = op{5}; pos = op{6};
      src = snp_block_source(blkType);
      assert(~isempty(src), 'snp_sync_m: 块型 %s 未收录进 snp_block_source，无法回灌 M 侧 add_block', blkType);
      flat = {};
      for q = 1:numel(params), flat = [flat, params{q}]; end %#ok<AGROW>
      snp_patch(mFile, 'add_block', 'Name', blkName, 'Source', src, ...
        'Position', pos, flat{:});
    case {'remove_block', 'add_line', 'remove_line'}
      snp_patch(mFile, op{:});
    otherwise
      % {块路径, 参数, 值} —— snp_patch 的非动词形式
      snp_patch(mFile, op{:});
  end
end
end
