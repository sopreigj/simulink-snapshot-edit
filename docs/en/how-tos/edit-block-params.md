# How-to: Edit Block Parameters — Which Tier to Choose

Task: change some block parameters of an existing model. You have heard of the "three-tier editing ladder" but are not sure which tier to pick. This guide only helps you **choose**; for the full API of each tier, see [Reference: Tool API](../reference/tool-api.md).

## The three-tier editing ladder at a glance

| Tier | Tool | Output | When to choose it |
|---|---|---|---|
| Tier 1: XML in-place edit | `snp_xml_edit` | modified `.slx` | **Default first choice**: fastest, highest fidelity, needs no block-type table |
| Tier 2: XML→M sync-back | `snp_sync_m` | `.slx` + synced M | You ran tier 1 and also want the M side to agree |
| Tier 3: edit the M snapshot directly | manual / `snp_patch` + `run` | rebuilt `.slx` | You need cross-version portability / byte-for-byte verifiability |

## Decision tree

```
Does your model have a snapshot (test/snapshots/snapshot_X.m)?
├─ No → export one first with snp_export (tutorial in tutorials/)
└─ Yes → does this change involve many unknown block types?
    ├─ Many (block types not listed in snp_block_source, Simscape, Stateflow) → tier 1
    │      (the XML route needs no block-type-to-library-path mapping; unknown block types still edit fine)
    └─ Few (parameter changes on ordinary blocks) → do you need cross-version portability or byte-for-byte verification?
        ├─ Yes → tier 3 (the M snapshot is the cross-version fallback truth)
        └─ No → tier 1 (fastest)
```

## Tier 1: XML in-place edit (default first choice)

Edit block parameters directly in `simulink/systems/system_*.xml` inside the `.slx` package, then repack the entries in their original order. **You never need to know the block type's library path**, and parameters on no whitelist, Stateflow, and Simscape physical connections are all preserved byte-for-byte:

```matlab
addpath('src');
ops = { {'ToyLibRef/tm', 'Kp', '7'} };     % shorthand = set_param
info = snp_xml_edit('test/models/ToyLibRef.slx', 'test/scratch/edited.slx', ops);
```

Returns `info.applied` / `info.skipped` (with reasons) / `.mops` (the equivalent M-side operations, needed for tier 2).

**Note**: the output is a "modified .slx", not a "rebuildable M". Cross-version portability and byte-for-byte freshness criteria must be backed by the M route (see [Why the snapshot is the truth](../explanation/why-snapshot-is-truth.md)).

**Storage fact (not a bug)**: Simulink writes only parameters that differ from their defaults when saving — if the target parameter currently holds its default value (e.g. `Gain=1` on a `Gain` block), there is no `<P Name="Gain">` in the in-package XML at all, and `snp_xml_edit`'s set_param will skip it (`info.skipped` states the reason). Workaround: change the parameter to any non-default value in the GUI or with set_param before taking the tier 1 route, or take the tier 3 M route directly (the M snapshot always writes the full parameter set).

## Tier 2: XML→M sync-back (tier 1 plus M agreement)

Tier 1's `info.mops` holds the equivalent M-side operations. `snp_sync_m` does it in one step: the XML edit plus applying the mops into the M snapshot — M and .slx agree in both directions, with no manual comparison:

```matlab
info = snp_sync_m('test/models/MyModel.slx', 'test/snapshots/snapshot_MyModel.m', ops);
```

The block-type-to-library-path conversion uses the shared table `snp_block_source` — **if a block type is missing from the table, the sync-back errors out** (`未收录进 snp_block_source，无法回灌 M 侧 add_block`, "not listed in snp_block_source, cannot pull back the M-side add_block"). In that case, fall back to tier 1, or add the entry to the table first (see [Reference: Block-Type Coverage](../reference/block-coverage.md)).

## Tier 3: edit the M snapshot directly

Edit the target block's few lines in the snapshot by hand (or with `snp_patch`), then `run` to rebuild:

```matlab
snp_patch('test/snapshots/snapshot_ToyBasic.m', 'g1', 'Gain', '5');
cd test/snapshots; snapshot_MyModel(); cd ../..
```

**Known limitations** (deliberately narrowed in the current implementation):
- Character-class boundaries for `snp_patch` parameter values (refined by testing on 2026-10-29):
  - **Commas** break line parsing (e.g. `'2,5'` fails rebuilding with "invalid argument") — genuinely broken; preprocess the value or take the XML route;
  - **Quotes** must be escaped inside the value;
  - **Parentheses were verified to round-trip completely** — written into the snapshot, rebuilt, and read back with effect (the value is evaluated as an expression when read back, e.g. `'(3)'` reads back as `Gain=(3)`). The earlier wording "parentheses also fail" was too strict; do not avoid them. When you hit a bad value (containing a comma), edit the corresponding snapshot line by hand instead of forcing patch.
- `snp_patch` block addition supports only the top level (`Parent='m'`); to add a block inside a subsystem, expand the position first and then patch.

The core reason to choose tier 3: the M snapshot is the **cross-version portable** fallback truth (a snapshot exported on R2023b rebuilds byte-for-byte identically on R2026a — verified by testing); a tier 1 `.slx` does not carry this property.

## Verify your change

Whichever tier you used, after the edit run `snp_collab_check`'s function-level checksum to confirm "nothing else broke":

```matlab
rep = snp_collab_check('MyModel', 'Compare', 'MyModel_edited');
disp(rep.funcEqual);   % true = functionally equivalent (a parameter change will flip it; this is where you confirm the magnitude of the change)
```

For the full equivalence criteria and the file-level checksums that answer "who touched the file", see the `snp_collab_check` entry in [Reference: Tool API](../reference/tool-api.md).
