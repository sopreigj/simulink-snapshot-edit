# simulink-snapshot-edit

> 把 Simulink 模型变成**可读、可编辑、可逐字节验证的代码**——模型是唯一真相，小改只动几行，其余原样。

**English** · [中文](README.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## 这是什么

一个 MATLAB/Simulink 工具链：给一个 `.slx` 模型导出一份**自足 M 快照**（一个 `.m` 函数，运行一次即完全重建模型——全部块、全部参数、位置、连线折线），之后的局部编辑只改快照里对应块的几行，**其他块与相对位置逐字节不变**。

它解决一个具体痛点：**从零生成模型的 build 脚本每次全量重建，手工排版成果（拖动出的布局、相对位置）全部丢失**。本工具把工作流倒过来：**模型 → M**，小改只需改 M 里几行再重跑；人在 GUI 里改的模型，也能回流进代码（注释全保留）。

面向两类用户：
- **工程师**：把成熟模型纳入文本工具链（git diff、code review、CI 验证），局部修改精确、可审、可回滚
- **LLM / agent**：得到一份模型的可读表示，能直接编辑并验证，而不是面对二进制 `.slx` 无从下手

## 特性

- **模型 → M 快照**：自足可重建；块 `Position`、线 `Points` 折线、数值 17 位有效数字（double 精确往返）
- **局部编辑**：`snp_patch` 改快照中某个块，其余逐字节不动；XML 原地编辑（级①）连重跑快照都省了
- **双向**：人改模型 → `snp_pull` 回流进代码，`snp_merge3` 做人机并发三路合并
- **三级编辑阶梯**：XML 原地编辑（最快）→ XML→M 回灌 → 直接编辑 M 快照（跨版本保真的兜底真相）
- **跨版本**：快照是纯 M 代码，R2023b 基线实测兼容 R2025a/R2026a
- **自带验证套件**：重建保真、产物新鲜度、行为等价、跨版本可跑——10 个套件全绿

## 前置条件

- MATLAB **R2023b** 基线（R2025a/R2026a 实测兼容）；装 **Simulink**
- 验证套件另需 **Stateflow** 与 **Simscape**（示例资产含 chart 与物理网络）

## 安装

```bash
git clone <repo-url> simulink-snapshot-edit
cd simulink-snapshot-edit
```

无第三方依赖、无构建步骤。机器相关的路径（MATLAB 二进制、输出目录等）按需配置：

```matlab
% 复制配置示例孪生为本机配置（gitignore，不入库）
copyfile('config_example.m', 'config_local.m');
% 编辑 config_local.m 里的 MatlabBin / LibDir / OutDir 等字段为本机真值
cfg = snp_config();   % 优先读 config_local.m，回落 config_example.m
```

> 仓库不带任何本机配置，克隆即可用。

## 快速开始

**在仓库根目录执行**（`addpath('src')` 与 `test/...` 路径都相对仓库根）：

```matlab
addpath('src');

% 起点 A：只有模型 → 生成快照代码
opts = struct(); opts.OutDir = 'test/snapshots'; opts.LibDir = 'test/lib/blocks';
opts.AliasMap = cell(0,2); opts.LibRel = '../lib/blocks'; opts.SaveRel = '../models';
load_system('test/models/ToyBasic.slx');      % 先加载模型（snp_export 按裸名找已载入模型）
snp_export('ToyBasic', opts);                 % → test/snapshots/snapshot_ToyBasic.m

% 起点 B：只有代码 → 生成模型（在 snapshot 所在目录执行）
cd test/snapshots; snapshot_ToyBasic(); cd ../..

% 起点 C：两边都有 → 双向协同
%   agent 改代码：直接编辑 snapshot 里目标块的几行 → 重跑（其余原样）
%   人类改模型：GUI 改完存盘 → snp_pull 把改动回写进代码（注释全留）
snp_pull('ToyBasic', 'test/snapshots/snapshot_ToyBasic.m', opts);

% 局部编辑 API（改快照中某个块，其余逐字节不动）
snp_patch('test/snapshots/snapshot_ToyBasic.m', 'g1', 'Gain', '5');
```

## 工作流

**三级编辑阶梯**（按速度选，M 快照是贯穿三级的兜底真相）：

| 级 | 做法 | 适合 |
|---|---|---|
| ① XML 原地编辑 | 直接改 `.slx` 包内 XML 块参数再重打包（`snp_xml_edit`） | 最快、保真最高；产物不是"可重建的 M" |
| ② XML→M 回灌 | XML 改动经解析后写回 M 快照（`snp_sync_m`） | 要保持 M 与模型一致 |
| ③ 编辑 M 快照 | 直接改 M 代码 | 可逐字节验证、跨版本可移植 |

**双向工作流**（代码 ↔ 模型，两条链路都"最小改动、其余原样"）：

| 方向 | 操作 | 保留保证 |
|---|---|---|
| agent → 模型 | 编辑 snapshot 里目标块的几行 → `run(snapshot)` | 其他块/位置/注释全不动（文本层天然保留） |
| 人类 → 代码 | GUI 改模型（存盘）→ `snp_pull(mdl, snapFile, opts)` | 所有现有代码及相对位置保留：块节按块名对齐，LLM 手写区逐行保留；`snp_merge3` 处理人机并发 |

## 项目结构

```
src/            工具链（13 个 snp_* 函数，API 清单见 docs/zh/reference/tool-api.md）
test/           验证套件 + 示例资产
  models/         示例模型：ToyBasic / ToyLibRef / ToyChart / ToyPhys
  lib/            示例库 ToyLib.slx
  snapshots/      快照代码（snapshot_<name>.m，1 库 + 4 模型）
  scripts/        验证脚本（verify_*、demo_local_edit、test_roundtrip 等）
  fixtures/       测试小模型
docs/           中英双语文档（见下）
config_example.m 配置示例孪生（复制为 config_local.m 填本机值）
```

## 文档

完整文档在 `docs/` 下，**中文**与**英文**两个对称版本：

- [中文文档](docs/zh/README.md)：教程 / 操作指南 / 参考 / 解释
- [English docs](docs/en/README.md): tutorials / how-tos / reference / explanation

入门路线：[教程：模型 → 快照](docs/zh/tutorials/model-to-snapshot.md) → [为什么快照是真相](docs/zh/explanation/why-snapshot-is-truth.md) → [API 参考](docs/zh/reference/tool-api.md)。

**agent 接手本项目**：先读 [用法 skill](docs/zh/skills/simulink-snapshot-editing/SKILL.md)（决策树、验证三件套、踩坑清单），再看 [建模规范 skill](docs/zh/skills/simulink-modeling-conventions/SKILL.md) 副本。

## 测试

```bash
# 用你的 MATLAB R2023b 二进制（PATH 上的 matlab 可能是别的版本）
"<matlab-bin>" -batch "cd('<repo>\test\scripts'); verify_rebuild_all"
```

主要套件：`verify_rebuild_all`（重建保真 5/5）、`verify_snapshots_fresh`（产物新鲜度 5/5）、`verify_snp_patch`、`verify_xml_structure/edit/sync`（XML 三阶）、`verify_behavior`（行为等价）、`verify_cross_version`/`verify_multiver`（跨版本）、`verify_collab`（人机协作）。

各套件日志与临时产物统一落在 `test/scratch/`（gitignore，不入库）。

## 已知限制

- 变体子系统只保留当前激活分支（变体切换无法用文本表达，导出时打印提示）
- `.slx` 包内 XML 不能留 agent 注释（Simulink 拒绝载入）；注释写进 M 快照的注释节或用画布注解
- XML 重打包路径的产物 `.slx` 不带跨版本可移植性，跨版本场景走 M 快照路线

## 许可

MIT，见 [LICENSE](LICENSE)。

## 贡献

欢迎提 issue 与 PR。改动请保持 `test/scripts/` 下验证套件全绿；涉及文档时请同步 `docs/zh/` 与 `docs/en/` 两份。
