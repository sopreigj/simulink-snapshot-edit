# 操作指南：增删块

任务：给模型加一个块 / 删一个块。M 线和 XML 线的写法不同，还有 pull 的容器行兜底要知道。

## M 线：通过 `snp_patch` 的动词形式

**增块**（插在 `lines` 分节之前；目前只支持顶层 `Parent='m'`）：

```matlab
snp_patch('test/snapshots/snapshot_MyModel.m', 'add_block', ...
  'Name', 'NewConst', ...
  'Source', 'simulink/Sources/Constant', ...
  'Position', [100 100 130 130], ...
  'Value', '42');
```

`Source` 是**库路径**——`add_block` 需要它。普通块查[snp_block_source 表](../reference/block-coverage.md)；表里没有的块型会拦住你，这时候换 XML 线（见下）。

**删块**：

```matlab
snp_patch('test/snapshots/snapshot_MyModel.m', 'remove_block', 'NewConst');
```

**已知限制**：
- `remove_block` 会清理 `lines` 分节里指向被删块的连线（按末段块名 + parent 路径判，同名前缀块不误删）——无需手工 `remove_line` 补线。
- MATLAB Function 块**拒绝删除**（它的 chart 脚本段会悬空）。
- 子系统内部加块：先在 GUI / XML 线做，或先展开位再 patch。

**批量**（表驱动）：

```matlab
ops(1) = struct('op', 'g1', 'args', {{'Gain', '5'}});
ops(2) = struct('op', 'add_block', 'args', ...
  {{'Name','C1','Source','simulink/Sources/Constant','Position',[100 100 130 130]}});
snp_patch(file, 'batch', ops);
```

## XML 线：`snp_xml_edit` 的 add/remove

不依赖块型表，**未知块型也能加**：

```matlab
ops = { ...
  {'add_block', '', 'Gain', 'G1', {{'Gain','2'}}}; ...   % 父路径 '' = 顶层
  {'remove_block', 'OldBlock'};
};
info = snp_xml_edit('test/models/ToyBasic.slx', 'test/scratch/edited.slx', ops);
```

要让 M 侧同步一致，用 `snp_sync_m`（级②）：

```matlab
info = snp_sync_m('test/models/MyModel.slx', 'test/snapshots/snapshot_MyModel.m', ops);
```

`snp_sync_m` 内部会把 add_block 的块型经 `snp_block_source` 转成库路径—— **块型没收录进表会报错**，此时要么给表补条目，要么只走级①（产物是 .slx）。

## 验证：载入成功不等于写对了

新增的块必须做"载入后回读 BlockType/参数 + 仿真"校验，不能只看"载入成功"（这条教训在项目里反复出现过：载入成功不等于块写对了）：

```matlab
open_system('test/scratch/edited.slx');
disp(get_param('MyModel/G1', 'BlockType'));   % 期望 Gain
% 一步比对：编辑件 vs M 重建件功能等价
rep = snp_collab_check('MyModel', 'Compare', 'MyModel');
disp(rep.funcEqual);
```

## 人 GUI 增删的块怎么回流

人在 GUI 新建了一个**裸子系统**（不属于任何库）并往里放了块，pull 时：

- 导出器对无库源的 SubSystem 有**兜底**：输出`add_block('built-in/SubSystem', ...)` 容器行；
- 容器内部块照常按独立块导出；
- pull 把容器行 + 内部块一起回流，快照可重建。

这条兜底是有来由的：以前无库源的裸 SubSystem 会被 skip，pull 产出的快照缺容器行，重建时 `add_block('X/Sub/blk')` 报"父容器不存在"。

## 跨子系统移动块

M 线没有"移动"动词——本质是"旧位置删 + 新位置加"。pull 侧同理：顶层旧行消失、子系统内新位置块回流。人 GUI 拖动块进子系统后直接 pull 即可。
