# Changelog

本项目是 MATLAB/Simulink 工具集合，不使用 npm 包管理；版本约定：发布版本号 `vMAJOR.MINOR`（语义化）打 git tag 为真值，本文件顶部`## [Unreleased]` 记已合并但未打 tag 的条目，发版时整段挪入新版本。

## [Unreleased]

### Added
- **中英双语文档**：`README.md`（英文，默认）+ `README.zh-CN.md`（中文），顶部互链；`docs/zh/` 与 `docs/en/` 两份完全对称的文档树（教程 / 操作指南 / 参考 / 解释 / skills），`docs/README.md` 为语言门户。skills 的 `.m` 脚本与代码块原文不翻译；英文版由 7 个并行子代理写新文件产出（逐篇结构计数核对）。

### Changed（文档）
- **README 按开源规范重写**：slogan、特性、前置条件、安装、快速开始、工作流（三级阶梯 + 双向表）、项目结构、文档导航、测试、已知限制、许可、贡献。保真细节与能力边界表保留在 `docs/{zh,en}/explanation/` 与 `reference/`。

### Fixed
- **假成功路径：`funcEqual`/`fileEqual` 三态化（T71）**：两侧 `Simulink.BlockDiagram.getChecksum` 都获取失败时旧版 `isequal([],[])` 返回 true，被误报"功能等价"（外部只读审查证实，静态可判定）。改为 **1=相同 / 0=不同 / -1=不可判定**，不可判定不得视为通过（与 verify_collab C3 既有 -1 哨兵实践一致）。
- **数据丢失路径：dirty 默认阻断（T70）**：`snp_pull` / `snp_propagate` 对 `Dirty=on`（人有未保存 GUI 改动）从"只警告"升级为默认 error `snp:dirtyBlocked`——无保存强关会**不可恢复地丢弃**这些改动，"会丢数据"必须由明确意图推翻而非默认通过。放行口：`opts.Force=true`。`snp_propagate` 的守卫覆盖**全部已加载块图**（`Simulink.allBlockDiagrams`，因为 `bdclose('all')` 波及全量），枚举自身失败时降级为 warning（fail-open）。`snp_runtime_warn` 同时返回结构化状态 `st.simRunning` / `st.dirty` 供调用方决策。仿真中仍只警告（中断仿真不丢模型数据）。verify_collab C4 更新为阻断语义。
- **死接口：`snp_propagate` 的 `models='auto'` 崩溃（T72）**：旧顺序对 `models` 先做 `models{i}` 花括号索引、后才判 `'auto'`，char 输入直接报错、自动发现**永远走不到**（外部只读审查证实）。改为先发现再进提醒/守卫循环，并补 string 标量 `"auto"` 支持。
- **测试覆盖缺口：新增 `verify_propagate` 套件**：库传播 4 例（手改库文件传播 / `auto` 发现名单 / Dirty 阻断+Force 放行 / 改库快照整链重建）——此前 `snp_propagate` 在 test/ 下零覆盖。
- `docs/{zh,en}/skills/simulink-snapshot-editing/SKILL.md` 内 `../../docs/reference/tool-api.md` 错链（应为 `../../reference/tool-api.md`）。
- **教程可照抄性**：`model-to-snapshot.md` 第 1 步补 `load_system('test/models/ToyBasic.slx')` 前置（`snp_export` 只按裸名找已载入模型）；7 处 `examples/scripts` 过期路径（verify_multiver/verify_cross_behavior/demo_local_edit 头注释、work-across-versions）改 `test/scripts`；how-tos 三处 XML 示例的占位资产 `MyModel.slx` 换成仓库真实玩具模型。
- **SKILL.md YAML frontmatter**：两份 skill 副本的 frontmatter 在此前段落合并中被压成单行（YAML 解析失败），已按原结构恢复。
- **公开面悬空引用**：src 与 test 里 5 处指向内部状态文件的具名引用（plan.md/rationale/tortuous）改为自含说明。

