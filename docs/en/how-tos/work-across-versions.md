# How-To: Working across versions (2023b / 2025a / 2026a)

The task: using this tool across several MATLAB versions, or carrying a snapshot from an older version into a newer one.

## Baseline version and the version assertion

- The baseline version is **R2023b**. `snp_export` contains a version assertion in its function body; any version other than 2023b raises an error directly.
- To run on another version (e.g. for multi-version testing): set `opts.AllowUntestedVersion = true`, or the environment variable `SNP_ALLOW_UNTESTED=1` (`verify_multiver.m` uses it to let the downstream suites through). When allowed, stderr prints a warning: `未验证版本` (untested version) — this is a **notice, not an error**.

> Note on launching: the `matlab` on your PATH may be a non-baseline version (in practice it can be R2025a), in which case every suite with a version assertion fails with "verified on R2023b only". Invoke the MATLAB executable of the **baseline version (R2023b) explicitly** with `-batch`, e.g. `<R2023b install dir>/bin/matlab.exe -batch "cd('<repo>/test/scripts'); verify_xxx"` (Windows; on other platforms use the platform's `matlab` launch command).

## Coverage findings (verified conclusions)

| Aspect | Conclusion |
|---|---|
| Cross-version portability of the M snapshot | ✅ A snapshot exported on R2023b rebuilds and re-exports on R2026a **byte-for-byte identically**; each of the three versions passes the full suite set (export / rebuild / behavior / roundtrip) — historical large-scale verification 25/25, see the CHANGELOG history section; for the toy-asset basis see the status section of the README |
| Block-type table (200 cases) | ✅ No failure on any of the three versions — **exactly 1 known stale entry**: `PMComponent` (sps_lib), retired with the entire powersys product in R2026a; not a path drift |
| Library coverage | R2025a: 61 libraries / 121 BlockTypes (table covers 114); R2026a: 64 libraries / 134 BlockTypes (table covers 121) |

**Why the table needs no per-version variants**: the exhaustive verification of both versions found very little drift (one new block type each, `SimscapeArrayConnection`, already added to the table); the only table entry that stopped working is a "product retired" event, not a path change, which is a fact external to versions. For the full argument see [Explanation: Why the table needs no per-version variants](../explanation/why-not-versioned-table.md).

## How to run the cross-version verification

`test/scripts/verify_multiver.m` runs the full set on the current MATLAB version (env + snapshot export + rebuild + special + behavior + roundtrip) and archives the results under `test/scripts/multiver/<release>/` (gitignored, not committed):

```matlab
cd test/scripts;
verify_multiver;
```

Related scripts:
- `verify_cross_version.m`: rebuilds a snapshot exported on the baseline version in another version and re-exports it, comparing byte-for-byte (the CROSS criterion).
- `verify_cross_behavior.m`: cross-version behavioral equivalence.
- If a `run_suite` archive reports "no log produced": check `test/scratch/` for the actual log first — the archive path and the suite log path were mismatched at one point (fixed, but when something looks wrong, check test/scratch first).

## Known cross-version differences

- **R2026a model-name shadowing warning**: when the snapshot's `new_system('X')` shares a name with `test/lib/blocks/X.slx`, R2026a issues a stricter shadowing notice. It does not affect the result.
- **physmod library layout in R2025a/2026a**: library files moved one level down, from `library/*.slx` to `library/<subdir>/*.slx`. Adapt the glob pattern accordingly (`library/**/*.slx`) when enumerating libraries.
- **powersys product retired in R2026a**: loading `sps_lib` fails ("system or file not found"). Models depending on powersys blocks cannot work on that version — this is a MATLAB change, not a defect of this tool.
- **Non-ASCII parameter values**: localized enum display names, such as a Chinese-locale Scope's `TimeSpan` reading as `'自动'`, are only valid in a same-language version. The exporter writes such a value only when it differs from the default of the same block type; omitting it lets each version use its own default, which is semantically equivalent.

## Known version boundary: PMComponent / powersys (T46)

**Symptom**: the `PMComponent` entry in the `snp_block_source` table (library path `sps_lib`) fails `add_block` on R2026a — the powersys product is retired entirely in that version (zero hits across the library), not a path drift of the table entry.

**Why this is a fact external to versions rather than a defect of this tool**:
- The table entry's job is "fallback when there is no ReferenceBlock" (T40). Blocks that have an rb still export via the rb and never touch the table; only a bare M-route build of PMComponent would hit it.
- None of the models from the historical large-scale verification use PMComponent — the cross-version P0 verification already confirmed the full R2025a/R2026a suites at 25/25 IDENTICAL, so the entry has zero impact on the verification assets.
- If your model **actually** uses powersys-specific blocks and you need to move it to 2026a: that is a semantic migration problem between versions (the blocks no longer exist), and a human must find replacements or stay on 2025a — the table is not changed and is not versioned for this (see the [explanation](../explanation/why-not-versioned-table.md)).

**Why the table stays single-version**: all three versions verified green, with exactly this 1 drift and it is external to versions; the complexity of splitting the table or adding a version column is not worth it (same explanation as above).

## When you must take the M route

Cross-version scenarios **must** go through the M snapshot route: an `.slx` carries no cross-version portability itself (its internal format changes between versions), and the M snapshot is the only byte-for-byte verifiable carrier. The XML in-place edit (tier ①) is for "quick edits within the current version"; do not carry its artifacts across versions.
