# 操作指南：改块参数——三级阶梯选哪级

任务：改一个已存在模型的某些块参数。你听说有"三级阶梯"，不知道该用哪级。本文只帮你**选**；每级的完整 API 见[参考：工具 API](../reference/tool-api.md)。

## 三级阶梯一句话版

| 级 | 工具 | 产物 | 什么时候选 |
|---|---|---|---|
| ① XML 原地编辑 | `snp_xml_edit` | 改过的 `.slx` | **默认首选**：最快、保真最高、不需要块型表 |
| ② XML→M 回灌 | `snp_sync_m` | `.slx` + 同步的 M | ① 做完还想要 M 侧一致 |
| ③ 直接改 M 快照 | 手改 / `snp_patch` + `run` | 重建的 `.slx` | 要跨版本可移植 / 要逐字节可验证 |

## 决策树

```
你的模型有快照吗（test/snapshots/snapshot_X.m）？
├─ 没有 → 先 snp_export 导一份（教程见 tutorials/）
└─ 有 → 这次改动的"未知块型"多吗？
    ├─ 多（含未收录进 snp_block_source 的块型、Simscape、Stateflow）→ 级①
    │      （XML 路线不需要块型→库路径映射，未知块型照样改）
    └─ 少（普通块改参数）→ 需要跨版本可移植或逐字节验证吗？
        ├─ 要 → 级③（M 是跨版本兜底真相）
        └─ 不要 → 级①（最快）
```

## 级①：XML 原地编辑（默认首选）

直接改 `.slx` 包内 `simulink/systems/system_*.xml` 的块参数，再按原条目顺序重打包。**不需要知道块型的库路径**，未列白的参数、Stateflow、Simscape 物理连接全部字节级保留：

```matlab
addpath('src');
ops = { {'ToyLibRef/tm', 'Kp', '7'} };     % 简写 = set_param
info = snp_xml_edit('test/models/ToyLibRef.slx', 'test/scratch/edited.slx', ops);
```

返回 `info.applied` / `info.skipped`（含原因）/ `.mops`（等价的 M 侧操作，级②要用）。

**注意**：产物是"改过的 .slx"，不是"能重建的 M"。跨版本可移植与逐字节新鲜度判据要让 M 路线兜底（见 [解释](../explanation/why-snapshot-is-truth.md)）。

**存储事实（非 bug）**：Simulink 保存时**只写与默认值不同的参数**——若目标参数当前是默认值（如 `Gain` 块的 `Gain=1`），包内 XML 里根本没有 `<P Name="Gain">`，`snp_xml_edit` 的 set_param 会 skip（`info.skipped` 里会写明原因）。处理：先把参数在 GUI/set_param 里改成任意非默认值再走级①，或直接走级③ M 路线（M 快照总是写全参数）。

## 级②：XML→M 回灌（① plus M 一致）

级① 的 `info.mops` 是等价的 M 侧操作。`snp_sync_m` 一步做完：XML 编辑 +把 mops 应用进 M 快照——M 与 .slx 双向一致，无需人工比对：

```matlab
info = snp_sync_m('test/models/MyModel.slx', 'test/snapshots/snapshot_MyModel.m', ops);
```

块型→库路径的转换用共享表 `snp_block_source`——**如果某个块型没收录进表，回灌会报错**（`未收录进 snp_block_source，无法回灌 M 侧 add_block`）。这时候退回级①，或先给表补条目（见 [参考：块型覆盖](../reference/block-coverage.md)）。

## 级③：直接改 M 快照

手动（或 `snp_patch`）编辑快照里目标块的几行，然后 `run` 重建：

```matlab
snp_patch('test/snapshots/snapshot_ToyBasic.m', 'g1', 'Gain', '5');
cd test/snapshots; snapshot_MyModel(); cd ../..
```

**已知限制**（当前实现有意收窄）：
- `snp_patch` 的参数值**字符类边界**（2026-10-29 实测精确化）：
  - **逗号**会使行解析失败（如 `'2,5'` 重建报"参数无效"）——真坏，需预处理或改走 XML；
  - **引号**需在值中转义；
  - **括号实测可完整往返**——写进快照、重建回读生效（语义按表达式求值，如 `'(3)'` 回读 `Gain=(3)`）。旧措辞"括号也不行"过严，不用回避。遇到坏值（含逗号）时直接手改快照对应行，不要硬调 patch。
- `snp_patch` 的增块只支持顶层（`Parent='m'`）；子系统内部加块先展开位再 patch。

选级③的核心理由：M 是**跨版本可移植**的兜底真相（R2023b 导出的快照在R2026a 上重建逐字节一致，已实测）；级①的 .slx 不带这个性质。

## 验证你的改动

无论哪级，改完用 `snp_collab_check` 的功能级校验和核对"没改坏"：

```matlab
rep = snp_collab_check('MyModel', 'Compare', 'MyModel_edited');
disp(rep.funcEqual);   % true = 功能等价（改参数会让它变，这里应验改动的量级）
```

完整等价判据与"谁动过文件"的文件级校验和见[参考：工具 API](../reference/tool-api.md) 的 `snp_collab_check` 条目。
