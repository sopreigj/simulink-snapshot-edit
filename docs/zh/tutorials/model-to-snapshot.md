# 教程：把模型变成可编辑的快照

跟走一遍完整闭环：**导出快照 → 运行快照重建模型 → 验证重建一致 → 改一行试试**。全程用仓库自带资产，命令可直接复制运行。假定你已在仓库根目录，MATLAB 是 R2023b（基线版本）。

## 你将学会

- 什么是"自足 M 快照"，它为什么能逐字节重建模型
- 怎么导出、怎么重建、怎么验证
- 怎么只改快照里一个块的几行，而不动其他任何内容

---

## 第 1 步：导出快照

拿仓库自带的示例模型 `test/models/ToyBasic.slx` 练手——一个普通块模型：常数 `c1` → 增益 `g1`（Gain=2）→ 示波器 `sc1`。它是纯模型，不含库实例，最简单：

```matlab
addpath('src');
load_system('test/models/ToyBasic.slx');   % snp_export 从内存加载：须先全路径载入
opts = struct();
opts.OutDir  = 'test/snapshots';      % 快照输出目录
opts.AliasMap = cell(0, 2);          % 无别名时显式给空
opts.SaveRel = '../models';          % 快照重建时：ToyBasic 是模型，存回 models/
snp_export('ToyBasic', opts);
```

产物：`test/snapshots/snapshot_ToyBasic.m`。

> `load_system` 用**全路径**（相对仓库根）——`snp_export` 只按裸名找已载入的模型，不会替你搜 path。导出后 `close_system('ToyBasic')` 释放内存。

> `SaveRel` 是**相对快照文件所在目录**的路径——快照拿到别的机器上跑也能找到正确位置，不含本机绝对路径。库模块导出时 `SaveRel` 指向 `../lib/blocks`；若模型含库链接实例（如本仓库的 `ToyLibRef`，引用 `ToyLib` 库的四块），还要给 `LibDir`（实例源解析的库搜索目录）与 `LibRel`（重建时找库的相对路径），快照头会自动生成 `load_system` 先把库装进来。

`snp_export` **没有返回值**——它直接写文件。如果想确认有没有块被跳过，看 **stderr**：出现 `[snp_export skip] <块名>` 或 `snapshot INCOMPLETE` 就说明有块没导出（原因见 [参考：块型覆盖](../reference/block-coverage.md)）。

> 快照是纯文本 MATLAB 函数。打开看看：分节注释（`%% ---- blocks ----`）、每块一行 `add_block(...'Position',...)`、`add_line(...'Points',...)`。这些几何行是故意的——重建需要它们（见[解释：为什么快照是真相](../explanation/why-snapshot-is-truth.md)）。

## 第 2 步：运行快照，重建模型

快照是**自足**的——它自己 `new_system` + 建全部块 + 连全部线 + 保存。在**快照所在目录**执行（快照内部用相对路径找输出目录）：

```matlab
cd test/snapshots;
snapshot_ToyBasic();
cd ../..
```

产物：`test/models/ToyBasic.slx` 被重建（`SaveRel` 指向那里）——这就是它叫"快照"的原因：重跑就还原。重建脚本执行完会关闭模型。

> 不设 `SaveRel` 时，重建的 `.slx` 默认落在**快照所在目录**（`test/snapshots/ToyBasic.slx`）。想覆盖原资产就必须显式给 `SaveRel`。

## 第 3 步：验证重建一致

项目的主力判据是**文本级**：对重建结果再导出一次，两份快照文本逐字节比对（`verify_rebuild_all` 对仓库全部 5 份资产做这个：1 个库 + 4 个模型）：

```matlab
cd test/scripts;
verify_rebuild_all;     % 全套结构重建验证（REBUILD 5/5）
verify_snapshots_fresh; % 仓库快照 vs 现导结果（FRESH 5/5）
```

对单个模型，也可以用 `snp_collab_check` 的**功能级**校验和做"没改坏"核对（它只度量、不改模型）：

```matlab
open_system('test/models/ToyBasic.slx');
rep = snp_collab_check('ToyBasic', 'Compare', 'ToyBasic');
disp(rep.funcEqual);   % true = 两模型功能等价
```

> 注意：`BlockDiagram.getChecksum` 对**库模块**（如 `ToyLib`）可能返回空（编译不适用）；库模块走文本级判据更稳。

日志落在 `<repo>/test/scratch/`（gitignore，不污染仓库）。

## 第 4 步：只改一个块的几行

现在体会"局部修改不动其余"。把 `g1` 增益块的值从 2 改成 5：

```matlab
snp_patch('test/snapshots/snapshot_ToyBasic.m', 'g1', 'Gain', '5');
```

`snp_patch` 只替换快照里 `g1` 那一行的 `Gain` 参数，**文件里其他所有字符逐字节不变**。再跑一次快照，重建出来的模型里只有增益变了：

```matlab
cd test/snapshots; snapshot_ToyBasic(); cd ../..;
open_system('test/models/ToyBasic.slx');
disp(get_param('ToyBasic/g1', 'Gain'));   % 5
```

> 这一步会覆盖仓库里的 `test/models/ToyBasic.slx`。练完想还原，用`git checkout -- test/models/ToyBasic.slx`（快照文件同理）。

（你的真实模型里，把块名和参数换成目标即可——例如给库链接实例改 mask 参数`snp_patch(f, 'tm', 'Kp', '7')`，或给限幅块改`snp_patch(f, 'tl', 'UpperLimit', '2')`。注意 `snp_patch` 的参数值**含逗号会使行解析失败**（引号需转义；括号实测可完整往返），遇含逗号的值直接手改快照行。）

完整工作流和每个 API 的参数细节见 [操作指南](../how-tos/) 和[参考：工具 API](../reference/tool-api.md)。

---

## 回顾

- **模型 = 唯一真相**：快照从模型导出，重跑快照就还原模型。
- **局部修改**：编辑快照里目标块的几行，其余内容（其他块、位置、布线、注释）逐字节保留——这是"最小改动"的来源。
- **两个方向都走同一条文本**：agent 改快照代码、人改 GUI 模型，回流闭环见[操作指南：人改完 GUI 怎么 pull 回来](../how-tos/merge-human-changes.md)。

下一步：读 [操作指南](../how-tos/) 学具体任务，或读[解释](../explanation/) 理解设计取舍。
