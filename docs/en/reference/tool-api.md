# Reference: Tool API

The signature, parameters, return values, and side effects of every function, **copied from the source code** and complete. To understand why things are designed this way, see [explanation/](../explanation/); to learn basic usage, see [tutorials/](../tutorials/).

General conventions:
- All functions are called after `addpath('src')`.
- Baseline version is R2023b; cross-version allowances are noted per function.
- Suite temporary artifacts go to `test/scratch/` (gitignored).

---

## snp_export — Model → Self-contained M Snapshot

```matlab
snp_export(mdl, opts)     % No return value
```

Exports a laid-out model as a self-contained M snapshot: running it once rebuilds the original model (all blocks / all parameters / Position / routing polylines / annotations / solver configuration / Model Workspace variables).

### opts Fields

| Field | Default | Description |
|---|---|---|
| `OutDir` | `pwd` | Snapshot output directory; artifact is `snapshot_<mdl>.m` |
| `LibDir` | `''` | Search directory for library `.slx` files (instance source resolution); empty means no library resolution |
| `AliasMap` | `cell(0,2)` | Instance name → library block name abbreviation table |
| `ExtraHeader` | `{}` | Extra lines prepended to the generated code header (e.g. `addpath(...)`) |
| `InlineMasks` | `false` | When `true`, masked subsystems are **expanded into plain subsystems**, exporting their internal structure |
| `LibRel` / `SaveRel` | `''` | Library directory / destination directory as a path **relative to the snapshot file's directory** (for portability) |
| `AllowUntestedVersion` | `false` | Allow non-baseline versions (or the environment variable `SNP_ALLOW_UNTESTED=1`) |

### Behavior and Side Effects

- **No return value**; results are written to files only.
- **Skips go to stderr**: when a block cannot be exported, `[snp_export skip] <block name> (BlockType=...)` is printed, and at the end `[snp_export WARNING] <model>: N blocks skipped — snapshot INCOMPLETE`. The pass criterion is no skip lines on stderr.
- Version assertion: non-R2023b versions assert immediately (unless allowed); when allowed, a warning is printed to stderr.
- The model must already be loaded (it is loaded automatically via `load_system` if not).

### Internal Mechanisms (Useful When Reading Snapshots)

- Instance source resolution has three tiers: `FP_*` fingerprint annotations inside subsystems → block name (trailing digits stripped) matched against `LibDir/*.slx` → alias table; plain built-in blocks go through the `snp_block_source` table.
- Blocks with a `ReferenceBlock` (rb) **prefer the rb**; the table entry is only a fallback when no rb exists.
- Numbers use 17 significant digits (exact round-trip for doubles); output is written to a temporary name and then `movefile`d into place.
- Standalone Stateflow charts: State/Transition are exported in structured form, `src='sflib/Chart'` (see [How-to: Stateflow](../how-tos/handle-stateflow.md)).
- Bare SubSystem with no library source: falls back to a `built-in/SubSystem` container line.
- Port blocks (Inport/Outport) write only the port number.

---

## snp_pull — Human GUI Changes → Merged Back into the Snapshot

```matlab
rep = snp_pull(mdl, snapFile, opts)
```

Merges changes in the current on-disk model minimally back into the snapshot: **LLM handwritten sections (section comments / block-header comments / auxiliary lines) are preserved line for line**, and statements are added, deleted, and modified aligned by block name.

- **Forces a reload from disk**: internally `close_system` + `bdclose` + `load_system` (prevents reading a stale in-memory model of the same name).
- First exports the current model to a temporary directory with `snp_export`, then performs a section-level merge with the old snapshot.

### Runtime Guard (T70)

Before the forced close-and-reload, two Simulink runtime states are checked:

| Condition | Behavior | id |
|---|---|---|
| `Dirty='on'` (the human has unsaved GUI changes) | **Blocks by default** (error): run `save_system(mdl)` first, or pass `opts.Force=true` to explicitly discard | error `snp:dirtyBlocked`, preceded by warning `snp:dirtyUnsaved` |
| `SimulationStatus~='stopped'` | Warning only (a forced close interrupts the simulation — stop it first) | warning `snp:simRunning` |

Why Dirty blocks while simulation only warns: a forced close-and-reload **irrecoverably discards** unsaved changes, while interrupting a simulation loses no model data — "destroys data" must be overridden by explicit intent, never by default.

The export side (`snp_export`) checks only simulation status; the propagation side (`snp_propagate`) issues the same warnings for the library and every model before `bdclose('all')`, and additionally blocks on Dirty across **all loaded block diagrams**.

