# 参考：工具 API

每个函数的签名、参数、返回、副作用，**从源码摘抄**，准确无遗漏。想理解为什么这样设计去 [explanation/](../explanation/)；想学基本用法去 [tutorials/](../tutorials/)。

通用约定：
- 所有函数在 `addpath('src')` 后调用。
- 基线版本 R2023b；跨版本放行见各函数条目。
- 套件临时产物统一落 `test/scratch/`（gitignore）。

---

## snp_export — 模型 → 自足 M 快照

```matlab
snp_export(mdl, opts)     % 无返回值
```

把已排版的模型导出为自足 M 快照：运行一次即重建原模型（全部块 / 全部参数 / Position / 布线折线 / 注解 / 求解器配置 / Model Workspace 变量）。

### opts 字段

| 字段 | 默认 | 说明 |
|---|---|---|
| `OutDir` | `pwd` | 快照输出目录；产物 `snapshot_<mdl>.m` |
| `LibDir` | `''` | 库 `.slx` 搜索目录（实例源解析）；空则不解析库 |
| `AliasMap` | `cell(0,2)` | 实例名 → 库模块名缩写表 |
| `ExtraHeader` | `{}` | 生成代码头部附加行（如 `addpath(...)`） |
| `InlineMasks` | `false` | `true` 时把 masked 子系统**展开成普通子系统**导出内部结构 |
| `LibRel` / `SaveRel` | `''` | 相对**快照文件所在目录**的库目录 / 目标目录（可移植） |
| `AllowUntestedVersion` | `false` | 非基线版本放行（或环境变量 `SNP_ALLOW_UNTESTED=1`） |

### 行为与副作用

- **没有返回值**，结果只写文件。
- **skip 走 stderr**：某块无法导出时打印 `[snp_export skip] <块名> (BlockType=...)`，结尾 `[snp_export WARNING] <模型>: N blocks skipped — snapshot INCOMPLETE`。判据 = stderr 无 skip 行。
- 版本断言：非 R2023b 直接 assert（除非放行）；放行时 stderr 打 warning。
- 模型需已加载（未加载自动 `load_system`）。

### 内部机制（读快照时有用）

- 实例源解析三级：子系统内 `FP_*` 指纹注解 → 块名（去尾数字）匹配`LibDir/*.slx` → 别名表；普通内置块走 `snp_block_source` 表。
- 有 `ReferenceBlock`（rb）的块**优先走 rb**；表条目仅是无 rb 时的回退。
- 数值 17 位有效数字（double 精确往返）；存临时名再 `movefile`。
- 独立 Stateflow chart：结构化导出 State/Transition，`src='sflib/Chart'`（详见 [操作指南：Stateflow](../how-tos/handle-stateflow.md)）。
- 无库源裸 SubSystem：兜底 `built-in/SubSystem` 容器行。
- 端口块（Inport/Outport）只写端口号。

---

## snp_pull — 人 GUI 改动 → 合并回快照

```matlab
rep = snp_pull(mdl, snapFile, opts)
```

把当前磁盘模型的变更最小化合并回快照：**LLM 手写区（分节注释 / 块上方注释 /辅助行）逐行保留**，按块名对齐增删改语句。

- **强制从磁盘重载**：内部 `close_system` + `bdclose` + `load_system`（防止读到内存里的同名旧模型）。
- 先用 `snp_export` 把当前模型导到临时目录，再与旧快照做节级合并。

### 运行时提醒（不阻断；`warning('off',…)` 可静默）

强关重载之前会检查两项 Simulink 运行时状态，命中时发 warning：

| 条件 | warning id | 含义 |
|---|---|---|
| `Dirty='on'`（人有未保存的 GUI 改动） | `snp:dirtyUnsaved` | 无保存强关会**丢弃未保存改动**——先 `save_system(mdl)` |
| `SimulationStatus~='stopped'` | `snp:simRunning` | 仿真中不能改结构、强关会中断仿真——先停仿真 |

导出端（`snp_export`）只查仿真状态；库传播端（`snp_propagate`）在`bdclose('all')` 前对库与每个模型两项都查。

