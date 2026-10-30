# Reference: Block Type Coverage Scope

The factual record of the `snp_block_source` table: what it covers, what it does not, and the shape of cross-version drift. For the API itself, see [tool-api.md](tool-api.md).

## Scale

- **200 cases** (BlockType → library path), drawn from three layers of empirical probing:
  1. Each BlockType used by the early large-scale verification assets (since moved out of this repository; counts are in the CHANGELOG history section) was probed one by one;
  2. Enumeration of the R2023b `simulink` core library (502 blocks / 163 BlockTypes); the 119 out-of-table types were each probed with a real `add_block` and added;
  3. Toolbox library exhaustion (`slblocks().OpenFcn` yields 52 top-level libraries + `physmod/**/library/*.slx` yields 278 sublibraries), which added 33 new block types (SimEvents entity family, nesl_utility Simscape utilities, FMU/Reciprocal/Reference/Observer, and others).
- **Path newline convention**: library names containing a literal `char(10)` (such as `'Math⏎Operations'`) are recorded in the table as a literal `\n` and restored before the function returns.

## Two "by-design exceptions" (intentionally out of table)

| BlockType | Why it is not in the table |
|---|---|
| `SubSystem` | Container: with an rb, the rb is used; without one, `built-in/SubSystem` is the fallback / `expand_masked` expands it |
| `S-Function` | Special-cased by the exporter (`simulink/User-Defined Functions/S-Function`); the `.m` implementation is copied along with the snapshot |

## Structural port blocks (T39: out of table, and they should be)

Port blocks **structurally dependent on their parent system**, such as `FaultInport` / `FaultOutport` / `FaultDataInport` / `StateControl` / `EnablePort` / `TriggerPort`:

- They cannot be added with a bare `add_block` (errors like "must reside at the root level of a fault subsystem");
- In real models they are **created along with** the parent system (for example Fault Subsystem) — probing `add_block('mwfaultblocklib/Fault Subsystem')` shows it carries FaultInport + FaultOutport;
- M-route rebuild only needs the parent block path; it does not need (and should not have) an independent table entry.

## Cross-version drift (measured shape)

| Version | Libraries | BlockType count | Table coverage | True gap |
|---|---|---|---|---|
| R2025a | 61 | 121 | 114 | 1 (`SimscapeArrayConnection`, since added) |
| R2026a | 64 | 134 | 121 | 1 (same, since added) |

- Each version was exhausted in turn (mechanism ① `slblocks` + mechanism ② `physmod/**/library/**/*.slx`); every FAIL is a T39 structural port block (expected out of table; `FaultDataInport` is new in 2026a).
- **The single stale table entry**: `PMComponent` (`sps_lib/Passives/Mutual Inductance`) is **dead in R2026a** — but **not from path drift**: the powersys (Specialized Power Systems) product was taken offline entirely, with zero hits across the whole 2026a library. The entry stays as is: if a 2026a model really contains that block, its rb points at a retired library — a fact external to the table; the example assets do not use PMComponent (proven by three-version rebuild 25/25 IDENTICAL, per the historical scope). A genuine powersys → Simscape Electrical migration is semantic-level work, not a table-entry swap.
- **Conclusion: the table needs no per-version split / version column** (argument in [explanation/why-not-versioned-table.md](../explanation/why-not-versioned-table.md)).

## Blocks with an rb: the table is only a fallback

At export time, **ReferenceBlock is preferred** (`get_param(b,'ReferenceBlock')`); a table entry is only the fallback when there is no rb. So one entry more or fewer in the table is harmless for library-linked blocks — this is also why an entry like `SimscapeArrayConnection`, which "only exists in newer versions", is safe to add: older-version models do not contain that block type, so that case never fires.

## Discovery mechanisms (for exhaustion; run these when reproducing a scope change)

1. **Mechanism ① slblocks registration**: `which('-all','slblocks')`, then for each one `cd(fileparts(f{i})); s = slblocks();` and take **`s.OpenFcn` (unquoted, it is directly the library name)** → `load_system` to confirm `BlockDiagramType=='library'`.
2. **Mechanism ② physmod sublibraries**: `dir(fullfile(matlabroot,'toolbox','physmod','**','library','**','*.slx'))` (libraries in R2025a/2026a moved one level down; the old `library/*.slx` pattern matches only 4/2 of them).
3. Enumerate libraries with a finite depth (for example 20) and **without** `LookUnderMasks`.
4. Probe each gap with a real `add_block` + readback of BlockType ("loaded successfully" does not mean the block is usable).