### opts Fields

| Field | Default | Description |
|---|---|---|
| `LibDir` | `''` | Library directory passed to the internal snp_export |
| `AliasMap` | `cell(0,2)` | Alias table |
| `Force` | `false` | `true`=proceed even if the model carries unsaved GUI changes (explicitly discarding them) |

### rep Fields

| Field | Meaning |
|---|---|
| `nAdd` | Number of added blocks (appended to the snapshot with a `[new]` marker) |
| `nDel` | Number of deleted blocks (statements removed; comments kept and marked) |
| `nChg` | Number of changed blocks / lines |
| `nNoteKept` | Number of preserved comment lines |
| `detail` | Itemized diff list (cell; the first 10 entries are printed to the command line) |

For merge algorithm details (section alignment / block token streams / chart Script following its block), see [How-to: Pulling Human GUI Changes Back](../how-tos/merge-human-changes.md).

---

## snp_merge3 — Three-way Merge (Human and Agent Concurrently)

```matlab
rep = snp_merge3(baseFile, oursFile, theirsFile, outFile)
rep = snp_merge3(..., opts)     % opts.UseGit / opts.TheirsPriority
```

`base` = the common ancestor snapshot, `ours` = the agent-side derived snapshot, `theirs` = the human-side derived snapshot. The M snapshot is a strongly structured plain-text format (clear section boundaries, block lines have unique keys), so the merge does not use the line-level LCS of a generic diff3 — it does a **key-level merge** (aligned by section/block name, with orthogonal parameter-level auto-merging).

Covers the scenario `snp_pull` cannot: the human and the agent **concurrently** modifying the same model (pull is only a serial two-way flow). The merged result is written to `outFile`, and a diff report is returned.

### opts Fields

| Field | Default | Description |
|---|---|---|
| `UseGit` | `false` | Use the `git merge-file --diff3` fast path; **off by default** (see below) |
| `TheirsPriority` | `true` | Tie-break direction when both sides change the same key; `false` flips it to ours-priority |

### rep Fields

| Field | Meaning |
|---|---|
| `nMerged` | Number of auto-merged entries (no conflict) |
| `nConflict` | Number of conflicting entries |
| `nOursKept` / `nTheirsKept` | Number of ours / theirs changes kept |
| `conflictList` | Cell of conflicting keys (block names / line keys) |
| `strategy` | The path actually used (`'git'` / `'builtin'`) |
| `notes` | Explanatory lines |

### Tie-break Table

| Situation | Resolution |
|---|---|
| Both sides change the same key differently | Conflict → **theirs** (the model is the single source of truth; `TheirsPriority=false` flips it) |
| One side deletes a key, the other changes it | Conflict → **delete wins** (structural intent outranks parameter intent) |
| Both sides add the same key with different content | Conflict → theirs + a warning |
| Everything else (one-sided change / orthogonal) | Auto-merged |

### Known Limitations

- **Why UseGit defaults to false**: line-level diff3 has no block semantics — when each side changes one entry in adjacent blocks, they get merged into a spurious conflict region and the ours change is swallowed (confirmed with a minimal reproduction); the "delete wins over change" tie-break fails completely on the git path. The git path is for cross-validation only.
- Keys in `conflictList` are bare block names (e.g. `'G1'`, `'Sub1/SG'` — the internal subsystem slash is kept). Earlier versions carried a leading `/` (the internal path convention); it has since been uniformly stripped at the output boundary. **Keys for multi-block conflicts are joined with `'; '`** (e.g. `'G1; G2'` — deliberately not a slash, to avoid confusion with the subsystem path `'SubA/G1'`; consumers split on `'; '`).
- The function names of the three snapshots should match the model name (as is naturally the case for three derived snapshots of the same model); when function names differ, the header section detects multiple `function` declarations, **keeps only the first one, and reports a warning in notes** (keeping the merged file valid).

---

## snp_patch — Surgical Snapshot Editing

```matlab
snp_patch(file, block, 'Param1', value1, 'Param2', value2, ...)
snp_patch(file, 'line', src, dst, 'Parent', p, 'Points', [x y; ...])
snp_patch(file, 'add_block', 'Name', n, 'Source', src, 'Position', pos, ...)
snp_patch(file, 'remove_block', name)
snp_patch(file, 'batch', ops)
```

Touches only the target lines; the rest of the file stays byte-for-byte unchanged.

### Verbs

