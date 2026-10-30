---
name: simulink-snapshot-editing
description: >-
  Edit/snapshot/merge Simulink models with the simulink-snapshot-edit toolchain:
  when handed a .slx for a local edit, follow the three-tier editing ladder
  (XML in-place edit → XML→M sync-back → edit the M snapshot directly), snapshot
  and pull back (snp_pull), two-way checksums (snp_collab_check), and the
  verification criteria for "did I edit it right". Covers "change this model's
  parameters/structure", "how do a human's GUI edits pull back", "cross-version
  rebuild verification". Does not teach modeling itself — modeling conventions
  live in simulink-modeling-conventions — nor geometric layout (the agent never
  writes geometry; auto-layout is empirically unusable).
metadata:
  priority: 5
  toolchain: "MATLAB/Simulink R2023b (verified on 2023b/2025a/2026a)"
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
      - "local edit"
      - "edit snapshot"
      - "snp_export"
      - "snp_patch"
      - "snp_pull"
      - "pull back"
      - "xml repack"
      - "human-agent collaboration"
      - "rebuild model"
      - "snapshot verification"
---

# Simulink Snapshot Editing

## Overview

This skill teaches an agent to edit Simulink models with the `simulink-snapshot-edit` toolchain (`src/snp_*.m`). Core contract: **the model (.slx) is the single source of truth, and the self-contained snapshot `.m` function is the fallback truth that rebuilds it.** A surgical edit touches only the target block; every other block stays byte-for-byte identical.

Tool overview (the `src/*.m` source is authoritative for interfaces):

| Function | Purpose | Tier |
|---|---|---|
| `snp_export` | model → self-contained M snapshot | entry point for every route |
| `snp_xml_edit` | edit the XML inside the .slx package and repack | ① fastest |
| `snp_sync_m` | XML edit → sync back into M (①+② bridge) | ② |
| `snp_patch` | edit a few lines of the M snapshot directly | ③ |
| `snp_view_nogeom` | geometry-stripped **read view** of M (no rebuild) | ③ read |
| `snp_pull` | human GUI edits → pull back into M (comments all kept) | human→agent |
| `snp_collab_check` | dual checksums: who touched it / did the edit break anything | guard |
| `snp_block_source` | shared BlockType → library path table (200 cases) | M route depends on it |
| `snp_merge3` | human–agent **concurrent** three-way merge (key-level, not line-level diff3) | multi-user / multi-agent |
| `snp_propagate` | edit library → rebuild referencing models (snapshot unchanged) | library propagation |

For interface details (signatures/parameters/return fields/known limitations) see [docs/en/reference/tool-api.md](../../reference/tool-api.md).

## When to Use
- "Change block X's parameter to Y in this model" (parameter-level → tier ① or ③)
- "Add/remove a block or rewire the model" (structure-level → ① or ③, depending on whether cross-version is needed)
- "The human finished editing in the GUI; sync the changes into the code" (→ `snp_pull`)
- "A human and an agent edited the same model at the same time; how do I merge" (→ `snp_merge3`: base/ours/theirs snapshots; same block edited by both defaults to theirs; delete-vs-edit defaults to delete-wins)
- "I edited the library; what about the models referencing it" (→ `snp_propagate`: library instances are linked, rebuilding the referencing models picks up the new content; the snapshot needs no sync)
- "Did I edit it right?" (→ the verification trio: read-back + structural comparison + behavioral equivalence)
- "Are the artifacts of two versions / two routes equivalent" (→ `snp_collab_check`)

## Decision tree: which tier to take

```
Handed a .slx to make a local edit
├─ Only changing parameters (no blocks/lines added or removed)?
│   ├─ Need cross-version portability / byte-for-byte audit trail → ③ snp_patch the M (or export first, then edit)
│   └─ Just want the edited model itself, fastest → ① snp_xml_edit
├─ Adding/removing blocks or lines (structure-level)?
│   ├─ Block type already covered in snp_block_source (200 cases) → ① or ③ both work
│   ├─ Block type not covered / unknown → ① (XML needs no library path; only the M route's add_block does)
│   └─ Want M and .slx to agree both ways → ② snp_sync_m (tier ① plus a bridge that auto-syncs the M)
├─ The human edited the GUI → snp_pull to pull back
└─ Need to decide "who touched it / did the edit break anything" → snp_collab_check
```

