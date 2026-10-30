---
name: simulink-modeling-conventions
description: >-
  Simulink 建模规范：子系统封装（mask/调色板/自解释）、信号流组织
  （Goto/From/Scope/总线/Mux/接线点）、命名与缩写词表、以及可编程检查。
  用于构建或审查 .slx 模型、写 build 脚本、判断"这个信号该不该用 Goto"、
  "Scope 该怎么接"、"块该不该封装"。不用于指导几何排版——自动排版实测无效，
  见下文「能力边界：自动排版不可用」。
metadata:
  priority: 5
  toolchain: "MATLAB/Simulink R2023b (verified)"
  docs:
    - "https://ww2.mathworks.cn/help/simulink/slref/simulink.annotation.html"
    - "https://ww2.mathworks.cn/help/simulink/slref/simulink.blockdiagram.arrangesystem.html"
    - "https://ww2.mathworks.cn/help/simulink/slref/get_param.html"
    - "https://ww2.mathworks.cn/help/simulink/slref/set_param.html"
  pathPatterns:
    - '**/*.slx'
    - '**/*.mdl'
    - '**/build_*.m'
promptSignals:
  phrases:
      - "simulink 建模"
      - "simulink 封装"
      - "子系统 mask"
      - "goto from"
      - "信号流"
      - "scope 怎么接"
      - "总线 mux"
      - "simulink 规范"
      - "MAAB"
---

# Simulink Modeling Conventions

Simulink 的**建模规范**：怎么封装、怎么组织信号流、怎么命名。不包含可用的几何排版指导——原因见下。

## Overview

**核心原则：规范的收益在"可读性"和"可维护性"，不在"好看"。**

模型是给人读的。一个 Clark 变换块，读者应该一眼看出它做什么、参数是什么、输入输出是什么含义——这靠封装（mask + 调色板 + 中文说明）达成，不靠坐标。