| Verb | Description |
|---|---|
| (block name, not a verb) | Change block parameters: existing parameters have their values replaced; new parameters are appended before the trailing `');'` on the line; `Position` is replaced in place |
| `'line'` | Change the routing points of an add_line: if a Points line exists it is replaced, otherwise try/set_param/catch lines are added |
| `'add_block'` | Add a block, inserted before the `% ---- lines ----` section marker; **top level only (`Parent='m'`)** |
| `'remove_block'` | Remove a block and clean up `add_line` entries in the lines section that reference it (same-name prefix blocks are not accidentally removed); **MATLAB Function blocks are rejected** (the chart script section would be left dangling) |
| `'add_line'` / `'remove_line'` | Add / remove a line |
| `'batch'` | Table-driven: `ops` is a struct array whose entries are `{op, args}` |

### Known Limitations

- **Boundaries on parameter value strings** (precisely characterized experimentally on 2026-10-29): **commas** break line parsing (`'2,5'` fails rebuilding with "invalid argument"); **quotes** must be escaped; **parentheses round-trip intact** (`'(3)'` reads back as `Gain=(3)`, evaluated as an expression). For values containing commas, edit the snapshot line by hand.
- A missing target, or multiple semantic conflicts → an error is raised and no file is written.

---

## snp_xml_edit — In-place XML Editing + Repacking (Tier 1)

```matlab
info = snp_xml_edit(srcSlx, dstSlx, ops, 'Verbose', true)
```

Edits the `.slx` package's internal `simulink/systems/system_*.xml` directly and repacks entries in their original order (Java ZipOutputStream; binary entries are copied verbatim).

### ops (One Operation per Element)

| Form | Description |
|---|---|
| `{block path, parameter name, new value}` | Shorthand, equivalent to set_param |
| `{'set_param', block path, parameter name, new value}` | Change a parameter |
| `{'add_block', parent path, block type, block name, parameter cell}` | Add a block; parameter cell = `{{'Gain','3.5'},...}`, may be empty |
| `{'remove_block', block path}` | Remove a block |
| `{'add_line', parent path, source block name, source port, destination block name, destination port}` | Connect a line |
| `{'remove_line', parent path, source block name, source port, destination block name, destination port}` | Remove a line |

- Parent path: `''` = model top level; `'Plant'` = the subsystem named Plant. Block paths follow the `get_param` convention (e.g. `'ToyLibRef/tm'`).
- Ports: plain signals use the port number (`'1'`); **Simscape physical ports use `'LConn1'` / `'RConn1'`**.

### info Fields

| Field | Description |
|---|---|
| `applied` | `{verb, target, description}` |
| `skipped` | `{verb, target, reason}` |
| `mops` | The M-side operations equivalent to this run (for tier 2 sync-back) |

### Boundaries

- **Only non-default parameters are ever changed (a storage fact, not a bug)**: Simulink writes only parameters that differ from their defaults when saving — if the target parameter is currently at its default, there is no corresponding `<P>` entry in the package XML, and set_param-style operations land in `info.skipped` (the reason is recorded). Workarounds: change it to any non-default value first, or take the M route (the snapshot always writes all parameters).
- **No comments can be left in the XML**: Simulink's system XML parser rejects `<!-- -->` (confirmed by a controlled experiment: through the same repacking flow, the package with an inserted XML comment fails `load_system` with "invalid document structure", while the control package without a comment loads normally). This is a parser limitation, not a standard XML constraint — **agent notes belong in the M snapshot's handwritten section / comment section, or as a canvas annotation (the `<Annotation>` element, which the exporter supports)**.
- **Geometry is untouched**: coordinates and routing are presentation attributes (D5).
- Depends on the Java bundled with MATLAB (`java.util.zip`): **unavailable when launched with `-nojvm`**.
- The artifact is a "modified .slx", not a "rebuildable M".

---

## snp_sync_m — XML→M Sync-back (Tier 2)

```matlab
info = snp_sync_m(srcSlx, mFile, ops, 'DstSlx', dstPath)
```

Flow: `snp_xml_edit` performs the edits on the XML (producing the edited file + `info.mops`) → the mops are applied to the M snapshot via `snp_patch` → the M and the .slx agree in both directions.

- Block type → library path conversion uses the shared table `snp_block_source`: **an unlisted block type raises an error** (`未收录进 snp_block_source，无法回灌 M 侧 add_block`).
- Name-value parameter `'DstSlx', <path>`: where the edited file is written (defaults to a temporary file).
- Returns `info` as in `snp_xml_edit`, plus `.dstSlx`.

---

