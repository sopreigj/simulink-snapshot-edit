# 操作指南：跨版本工作（2023b / 2025a / 2026a）

任务：在多个 MATLAB 版本间使用本工具，或把快照从老版本带到新版本。

## 基线版本与版本断言

- 基线版本 **R2023b**。`snp_export` 函数体内有版本断言，非 2023b 直接报错。
- 需要在别的版本跑（如多版本测试）：`opts.AllowUntestedVersion = true`，或环境变量 `SNP_ALLOW_UNTESTED=1`（`verify_multiver.m` 用它放行下游套件）。放行时 stderr 会打 warning：`未验证版本`——这是**提示**不是错误。

> 运行注意：PATH 上的 `matlab` 可能是非基线版本（实测可能是 R2025a），带版本断言的套件会全部报"仅验证于 R2023b"。请**显式用基线版本（R2023b）的 MATLAB 可执行文件**以 `-batch` 方式调用，例如：`<R2023b 安装目录>/bin/matlab.exe -batch "cd('<repo>/test/scripts'); verify_xxx"`（Windows；其它平台用对应的 `matlab` 启动命令）。

## 覆盖口径（实测结论）

| 维度 | 结论 |
|---|---|
| M 快照跨版本可移植 | ✅ R2023b 导出的快照在 R2026a 上重建并复导出**逐字节一致**；三版本各自全套（导出/重建/行为/roundtrip）全绿（历史大规模验证 25/25，见 CHANGELOG 历史段；玩具资产口径见 README 状态节） |
| 块型表（200 case） | ✅ 在三版本无一失效——**只有 1 条已知漂移**：`PMComponent`（sps_lib）在 R2026a 整个 powersys 产品下线，不是路径漂移 |
| 库覆盖 | R2025a 61 库 / 121 种 BlockType（表覆盖 114）；R2026a 64 库 / 134 种（覆盖 121） |

**为什么表不需要分版本**：两版本穷举实测漂移极小（各仅 1 个新块型`SimscapeArrayConnection`，已入表）；唯一的表条目失效是"产品下线"而非"路径变化"，是版本外部事实。完整论证见[解释：为什么表不需要分版本](../explanation/why-not-versioned-table.md)。

## 跨版本验证怎么跑

`test/scripts/verify_multiver.m` 在当前 MATLAB 版本跑全套（env + 快照导出 + rebuild + special + behavior + roundtrip），归档到 `test/scripts/multiver/<release>/`（gitignore，不入库）：

```matlab
cd test/scripts;
verify_multiver;
```

其它相关脚本：
- `verify_cross_version.m`：基线版本导出的快照在别的版本上重建并复导出，逐字节比对（CROSS 判据）。
- `verify_cross_behavior.m`：跨版本行为等价。
- 遇到 `run_suite` 归档显示 "no log produced"：先查 `test/scratch/` 里有没有实际日志——归档路径与套件日志路径曾错配过（已修，但出问题时先看 test/scratch）。

## 已知跨版本差异

- **R2026a 的模型名 shadowing 警告**：快照 `new_system('X')` 与`test/lib/blocks/X.slx` 同名时 R2026a 会收紧的 shadowing 提示。不影响结果。
- **R2025a/2026a 的 physmod 库布局**：库文件从 `library/*.slx` 下移一层到`library/<子目录>/*.slx`。枚举库时要相应改 glob 模式（`library/**/*.slx`）。
- **R2026a powersys 产品下线**：`sps_lib` 加载失败（"找不到系统或文件"）。依赖 powersys 块的模型在该版本无法工作——这是 MATLAB 的变化，不是本工具的。
- **非 ASCII 参数值**：中文环境 Scope 的 `TimeSpan` 读作 `'自动'` 这类本地化枚举显示名只在同语言版本可用；导出器只在"不等于同类块默认值"时才写入，省略则各版本用自身默认，语义等价。

## 已知版本边界：PMComponent / powersys（T46）

**现象**：`snp_block_source` 表中的 `PMComponent` 条目（库路径 `sps_lib`）在R2026a 上 `add_block` 失败——powersys 产品在该版本整个下线（全库零命中），不是表条目的路径漂移。

**为什么这是版本外部事实，不是本工具缺陷**：
- 表条目的作用是"无 ReferenceBlock 时的回退"（T40）。有 rb 的块导出仍走 rb，不经表；只有 M 线裸建 PMComponent 才会碰到。
- 历史大规模验证的模型没有一个用 PMComponent——跨版本验证 P0 已实测R2025a/R2026a 全套 25/25 IDENTICAL，该条目对验证资产零影响。
- 若你的模型**确实**用了 powersys 专有块并要迁移到 2026a：这是版本间的语义迁移问题（块本身不存在了），需人工找替代块或保留在 2025a——表不动、不为此分版本（见 [解释](../explanation/why-not-versioned-table.md)）。

**表保持单版本的理由**：三版本实测全绿，漂移仅此 1 条且属版本外部事实；分表/加版本列的复杂度不值（同上解释文）。

## 什么时候必须回 M 线

跨版本场景**必须**走 M 快照路线：`.slx` 本身不带跨版本可移植性（内部格式随版本变），M 是唯一逐字节可验证的载体。XML 原地编辑（级①）适合"当前版本内快速改"，它的产物不要跨版本传。
