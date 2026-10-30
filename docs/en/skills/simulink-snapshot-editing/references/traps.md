# Traps: a trap list for agents using the toolchain

Each entry gives: symptom / criterion / avoidance. Condensed from the project's measured experience and pitfall log.

## 1. "It loads" does not prove the edit is right
- **Symptom**: after editing the XML/snapshot, the model opens and you assume the edit is correct
- **Criterion**: you must read back the target block's `BlockType` + parameters + (for new blocks) `LineHandles`/`PortConnectivity`, then compare by simulation
- **Avoidance**: after every edit, run the "verification trio" (read-back → structural comparison → behavioral equivalence); a failed check reports a "proxied block" — never let it pass silently
- **Where new blocks are inserted**: in the XML, a new block must be inserted at the end of the blocks section (after the last `</Block>`), never in front of `</System>`

## 2. Library paths must be the raw truth from find_system
- **Symptom**: `add_block('fl_lib/<name that looks like one line>', ...)` fails with "no such block"
- **Root cause**: physical-source block names in fl_lib **contain a real newline char(10)**; the one-line display is an illusion
- **Avoidance**: use exactly what `find_system(fl_lib, ...)` returns, never hand-write it; a literal `\n` written into the snapshot must be restored with `strrep` before execution

## 3. A single-quoted '\n' in MATLAB is a literal two characters
- **Symptom**: a chart LabelString / multi-line string does not get its newline; state names pick up parse residue like `A_nen_`
- **Criterion**: `'\n'` (single quotes) = backslash + n, two characters; `sprintf('\n')` = a real newline
- **Avoidance**: in generated code, wrap literals containing `\n` in `sprintf('...')`; do not join strings with `+` — use sprintf or split lines
- **Chart specifics**: state machines are exported through structured `Stateflow.State`/`Transition` rebuilds (a chart has no `Script` property); when rebuilding a chart block, do not hand-set Position (it raises a dimension error during initialization)

## 4. Structural port blocks are not added standalone
- **Symptom**: `add_block('mwfaultblocklib/.../Fault Inport')` fails
- **Root cause**: FaultInport/FaultOutport/StateControl and the like attach to their parent system
- **Criterion**: after `add_block` on the parent (e.g. the Fault Subsystem) succeeds, these port blocks **come with it** (measured on R2023b) — the M route neither needs to nor should create them standalone
- **Avoidance**: when enumerating libraries, mark such blocks as "by-design skipped" and keep them out of `snp_block_source`

## 5. bdIsLoaded is always 0 after a rebuild
- **Symptom**: after `run`ning a snapshot, `bdIsLoaded(model)` returns 0 and you assume the rebuild failed
- **Root cause**: the snapshot script called `close_system` itself when it finished
- **Avoidance**: `open_system(the artifact file)` and then `get_param`; never read "empty" as "functionally broken". The artifact file name must match the internal model name (put it in a different directory to avoid overwriting, otherwise get_param cannot find it by file name)

## 6. Where InlineMasks=false saves its output
- **Symptom**: the rebuild artifact cannot be found / you assume it overwrote the assets
- **Root cause**: the InlineMasks=false route writes the rebuilt .slx into **the directory holding the snapshot itself**
- **Avoidance**: `OutDir = tempname` (never `test/models/`, `test/lib/blocks/`); after the rebuild, `bdclose(model name)` before `open_system` (a same-name leftover raises "a model with the same name is already loaded under a different path")

## 7. Physical port block types go through built-in
- **Symptom**: searching fl_lib for 'Physical' does not find PMIOPort
- **Avoidance**: PMIOPort goes through `'built-in/PMIOPort'` (via `snp_block_source`); that is the PS signal library, not the physical-port library; physical connections are exported by port name + connected component

## 8. The functional-level checksum's RTP trap
- **Symptom**: after rebuilding a Simscape model, the functional-level checksum differs — but that is not a functional loss
- **Root cause**: blocks with `RTP_XXXXXXXX` hash names change with the rebuild
- **Avoidance**: when interpreting, exclude `RTP_`-prefixed blocks, or compare the non-RTP items with a per-item `setdiff`

## 9. snp_patch's character-class boundaries (measured and refined)
- **Commas** break line parsing (`'2,5'` rebuilds to an "invalid parameter" error) — genuinely bad; pre-process, or take the XML route instead
- **Quotes** must be escaped inside values
- **Parentheses round-trip intact** (written into the snapshot, read back at rebuild, semantics evaluated as an expression, e.g. `'(3)'` reads back `Gain=(3)`) — the old wording "parentheses don't work either" was too strict; do not avoid them
- `remove_block` cleans up the `add_line` entries pointing at the removed block (same-prefix blocks are not wrongly deleted) — no manual re-wiring is needed after deleting a block

## 10. Enumerating libraries (fidelity side)
- Use a bounded depth (e.g. 20) and do **not** enable LookUnderMasks; before enumerating, run a diag probe to confirm this version's behavior instead of copying how it is done on models
- Library discovery: library name = `slblocks().OpenFcn` (unquoted); in newer versions the physmod sub-library pattern is `library/**/*.slx` (libraries moved one level down)
- Running 60+ libraries in one go can crash the process — batch 16 libraries per process (measured on 2026a)

## 11. Cross-version library drift
- **Symptom**: a table entry fails on add_block in a newer version (PMComponent on R2026a)
- **Root cause**: the whole product went offline (powersys), not a path drift
- **Criterion**: a table entry is only a **fallback** when there is no rb; exports that have an rb still use the rb. If a model genuinely uses that block type, its rb pointing at an offline library is a version-external fact
- **Avoidance**: the example assets are unaffected (the three-version coverage audit proved there is no real coverage gap); no per-version table is needed