## snp_block_source — Block Type → Library Path (Shared Table)

```matlab
src = snp_block_source(blockType)     % Returns char; returns '' if unlisted
```

- **Only `add_block` needs a library path**: the model file itself records only the BlockType, and Simulink resolves it at load time (verified experimentally: a new block written with only `BlockType="Gain"` and zero library path is recognized, its parameters read back, its connections valid, and simulation matches).
- For coverage criteria and what is deliberately not listed, see [Reference: Block Type Coverage](block-coverage.md).
- **Path newline convention**: library names containing a literal `char(10)` (e.g. `'Math⏎Operations'`) are stored as a literal `\n` in the table, and `strrep` restores the real `char(10)` before the function returns.
- Blocks with an rb prefer the rb at export time; the table entry is the fallback when no rb exists.

---

## snp_collab_check — Human/Agent Collaboration Guard (Measure Only, No Model Changes)

```matlab
rep = snp_collab_check('Model')                                % Single model: two checksums
rep = snp_collab_check('ModelA', 'Compare', 'ModelB')          % Two models: functional equivalence
rep = snp_collab_check('Model', 'BaselineFile', 'x.slx')       % Against an on-disk file: file-level
```

Two layers of official checksums with a **deliberate division of labor**:

| Layer | API | Changes When | Purpose |
|---|---|---|---|
| File level | `Simulink.getFileChecksum` (MD5) | Any file content change (including moving a block) | "Has a human touched this file" |
| Functional level | `Simulink.BlockDiagram.getChecksum` (128-bit) | Unchanged as long as functionality is unchanged (moving a block does not change it; changing a parameter does) | "Are two pipeline artifacts functionally equivalent" |

### rep Fields

| Field | Description |
|---|---|
| `fileChecksum` | File-level MD5 (char); empty when the model is not saved to disk |
| `funcChecksum` | Functional-level `[4x1 uint32]`; `[]` when unavailable |
| `funcEqual` | Compare mode, **tri-state**: `1`=equal / `0`=different / `-1`=undecidable |
| `fileEqual` | BaselineFile mode, **tri-state**: `1`=identical / `0`=different / `-1`=undecidable |
| `notes` | Explanations (the basis for each judgment) |

- **Tri-state semantics (T71)**: an unavailable checksum (model not saved / compilation failure / read error) is **undecidable `-1`, not "equal"** — the old `isequal([],[])` reported spurious "functionally equivalent" when both sides failed. Consumers must rule out `-1` before trusting the value; **undecidable must never count as a pass**.
- `BlockDiagram.getChecksum` **compiles the model** (official behavior), so it is slow inside `-batch`.
- When the model is not saved, `fileChecksum` is left empty (`get_param('FileName')` is unavailable).

---

## snp_view_nogeom — Geometry-stripped Reading View of the M Snapshot

```matlab
out = snp_view_nogeom(snapshotFile, 'OutFile', outFile)
```

Strips the geometry lines (`'Position'` / `'Points'` parameter pairs) from the M snapshot, for **reading the model**. An early large-scale verification measured geometry lines across 25 snapshots at **35.1%** of total lines (4364/12427, a historical measurement), and readability improves markedly once they are removed.

- **Produces a reading view only — it never replaces the M snapshot itself**: Position/Points in the M are required for byte-for-byte rebuildability, and rebuilding must use the original M.
- Criterion: whole lines are kept, only geometry parameter pairs are removed; the line count does not change and the structure stays intact.

---

## snp_propagate — Library Propagation Runner (Library Change → Referencing Models Pick Up the New Content Automatically)

```matlab
rep = snp_propagate('mylib', {'mA', 'mB'}, opts)
rep = snp_propagate('mylib', 'auto', opts)     % Referencing models discovered automatically
```

Mechanism: library instances inside referencing models are **linked** (`ReferenceBlock` / `LinkStatus='resolved'`), and the model snapshot records only the link `add_block('mylib/blk',…)` — not the library's internal parameters — so **after a library change, rebuilding with the untouched model snapshot makes the instances pick up the library's new content automatically at resolve time**. Automatic propagation is therefore just two steps:

1. **(Optional) Rebuild the library**: run the library snapshot M to generate the new `.slx`; skip if the library file already holds the new values.
2. **Rebuild each model**: run each referencing model's snapshot M (the text contains no library parameters, so the rebuild picks up the new content), then read back and verify.

The model snapshot itself stays **byte-for-byte unchanged** (`rep.snapHashBefore == After`) — propagation works through library-side resolution, so the snapshots need no synchronization.