### opts 字段

| 字段 | 默认 | 说明 |
|---|---|---|
| `LibDir` | `''` | 传给内部 snp_export 的库目录 |
| `AliasMap` | `cell(0,2)` | 别名表 |

### rep 字段

| 字段 | 含义 |
|---|---|
| `nAdd` | 新增块数（快照追加 `[new]` 标记） |
| `nDel` | 删除块数（删语句、留注释并标记） |
| `nChg` | 变更块 / 行数 |
| `nNoteKept` | 保留的注释行数 |
| `detail` | 逐项差异清单（cell，前 10 条打到命令行） |

合并算法细节（节对齐 / 块 token 流 / chart Script 随块走）见[操作指南：人改完 GUI 怎么 pull 回来](../how-tos/merge-human-changes.md)。

---

## snp_merge3 — 三路合并（人机并发）

```matlab
rep = snp_merge3(baseFile, oursFile, theirsFile, outFile)
rep = snp_merge3(..., opts)     % opts.UseGit / opts.TheirsPriority
```

`base` = 共同祖先快照，`ours` = agent 侧派生快照，`theirs` = 人侧派生快照。M 快照是强结构化纯文本（节边界明确、块行有唯一键），因此合并不做通用 diff3的行级 LCS，而做**键级合并**（按节/块名对齐，参数级正交自动合并）。

覆盖 `snp_pull` 管不到的场景：人与 agent **并发**改动同一模型（pull 只是两路串行）。合并结果写出 `outFile`，并返回差异报告。

### opts 字段

| 字段 | 默认 | 说明 |
|---|---|---|
| `UseGit` | `false` | 走 `git merge-file --diff3` fast path；**默认不开**（见下） |
| `TheirsPriority` | `true` | 双方改同一键时的裁决方向；`false` 翻转为 ours 优先 |

### rep 字段

| 字段 | 含义 |
|---|---|
| `nMerged` | 自动合并条目数（无冲突） |
| `nConflict` | 冲突条目数 |
| `nOursKept` / `nTheirsKept` | ours / theirs 侧改动被保留数 |
| `conflictList` | 冲突键（块名/行键）cell |
| `strategy` | 实际使用的路径（`'git'` / `'builtin'`） |
| `notes` | 说明行 |

### 裁决表

| 情形 | 裁决 |
|---|---|
| 双方改同一键且不同 | 冲突 → **theirs**（模型=唯一真相；`TheirsPriority=false` 可翻转） |
| 一方删键另一方改该键 | 冲突 → **删优先**（结构性意图强于参数意图） |
| 双方加同名键内容不同 | 冲突 → theirs + 报警 |
| 其余（单方改 / 正交） | 自动合并 |

### 已知限制

- **UseGit 默认 false 的理由**：行级 diff3 无块语义——相邻块双方各改一处会被并成一个假冲突区，ours 改动被吞（实测最小复现确认）；"删 vs 改"的删优先裁决在 git 路径下完全失效。git 路径仅作交叉验证。
- `conflictList` 的键为裸块名（如 `'G1'`、`'Sub1/SG'`——内部子系统斜杠保留）。历史版本曾带前导 `/`（内部路径口径），已在出口统一剥除。**多块冲突的键以 `'; '` 分号连接**（如 `'G1; G2'`——故意不用斜杠，避免与子系统路径 `'SubA/G1'` 混淆；消费方按 `'; '` split）。
- 三份快照的函数名应与模型名一致（同模型的三份派生快照本就如此）；函数名不一致时 header 节会检测到多条 `function` 声明，**只保留第一条并在 notes 报警**（合并文件保持合法）。

---

## snp_patch — 快照局部编辑

```matlab
snp_patch(file, block, 'Param1', value1, 'Param2', value2, ...)
snp_patch(file, 'line', src, dst, 'Parent', p, 'Points', [x y; ...])
snp_patch(file, 'add_block', 'Name', n, 'Source', src, 'Position', pos, ...)
snp_patch(file, 'remove_block', name)
snp_patch(file, 'batch', ops)
```

