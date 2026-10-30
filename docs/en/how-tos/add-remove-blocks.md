# How-to: Add and Remove Blocks

Task: add a block to a model / remove a block from a model. The M route and the XML route take different forms, and you also need to know about the container-row fallback on pull.

## The M route: verb form via `snp_patch`

**Adding a block** (inserted before the `lines` section; only the top level `Parent='m'` is currently supported):

```matlab
snp_patch('test/snapshots/snapshot_MyModel.m', 'add_block', ...
  'Name', 'NewConst', ...
  'Source', 'simulink/Sources/Constant', ...
  'Position', [100 100 130 130], ...
  'Value', '42');
```

`Source` is a **library path** — `add_block` needs it. Look up ordinary blocks in the [snp_block_source table](../reference/block-coverage.md); a block type missing from the table will stop you — in that case, switch to the XML route (below).

**Removing a block**:

```matlab
snp_patch('test/snapshots/snapshot_MyModel.m', 'remove_block', 'NewConst');
```

**Known limitations**:
- `remove_block` also cleans up the lines in the `lines` section that point to the removed block (matched by last-segment block name plus parent path, so blocks sharing a name prefix are not removed by mistake) — no manual `remove_line` cleanup is needed.
- MATLAB Function blocks **refuse to be removed** (their chart script section would be left dangling).
- Adding a block inside a subsystem: do it in the GUI or on the XML route, or expand the position first and then patch.

**Batch** (table-driven):

```matlab
ops(1) = struct('op', 'g1', 'args', {{'Gain', '5'}});
ops(2) = struct('op', 'add_block', 'args', ...
  {{'Name','C1','Source','simulink/Sources/Constant','Position',[100 100 130 130]}});
snp_patch(file, 'batch', ops);
```

## The XML route: add/remove with `snp_xml_edit`

No block-type table dependency — **unknown block types can be added too**:

```matlab
ops = { ...
  {'add_block', '', 'Gain', 'G1', {{'Gain','2'}}}; ...   % parent path '' = top level
  {'remove_block', 'OldBlock'};
};
info = snp_xml_edit('test/models/ToyBasic.slx', 'test/scratch/edited.slx', ops);
```

To keep the M side in sync, use `snp_sync_m` (tier 2):

```matlab
info = snp_sync_m('test/models/MyModel.slx', 'test/snapshots/snapshot_MyModel.m', ops);
```

`snp_sync_m` internally converts each add_block's block type to a library path through `snp_block_source` — **a block type missing from the table errors out**, and in that case you either add an entry to the table or stay on tier 1 only (the output is a `.slx`).

## Verification: loading successfully is not the same as being written correctly

Newly added blocks must be verified by "load, then read back BlockType/parameters, then simulate" — looking only at "loaded successfully" is not enough (a lesson that has come up repeatedly in this project: loading successfully does not mean the block was written correctly):

```matlab
open_system('test/scratch/edited.slx');
disp(get_param('MyModel/G1', 'BlockType'));   % expect Gain
% one-step comparison: edited file vs M-rebuilt file, functionally equivalent
rep = snp_collab_check('MyModel', 'Compare', 'MyModel');
disp(rep.funcEqual);
```

## How blocks added or removed by a person in the GUI pull back

A person creates a **bare subsystem** (not part of any library) in the GUI and places blocks inside it. On pull:

- the exporter has a **fallback** for SubSystems without a library source: it emits an `add_block('built-in/SubSystem', ...)` container row;
- the blocks inside the container are exported as independent blocks, as usual;
- pull brings the container row and the inner blocks back together, so the snapshot can rebuild.

This fallback exists for a reason: bare SubSystems without a library source used to be skipped, the pulled snapshot was missing the container row, and the rebuild then failed at `add_block('X/Sub/blk')` with a "parent container does not exist" error.

## Moving a block across subsystems

The M route has no "move" verb — the essence is "delete at the old position, add at the new one". The pull side works the same way: the old top-level row disappears, and the block at its new position inside the subsystem pulls back. After a person drags a block into a subsystem in the GUI, just pull.
