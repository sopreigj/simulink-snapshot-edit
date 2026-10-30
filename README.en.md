# simulink-snapshot-edit

> Turn Simulink models into **readable, editable, byte-for-byte verifiable code** — the model stays the single source of truth; small edits touch a few lines and leave everything else untouched.

[English](README.en.md) · 中文

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## What it is

A MATLAB/Simulink toolchain: export a `.slx` model to a **self-contained M snapshot** (a single `.m` function that fully rebuilds the model — every block, every parameter, positions, line routings), then make local edits by changing a few lines of the snapshot, **leaving all other blocks and relative positions byte-for-byte unchanged**.

It solves a concrete pain point: **build scripts that generate a model from scratch rebuild everything, and every hand-tuned layout (dragged positions, relative arrangement) is lost**. This inverts the workflow: **model → M**, and the next small edit means changing a few lines of M and re-running. Changes made by humans in the GUI flow back into the code (comments fully preserved).

Two audiences:
- **Engineers**: bring mature models into a text toolchain (git diff, code review, CI verification) — precise, auditable, reversible local edits
- **LLMs / agents**: get a readable representation of the model that can be edited and verified directly, instead of staring at a binary `.slx`

## Features

- **Model → M snapshot**: self-contained and rebuildable; block `Position`s, line `Points` polylines, 17 significant digits for doubles (exact round-trip)
- **Surgical edits**: `snp_patch` changes one block in the snapshot and nothing else; the XML in-place tier (tier ①) doesn't even require re-running the snapshot
- **Bidirectional**: humans edit the model → `snp_pull` flows the changes back into the code; `snp_merge3` handles concurrent human/agent three-way merges
- **Three-tier editing ladder**: XML in-place edit (fastest) → XML→M sync-back → edit the M snapshot directly (the portable, byte-verifiable ground truth)
- **Cross-version**: snapshots are plain M code; R2023b baseline, verified compatible with R2025a/R2026a
- **Ships with a verification suite**: rebuild fidelity, artifact freshness, behavioral equivalence, cross-version — 10 suites all green

## Prerequisites

- MATLAB **R2023b** baseline (R2025a/R2026a verified compatible); **Simulink** required
- The verification suites additionally need **Stateflow** and **Simscape** (the toy assets include a chart and a physical network)

## Installation

```bash
git clone <repo-url> simulink-snapshot-edit
cd simulink-snapshot-edit
```

No third-party dependencies, no build step. Configure machine-specific paths as needed:

```matlab
% Copy the example twin into a local config (gitignored, not committed)
copyfile('config_example.m', 'config_local.m');
% Edit MatlabBin / LibDir / OutDir etc. in config_local.m to your machine's values
cfg = snp_config();   % reads config_local.m first, falls back to config_example.m
```

> The repo carries no machine-specific configuration — clone and go.

## Quick start

**Run from the repository root** (`addpath('src')` and the `test/...` paths are relative to it):

```matlab
addpath('src');

% Entry A: model only → generate snapshot code
opts = struct(); opts.OutDir = 'test/snapshots'; opts.LibDir = 'test/lib/blocks';
opts.AliasMap = cell(0,2); opts.LibRel = '../lib/blocks'; opts.SaveRel = '../models';
load_system('test/models/ToyBasic.slx');      % load the model first (snp_export looks up loaded models by name)
snp_export('ToyBasic', opts);                 % → test/snapshots/snapshot_ToyBasic.m

% Entry B: code only → generate the model (run from the snapshot's directory)
cd test/snapshots; snapshot_ToyBasic(); cd ../..

% Entry C: both sides exist → bidirectional collaboration
%   agent edits code: change a few lines of the target block in the snapshot → re-run (everything else unchanged)
%   human edits model: change in the GUI, save → snp_pull writes the changes back into the code (comments preserved)
snp_pull('ToyBasic', 'test/snapshots/snapshot_ToyBasic.m', opts);

% Surgical edit API (one block in the snapshot, everything else byte-for-byte unchanged)
snp_patch('test/snapshots/snapshot_ToyBasic.m', 'g1', 'Gain', '5');
```

