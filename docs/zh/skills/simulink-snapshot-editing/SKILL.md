---
name: simulink-snapshot-editing
description: >-
  用 simulink-snapshot-edit 工具链编辑/快照/合并 Simulink 模型：拿到 .slx
  做局部编辑时走三级阶梯（XML 原地改 → XML→M 回灌 → 直接改 M 快照）、
  快照与回流（snp_pull）、双向校验（snp_collab_check）与"什么叫改对了"
  的验证判据。用于"改这个模型的参数/结构""人改完 GUI 怎么回流""跨版本
  重建验证"。不教建模本身——建模规范见 simulink-modeling-conventions；
  也不教几何排版（几何 agent 不写，自动排版实测不可用）。
metadata:
  priority: 5
  toolchain: "MATLAB/Simulink R2023b (verified, 三版本 2023b/2025a/2026a)"
  docs:
    - "https://ww2.mathworks.cn/help/simulink/slref/get_param.html"
    - "https://ww2.mathworks.cn/help/simulink/slref/add_block.html"
    - "https://ww2.mathworks.cn/help/simulink/ref/simulink.getfilechecksum.html"
    - "https://ww2.mathworks.cn/help/simulink/ref/simulink.blockdiagram.getchecksum.html"
  pathPatterns:
    - '**/*.slx'
    - '**/snapshot_*.m'
    - '**/snp_*.m'
    - '**/verify_*.m'
promptSignals:
  phrases:
      - "局部编辑"
      - "改快照"
      - "snp_export"
      - "snp_patch"
      - "snp_pull"
      - "回灌"
      - "xml 重打包"
      - "人机协作"
      - "重建模型"
      - "快照验证"
---

# Simulink Snapshot Editing

## Overview

本 skill 教 agent 使用 `simulink-snapshot-edit` 工具链（`src/snp_*.m`）编辑Simulink 模型。核心契约：**模型（.slx）是唯一真相，M 快照是自足重建的兜底真相**。局部修改只动目标块，其他块逐字节不变。

工具一览（接口以 `src/*.m` 源码为准）：

| 函数 | 作用 | 阶梯 |
|---|---|---|
| `snp_export` | 模型 → 自足 M 快照 | 全路线起点 |
| `snp_xml_edit` | 改 .slx 包内 XML 并重打包 | ① 最快 |
| `snp_sync_m` | XML 编辑 → 回灌 M（①+② 桥） | ② |
| `snp_patch` | 直接改 M 快照的若干行 | ③ |
| `snp_view_nogeom` | M 去几何**读视图**（不重建） | ③ 读 |
| `snp_pull` | 人改 GUI → 回流进 M（注释全留） | 人→agent |
| `snp_collab_check` | 双校验和：谁动过 / 改没改坏 | 守卫 |
| `snp_block_source` | BlockType → 库路径共享表（200 case） | M 线依赖 |
| `snp_merge3` | 人机**并发**三路合并（键级，非行级 diff3） | 多人/多 agent |
| `snp_propagate` | 改库 → 重建引用模型（快照不变） | 库传播 |

接口细节（签名/参数/返回字段/已知限制）见[docs/zh/reference/tool-api.md](../../reference/tool-api.md)。

## When to Use
- "把这个模型的 X 块参数改成 Y"（参数级 → 走 ① 或 ③）
- "给模型加/删个块、改连线"（结构级 → ① 或 ③，看是否要跨版本）
- "人改完 GUI 了，把改动同步进代码"（→ `snp_pull`）
- "人和 agent 同时改了同一模型，怎么合"（→ `snp_merge3`：base/ours/theirs三份快照；同块双改默认 theirs，删 vs 改默认删优先）
- "改了库，引用它的模型怎么办"（→ `snp_propagate`：库实例是链接式，重建引用模型即带新内容；快照无需同步）
- "改对了没有？"（→ 验证三件套：回读 + 对比 + 行为等价）
- "两个版本/两条路线的产物是否等价"（→ `snp_collab_check`）

## 决策树：走哪条阶梯

