# 操作指南：Stateflow——chart 与 MATLAB Function 块

任务：模型里有 Stateflow 内容。两种东西长得很像、处理方式完全不同：**独立 chart**（状态机）和 **MATLAB Function 块**（函数体）。

## 先分清是哪一种

| | 独立 chart（`sflib/Chart`） | MATLAB Function 块 |
|---|---|---|
| 内容 | 图形化状态机（状态 + 转移） | 文本函数体（`Script` 属性） |
| BlockType | `SubSystem` | `S-Function`（`sf_sfun`） |
| 内容怎么导出 | **结构化导出** State/Transition | `Script` 文本回灌 |

## 独立 chart：结构化导出（已内置，你通常不用管）

`snp_export` 检测到独立 chart 时自动：
1. 用 `sflib/Chart` 建块；
2. 把 chart 的**状态**（`Name` / `LabelString`）和**转移**（`Source` / `Destination` / `LabelString`，无 Source 的为默认转移）逐个序列化进快照；
3. 重建时用 `Stateflow.State` / `Stateflow.Transition` 对象逐个重建。

**关键写法**（如果你手改快照里的 chart 内容）：`LabelString` 的换行在快照里写字面 `\n`，但重建代码**必须**用 `sprintf('...')` 包裹——单引号字面 `\n` 不会被还原成真换行，Stateflow 会把字面反斜杠解析进状态名。生成的快照已经这么写了，你跟着它的格式改即可。

**状态名取首行**：Stateflow 的 `Name` 属性可能含 `\n` 解析残留（如标签 `A\nen: ...` 的 Name 变成 `A<换行>en:`），导出时取首行干净名。

## MATLAB Function 块：Script 回灌

MATLAB Function 块的内容在 Stateflow **EMChart** 的 `Script` 属性里。`snp_export` 把它收集到快照尾部段，`save` + `reload` 后统一写入—— **重建后端口签名与原件一致**（Stateflow 解析函数签名自动适配接口）。

坑（项目里踩过）：`Script` 多行文本必须以正确方式写入——用`strjoin(lines, sprintf('\n'))` 把真换行的 char 数组写进 `rtc.Script`；`char("...\n...")` 会把多行字符串变成字符矩阵，Stateflow 只识别首行，接口会被推断错。

## 改 chart / 改函数体

- **改 chart 状态机**（加状态、改转移条件）：最稳的是 GUI 改 → `snp_pull`回流（pull 的块节合并会处理 chart 行）。XML 线（级①）改 chart 也行——改 XML 不需要知道 chart 的结构知识。
- **改 MATLAB Function 块的函数体**：直接改快照里对应的 Script 行（快照尾部段），或 GUI 改完 pull。
- **`snp_patch` 删 MATLAB Function 块会被拒绝**——它的 chart 脚本段会悬空。

## 验证

- chart 导出已端到端验证（2 状态 + 2 转移含默认转移，重建逐项一致、`skip=0`、无 `INCOMPLETE`）。
- 重建后用 `snp_collab_check` 比功能级校验和，或跑`test/scripts/verify_rebuild_all`。

## 一个有用的捷径（非自足场景）

如果**源模型在场**，`add_block('srcModel/Chart', 'dstModel/C1')` 会把chart 连状态机一起整体复制（实测有效，2 状态 2 转移全部随行），`sfclipboard` 的 `copy` + `pasteTo` 也可以。这适合**验证或快速重建**；**自足 M 快照**仍必须走结构化导出——文本序列化才是跨版本可移植的载体。