## Workflow

**Three-tier editing ladder** (pick by speed; the M snapshot is the ground truth across all three):

| Tier | How | Suits |
|---|---|---|
| ① XML in-place edit | Edit block parameters in the `.slx` package XML and repack (`snp_xml_edit`) | Fastest, highest fidelity; the artifact is not a "rebuildable M" |
| ② XML→M sync-back | XML changes parsed and written back into the M snapshot (`snp_sync_m`) | When M must stay in sync with the model |
| ③ Edit the M snapshot | Edit the M code directly | Byte-verifiable, cross-version portable |

**Bidirectional workflow** (code ↔ model; both directions "minimal change, everything else untouched"):

| Direction | Operation | Preservation guarantee |
|---|---|---|
| agent → model | Edit a few lines of the target block in the snapshot → `run(snapshot)` | All other blocks/positions/comments untouched (preserved by construction at the text layer) |
| human → code | Edit model in GUI (save) → `snp_pull(mdl, snapFile, opts)` | All existing code and its relative order preserved: block sections aligned by block name, the LLM's hand-written regions kept line by line; `snp_merge3` handles human/agent concurrency |

## Project layout

```
src/            the toolchain (13 snp_* functions; API list in docs/en/reference/tool-api.md)
test/           verification suites + toy assets
  models/         toy models: ToyBasic / ToyLibRef / ToyChart / ToyPhys
  lib/            toy library ToyLib.slx
  snapshots/      snapshot code (snapshot_<name>.m, 1 library + 4 models)
  scripts/        verification scripts (verify_*, demo_local_edit, test_roundtrip, ...)
  fixtures/       small test models
docs/           bilingual documentation (see below)
config_example.m example config twin (copy to config_local.m and fill in your machine's values)
```

## Documentation

Full documentation lives under `docs/` in two symmetric versions:

- [English docs](docs/en/README.md): tutorials / how-tos / reference / explanation
- [中文文档](docs/zh/README.md)：教程 / 操作指南 / 参考 / 解释

Recommended path: [Tutorial: model → snapshot](docs/en/tutorials/model-to-snapshot.md) → [Why the snapshot is the truth](docs/en/explanation/why-snapshot-is-truth.md) → [API reference](docs/en/reference/tool-api.md).

**Agents picking up this project**: start with the [usage skill](docs/en/skills/simulink-snapshot-editing/SKILL.md) (decision tree, verification trio, trap list), then the [modeling-conventions skill](docs/en/skills/simulink-modeling-conventions/SKILL.md) copy.

## Testing

```bash
# Use your MATLAB R2023b binary (the matlab on PATH may be a different release)
"<matlab-bin>" -batch "cd('<repo>\test\scripts'); verify_rebuild_all"
```

Main suites: `verify_rebuild_all` (rebuild fidelity 5/5), `verify_snapshots_fresh` (artifact freshness 5/5), `verify_snp_patch`, `verify_xml_structure/edit/sync` (XML tiers), `verify_behavior` (behavioral equivalence), `verify_cross_version`/`verify_multiver` (cross-version), `verify_collab` (human-agent collaboration).

Suite logs and temporary artifacts all land in `test/scratch/` (gitignored, not committed).

## Known limitations

- Variant subsystems keep only the currently active branch (variant switching cannot be expressed in text; a notice is printed on export)
- Agent comments cannot live inside the `.slx` package XML (Simulink refuses to load it); put them in the M snapshot's comment section or use canvas annotations
- Artifacts from the XML repack path are `.slx` files without cross-version portability — use the M snapshot path for cross-version scenarios

## License

MIT — see [LICENSE](LICENSE).

## Contributing

Issues and PRs welcome. Keep the verification suites under `test/scripts/` green; when touching documentation, update both `docs/zh/` and `docs/en/`.
