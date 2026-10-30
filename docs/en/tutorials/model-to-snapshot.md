# Tutorial: Turn a model into an editable snapshot

Walk through the full loop: **export a snapshot → run the snapshot to rebuild the model → verify the rebuild is identical → change one line and see**.
Everything uses the repo's own assets, and every command is copy-paste ready.
Assumes you are at the repo root and MATLAB is R2023b (the baseline release).

## What you will learn

- What the self-contained snapshot `.m` function is, and why it can rebuild a model byte-for-byte
- How to export, how to rebuild, and how to verify
- How to change only the few lines of one block in the snapshot without touching anything else

---

## Step 1: Export a snapshot

Practice on the repo's example model `test/models/ToyBasic.slx` — a plain block model: constant `c1` → gain `g1` (Gain=2) → scope `sc1`.
It is a pure model with no library instances, so it is the simplest case:

```matlab
addpath('src');
load_system('test/models/ToyBasic.slx');   % snp_export loads from memory: load with the full path first
opts = struct();
opts.OutDir  = 'test/snapshots';      % snapshot output directory
opts.AliasMap = cell(0, 2);          % explicitly empty when there are no aliases
opts.SaveRel = '../models';          % on rebuild: ToyBasic is a model, save it back to models/
snp_export('ToyBasic', opts);
```

Output: `test/snapshots/snapshot_ToyBasic.m`.

> Call `load_system` with the **full path** (relative to the repo root) — `snp_export` looks up already-loaded models by bare name only and never searches the path for you.
> Run `close_system('ToyBasic')` afterwards to free memory.

> `SaveRel` is a path **relative to the directory that holds the snapshot file** — the snapshot still lands in the right place when you run it on another machine, and it contains no machine-local absolute path.
> When exporting a library module, `SaveRel` points at `../lib/blocks`; if the model contains linked library instances (like this repo's `ToyLibRef`, which references four blocks of the `ToyLib` library), you must also supply `LibDir` (the library search directory for resolving instance sources) and `LibRel` (the relative path used to find the library at rebuild time), and the snapshot header then auto-generates a `load_system` that loads the library first.

`snp_export` **returns no value** — it writes files directly.
To check whether any blocks were skipped, watch **stderr**: a `[snp_export skip] <block name>` line or `snapshot INCOMPLETE` means something was not exported (reasons in [Reference: Block type coverage](../reference/block-coverage.md)).

> The snapshot is a plain-text MATLAB function. Open it and look: section comments (`%% ---- blocks ----`), one `add_block(...'Position',...)` line per block, and `add_line(...'Points',...)`.
> The geometry lines are deliberate — the rebuild needs them (see [Explanation: Why the snapshot is the truth](../explanation/why-snapshot-is-truth.md)).

## Step 2: Run the snapshot to rebuild the model

The snapshot is **self-contained** — it calls `new_system` itself, builds every block, wires every line, and saves.
Run it **from the directory that holds the snapshot** (the snapshot uses relative paths internally to locate its output directory):

```matlab
cd test/snapshots;
snapshot_ToyBasic();
cd ../..;
```

Output: `test/models/ToyBasic.slx` is rebuilt (`SaveRel` points there) — which is why it is called a "snapshot": rerun it and the model is restored.
The rebuild script closes the model when it finishes.

> Without `SaveRel`, the rebuilt `.slx` lands in the **directory that holds the snapshot** (`test/snapshots/ToyBasic.slx`).
> To overwrite the original asset you must set `SaveRel` explicitly.

## Step 3: Verify the rebuild is identical

The project's primary criterion is **text-level**: export the rebuilt result once more and compare the two snapshot texts byte-for-byte (`verify_rebuild_all` does this for all 5 repo assets: 1 library + 4 models):

```matlab
cd test/scripts;
verify_rebuild_all;     % full structural rebuild verification (REBUILD 5/5)
verify_snapshots_fresh; % repo snapshots vs fresh exports (FRESH 5/5)
```

For a single model you can also use the **functional-level** checksum from `snp_collab_check` as a "nothing broke" check (it only measures; it never modifies the model):

```matlab
open_system('test/models/ToyBasic.slx');
rep = snp_collab_check('ToyBasic', 'Compare', 'ToyBasic');
disp(rep.funcEqual);   % true = the two models are functionally equivalent
```

> Note: `BlockDiagram.getChecksum` can return empty for **library modules** (like `ToyLib`) because compilation does not apply; the text-level criterion is the safer check for libraries.

Logs land in `<repo>/test/scratch/` (gitignored, so they never pollute the repo).

## Step 4: Change only the lines of one block

Now feel what "a surgical edit changes nothing else" means.
Change the value of the `g1` gain block from 2 to 5:

```matlab
snp_patch('test/snapshots/snapshot_ToyBasic.m', 'g1', 'Gain', '5');
```

`snp_patch` replaces only the `Gain` parameter on the `g1` line of the snapshot; **every other character in the file stays byte-for-byte unchanged**.
Run the snapshot once more, and the rebuilt model differs in the gain alone:

```matlab
cd test/snapshots; snapshot_ToyBasic(); cd ../..;
open_system('test/models/ToyBasic.slx');
disp(get_param('ToyBasic/g1', 'Gain'));   % 5
```

> This step overwrites the repo's `test/models/ToyBasic.slx`.
> To restore it after practicing, run `git checkout -- test/models/ToyBasic.slx` (same for the snapshot file).

(On your own models, swap in the target block name and parameters — for example, change a mask parameter of a linked library instance with `snp_patch(f, 'tm', 'Kp', '7')`, or a saturation block with `snp_patch(f, 'tl', 'UpperLimit', '2')`.
Note that a `snp_patch` parameter value **containing a comma breaks the line parse** (quotes would need escaping; parentheses round-trip fine in practice), so for comma-containing values, edit the snapshot line by hand.)

For the full workflow and the parameter details of every API, see the [How-tos](../how-tos/) and [Reference: Tool API](../reference/tool-api.md).

---

## Recap

- **The model is the single source of truth**: the snapshot is exported from the model, and rerunning the snapshot restores the model.
- **Surgical edits**: edit the few lines of the target block in the snapshot and everything else — other blocks, positions, routing, comments — is preserved byte-for-byte; that is where the minimal diff comes from.
- **Both directions share one text**: the agent edits the snapshot code, the human edits the GUI model, and the pull-back loop is described in [How-to: Pulling human GUI changes back](../how-tos/merge-human-changes.md).

Next: read the [How-tos](../how-tos/) for specific tasks, or the [Explanations](../explanation/) to understand the design trade-offs.
