# 操作指南：人改完 GUI，怎么把改动 pull 回快照

任务：人在 Simulink GUI 里改了模型（挪块、改参数、加块删块）并保存，现在要把这些变更合并回 M 快照，而且**不能弄丢 agent 之前写的注释和代码结构**。

## 一条命令

```matlab
addpath('src');
opts = struct();
opts.LibDir = 'test/lib/blocks';
opts.AliasMap = cell(0, 2);
rep = snp_pull('MyModel', 'test/snapshots/snapshot_MyModel.m', opts);
```

`snp_pull` 会先**强制从磁盘重载模型**（MATLAB 可能残留同名已加载模型，不重载会读到旧内容——pull 的前提是"磁盘上的模型即人刚改的"），然后把变更合并进快照，并返回差异报告：

| `rep` 字段 | 含义 |
|---|---|
| `nAdd` | 模型里新增的块（快照追加 `[new]` 标记） |
| `nDel` | 模型里删除的块（删语句、**保留注释**并标记） |
| `nChg` | 变更的块 / 行 |
| `nNoteKept` | 保留的注释行数 |
| `detail` | 逐项差异清单（前 10 条打印到命令行） |

## 注释为什么能保留（算法要点）

合并器按**节**对齐（快照的分节注释 `%% ---- blocks ----` 是天然边界）：

- 节标题与手写内容（非语句行）**一律保留旧快照的**；
- 块节按**块名**对齐：模型仍有该块 → 换新语句（注释不动）；模型没了 →删语句留注释并标记；模型新增 → 追加到块节末尾并标记 `[new]`；
- chart 的 Script 行（`rtc.…`）作为所属块的附属行随块走；
- 其余节（lines / annotations / config / ws）：文本相同则保留旧（含注释），不同则换新文本并报告变化。

一句话：**agent 的手写区（分节注释、块上方注释、辅助行）逐行保留，只按块名对齐增删改语句**。

## pull 前必须知道的 Simulink 运行时行为

以下四条是 pull 工作的前提（MathWorks 官方文档 + 本项目实测）：

1. **GUI 修改不自动存盘**——改动只存在 MATLAB 内存里，标题栏的星号（dirty flag）就是未保存标记。必须 Ctrl+S 或 `save_system`。所以约定的流程是：**人改完 → 停仿真 → 存盘 → 再 pull**。
2. **仿真运行中不能改结构**——官方明确"During simulation, you cannot make changes to the structure of the model"。参数调整在停止后生效，且通常要重新运行（fast restart 模式可避免重复编译）。
3. **Simulink 窗口不监视磁盘文件**——agent 重建出的新 .slx 不会自动出现在仍开着的窗口里；窗口显示的是 MATLAB 内存中的模型。
4. **想看到文件新内容：`bdclose` + `open_system`，不用关 MATLAB**——关掉窗口不够（模型仍在内存），关整个 MATLAB 太重（丢工作区变量）。pull 内部正是这么做的（强制 `close_system`+`bdclose`+`load_system`从磁盘重载）。

来源：[Saving a Model](https://in.mathworks.com/help/simulink/ug/saving-a-model.html)、[Controlling Execution of a Simulation](https://es.mathworks.com/help/simulink/ug/controlling-execution-of-a-simulation.html)、[Fast Restart](https://au.mathworks.com/help/simulink/ug/fast-restart-workflow.html)；内存/文件分叉与 `bdclose` 重载姿势见上文"内存里的模型 vs 磁盘上的文件"。

工具会就上述两条主动提醒（不阻断执行，`warning('off','snp:dirtyUnsaved')`可静默）：`snp_pull` / `snp_propagate` 在无保存强关模型前检测`Dirty='on'` 与 `SimulationStatus`，命中时分别发`snp:dirtyUnsaved` / `snp:simRunning`；`snp_export` 只查仿真状态。

## pull 前先判断"谁动过"

`pull` 之前可以用 `snp_collab_check` 的文件级校验和确认"人确实动过这个文件"：

```matlab
rep = snp_collab_check('MyModel', 'BaselineFile', 'test/models/MyModel.slx');
disp(rep.fileEqual);   % false = 文件级不同（人动过或重新保存过）
```

两个校验和刻意分工：**文件级**（`Simulink.getFileChecksum`，MD5）管"谁动过"（挪一个块也会变）；**功能级**（`BlockDiagram.getChecksum`，128 位）管"改没改坏"（挪块不变、改参数变）。

## pull 之后验证"没改坏"

pull 完重跑快照，再比功能级校验和：

```matlab
cd test/snapshots; snapshot_MyModel(); cd ../..;
open_system('test/models/MyModel.slx');
rep = snp_collab_check('MyModel', 'Compare', 'MyModel');
disp(rep.funcEqual);   % 期望 true：pull 后的快照重建件与改后模型功能等价
```

## 验证脚本

- `test/scripts/test_roundtrip.m` 端到端覆盖基础循环：A1 快照重建 == 模型 diff=0；A2 最小改动 + 注释保留；B 人类三操作（移位 / 加块 / 删块）pull 后注释全留；C pull 后快照重建 == 改后模型 diff=0。
- `test/scripts/verify_collab.m` 场景矩阵（8 条）：C1-C3 同上沉淀，另含 **C4 dirty 提醒**（人没存盘就 pull → `snp:dirtyUnsaved`）、**C5 仿真中提醒**（SimulationStatus=running → `snp:simRunning`）、C6-C8 merge3 正交 / 同块冲突（theirs 优先） / 删 vs 改（删优先）。

## 常见坑

- **PATH 上有同名模型残留**：`snp_pull` 内部已 `close_system` + `bdclose`强制重载，不用你手动处理。
- **人来回改了好几轮才 pull**：没问题——pull 是"当前模型 vs 旧快照"的两路合并，中间过程不参与。
- **人重命名了块**：pull 表现为"删旧名 + 加新名"（注释随旧块行走，会在 detail 里看到两条）。重命名不跟踪身份，这是当前实现的边界。
- **结构性大改动**（删整个子系统、把块移进子系统）：可以 pull——容器行由导出器的 `built-in/SubSystem` 兜底产出（详见[操作指南：增删块](add-remove-blocks.md)）。