```
拿到 .slx 要做局部编辑
├─ 只改参数（不增删块/线）？
│   ├─ 需要跨版本可移植 / 逐字节留痕 → ③ snp_patch 改 M（或先 export 再改）
│   └─ 只要改完模型本身、最快 → ① snp_xml_edit
├─ 增删块/线（结构级）？
│   ├─ 块型已收录在 snp_block_source（200 case）→ ① 或 ③ 均可
│   ├─ 块型未收录/未知 → ①（XML 不需要库路径；M 线 add_block 才需要）
│   └─ 要 M 与 .slx 双向一致 → ② snp_sync_m（① 打桥，自动回灌 M）
├─ 人改了 GUI → snp_pull 回流
└─ 要判断"谁动过/改没改坏" → snp_collab_check
```

两条铁律：
1. **库路径是 API 侧知识**——只有 `add_block`（M 线）需要它；XML 原地编辑不需要块型白名单（D6）。M 线的 add_block 经 `snp_block_source` 查表。
2. **几何 agent 不写**——块位置与走线是展示属性（D5）。XML 路径剔除几何；M 快照刻意保留 `Position`/`Points`（为逐字节可重建），读模型时用 `snp_view_nogeom` 产出去坐标视图。

## ① XML 原地编辑（snp_xml_edit）
```matlab
addpath('src');
ops = { {'set_param', 'ToyLibRef/tm', 'Kp', '7'}, ...
        {'add_block', '', 'Gain', 'G1', {{'Gain','2'}}}, ...
        {'add_line',  '', 'g1', 1, 'G1', 1}, ...
        {'remove_block', 'OldBlock'} };
info = snp_xml_edit('m.slx', 'm_edited.slx', ops, 'Verbose', true);
```
- 源/目的端口：普通信号写端口号 `'1'`；Simscape 物理端口写 `'LConn1'`/`'RConn1'`
- 块路径用模型内路径（与 `get_param` 一致）；父路径 `''` = 模型顶层
- 未列白参数、Stateflow、Simscape 物理连接**原样保留**；布局不碰
- 返回 `info.applied/skipped`；`skipped` 非空要读原因，别静默放过
- **只改非默认值参数（存储事实，非 bug）**：Simulink 只写与默认值不同的参数，默认值参数的 XML 里没有对应条目 → set_param 类操作进 `skipped`。先改成任意非默认值再编辑，或走 M 路线（快照写全参数）
- **XML 里不能留注释**：Simulink 的 system XML 解析器拒绝 `<!-- -->`（对照实验证实，插入注释的包无法载入）。agent 备注写 M 快照手写区/注释节，或用画布注解（`<Annotation>`，导出器支持）
- 依赖 MATLAB 自带 Java（`-nojvm` 启动不可用）

## ② XML→M 回灌（snp_sync_m）
```matlab
info = snp_sync_m('m.slx', 'test/snapshots/snapshot_m.m', ops);
% 等价于：snp_xml_edit 产出编辑件 + 把 info.mops 应用到 M
```
- 让 M 与 .slx 双向一致、无需人工比对；M 仍是兜底真相
- M 侧 `add_block` 需要 `snp_block_source` 收录该块型——未收录会报错（此时要么先补表，要么只用 ①）

## ③ 直接改 M 快照（snp_patch）
```matlab
snp_patch(f, 'SpeedPI', 'Ilim', '30');                 % 参数
snp_patch(f, 'add_block', 'Name','NewConst', ...
          'Source','simulink/Sources/Constant', ...
          'Position',[100 100 130 130], 'Value','42');
snp_patch(f, 'remove_block', 'NewConst');
```
- 只动目标行，文件其余逐字节不变——这是"局部编辑"的承诺
- **字符类边界（实测精确）**：逗号使行解析失败（引号需转义；括号可完整往返，如 `'(3)'` 回读 `Gain=(3)`）——含逗号的值手改快照行，别硬调 patch
- `remove_block` 会清理 lines 分节里指向被删块的 `add_line`（按末段块名 + parent 路径判，同名前缀块不误删）；MATLAB Function 块拒绝删（chart 脚本段悬空）

## 快照的正确姿势（snp_export）

```matlab
o = struct(); o.OutDir = tempname; mkdir(o.OutDir);   % ← 临时目录！
o.LibDir = 'test/lib/blocks'; o.AliasMap = cell(0,2);
snp_export('MyModel', o);
```

三条实测纪律：
1. **OutDir 用 `tempname`**——InlineMasks=false 路线重建会把 .slx 写进快照所在目录；写 temp 就不会覆盖 `test/models/`、`test/lib/blocks/` 等资产
2. **InlineMasks 语义**：`true`→ masked 子系统展开成普通子系统导出内部（默认主路线）；`false`→ 保留 masked 副本（验证 mask 参数级保真用，需要被引用的库可加载）
3. **重建后回读**：快照脚本执行完模型已关闭（`bdIsLoaded` 恒 0）——判据是 `open_system(产物)` 再读块数/参数，绝不能把"读到空"当失败

