# 参考：块型覆盖口径

`snp_block_source` 表的事实清单：覆盖什么、不覆盖什么、跨版本漂移几何。只想查 API 去看 [tool-api.md](tool-api.md)。

## 规模

- **200 条 case**（BlockType → 库路径），来自三层实测：
  1. 早期大规模验证所用资产（已移出本仓库，数字见 CHANGELOG 历史段）用到的 BlockType 逐一实测；
  2. R2023b `simulink` 核心库枚举（502 块 / 163 种 BlockType），表外 119 种逐一 `add_block` 实测收录；
  3. 工具箱库穷举（`slblocks().OpenFcn` 得 52 顶层库 + `physmod/**/library/*.slx` 得 278 子库），收录 33 种新块型（SimEvents 实体系、nesl_utility Simscape 工具系、FMU/Reciprocal/ Reference/Observer 等）。
- **路径换行约定**：库名含真 `char(10)` 的（如 `'Math⏎Operations'`），表中记为字面 `\n`，函数返回前还原。

## 两个"设计性例外"（有意不入表）

| BlockType | 为什么不入表 |
|---|---|
| `SubSystem` | 容器：有 rb 走 rb，无 rb 走 `built-in/SubSystem` 兜底 / `expand_masked` 展开 |
| `S-Function` | 导出器特判（`simulink/User-Defined Functions/S-Function`），`.m` 实现随快照复制 |

## 结构性端口块（T39：不入表，也不应该入）

`FaultInport` / `FaultOutport` / `FaultDataInport` / `StateControl` / `EnablePort` / `TriggerPort` 一类**结构性依赖父系统**的端口块：

- 它们不能裸 `add_block`（报"必须位于故障子系统的根级中"一类错）；
- 真实模型里由父系统（如 Fault Subsystem）创建时**随之生成**—— `add_block('mwfaultblocklib/Fault Subsystem')` 实测自带 FaultInport + FaultOutport；
- M 线重建只需要父块路径，不需要（也不应）独立表条目。

## 跨版本漂移（实测几何）

| 版本 | 库数 | BlockType 种数 | 表覆盖 | 真缺口 |
|---|---|---|---|---|
| R2025a | 61 | 121 | 114 | 1（`SimscapeArrayConnection`，已入表） |
| R2026a | 64 | 134 | 121 | 1（同上，已入表） |

- 两版本各自穷举（机制① `slblocks` + 机制② `physmod/**/library/**/*.slx`），FAIL 全是 T39 结构性端口块（预期不入表；`FaultDataInport` 是 2026a 新增）。
- **唯一一条表条目失效**：`PMComponent`（`sps_lib/Passives/Mutual Inductance`）在 **R2026a 失效**——但**不是路径漂移**：powersys（Specialized Power Systems）产品整个下线，2026a 全库零命中。表条目保持不动：若 2026a 模型真有该块，它的 rb 会指向已下线的库——这是版本外部事实；示例资产不使用 PMComponent（三版本重建 25/25 IDENTICAL 已证，历史口径）。真正的 powersys→Simscape Electrical迁移是语义级工作，不是表条目替换。
- **结论：表不需要分版本 / 加版本列**（论证见[explanation/why-not-versioned-table.md](../explanation/why-not-versioned-table.md)）。

## 有 rb 的块：表只是回退

导出时**优先走 ReferenceBlock**（`get_param(b,'ReferenceBlock')`），表条目仅是无 rb 时的回退。所以表里多一条少一条对有库链接的块**无损**——这也是为什么 `SimscapeArrayConnection` 这类"新版本才有"的条目可以安全入表：旧版本模型不含该块型，这条 case 永远不触发。

## 发现机制（穷举用，复现口径变更时照这个跑）

1. **机制① slblocks 注册**：`which('-all','slblocks')` 逐个`cd(fileparts(f{i})); s = slblocks();` 取 **`s.OpenFcn`（不带引号，直接是库名）** → `load_system` 确认 `BlockDiagramType=='library'`。
2. **机制② physmod 子库**：`dir(fullfile(matlabroot,'toolbox','physmod','**','library','**','*.slx'))`（R2025a/2026a 库下移一层，老模式 `library/*.slx` 只剩 4/2 个）。
3. 枚举库用有限深度（如 20）且**不加** `LookUnderMasks`。
4. 缺口逐一 `add_block` + 回读 BlockType 实测（"载入成功"不等于块可用）。