只动目标那几行，文件其他内容逐字节不变。

### 动词

| 动词 | 说明 |
|---|---|
| （块名，非动词） | 改块参数：已有参数替换值；新参数在行尾 `');'` 前追加；`Position` 就地替换 |
| `'line'` | 改某条 add_line 的走线点：Points 行存在则替换，不存在则补 try/set_param/catch 行 |
| `'add_block'` | 增块，插在 `% ---- lines ----` 分节标记前；**只支持顶层 `Parent='m'`** |
| `'remove_block'` | 删块，并清理 lines 分节指向它的 `add_line`（同名前缀块不误删）；**MATLAB Function 块拒绝删**（chart 脚本段会悬空） |
| `'add_line'` / `'remove_line'` | 连线增删 |
| `'batch'` | 表驱动：`ops` 为 struct 数组，每项 `{op, args}` |

### 已知限制

- **参数值字符类边界**（2026-10-29 实测精确化）：**逗号**会使行解析失败（`'2,5'` 重建报"参数无效"）；**引号**需转义；**括号实测可完整往返**（`'(3)'` 回读 `Gain=(3)`，语义按表达式求值）。遇含逗号的值直接手改快照行。
- 找不到目标或多处语义冲突 → 报错，不写文件。

---

## snp_xml_edit — XML 原地编辑 + 重打包（级①）

```matlab
info = snp_xml_edit(srcSlx, dstSlx, ops, 'Verbose', true)
```

直接改 `.slx` 包内 `simulink/systems/system_*.xml`，按原条目顺序重打包（Java ZipOutputStream，二进制条目原样复制）。

### ops（每元素一条操作）

| 形式 | 说明 |
|---|---|
| `{块路径, 参数名, 新值}` | 简写，等价 set_param |
| `{'set_param', 块路径, 参数名, 新值}` | 改参数 |
| `{'add_block', 父路径, 块型, 块名, 参数cell}` | 增块；参数cell=`{{'Gain','3.5'},...}`，可空 |
| `{'remove_block', 块路径}` | 删块 |
| `{'add_line', 父路径, 源块名, 源端口, 目的块名, 目的端口}` | 连线 |
| `{'remove_line', 父路径, 源块名, 源端口, 目的块名, 目的端口}` | 删线 |

- 父路径：`''` = 模型顶层；`'Plant'` = 名为 Plant 的子系统。块路径与 `get_param` 一致（如 `'ToyLibRef/tm'`）。
- 端口：普通信号用端口号（`'1'`）；**Simscape 物理端口用 `'LConn1'`/`'RConn1'`**。

### info 字段

| 字段 | 说明 |
|---|---|
| `applied` | `{动词, 目标, 说明}` |
| `skipped` | `{动词, 目标, 原因}` |
| `mops` | 与本次操作等价的 M 侧操作（供级②回灌） |

### 边界

- **只改非默认值参数（存储事实，非 bug）**：Simulink 保存时只写与默认值不同的参数——若目标参数当前是默认值，包内 XML 里没有对应 `<P>` 条目，set_param 类操作会进 `info.skipped`（原因写明）。处理：先把它改成任意非默认值再编辑，或走 M 路线（快照总是写全参数）。
- **XML 内不能留注释**：Simulink 的 system XML 解析器拒绝 `<!-- -->`（对照实验证实：同一重打包流程，插入 XML 注释的包 `load_system` 报"invalid document structure"，不插注释的对照正常载入）。这是解析器限制而非标准 XML 约束——**agent 的备注请写 M 快照的手写区/注释节，或用画布注解（`<Annotation>` 元素，导出器支持）**。
- **不碰几何**：坐标与走线是展示属性（D5）。
- 依赖 MATLAB 自带 Java（`java.util.zip`）：**`-nojvm` 启动时不可用**。
- 产物是"改过的 .slx"，不是"能重建的 M"。

---

## snp_sync_m — XML→M 回灌（级②）

