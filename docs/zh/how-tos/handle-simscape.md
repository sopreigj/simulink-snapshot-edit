# 操作指南：Simscape 物理连接

任务：模型里有 Simscape 物理网络（电阻、电感、端口块），要导出/编辑/重建。物理连接和普通信号线的处理方式不同，坑也多。

## 导出约定（snp_export 内部已完成，你只需知道）

- **物理端口按名字**导出：`LConn1` / `RConn1`，不用端口号。原因：物理端口没有"端口序号"语义，`get_param(port, 'PortNumber')`对它们一律返回 1，`add_line` 传 `<块>/1` 会报"Simulink 对象名称无效"。
- **按连通分量还原网络**：一个物理网络（多条两两连接归并而成）在快照里连成一棵**星形生成树**（n 个端点 n-1 条边），Simscape 自己会归并回同一网络。原因：`PortConnectivity` 给出的是完全图（3 端口 → 3 条两两配对），照配对逐条 `add_line` 会在第三个端口报"第二个端口已有信号线连接"。
- **PMIOPort 等物理端口块**走 `built-in/PMIOPort`（经 `snp_block_source` 表），不要去 Simscape 库里按名字搜 'Physical'——那是 PS 信号库，不是物理端口。

## XML 线编辑物理连线

`snp_xml_edit` 的 `add_line` / `remove_line` 支持物理端口，端口参数传`'LConn1'` / `'RConn1'`（XML 里写为 `#lconn:N` / `#rconn:N`，`<Line LineType="Connection">`，不扇出）：

```matlab
ops = { {'add_line', '', 'R1', 'RConn1', 'gnd', 'LConn1'} };
info = snp_xml_edit('test/models/ToyPhys.slx', 'test/scratch/edited.slx', ops);
```

## 验证

- `test/scripts/verify_special_blocks.m`：特性测试，含物理网络（2 网络 5 端点重建后一致）。
- `test/scripts/verify_phys_coverage.m` / `verify_xml_phys_line.m`：物理覆盖与 XML 物理连线验证。

## 已知边界

- **覆盖范围**：电阻 / 参考地类的**纯物理网络**已验证；电容 / 电感 /受控源等未逐一验证。遇到这类网络先跑 `verify_rebuild_all` 确认 diff=0。
- **RTP 哈希名**：重建后功能级校验和可能因 `RTP_XXXXXXXX` 哈希块名变化而不等，但这不代表功能丢失。判读时排除 `RTP_*` 块，或改用非 RTP 项逐项比对。
- **snp_patch 改物理线**：`snp_patch` 的 `line` 动词只处理**普通信号线**的走线点（Points），物理连接不走这条路——改物理网络拓扑用 XML 线。

## 为什么物理连接难（背景）

物理网络在模型里不是"块树"，是端口间的连接图：T 型网络里分支线只有一端落在端口上，按 `find_system(Type='line')` 枚举会丢端口（实测 3 端口网络只看到 1 条完整边）。所以导出器用 `snp_phys_connections` 按`PortConnectivity` 收集网络，而不是枚举线。这也是为什么物理连接的导出逻辑单独成一个模块。
