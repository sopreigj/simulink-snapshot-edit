# docs — simulink-snapshot-edit 维护文档

[English](../en/README.md) · 中文

这里回答 **README 之外**的问题：README 教你"怎么跑起来"（[回 README](../../README.md)），这里教"怎么维护、为什么这样设计"。

按 [Diátaxis](https://diataxis.fr/) 四类组织，**一篇服务一种读者需求**：

| 类 | 你想…… | 去哪 |
|---|---|---|
| 教程 | 跟着走一遍，学会基本闭环 | [tutorials/](tutorials/) |
| 操作指南 | 完成一个具体任务（假定已会基础） | [how-tos/](how-tos/) |
| 参考 | 查接口/参数/覆盖口径的准确清单 | [reference/](reference/) |
| 解释 | 理解为什么这样设计、取舍在哪 | [explanation/](explanation/) |

## 速查

- **第一次来**：读 [tutorials/model-to-snapshot.md](tutorials/model-to-snapshot.md)，跟着走"导出→重建→验证"一遍。
- **要改模型**：先看 [how-tos/edit-block-params.md](how-tos/edit-block-params.md)（三级阶梯选哪级）。
- **人改了 GUI 要回流**：[how-tos/merge-human-changes.md](how-tos/merge-human-changes.md)。
- **查 API 签名**：[reference/tool-api.md](reference/tool-api.md)。
- **查块型覆盖**：[reference/block-coverage.md](reference/block-coverage.md)。
- **要发布/导出**：[how-tos/prepare-release.md](how-tos/prepare-release.md)。
- **问"为什么"**：[explanation/](explanation/)。

## 约定

- 示例命令里的 `<repo>` 指仓库根目录；MATLAB 命令在 `<repo>` 下执行（`addpath('src')` 后）。
- 基线版本 **R2023b**。跨版本注意事项见 [how-tos/work-across-versions.md](how-tos/work-across-versions.md)。
- 套件临时产物（日志、中间模型）统一落 `test/scratch/`（gitignore），不散在仓库各处。
