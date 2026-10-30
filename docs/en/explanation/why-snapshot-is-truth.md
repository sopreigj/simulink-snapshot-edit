# Explanation: Why the model is the single source of truth and the snapshot is its code shadow

This page covers design motivation and trade-offs; it does not teach operations.
For "how to do things", go to [how-tos/](../how-tos/).

## The problem being solved

A build script that generates a model from scratch **rebuilds everything** on every run — manual dragging, relative placement, all of the layout work is thrown away.
Every "change one parameter" means rerunning the entire generation script, and then a human re-lays-out the diagram.

This tool inverts the workflow: **model → M**.
The model (maintained by a human in the GUI, carrying all the layout work) is the **single source of truth**; the M snapshot is its **code shadow**.
From then on, a small change means editing a few lines in the M and rerunning — every other block and every relative position stays byte-for-byte unchanged.

"Single source of truth" means something specific:
- When the two sides disagree, **the model wins** (`snp_pull` merges the model's changes back into the snapshot).
- The value of the snapshot is not that it is "another copy of the model", but that it is a **readable, byte-for-byte verifiable, cross-version portable** vehicle.
- The human always works in the GUI and never has to read code; the agent always works in code and never has to drive the GUI.
The two collaborate through one shared text.

## The three-tier editing ladder: why it is not one tool

(Convention: tier 1 XML in-place edit + repack; tier 2 XML→M sync-back; tier 3 the agent reads filtered content and edits the M snapshot directly.)

The key observation: **the two routes are complementary, not alternatives** —

The XML route (tier 1):
- Editing the XML **needs no library path per block type** (only `add_block` does).
- It needs no model rebuild — parameters outside the whitelist, Stateflow, and Simscape physical connections are **preserved at the byte level**.
- The cost: the result is a "modified .slx", not a "rebuildable M".

The M route (tier 3):
- The result is rebuildable, byte-for-byte verifiable, and **portable across versions** (an R2023b snapshot rebuilt on R2026a came out byte-for-byte identical — verified).
- The cost: it needs a block-type → library-path table, and it needs a structured export for each kind of special content (charts, physical networks).

Tier 2 (`snp_sync_m`) is the bridge: the edit happens in the XML, and `info.mops` syncs it back into the M automatically — the speed of tier 1 plus the verifiability of tier 3.
**The M is designated the fallback truth that runs through all three tiers**: no matter which tier you start from, the M must end up consistent with the model.

## Why the M snapshot deliberately keeps geometry (Position / Points)

This is the easiest point to get wrong, so it deserves its own section:

- **The XML route drops geometry**: block positions and line routing are **presentation properties** — Simulink auto-layout handles them.
Measured, layout-related parameters are about 59% of the XML parameter entries, so dropping them roughly halves the XML size.
Human–agent collaboration never needs the agent to write geometry.
- **But the M snapshot keeps `Position` and `Points`**: because "run it once and the whole model is rebuilt" requires **byte-for-byte rebuildability** — measured across the 5 example-asset snapshots, every one contains `add_block(...,'Position',...)` and `add_line(...'Points',...)`.
This is not "editing coordinates"; it is what the rebuild requires.

So the "geometry-free view" used by the tier-3 route is a **read view** (produced by `snp_view_nogeom`), based on "ignore the geometry lines" rather than "the snapshot has no coordinates" — the M itself always carries geometry, so do not delete it for readability.

## Where library-path knowledge belongs (why there is only one table)

The library path is **API-side** knowledge — only `add_block` needs it.
The model file does not: in the `.slx` internal XML, a plain block records only its `BlockType`, and Simulink resolves the rest at load time (verified: a new block written with only `BlockType="Gain"` and no library path is recognized, its parameters read back, its connections valid, and the simulation matches the original signal by signal).

Therefore:
- In-place structural XML editing **needs no** block-type whitelist.
- The M route and the XML→M sync-back do, and they go through the shared table `snp_block_source` — **one concept, one name, one table, no second copy**.

## How library changes propagate (design seed)

Library instances inside a referencing model are **linked** (`ReferenceBlock` / `LinkStatus='resolved'`): the model snapshot records only the link, `add_block('mylib/blk',…)`, not the library's internal parameters.
So **change the library → the referencing model rebuilds with the new content automatically** holds true (verified: the library's Gain 2→7; after rebuilding from the untouched model snapshot, the instance automatically carries the new value).

Future automated propagation needs only two steps: **rebuild the library + rebuild the referencing model**.
The model snapshot needs no synchronization.

## Bidirectional preservation (why comments never get lost)

The `snp_pull` merge aligns by **section** and by **block name**: section headers, comments, and helper lines (the hand-written region) always keep the old content; the statements (block X) are replaced with whatever the model currently has.
This is both an engineering choice and the core promise of human–agent collaboration: **the code structure the agent wrote survives the human's GUI edits, and the model the human edited is never overwritten by the agent**.

Division of labor with the official tools:
- MathWorks Comparison / Three-Way Merge compares **model ↔ model**, and the output is still a `.slx` — the agent can neither read nor edit it.
- This project fills the bidirectional **model ↔ readable code** layer, so the LLM and the human share one text.