Two iron rules:
1. **Library paths are API-side knowledge** — only `add_block` (the M route) needs them; XML in-place editing needs no block-type whitelist (D6). The M route's `add_block` looks the path up in `snp_block_source`.
2. **The agent never writes geometry** — block positions and line routing are presentation attributes (D5). The XML path strips geometry; the M snapshot deliberately keeps `Position`/`Points` (required for byte-for-byte rebuildability), and when reading a model use `snp_view_nogeom` to produce the coordinate-free view.

## ① XML in-place edit (snp_xml_edit)
```matlab
addpath('src');
ops = { {'set_param', 'ToyLibRef/tm', 'Kp', '7'}, ...
        {'add_block', '', 'Gain', 'G1', {{'Gain','2'}}}, ...
        {'add_line',  '', 'g1', 1, 'G1', 1}, ...
        {'remove_block', 'OldBlock'} };
info = snp_xml_edit('m.slx', 'm_edited.slx', ops, 'Verbose', true);
```
- Source/destination ports: plain signals use the port number `'1'`; Simscape physical ports use `'LConn1'`/`'RConn1'`
- Block paths use in-model paths (same convention as `get_param`); parent path `''` = model top level
- Non-whitelisted parameters, Stateflow, and Simscape physical connections are **preserved as-is**; layout is never touched
- Returns `info.applied/skipped`; if `skipped` is non-empty, read the reasons — never silently let them pass
- **Only non-default parameter values are editable (a storage fact, not a bug)**: Simulink writes only parameters that differ from their defaults, so default-valued parameters have no entry in the XML → set_param-style ops land in `skipped`. Set some non-default value first, then edit — or take the M route (the snapshot writes every parameter)
- **No comments can live in the XML**: Simulink's system XML parser rejects `<!-- -->` (a controlled experiment confirmed that a package with inserted comments fails to load). Agent notes go in the M snapshot's hand-written section/comments block, or use canvas annotations (`<Annotation>`, which the exporter supports)
- Depends on the Java shipped with MATLAB (unavailable under `-nojvm` startup)

## ② XML→M sync-back (snp_sync_m)
```matlab
info = snp_sync_m('m.slx', 'test/snapshots/snapshot_m.m', ops);
% Equivalent to: snp_xml_edit producing the edited file + applying info.mops to the M
```
- Keeps M and .slx in agreement both ways, with no hand comparison; the M remains the fallback truth
- The M-side `add_block` needs the block type covered in `snp_block_source` — an uncovered type raises an error (either extend the table first, or stay on ①)

## ③ Edit the M snapshot directly (snp_patch)
```matlab
snp_patch(f, 'SpeedPI', 'Ilim', '30');                 % parameter
snp_patch(f, 'add_block', 'Name','NewConst', ...
          'Source','simulink/Sources/Constant', ...
          'Position',[100 100 130 130], 'Value','42');
snp_patch(f, 'remove_block', 'NewConst');
```
- Touches only the target lines; the rest of the file stays byte-for-byte identical — this is the "surgical edit" promise
- **Character-class boundaries (measured precisely)**: commas break line parsing (quotes must be escaped; parentheses round-trip intact, e.g. `'(3)'` reads back as `Gain=(3)`) — for values containing commas, hand-edit the snapshot line instead of forcing a patch
- `remove_block` cleans up the `add_line` entries in the lines section that point at the removed block (matched by final-segment block name + parent path, so same-prefix blocks are not wrongly deleted); MATLAB Function blocks refuse deletion (that would leave the chart script section dangling)

## Correct snapshot posture (snp_export)

```matlab
o = struct(); o.OutDir = tempname; mkdir(o.OutDir);   % ← a temp directory!
o.LibDir = 'test/lib/blocks'; o.AliasMap = cell(0,2);
snp_export('MyModel', o);
```

Three measured disciplines:
1. **Use `tempname` for OutDir** — the InlineMasks=false route writes the rebuilt .slx into the directory holding the snapshot; a temp path never clobbers assets under `test/models/`, `test/lib/blocks/`, and the like
2. **InlineMasks semantics**: `true` → masked subsystems are expanded into plain subsystems and their internals exported (the default main route); `false` → masked copies are kept (use this to verify mask parameter-level fidelity; requires the referenced libraries to be loadable)
3. **Read back after rebuild**: the snapshot script closes the model when it finishes (`bdIsLoaded` is always 0) — the correct check is `open_system(the artifact)` and then reading block counts/parameters; never read "empty" as a failure

