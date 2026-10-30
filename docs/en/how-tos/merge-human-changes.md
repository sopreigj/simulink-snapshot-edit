# How-To: Pulling human GUI changes back into the snapshot

The task: someone edited the model in the Simulink GUI (moved blocks, changed parameters, added and deleted blocks) and saved it; now you need to merge those changes back into the M snapshot **without losing the comments and code structure the agent wrote earlier**.

## One command

```matlab
addpath('src');
opts = struct();
opts.LibDir = 'test/lib/blocks';
opts.AliasMap = cell(0, 2);
rep = snp_pull('MyModel', 'test/snapshots/snapshot_MyModel.m', opts);
```

`snp_pull` first **forces a reload of the model from disk** (MATLAB may still hold a same-named model in memory, and without a reload you would read stale content — the premise of a pull is that "the model on disk is the one the human just edited"), then merges the changes into the snapshot and returns a diff report:

| `rep` field | Meaning |
|---|---|
| `nAdd` | Blocks added in the model (the snapshot appends a `[new]` marker) |
| `nDel` | Blocks deleted in the model (statement removed, **comment kept and marked**) |
| `nChg` | Changed blocks / lines |
| `nNoteKept` | Number of comment lines kept |
| `detail` | Item-by-item diff list (first 10 entries printed to the command line) |

## Why the comments survive (how the algorithm works)

The merger aligns by **section** (the snapshot's section comments like `%% ---- blocks ----` are natural boundaries):

- Section headers and hand-written content (non-statement lines) are **always kept from the old snapshot**.
- The blocks section aligns by **block name**: if the model still has the block, the statement is replaced with the new one (comments untouched); if the model no longer has it, the statement is removed, the comment kept and marked; if the model added it, it is appended to the end of the blocks section and marked `[new]`.
- A chart's Script lines (`rtc.…`) travel with the block they belong to.
- All other sections (lines / annotations / config / ws): if the text is identical, the old text is kept (including comments); otherwise the new text replaces it and the change is reported.

In one sentence: **the agent's hand-written regions (section comments, comments above blocks, auxiliary lines) are preserved line by line; only statements are added, removed, or changed, aligned by block name**.

## Simulink runtime behavior you must know before pulling

The following four points are the premises a pull relies on (MathWorks official docs + verified in this project):

1. **GUI edits are not saved automatically** — changes exist only in MATLAB memory; the asterisk in the title bar (the dirty flag) marks unsaved state. You must press Ctrl+S or call `save_system`. So the agreed workflow is: **human finishes editing → stops the simulation → saves → then pulls**.
2. **You cannot change the model structure while a simulation runs** — the docs state explicitly "During simulation, you cannot make changes to the structure of the model". Parameter changes take effect after stopping, and you usually need to re-run (fast restart mode avoids recompiling).
3. **Simulink windows do not watch the file on disk** — a new .slx rebuilt by the agent does not appear in an already-open window; the window shows the model as it lives in MATLAB memory.
4. **To see the new file contents: `bdclose` + `open_system`, without restarting MATLAB** — closing the window is not enough (the model is still in memory), and closing all of MATLAB is too heavy (you lose your workspace variables). This is exactly what the pull does internally (forcing `close_system` + `bdclose` + `load_system` to reload from disk).

Sources: [Saving a Model](https://in.mathworks.com/help/simulink/ug/saving-a-model.html), [Controlling Execution of a Simulation](https://es.mathworks.com/help/simulink/ug/controlling-execution-of-a-simulation.html), [Fast Restart](https://au.mathworks.com/help/simulink/ug/fast-restart-workflow.html); for the memory/file divergence and the `bdclose` reload pattern see the earlier section "The model in memory vs the file on disk".

The tools proactively warn about two of the above (without blocking execution; `warning('off','snp:dirtyUnsaved')` silences them): `snp_pull` / `snp_propagate` check `Dirty='on'` and `SimulationStatus` before force-closing an unsaved model and emit `snp:dirtyUnsaved` / `snp:simRunning` respectively when hit; `snp_export` checks only the simulation status.

## Before pulling, check "who touched the file"

Before pulling, you can use `snp_collab_check`'s file-level checksum to confirm that the human actually touched the file:

```matlab
rep = snp_collab_check('MyModel', 'BaselineFile', 'test/models/MyModel.slx');
disp(rep.fileEqual);   % false = file-level difference (edited or re-saved by a human)
```

The two checksums have deliberately separate jobs: the **file-level** one (`Simulink.getFileChecksum`, MD5) answers "who touched it" (it changes even when a block is merely moved); the **functional-level** one (`BlockDiagram.getChecksum`, 128-bit) answers "was anything broken" (unchanged by moving a block, changed by editing a parameter).

## After pulling, verify "nothing broke"

After the pull, re-run the snapshot and compare the functional-level checksum:

```matlab
cd test/snapshots; snapshot_MyModel(); cd ../..;
open_system('test/models/MyModel.slx');
rep = snp_collab_check('MyModel', 'Compare', 'MyModel');
disp(rep.funcEqual);   % expected true: the post-pull rebuilt snapshot is functionally equivalent to the edited model
```

## Verification scripts

- `test/scripts/test_roundtrip.m` covers the basic loop end to end: A1 the snapshot rebuild equals the model with diff=0; A2 a minimal edit with comment retention; B the three human operations (move / add / delete a block) with all comments kept after pull; C the post-pull snapshot rebuild equals the edited model with diff=0.
- `test/scripts/verify_collab.m` runs a scenario matrix (8 cases): C1-C3 consolidate the above, plus **C4 the dirty warning** (pull while the human has not saved → `snp:dirtyUnsaved`), **C5 the during-simulation warning** (SimulationStatus=running → `snp:simRunning`), and C6-C8 merge3 on orthogonal changes / same-block conflict (theirs wins) / delete-vs-edit (delete wins).

## Common pitfalls

- **A same-named model left on the PATH**: `snp_pull` already force-reloads with `close_system` + `bdclose` internally, so you do not need to handle this manually.
- **The human made several rounds of edits before pulling**: not a problem — a pull is a two-way merge of "current model vs old snapshot"; intermediate states never participate.
- **The human renamed a block**: the pull sees this as "delete old name + add new name" (the comment travels with the old block's lines, so you will see two entries in `detail`). Renames are not identity-tracked; that is a boundary of the current implementation.
- **Large structural changes** (deleting a whole subsystem, moving a block into a subsystem): these can be pulled — container lines are produced by the exporter's `built-in/SubSystem` fallback (see [How-To: Add and remove blocks](add-remove-blocks.md)).
