# Traps：agent 使用工具链的坑清单

每条给：症状 / 判据 / 规避。浓缩自项目实测与踩坑记录。

## 1. "载入成功"不能证明改对了
- **症状**：改 XML/快照后模型能打开，以为改对了
- **判据**：必须回读目标块 `BlockType` + 参数 + （新块）`LineHandles`/ `PortConnectivity`，再仿真比对
- **规避**：每次改完跑"验证三件套"（回读 → 结构对比 → 行为等价）；校验失败报"代理块"，不静默放过
- **新块插入位置**：XML 里必须插在 blocks 段末尾（最后一个 `</Block>`之后），绝不能放 `</System>` 前

## 2. 库路径要用 find_system 的原始真值
- **症状**：`add_block('fl_lib/<看起来一行的名字>', ...)` 报"没有该模块"
- **根因**：fl_lib 物理源块名**含真换行 char(10)**，显示成一行是假象
- **规避**：`find_system(fl_lib, ...)` 返回什么用什么，绝不手写；写进快照的字面 `\n` 在执行前用 `strrep` 还原

## 3. MATLAB 单引号 '\n' 是字面两字符
- **症状**：chart LabelString / 多行字符串写进去换行没生效，状态名变成 `A_nen_` 之类的解析残留
- **判据**：`'\n'`（单引号）= 反斜杠+n 两字符；`sprintf('\n')` = 真换行
- **规避**：生成代码里写 `sprintf('...')` 包裹含 `\n` 的字面量；拼字符串不要用 `+`，用 sprintf 或分行
- **chart 专用**：状态机导出走 `Stateflow.State`/`Transition` 结构化重建（chart 无 `Script` 属性）；chart 块重建别手 set Position（初始化期报维度错）

## 4. 结构性端口块不独立 add_block
- **症状**：`add_block('mwfaultblocklib/.../Fault Inport')` 失败
- **根因**：FaultInport/FaultOutport/StateControl 等依附父系统
- **判据**：`add_block` 父块（如 Fault Subsystem）成功后**自带**这些端口块（实测 R2023b）——M 线重建不需要、也不应独立建
- **规避**：枚举库时这类块记为"设计性跳过"，不入 `snp_block_source`

## 5. 重建后 bdIsLoaded 恒 0
- **症状**：快照 `run` 后 `bdIsLoaded(model)` 返回 0，以为重建失败
- **根因**：快照脚本执行完自己 `close_system` 了
- **规避**：`open_system(产物文件)` 再 `get_param`；绝不能把"读到空"当功能不成立。产物文件名必须与内部模型名一致（放不同目录避免覆盖，否则 get_param 按文件名找不到

## 6. InlineMasks=false 的保存位置
- **症状**：重建产物找不到 / 误以为覆盖了资产
- **根因**：InlineMasks=false 路线把重建 .slx 写进**快照所在目录自身**
- **规避**：`OutDir = tempname`（绝不写 `test/models/`、`test/lib/blocks/`）；重建后 `open_system` 前先 `bdclose(模型名)`（同名残留会报"已加载具有不同路径的同名模型"）

## 7. 物理端口块型走 built-in
- **症状**：在 fl_lib 搜 'Physical' 找不到 PMIOPort
- **规避**：PMIOPort 走 `'built-in/PMIOPort'`（经 `snp_block_source`）；那是 PS 信号库不是物理端口库；物理连接按端口名 + 连通分量导出

## 8. 功能级校验和的 RTP 陷阱
- **症状**：Simscape 模型重建后功能级校验和不等于功能丢失
- **根因**：`RTP_XXXXXXXX` 哈希名的块随重建变化
- **规避**：判读时排除 `RTP_` 前缀块，或改用非 RTP 项逐项 `setdiff` 比对

## 9. snp_patch 的字符类边界（实测精确化）
- **逗号**会使行解析失败（`'2,5'` 重建报"参数无效"）——真坏，预处理或改走 XML
- **引号**需在值中转义
- **括号实测可完整往返**（写进快照、重建回读生效，语义按表达式求值，如 `'(3)'` 回读 `Gain=(3)`）——旧措辞"括号也不行"过严，不用回避
- `remove_block` 会清理指向被删块的 `add_line`（同名前缀块不误删）——删块后无需手工补线

## 10. 枚举库（fidelity 侧）
- 有限深度（如 20）、**不加** LookUnderMasks；枚举前写 diag探针确认本版本行为，别照搬模型上的用法
- 库发现：库名 = `slblocks().OpenFcn`（不带引号）；physmod 子库模式新版本为 `library/**/*.slx`（库下移一层）
- 一次跑 60+ 库可能进程级崩溃——分批 16 库/进程（2026a 实测）

## 11. 跨版本库漂移
- **症状**：某表条目在新版本 add_block 失败（PMComponent 于 R2026a）
- **根因**：产品整体下线（powersys），不是路径漂移
- **判据**：表条目只是无 rb 时的**回退**；有 rb 的导出仍走 rb。模型若真用该块型，其 rb 指向下线库是版本外部事实
- **规避**：示例资产不受影响（三版本覆盖盘点已证无真覆盖缺口）；无需分版本表