```matlab
info = snp_sync_m(srcSlx, mFile, ops, 'DstSlx', dstPath)
```

流程：`snp_xml_edit` 在 XML 上做编辑（产出编辑件 + `info.mops`）→把 mops 经 `snp_patch` 应用进 M 快照 → M 与 .slx 双向一致。

- 块型→库路径转换用共享表 `snp_block_source`：**块型未收录会报错**（`未收录进 snp_block_source，无法回灌 M 侧 add_block`）。
- 名值参数 `'DstSlx', <path>`：编辑件落盘位置（默认临时文件）。
- 返回 `info` 同 `snp_xml_edit`，另含 `.dstSlx`。

---

## snp_block_source — 块型 → 库路径（共享表）

```matlab
src = snp_block_source(blockType)     % 返回 char；未收录返回 ''
```

- **只有 `add_block` 需要库路径**：模型文件本身只记 BlockType，Simulink载入时自己解析（实测：只写 `BlockType="Gain"`、零库路径的新块能被识别、参数可读回、连线成立、仿真一致）。
- 覆盖口径与"什么不入表"见 [参考：块型覆盖](block-coverage.md)。
- **路径换行约定**：库名含真 `char(10)` 的（如 `'Math⏎Operations'`），表中记为字面 `\n`，函数返回前 `strrep` 还原成真 `char(10)`。
- 有 rb 的块导出时优先走 rb，表条目是无 rb 时的回退。

---

## snp_collab_check — 人机协作守卫（只度量不改模型）

```matlab
rep = snp_collab_check('Model')                                % 单模型：两个校验和
rep = snp_collab_check('ModelA', 'Compare', 'ModelB')          % 双模型功能等价
rep = snp_collab_check('Model', 'BaselineFile', 'x.slx')       % 与磁盘文件比文件级
```

两层官方校验和，**刻意分工**：

| 层 | API | 变化条件 | 用途 |
|---|---|---|---|
| 文件级 | `Simulink.getFileChecksum`（MD5） | 文件内容变就变（挪块也变） | "人类是否动过此文件" |
| 功能级 | `Simulink.BlockDiagram.getChecksum`（128 位） | 功能不变就不变（挪块不变、改参数变） | "双线产物是否功能等价" |

### rep 字段

| 字段 | 说明 |
|---|---|
| `fileChecksum` | 文件级 MD5（char）；模型未存盘时留空 |
| `funcChecksum` | 功能级 `[4x1 uint32]` |
| `funcEqual` | Compare 模式：两模型功能是否等价 |
| `fileEqual` | BaselineFile 模式：与基线文件是否字节一致 |
| `notes` | 说明（判断依据） |

- `BlockDiagram.getChecksum` 会**编译模型**（官方行为），`-batch` 里调用较慢。
- 模型未存盘时 `fileChecksum` 留空（`get_param('FileName')` 不可得）。

---

## snp_view_nogeom — M 快照去几何读视图

```matlab
out = snp_view_nogeom(snapshotFile, 'OutFile', outFile)
```

剔除 M 快照里的几何行（`'Position'` / `'Points'` 参数对），给**读模型**用。早期大规模验证实测 25 份快照几何行占总行数 **35.1%**（4364/12427，历史测量口径），剔除后可读性显著提升。

- **只产出读视图，绝不替代 M 快照本身**——M 里的 Position/Points 是逐字节可重建所必需，重建必须用原 M。
- 判据：整行保留、只删几何参数对，行数不变结构不乱。

---

## snp_propagate — 库传播 runner（改库 → 引用模型自动带新内容）

```matlab
rep = snp_propagate('mylib', {'mA', 'mB'}, opts)
rep = snp_propagate('mylib', 'auto', opts)     % 引用模型自动发现
```

机制：引用模型的库实例是**链接式**（`ReferenceBlock` / `LinkStatus='resolved'`），模型快照只记链接 `add_block('mylib/blk',…)`、不记库内部参数——**改库后用未改动的模型快照重建，实例 resolve 时自动带上库新内容**。所以自动传播只需两步：