## Pulling back human GUI edits (snp_pull)

```matlab
rep = snp_pull('MyModel', 'test/snapshots/snapshot_MyModel.m', opts);
% rep.nAdd/nDel/nChg/nNoteKept — comments (section headers / above-block) are all preserved
```

- Algorithm: align by section, then by block name; comments travel with the block, statements are replaced with new ones
- **Container fallback**: a bare subsystem the human created (no library link) is emitted as an `add_block('built-in/SubSystem', ...)` container line — the snapshot still rebuilds after the pull
- Read the change report in `rep.detail`: entries like `section kept (new model has no such section)` mean the human deleted a whole section; confirm whether that was intended
- Library edits propagate automatically: the model snapshot records only the link `add_block('lib/blk',…)`, so after a library change, rebuilding with the untouched model snapshot brings the new library content into the instances

## Verification: what "edited it right" means

**"It loads" does not prove the edit is right** (an iron rule of this project). After every edit, in order:
1. **Read back**: `open_system` the artifact → read back `get_param(block,'BlockType')` and every target parameter; for blocks newly created with `add_block`, also read back `LineHandles`/`PortConnectivity`
2. **Structural comparison**: compare block counts and block-type sets against the original model (the `verify_rebuild_all` convention: REBUILD IDENTICAL); when functional-level checksums match, remember to exclude `RTP_XXXXXXXX` hash block-name changes (an RTP change is not a functional loss)
3. **Behavioral equivalence**: simulate the original and the edited model and compare signal-by-signal `max|diff|` (expected 0; the `verify_behavior` convention). If the original model itself fails to simulate, the verdict is "undecidable", not "rebuild failed"

## Two-way checksums (snp_collab_check)

```matlab
rep = snp_collab_check('M');                              % both checksums
rep = snp_collab_check('EditSlx', 'Compare', 'RebuiltM'); % two-route functional equivalence
rep = snp_collab_check('M', 'BaselineFile', 'm.slx');     % did a human touch the file
```
- **File-level** `Simulink.getFileChecksum` (MD5): changes whenever the file content changes — answers "who touched it" (moving a block changes it too)
- **Functional-level** `BlockDiagram.getChecksum` (128-bit): unchanged as long as the function is unchanged — answers "did the edit break anything" (moving a block does not change it; changing a parameter does)
- When to run: before a merge/pull-back, when judging whether two-route artifacts (XML-edited file vs M-rebuilt file) agree, and when deciding whether a pull is needed
- It only measures and never modifies the model; the functional level compiles the model, so being slow under `-batch` is official behavior

## Common traps (condensed; full list in references/traps.md)

| Symptom | Root cause | Remedy |
|---|---|---|
| `add_block` reports "no such block" | hand-writing a "one-line" library name | use the raw path returned by `find_system` (it may contain a real newline char(10)) |
| MATLAB string concatenation parses wrong | joining strings with `+` | use `sprintf` or split the calls across lines |
| The newline never gets written | single-quoted `'\n'` is a literal two characters | `sprintf('\n')` for a real newline |
| FaultInport/StateControl bare add_block fails | structural port blocks attach to their parent system | they are generated along with the parent block (e.g. the Fault Subsystem); never create them standalone |
| `bdIsLoaded` = 0 after a rebuild | the snapshot script closed the model when it finished | `open_system(the artifact)` and then read back |
| Library instance resolve fails | a product went offline in a newer version (e.g. powersys in R2026a) | an external fact, not the toolchain's responsibility; the example assets are unaffected |

## Bundled Tooling
- `test/scripts/`: `export_all_snapshots`, `verify_rebuild_all`, `verify_behavior`, `verify_special_blocks`, `test_roundtrip`, `verify_multiver` (three versions), `verify_snapshots_fresh`
- `test/scratch/`: the agreed home for all verification/diagnostic output (`dbg_*.txt` etc., gitignored)
- Complements the modeling-conventions skill: for **building** models, see `simulink-modeling-conventions`

## Additional Resources
- `references/traps.md`: the trap-by-trap list (with criteria and avoidance code)
- `README.md`: three starting points (model only / code only / both) on one chain
- Criteria and design decisions: `docs/` (three-tier editing ladder, D5 geometry, D6 library-path ownership)