### Changed
- **README 前置条件**：新增一节声明 R2023b 基线 + Simulink/Stateflow/Simscape 依赖，并提醒所有命令在仓库根执行；套件清单补 `verify_snp_patch`/`verify_xml_*`/`demo_local_edit` 等漏列脚本；新增「Skills」节给 `docs/zh/skills/simulink-snapshot-editing/`（本工具用法 skill）入口。
- **默认产物目录**：`config_example.m` 的 `OutDir` 从 `scratch` 改 `test/scratch`（与套件约定一致，避免在仓库根生成 gitignore 外的目录）；`.gitignore` 加 `/scratch/` 兜底。

### Changed（结构）
- **项目结构整肃为四层**：`src/` 源码｜`test/` 测试套件+示例资产（scripts/models/lib/snapshots/fixtures）｜`docs/` 文档（含 skills内置副本）｜`private/` 状态。顶层跟踪目录从 8 个（docs/examples/lib/ models/parameters/skills/snapshots/src）整合为 4 个；`scratch/` 与`sfun_probe/` 为 gitignore 的运行时目录（不计入项目结构）。资产归 test/ 的理由：示例库+模型+快照全部服务于验证套件；快照与models/lib 在 test/ 下同层，`SaveRel`/`LibRel` 兄弟相对值零改。`config_example.m`/`config_local.m` 的资产目录字段同步加 test/ 前缀。

### Added
- **发布前清理与导出指南**（[docs/zh/how-tos/prepare-release.md](docs/zh/how-tos/prepare-release.md)）：用 `git archive` 导出（只打跟踪文件，gitignore 的本机产物天然不带；且不含 git 历史），含导出前复验步骤。**"复制整树"会把`scratch/`/`config_local.m`/`sfun_probe/` 等本机文件带出去**。
- **LICENSE** — MIT 许可证；README 加「许可」节。此前无 LICENSE 等于默认"保留所有权利"，他人在法律上不能复用本仓库。
- **snp_config** — 配置抽象：机器相关值（`MatlabBin`/`TargetRelease`/ `LibDir`/`ModelsDir`/`SnapDir`/`AliasMap`/`ExtraHeader`/`OutDir`）抽进配置文件。`cfg = snp_config()` 优先读 `config_local.m`（本机真值，**gitignore 不入库**），回落 `config_example.m`（仓库附带的示例孪生，占位值）。从任意子目录调用可工作（`which` 锚定仓库根）。
- **snp_merge3** — 三路合并器：两份派生快照（人侧/agent 侧）与共同祖先合并，按节+键级对齐。同块双改默认 theirs（模型=唯一真相），删 vs 改默认删优先并进冲突清单；正交改动自动合并。`opts.UseGit` 可切换`git merge-file --diff3` 做交叉验证（默认关：行级 diff 无块语义，相邻块双侧各改一处并成假冲突区会丢数据）。
- **snp_propagate** — 库传播 runner：改库后一键重建引用模型并逐模型回读校验。支持 `models='auto'` 自动扫含 `add_block('<lib>/…')` 的快照。主用法为直传（`RebuildLib=false`，库源已改只重建模型）；快照不随库改动变化（链接式实例重建时自动带新内容）。
- **snp_runtime_warn** — 内部 helper：dirty/仿真中两态发`snp:dirtyUnsaved`/`snp:simRunning` 提醒（可 `warning off` 静默），接入 pull/propagate/export 三处真实事故点。
- **verify_collab** — 人机协作场景矩阵（pull 注释保留/加删块/重建等价、dirty/sim 提醒、merge3 三路合并）8/8。

### Removed
- **示例资产整体替换**：此前的示例工程资产（多模型 + 多库模块 + 参数）已移出公开面，替换为玩具资产（`ToyLib` 真库四块 + ToyBasic/ToyLibRef/ ToyChart/ToyPhys 四模型）。旧快照随之删除。原资产上的历史验证数字（重建 25/25、行为 30/30、跨版本 CROSS 25/25）转入 CHANGELOG 历史记录。