1. **（可选）重建库**：run 库快照 M 生成新 `.slx`；若库文件已是新值可跳过
2. **逐模型重建**：对每个引用模型 run 其快照 M（文本不含库参数，重建即带上新内容），并回读校验

模型快照本身**逐字节不变**（`rep.snapHashBefore == After`）——传播靠库侧解析，快照无需同步。

### opts 字段

| 字段 | 默认 | 说明 |
|---|---|---|
| `WorkDir` | `pwd` | 库 / 模型 / 快照所在目录；**run 前 cd 到此**（快照产物落执行时 cwd） |
| `RebuildLib` | `true` | `true` = 先 run 库快照重建库；`false` = 库文件已是新值，只重建模型（**主用法**） |
| `LibSnap` | `WorkDir/snapshot_<lib>.m` | 库快照路径 |
| `ModelSnaps` | `{}`（逐个 `WorkDir/snapshot_<m>.m`） | 各模型快照路径 |
| `Check` | 空 struct 数组 | 期望校验：每项字段 `.model` / `.block` / `.param` / `.value`（字符串比对） |

`models` 参数可传 cell（模型名列表）或 `'auto'`：后者扫描 `WorkDir` 里所有含 `add_block('<libModel>/…', …)` 的 `snapshot_*.m` 自动发现引用模型。

### rep 字段

| 字段 | 含义 |
|---|---|
| `libRebuilt` | 库是否重建（`RebuildLib` 且成功） |
| `libFile` | 库产物路径 |
| `nModels` / `nPropagated` / `nFailed` | 模型数 / 传播成功 / 失败 |
| `models` | 每模型 struct：`.name` / `.rebuilt` / `.err` / `.snapHashBefore` / `.snapHashAfter`（MD5，传播前后应相等）/ `.checks`（每项 `.ok` / `.got`） |
| `notes` | 说明 |

### 已知限制

- **库链接只在 SubSystem 库块上发生**：普通叶子库块（如 Gain）的`add_block` 永远是**内联副本**（`rb` 为空），改叶子库块**不会**传播到已拷贝的模型；只有 SubSystem 库块的实例是链接式。
- **`RebuildLib=true` 需库快照可重建**：库内含**有内部连线的普通SubSystem** 时，内部线的容器路径已正确 emit（`[m '/blk']`，修复见CHANGELOG），重建可过；极旧版本导出的库快照若内部线仍是旧式`add_line(m,...)`，需用当前版本重新导出一次。
- 重建前 `close_system(lib)` 解锁（库默认上锁）；重建后 `open_system`产物文件再 `get_param`（重建脚本会关闭模型）。

---

## snp_config — 读取本机配置

```matlab
cfg = snp_config()
```

集中读取所有**随机器/环境变化**的值。优先 `config_local.m`（仓库根，`.gitignore` 已忽略、不入库），缺失时回落 `config_example.m`（示例孪生，入库，值是占位符）。新克隆的机器按 `config_example.m` 头注释复制一份改成自己机器的值即可。

### cfg 字段

| 字段 | 示例值 | 说明 |
|---|---|---|
| `MatlabBin` | `'<matlab-bin>'` | MATLAB 可执行路径；外部调度 verify 脚本/跨版本测试时用 |
| `TargetRelease` | `'R2023b'` | 版本断言基线 |
| `LibDir` | `fullfile('lib','blocks')` | 自定义库目录（相对仓库根） |
| `ModelsDir` | `'models'` | 演示模型目录 |
| `SnapDir` | `'snapshots'` | 快照目录 |
| `AliasMap` | `cell(0,2)` | 块名→库名别名（默认空） |
| `ExtraHeader` | `{}` | 快照头部注入行（默认空） |
| `OutDir` | `fullfile('test','scratch')` | 默认输出目录 |

`config_local.m` 中定义的本函数未列字段**原样透传**（允许本机扩展）。脚本用法（已接入的示例脚本如此读取环境值）：

```matlab
c = snp_config();
o = struct(); o.LibDir = c.LibDir; o.OutDir = c.OutDir;
```
