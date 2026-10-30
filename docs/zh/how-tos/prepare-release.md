# 操作指南：发布前清理与导出

**解决的问题**：要把仓库导出成别人能用的开源版本，怎么保证不带本机产物、私有状态与 git 历史。

**核心结论**：用 `git archive`，不要复制整棵目录树。

## 为什么不用"复制整树"

工作树里有一批 `.gitignore` 的本机产物（`test/scratch/` 验证中间件、`test/scripts/multiver/` 多版本归档、`config_local.m` 本机配置、`test/sfun_probe/` 运行时夹具目录）。复制整树会把它们全部带走；`git archive` 只打包 git 跟踪的文件，天然不带。

## 步骤

1. 确认工作树干净：`git status --short` 无输出（或只有你明确要带入发布的改动并已提交）。
2. 导出（在仓库根）：

   ```bash
   git archive --format=tar --prefix=simulink-snapshot-edit/ HEAD \
     | tar -x -C <目标目录>
   ```

3. 抽查导出树：
   - 无 `private/`（状态边界，未跟踪）
   - 无 `test/scratch/`、`config_local.m`、`test/sfun_probe/`、`*.slxc`、`slprj/`
   - `LICENSE`、`README.md`、`CHANGELOG.md`、`config_example.m`、`src/`、`test/`、`docs/` 齐全

## git archive 的一个重要性质

`git archive` 打包的是 HEAD 时刻的文件树，**不含 git 历史**。如果发布形式是"一份无历史的源码包"，这一条正好满足；如果发布形式是推送到公开仓库，则历史会一并公开——那属于另一个决定（是否先做历史剥离），不在本指南范围。

## 导出前的复验

发布前把验证套件跑一遍（`test/scripts/` 下），至少：

- `verify_rebuild_all`（重建保真 1 库 + 4 模型）
- `verify_snapshots_fresh`（快照新鲜度）
- `verify_special_blocks`（特殊块型）

```matlab
run('test/scripts/verify_rebuild_all.m');
```
