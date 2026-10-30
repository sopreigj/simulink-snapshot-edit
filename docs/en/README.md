# docs — simulink-snapshot-edit documentation

[English](README.md) · [中文](../zh/README.md)

This answers the questions **beyond the README**: the README teaches you "how to get it running" ([back to README](../../README.md)); here you learn "how to maintain it, and why it is designed this way".

Organized along [Diátaxis](https://diataxis.fr/), **one document per reader need**:

| Type | You want to… | Go to |
|---|---|---|
| Tutorial | Follow along once to learn the basic loop | [tutorials/](tutorials/) |
| How-to | Accomplish a specific task (basics assumed) | [how-tos/](how-tos/) |
| Reference | Look up exact API/parameter/coverage lists | [reference/](reference/) |
| Explanation | Understand why it is designed this way, and the trade-offs | [explanation/](explanation/) |

## Quick lookup

- **First time here**: read [tutorials/model-to-snapshot.md](tutorials/model-to-snapshot.md) and follow "export → rebuild → verify" once.
- **Want to edit a model**: start with [how-tos/edit-block-params.md](how-tos/edit-block-params.md) (which of the three tiers to pick).
- **Someone edited in the GUI and you want it back in code**: [how-tos/merge-human-changes.md](how-tos/merge-human-changes.md).
- **Look up an API signature**: [reference/tool-api.md](reference/tool-api.md).
- **Look up block-type coverage**: [reference/block-coverage.md](reference/block-coverage.md).
- **Releasing / exporting a snapshot**: [how-tos/prepare-release.md](how-tos/prepare-release.md).
- **Asking "why"**: [explanation/](explanation/).

## Conventions

- `<repo>` in example commands means the repository root; MATLAB commands run under `<repo>` (after `addpath('src')`).
- Baseline release is **R2023b**. Cross-version caveats: [how-tos/work-across-versions.md](how-tos/work-across-versions.md).
- Temporary suite artifacts (logs, intermediate models) go to `test/scratch/` (gitignored), never scattered around the repo.