**排版无能，先说清楚。** R2023b 的 `arrangeSystem` / `routeLine`在本项目模型上实测无效，详见[能力边界](#能力边界自动排版不可用)。本 skill 不指导排版。

## 能力边界：自动排版不可用

在含反馈回路的成熟模型上的实测（同一份代码、同一份输入），自动排版**无一改善、多数更差**：`arrangeSystem` 单独用会把横图压成竖图、交叉数不降反升；网格 + 各种分层策略（拓扑深度/保留原分层/中心吸附）交叉数都是原图的数倍；"只挪 Scope"这类局部手法也有数十字段净增。

**为什么必然失败**：模型里有结构性跨列回授（角度前馈、转速环进电流环、负载指令这一类跨越多列的长距离反馈边）。层次布局算法假设图接近 DAG，带级联回授的控制系统模型不是。且 `routeLine` 需要空白画布腾挪，块挤满时它一条线都不改。

**结论：几何排版只能人工。** 改 `build_*.m` 里的 `Position`，人在 Simulink 里看图调整，脚本可重复执行所以改一次永久生效。本 skill 不提供排版算法。

**经 simulink-snapshot-edit 工具链编辑时，几何只经 GUI 产生**——M 快照**刻意保留** `Position`/`Points`（逐字节可重建所必需，D5）；只在 agent 读模型时用`snp_view_nogeom` 剔除几何行产读视图（约省 35% 行），视图不替代 M。

## When to Use

- 写 `build_*.m` 生成 `.slx`，需要决定"这个功能要不要单独成子系统"
- 给子系统加 mask（说明、参数、配色）
- 判断一个信号该用直连线还是 Goto/From
- 决定 Scope / To Workspace / Terminator 怎么接
- 用 Mux/Bus 组织多信号，或需要分支
- 审查模型是否符合 MAAB 规范
- 生成缩写词表

**不用于**：几何排版、仿真行为、求解器设置。

## Editing（经 simulink-snapshot-edit 工具链编辑）

本仓库的模型（`test/models/`、`test/lib/blocks/`）分工固定：**人类只在 Simulink GUI 里改.slx**，改完由 `snp_pull` 把变更回流进 M 快照（手写注释区逐行保留）；**agent 不碰GUI，只经工具链改 M 快照或 .slx 包内 XML**，不改原始 `.slx` 的 GUI 侧内容。机器相关路径经 `snp_config()` 读 `config_local.m`（gitignore，不入库），不在脚本里硬编码本机值。agent 侧的三级阶梯（plan D4）：

1. **XML 原地编辑** `snp_xml_edit`：改 .slx 包内 `simulink/systems/system_*.xml`再重打包——最快、保真最高（未列白参数、Stateflow、物理连接原样保留）。
2. **XML→M 回灌** `snp_sync_m`：把 XML 编辑翻译成 M 快照改动，M 与 .slx 双向一致。
3. **agent 直接改 M 快照**：经 `snp_patch` 打补丁（M 快照保留坐标；读模型时用`snp_view_nogeom` 剔除几何行）。

贯穿三级的铁律：

- **几何归属（D5）**：块位置与连线走线由人经 GUI 调整，或由 XML 路线交由Simulink 自动排列；agent 不重排既有排版。M 快照**必须保留** `Position`/`Points` ——那是逐字节可重建的前提，去几何只发生在 `snp_view_nogeom` 的读视图里。
- **XML 里的新块只写 `BlockType` 即可**，库路径是 M 侧知识（D6，`snp_block_source` 管这件事），模型文件不需要。
- **XML 新块必须插在 blocks 段末尾**（最后一个 `</Block>` 之后）——插在线之后会按文档顺序被静默丢弃。
- **载入成功 ≠ 写对了**：未知 BlockType 会降级成代理块且载入不报错。编辑后必须回读 BlockType/参数/连接 + 仿真，校验失败按代理块报错，不静默放过。
- **验收 = 重导出成 M 做集合 diff**（`test/scripts/verify_xml_*.m` 的判据），不看"能打开"。人机协作链路的验收见 `test/scripts/verify_collab.m`（pull 注释保留、dirty/仿真中提醒、merge3 三路合并 8 场景）。

## Subsystem Encapsulation（封装）

### 什么该做成子系统

`db_0144`：按**功能分解**分组，不为省空间。每个子系统代表一个功能单元。

判断标准：这个块的集合，能否用一句话说明它做什么？说不清 → 拆；说得清但和旁边的功能混在一起 → 拆。

`db_0143`：每一层要么**全是子系统**，要么**全是基础块**，不混。（Inport/Outport/Mux/Goto/From/Sum/UnitDelay 等路由块可任意层出现。）

### 封装的四要素

```matlab
lib_build.mask(blk, 'transform', ...
  'Clark 变换：abc 到 alpha-beta（幅值不变）', ...
  struct('Name','k','Type','edit','Value','2/3'));
```

1. **MaskType = 功能类** —— 决定配色，来自固定调色板
2. **MaskDescription = 中文一行说明** —— 冒号前是短名（进图标），冒号后是详述
3. **MaskVariables = 具名参数** —— 禁止 Parameter1/Parameter2 这种默认名
4. **MaskDisplay = 短标题** —— 图标只显示短名，详述放 MaskDescription

### 调色板（固定，不得自创）

| 功能类 | 颜色 | 用途 |
|---|---|---|
| `transform` | lightBlue | Clark / Park / 反变换 |
| `estimator` | `[1 1 0.8]` 浅黄 | PLL / SMO / LDO / DSO |
| `control` | `[0.5 1 0.5]` 浅绿 | PI / 控制环 |
| `modulation` | `[1 0.75 1]` 浅紫 | SVPWM / 逆变器 |
| `signal` | orange | 滤波 / 解调 |
| `measure` | gray | 测量 / 工况 |
| `machine` | darkGreen | 电机本体 |
| `aux` | white | 常量 / 复用 |

颜色一旦分散，"同一个 Clark 在两个库里是两种蓝"，读者对颜色的记忆失效。

### 子系统接口必须完整展示

子系统的**每个端口名都必须显示出来**。块太矮时端口名会挤在一起甚至看不见，读者无法知道这个子系统吃什么、给什么。

判据（`check_port_visibility`，L13）：每端口约需 14 单位高度，上下各留 8 边距。

```
最小高度 = 16 + 14 × max(nIn, nOut)
```

8 个端口的子系统至少需要 128 单位高，默认 30 单位是绝对不够的。显示不下时：**拉伸放大**，不要靠隐藏端口名蒙混（`jm_0002` 允许隐藏的前提是"在块旁清晰标注信号线"——那是最后手段，不是首选）。

### 端口顺序

**这是唯一无法事后自动修复的事。** 端口顺序乱的子系统，任何排版引擎都只能交叉连线来够到正确的端口。

- Inport 按信号流重要性排序：给定 → 反馈 → 少改的参数 → 诊断
- Outport 顺序应读起来像算法的小标题
- 物理位置：Inport 在子系统内左列，Outport 在右列（`db_0042`）

## Signal Flow（信号流）

### Goto / From

`jc_0171`：必须保持信号流的视觉呈现。允许用 Goto/From 的条件：

- 至少有一条画出来的线连接两个子系统
- 前馈 + 反馈回路中，**每个方向**各有一条画出来的线

**例外**：用 Goto/From 组总线、或接 Merge 块的输入。

判据：如果一个图全是 Goto/From，读者看不到任何数据流——这是违反 `jc_0171` 的。Goto/From 占多数的层必须整改。

### 观测点：From → 处理 → Scope

需要数据处理的观测点，链路固定为：

```
From ──► 处理（Gain / Offset / BusSelector / Demux）──► Scope
```

"处理"块与其服务的 Scope 视为一组。不要从被观测对象直接拉一根线进Scope——那样 Gain 偏置、单位换算会散落在图里。

**Scope / Goto / From / To Workspace 一般不做主干**（它们不产生数据，只是转发或显示）。除非该层没有任何其他块可做主干。

### 信号标签

`na_0008`：以下块出来的信号**必须**有标签——Inport、From、Subsystem、Bus Selector、Demux、Selector、Data Store Read、Constant。以下块的输入**必须**有标签——Outport、Goto、Data Store Write、Bus Creator、Mux、Subsystem、Chart。

`na_0009`：标签的**录入 vs 传播**——

- 录入（直接打字）用于：根层 Inport 出来的信号、**变革性**块的输出（Bus Creator / Mux / Selector 算变革性）
- 传播（用 `<` 前缀）用于：嵌套子系统里 Inport 出来的、**非变革性**块的输出、Subsystem/Chart 的输出

`db_0097`：标签放在水平线**下方**，靠近源或目标块，不与其他标签/信号/块重叠。

### 总线与 Mux

- 同一 Mux 的输入按端口号顺序，不交叉
- 条件执行子系统的输出合并，优先用虚拟总线（Bus Creator + Bus Selector）而不是一堆 Merge 块
- 扇出不超过 2 个子分支（`db_0032`）
- 需要 5 个以上目标时，用 Goto/From 或总线，不要拉 5 条线

### 死块与空信号：三种不同的病

`db_0081` 只覆盖最表面的一种。实际有三类，检查手段不同：

| 类型 | 现象 | 检测 |
|---|---|---|
| **悬空口** | 端口没接线 | `check_unconnected`（L7）直接看 `get_param(port,'Line')` 是否 -1 |
| **空 From 标签** | From 接了线，但标签在本层没有对应 Goto | `check_orphan_tags`（L11）比对标签集合 |
| **孤岛子链** | 子链内部完整连通，但整体与主干无关 | `check_islands`（L12）算连通分量 |

第二类最隐蔽：从"端口是否连线"看完全正常，实际收不到任何信号。第三类也隐蔽：每个端口都连着，只是没人用它的结果。

`check_islands` 用两条互补判据：

- **无源无汇**：分量里既没有源（Inport/Constant/Step/From/Ground…）也没有汇（Outport/Scope/ToWorkspace/Terminator/Goto）→ 一定是死块
- **相对孤立**：本层存在 ≥3 块的主分量时，任何只有 1~2 块且不含Inport/Outport 的分量都是可疑旁支

注意判据的边界：`Constant → Terminator` 这种"有源有汇但整体无关"的链，按定义不算死块（它自洽），不会被报。

### 未连接的口

`db_0081`（Mandatory）：不允许有悬空的输入/输出/信号线。多余的输入接 `Ground`，多余的输出接 `Terminator`。

## Naming（命名）

`jc_0201` / `jc_0211` / `jc_0221` / `jc_0231` 四套规则约束一致，适用于子系统名、端口名、信号线名、块名：

- 不以数字开头，不含空格和回车
- 只允许 `a-z A-Z 0-9 _`
- 下划线可分词；不连续、不置于首尾

推论：`theta_hat` 合法；`θ^`、`speed (rpm)` 不合法。

`jm_0010`：端口名与信号名一致，或用一致的 `_in` / `_out` 前后缀。`jc_0081`：Inport/Outport 的 Icon display 设为 **Port number**。`db_0142`：块名显示在块**下方**。

## Abbreviation Legend（缩写词表）

每层放一个注释，列出该层可见缩写的全称与含义。不解释的缩写是读者最大的阅读成本。

```matlab
annotate_legend(mdl, 'Meanings', struct( ...
  'TH','电角度 electrical angle', ...
  'WE','电角速度 electrical angular speed', ...
  'UA','a相电压 a-phase voltage'));
```

未填含义的缩写会先列出并标 `TODO`。用 `Tag='ABBR_LEGEND'` 定位，重复调用只覆盖不堆叠。

自动收集该层可见缩写（Goto/From 标签、端口名、Scope 名、To Workspace变量名、信号线名）：

```matlab
abbr = legend_collect(mdl);   % 返回 cell，人工填含义
```

## Bundled Tooling

只保留**不依赖自动排版**、确定可用的脚本：

- `scripts/fit_block_text.m` — 把 Gain/Constant/Goto/From 撑到完整显示内容。R2023b 无 `resizeBlocksToFitContent`，这是替代实现。只放大不缩小。
- `scripts/annotate_legend.m` + `scripts/legend_collect.m` — 缩写词表生成。
- `scripts/audit_layout.m` — **只读**检查，13 类（`check_unconnected`、`check_orphan_tags`、`check_islands`、`check_port_visibility` 等都是它的**内部子函数**，不独立导出；下文表格里的 L7/L11/L12/L13 指这里的编号）：
  - L1 重叠 / L2 离屏 / L3 椭圆 Sum / L4 过窄块 / L5 名字位置 / L6 字体不一致
  - L7 悬空口 / **L11 空 From 标签** / **L12 孤岛与孤立旁支** / **L13 子系统接口显示不全**
  - L8 线穿块 / L9 线交叉 / L10 流向不改动模型，可随时安全跑。

不提供排版脚本。见[能力边界](#能力边界自动排版不可用)。

## Additional Resources

- 规则逐条正文、优先级、Model Advisor 检查名 → [references/maab-rules.md](references/maab-rules.md)
- R2023b 实测 API 行为（`arrangeSystem` / `routeLine` / `Simulink.Annotation` / `get_param` / `set_param`，含 4 处与现行文档的差异）→ [references/simulink-api-notes.md](references/simulink-api-notes.md)