### opts Fields

| Field | Default | Description |
|---|---|---|
| `WorkDir` | `pwd` | Directory holding the library / models / snapshots; **cds here before running** (snapshot artifacts land in the cwd at execution time) |
| `RebuildLib` | `true` | `true` = run the library snapshot to rebuild the library first; `false` = the library file already holds the new values, only rebuild the models (**the main usage**) |
| `LibSnap` | `WorkDir/snapshot_<lib>.m` | Library snapshot path |
| `ModelSnaps` | `{}` (each `WorkDir/snapshot_<m>.m`) | Per-model snapshot paths |
| `Check` | Empty struct array | Expected checks: each entry has fields `.model` / `.block` / `.param` / `.value` (string comparison) |
| `Force` | `false` | `true`=proceed even if any loaded model carries unsaved changes (explicitly discarding them) |

- **Dirty blocking across all loaded diagrams (T70)**: `bdclose('all')` force-closes **every** loaded block diagram, so the guard checks Dirty across all of them via `Simulink.allBlockDiagrams`; any unsaved model blocks by default with error `snp:dirtyBlocked` (names listed). `Force=true` overrides. If the guard's own enumeration fails it degrades to a warning (fail-open — the guard must not brick the toolchain, but it never silently proceeds either).
- **'auto' discovery order (T72)**: `WorkDir/snapshot_*.m` is scanned for the referencing list *before* the warning/guard loop — `'auto'` arrives as a char/string scalar, and brace-indexing it first would crash immediately.

The `models` argument accepts a cell (list of model names) or `'auto'`: the latter scans `WorkDir` for all `snapshot_*.m` containing `add_block('<libModel>/…', …)` to discover referencing models automatically.

### rep Fields

| Field | Meaning |
|---|---|
| `libRebuilt` | Whether the library was rebuilt (`RebuildLib` set and succeeded) |
| `libFile` | Path of the library artifact |
| `nModels` / `nPropagated` / `nFailed` | Number of models / propagation successes / failures |
| `models` | Per-model struct: `.name` / `.rebuilt` / `.err` / `.snapHashBefore` / `.snapHashAfter` (MD5; should be equal before and after propagation) / `.checks` (per entry `.ok` / `.got`) |
| `notes` | Explanations |

### Known Limitations

- **Library linking happens only on SubSystem library blocks**: `add_block` of an ordinary leaf library block (e.g. Gain) always produces an **inline copy** (empty `rb`), and changing a leaf library block does **not** propagate to models that copied it; only instances of SubSystem library blocks are linked.
- **`RebuildLib=true` requires the library snapshot to be rebuildable**: when the library contains an **ordinary SubSystem with internal lines**, the container path for internal lines is now emitted correctly (`[m '/blk']`, see CHANGELOG for the fix) and rebuilding passes; library snapshots exported by very old versions that still use the old-style `add_line(m,...)` for internal lines must be re-exported once with the current version.
- Before rebuilding, `close_system(lib)` unlocks the library (libraries are locked by default); after rebuilding, `open_system` the artifact file before `get_param` (the rebuild script closes the model).

---

## snp_config — Read the Local Machine Configuration

```matlab
cfg = snp_config()
```

Centrally reads all values that **vary by machine or environment**. It prefers `config_local.m` (repository root, ignored by `.gitignore` and never committed), falling back to `config_example.m` when absent (the example twin, committed, with placeholder values). On a freshly cloned machine, follow the header comment in `config_example.m` to copy it and fill in your own machine's values.

### cfg Fields

| Field | Example Value | Description |
|---|---|---|
| `MatlabBin` | `'<matlab-bin>'` | MATLAB executable path; used by externally scheduled verify scripts and cross-version testing |
| `TargetRelease` | `'R2023b'` | Version assertion baseline |
| `LibDir` | `fullfile('lib','blocks')` | Custom library directory (relative to the repository root) |
| `ModelsDir` | `'models'` | Demo model directory |
| `SnapDir` | `'snapshots'` | Snapshot directory |
| `AliasMap` | `cell(0,2)` | Block name → library name aliases (empty by default) |
| `ExtraHeader` | `{}` | Lines injected into the snapshot header (empty by default) |
| `OutDir` | `fullfile('test','scratch')` | Default output directory |

Fields defined in `config_local.m` that are not listed above are **passed through verbatim** (allowing per-machine extensions). Script usage (the example scripts read environment values this way):

```matlab
c = snp_config();
o = struct(); o.LibDir = c.LibDir; o.OutDir = c.OutDir;
```