### Fixed
- **snp_xml_edit**：`remove_block` 的 mops 不再附带相关连线的 `remove_line` ——与 `snp_patch` 删块自带的悬空线清理（strip_dangling_lines）双重清线，回灌时 remove_line 必报"找不到连线"。mops 只含 remove_block，XML 侧清线保留（玩具资产 `verify_xml_sync` 实测 3/3）。
- **snp_export** 四个真实缺陷（玩具库验证暴露）：① chart 检测的链式 `sfroot().find()` 在 `-batch` 抛错被 try/catch 静默吞，独立 chart 降级成普通子系统——拆开两步调用 + 失败告警；② 库模型重建丢 Library 类型（`BlockDiagramType` 实测返回小写`'library'`），库引用实例得内联副本失链——`new_system` 带第二参数；③ 库/子系统内部线在 blocks 节与 lines 节**双重 emit**，重建报"目标端口已有信号线连接"——lines 节跳过已展开容器；④ 快照头 `m=get_param(bdroot,'Name')` 在 head `load_system(库)` 之后取到**库名**（load 库会切换 bdroot），全部 add_block 写进锁定库—— m 改为字面模型名。rb 实例补注册 head `load_system`（否则引用模型重建时库未加载、实例失链）。
- **snp_pull**：chart 内容（状态/转移）随块回流——此前 merge_blocks 只认rtc 附属行，chart 的内容行不回流（加 `% ---- chart X end ----` 收尾标记 + 附属行判定扩展）。
- **snp_export**：裸 masked SubSystem（无 ReferenceBlock）的 mask 参数与内部块此前导出丢失（改用 `Simulink.Mask.create`+`addParameter`，并补`LookUnderMasks='none'` 遮蔽的内部块与内部线）。
- **snp_patch**：参数值旧正则在旧值含逗号时截断留半个值（改两形态正则）；`remove_block` 现清理指向被删块的悬空 `add_line`（按末段块名
  + parent 路径判，同名前缀块不误删）。

### Changed
- 文档精确化（按 A 组实测）：`snp_xml_edit` 只能改非默认值参数（Simulink存储事实）；`snp_patch` 字符类边界——逗号使行解析失败、引号需转义、**括号实测可完整往返**（旧措辞过严）；`snp_view_nogeom` 视图重建口径从"不能"改为"不保证"。
- `docs/zh/how-tos/merge-human-changes.md` 新增"pull 前必须知道的 Simulink运行时行为"：GUI 修改不自动存盘（dirty flag）、仿真运行中不能改结构、窗口不监视磁盘文件、看新内容用 `bdclose`+`open_system` 而非关 MATLAB。
- README / tool-api / SKILL 的工具清单同步（src 现含 snp_config / snp_runtime_warn 等内部 helper，公开 API 见 tool-api）。
- README 按玩具示例资产重写：目录表/能力边界表/保真验证口径（当前玩具基线 REBUILD 5/5 + FRESH 5/5；历史大规模验证数字转入本文件历史段）。
- 示例验证脚本去硬编码模型清单：`verify_behavior` 改目录枚举，`verify_rebuild_all` 临时快照用绝对 LibRel（temp 根无仓库层级关系），`export_all_snapshots` 入口加 `-batch` 下的仓库根锚定。

### Known Limitations（不计入版本语义，记录用）
- `snp_xml_edit` 的 XML 内不能留注释——Simulink 的 system XML 解析器拒绝 XML 注释（对照实验证实）。agent 注释请写 M 快照手写区/注释节或画布注解。

## [历史] — 2026-10-28 ~ 2026-10-30

本段记录项目早期的大规模验证结论。**这些验证使用的是当时的私有工程资产（已移出本仓库），本段数字为该资产下的实测结论**；当前开源仓库的可复现口径是示例资产（1 库 + 4 模型 + 5 份快照，REBUILD 5/5、FRESH 5/5，见 README 状态节）。

- **核心库穷举**：R2023b `simulink` 核心库枚举 502 块 / 163 种BlockType，表外 119 种逐一 `add_block` 实测入库（T24 判据）；后经跨版本验证再扩条目，现表为 200 条 case（见[docs/zh/reference/block-coverage.md](docs/zh/reference/block-coverage.md)）。
- **工具箱穷举**：`slblocks().OpenFcn` 得 52 顶层库 + `physmod/**/library/*.slx` 得 278 子库，收录 33 种新块型（SimEvents 实体系、nesl_utility Simscape 工具系、FMU/Reciprocal 等）。
- **三版本跨版本验证**（R2023b / R2025a / R2026a）各自全套全绿：快照导出 25/25、重建 25/25、行为 30/30、特殊块 11/11、roundtrip PASS；跨版本 CROSS 判据（基线版本导出的 25 份快照在新版本重建并复导出逐字节一致）25/25。
