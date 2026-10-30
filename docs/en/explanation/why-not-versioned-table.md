# Explanation: Why the block-type table needs no version split

This page documents **an expectation overturned by measurement**: we originally assumed that `snp_block_source` would need per-version splits (or a version column) to survive across releases, but measurement proved it does not.
To see what the table is, read [Reference: Block type coverage](../reference/block-coverage.md).

## Expectation vs. measurement

**Expectation**: the R2025a / R2026a libraries would rename, add, and deprecate block types in large numbers; the R2023b table (119 entries for the core library, later extended to 200 through cross-version verification) would fail broadly on the new releases, requiring per-version tables or a version column.

**Measurement** (the large-scale verification was an early-stage private engineering asset of this project and has been moved out of this repo; the numbers are the measured conclusions from that asset — see the CHANGELOG history section):
- 25 snapshots exported on R2023b were **rebuilt on R2026a and re-exported byte-for-byte identical** (CROSS 25/25).
- All three releases ran the full suite (export / rebuild / special blocks / behavior / roundtrip) **green**, and **not one** table entry failed on the newer releases.
- The R2025a enumeration covered 61 libraries / 121 BlockTypes; the table covers 114, with **exactly 1 real gap** (`SimscapeArrayConnection`).
- The R2026a enumeration covered 64 libraries / 134 BlockTypes; the table covers 121, with **the same single real gap**.

## Why the drift is so small

Three structural reasons (not luck):

1. **BlockType is the stable layer**. Simulink's BlockType semantics are highly stable across releases — library names and in-library paths change, but "Gain is Gain" does not.
The table stores BlockType → library path; the former is stable, the latter is the real risk — and the latter is protected by reason 2.
2. **Blocks with an rb never touch the table**. Export **prefers the ReferenceBlock route**; a table entry is only the fallback when there is no rb.
Most toolbox blocks carry an rb inside the model, so library-name changes never reach the table.
3. **Simscape blocks share one BlockType**. `fl_lib` grew from 311 blocks (2023b) to 366 (2026a), but these physical blocks all share the single BlockType `SimscapeBlock` — block-count growth creates no demand for new table entries.

## The one table-entry failure is not path drift

`PMComponent` (`sps_lib/Passives/Mutual Inductance`) failed on R2026a.
A full-library search confirmed: the **powersys (Specialized Power Systems) product was retired entirely**, with zero hits anywhere in the 2026a library set — the path did not change; the thing itself is gone.

Resolution: leave the table entry untouched. Reasons:
- If a 2026a model really did contain a PMComponent block, its rb would point at a retired library — that resolution failure is a **release-level fact external to this tool**, not this tool's responsibility.
- The historical verification assets do not use PMComponent (proven by the three-release 25/25 IDENTICAL rebuild).
- A genuine powersys → Simscape Electrical equivalent is a **semantic migration** (the parameters differ), not a table-entry swap — that needs its own project.

## When the table does need to change

- **A new release introduces a new BlockType**: run the discovery mechanism once (see the last section of [Reference: Block type coverage](../reference/block-coverage.md)) and append the new entries to the same table.
Older-release models never contain that block type, so the extra entries never fire — **zero side effects**.
- **A block type actually changes its library path** (zero measured cases so far): when adding the entry, confirm first that blocks with an rb are unaffected.

In one sentence: **the table is a "measured snapshot", not "runtime library discovery"** — the enumeration mechanism is generic (rerun it with a different library name), and the results are baked in (verified facts for that release).
This approach (generic mechanism + baked results + rb-first + one table) drives cross-version maintenance cost toward zero.