## 人改 GUI 后回流（snp_pull）

```matlab
rep = snp_pull('MyModel', 'test/snapshots/snapshot_MyModel.m', opts);
% rep.nAdd/nDel/nChg/nNoteKept —— 注释（分节/块上方）全部保留
```

- 算法：按节对齐 + 按块名对齐；注释随块走，语句换新
- **容器兜底**：人新建的裸子系统（无库链接）会输出`add_block('built-in/SubSystem', ...)` 容器行——pull 后快照仍可重建
- 改动报告要看 `rep.detail`：`节保留（新模型无此节）` 类条目说明人删了整节，确认是否符合预期
- 库改动会自动传播：模型快照只记链接 `add_block('lib/blk',…)`，改库后用未改的模型快照重建，实例自动带上库新内容

## 验证：什么叫"改对了"

**"载入成功"不能证明改对了**（本项目的铁律）。每次改完按序做：
1. **回读**：`open_system` 产物 → `get_param(块,'BlockType')` 与目标参数逐项读回；`add_block` 建的新块要回读 `LineHandles`/`PortConnectivity`
2. **结构对比**：与原模型比块数/块型集合（`verify_rebuild_all` 口径：REBUILD IDENTICAL）；功能级校验和相同时注意排除 `RTP_XXXXXXXX`哈希块名的变化（RTP 变不等于功能丢失）
3. **行为等价**：原模型与修改件同仿真比对逐信号 `max|diff|`（期望 0；`verify_behavior` 口径）。原模型自身仿真失败时属"不可判定"，不是重建失败

## 双向校验（snp_collab_check）

```matlab
rep = snp_collab_check('M');                              % 两个校验和
rep = snp_collab_check('EditSlx', 'Compare', 'RebuiltM'); % 双线功能等价
rep = snp_collab_check('M', 'BaselineFile', 'm.slx');     % 人是否动过文件
```
- **文件级** `Simulink.getFileChecksum`（MD5）：文件内容变它就变——管"谁动过"（人移动块也会变）
- **功能级** `BlockDiagram.getChecksum`（128 位）：功能不变它不变——管"改没改坏"（移动块不变，改参数变）
- 何时跑：合并回流前、双线产物（XML 编辑件 vs M 重建件）一致性判定、决定是否需要 pull
- 只度量不改模型；功能级会编译模型，`-batch` 里较慢是官方行为

## 常见坑（详见 references/traps.md，浓缩版）

| 症状 | 根因 | 对策 |
|---|---|---|
| `add_block` 报没有该模块 | 手写"一行"的库名 | 用 `find_system` 返回的原始路径（可能含真换行 char(10)） |
| MATLAB 字符串拼接解析错 | 用 `+` 连字符串 | `sprintf` 或分行调用 |
| 换行没写进去 | 单引号 `'\n'` 是字面两字符 | `sprintf('\n')` 才是真换行 |
| FaultInport/StateControl 裸 add_block 失败 | 结构性端口块依附父系统 | 由父块（如 Fault Subsystem）随之生成，不独立建 |
| 重建后 `bdIsLoaded`=0 | 快照脚本执行完已关闭 | `open_system(产物)` 再回读 |
| 库实例 resolve 失败 | 产品在新版本下线（如 powersys 于 R2026a） | 外部事实，非工具责任；示例资产不受影响 |

## Bundled Tooling
- `test/scripts/`：`export_all_snapshots`、`verify_rebuild_all`、`verify_behavior`、`verify_special_blocks`、`test_roundtrip`、`verify_multiver`（三版本）、`verify_snapshots_fresh`
- `test/scratch/`：所有验证/诊断输出的约定去处（`dbg_*.txt` 等，gitignore）
- 与建模规范 skill 互补：怎么**建**模型见 `simulink-modeling-conventions`

## Additional Resources
- `references/traps.md`：坑清单逐条（含判据与规避代码）
- `README.md`：三个起点（只有模型 / 只有代码 / 两边都有）同一条链
- 判据与设计决策：`docs/`（三级阶梯、D5 几何、D6 库路径归属）
