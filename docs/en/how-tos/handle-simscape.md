# How-to: Simscape Physical Connections

Task: the model contains a Simscape physical network (resistors, inductors, port blocks) and you need to export / edit / rebuild it. Physical connections are handled differently from ordinary signal lines, and there are more pitfalls to watch for.

## Export conventions (already done inside snp_export — you only need to know them)

- **Physical ports are exported by name**: `LConn1` / `RConn1`, never by port number. Reason: physical ports have no "port number" semantics — `get_param(port, 'PortNumber')` always returns 1 for them, and passing `<block>/1` to `add_line` fails with an "invalid Simulink object name" error.
- **The network is restored by connected component**: one physical network (formed by merging pairwise connections) is written into the snapshot as a **star-shaped spanning tree** (n endpoints, n−1 edges), and Simscape itself merges it back into one network. Reason: `PortConnectivity` reports a complete graph (3 ports → 3 pairwise edges), and issuing one `add_line` per edge fails on the third port with "second port already connected to a signal line".
- **PMIOPort and other physical port blocks** go through `built-in/PMIOPort` (via the `snp_block_source` table) — do not search the Simscape library by name for 'Physical'; that is the PS signal library, not physical ports.

## Editing physical lines on the XML route

`snp_xml_edit`'s `add_line` / `remove_line` support physical ports: pass the port arguments as `'LConn1'` / `'RConn1'` (written in the XML as `#lconn:N` / `#rconn:N`, with `<Line LineType="Connection">` and no fan-out):

```matlab
ops = { {'add_line', '', 'R1', 'RConn1', 'gnd', 'LConn1'} };
info = snp_xml_edit('test/models/ToyPhys.slx', 'test/scratch/edited.slx', ops);
```

## Verification

- `test/scripts/verify_special_blocks.m`: feature tests covering physical networks (2 networks, 5 endpoints — identical after rebuild).
- `test/scripts/verify_phys_coverage.m` / `verify_xml_phys_line.m`: physical coverage and XML physical-line verification.

## Known boundaries

- **Coverage**: pure physical networks of resistors and ground-reference blocks are verified; capacitors, inductors, and controlled sources have not been verified one by one. When you meet such a network, run `verify_rebuild_all` first and confirm diff=0.
- **RTP hash names**: after a rebuild, the function-level checksum may differ because the `RTP_XXXXXXXX` hash block names change, but that does not mean functionality was lost. When interpreting the report, exclude the `RTP_*` blocks, or compare the non-RTP items one by one instead.
- **Editing physical lines with snp_patch**: `snp_patch`'s `line` verb only handles the routing points (Points) of **ordinary signal lines** — physical connections do not go through it; use the XML route to change physical network topology.

## Why physical connections are hard (background)

A physical network in a model is not a "block tree" — it is a connection graph between ports: in a T-shaped network a branch line has only one end on a port, and enumerating with `find_system(Type='line')` drops ports (in testing, a 3-port network showed only one complete edge). This is why the exporter collects networks from `PortConnectivity` with `snp_phys_connections` instead of enumerating lines, and also why the export logic for physical connections is its own module.
