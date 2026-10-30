---
name: simulink-modeling-conventions
description: >-
  Simulink modeling conventions: masking subsystems (mask, color palette,
  self-documenting blocks), signal flow organization (Goto/From, Scope, bus,
  Mux, branching points), naming and abbreviation legends, plus programmable
  checks.
  Use when building or reviewing .slx models, writing build scripts, deciding
  "should this signal use Goto/From", "how should this Scope be wired", or
  "should this block be masked". Not for geometric layout — auto-layout is
  measured not viable; see "Capability Boundary: Auto-Layout Measured Not
  Viable" below.
metadata:
  priority: 5
  toolchain: "MATLAB/Simulink R2023b (verified)"
  docs:
    - "https://ww2.mathworks.cn/help/simulink/slref/simulink.annotation.html"
    - "https://ww2.mathworks.cn/help/simulink/slref/simulink.blockdiagram.arrangesystem.html"
    - "https://ww2.mathworks.cn/help/simulink/slref/get_param.html"
    - "https://ww2.mathworks.cn/help/simulink/slref/set_param.html"
  pathPatterns:
    - '**/*.slx'
    - '**/*.mdl'
    - '**/build_*.m'
promptSignals:
  phrases:
      - "simulink modeling"
      - "simulink masking"
      - "subsystem mask"
      - "goto from"
      - "signal flow"
      - "how to wire a scope"
      - "bus mux"
      - "simulink conventions"
      - "MAAB"
---

# Simulink Modeling Conventions

**Modeling conventions** for Simulink: how to mask, how to organize signal flow, how to name. Contains no usable geometric layout guidance — the reason is below.

## Overview

**Core principle: conventions pay off in readability and maintainability, not in looking good.**

Models are written for humans to read. A Clark transform block should let the reader see at a glance what it does, what its parameters are, and what its inputs and outputs mean — that is achieved through masking (mask + palette + description), not through coordinates.

**Layout incompetence, stated up front.** `arrangeSystem` / `routeLine` were measured not viable on this project's models in R2023b; see [Capability boundary](#capability-boundary-auto-layout-measured-not-viable). This skill gives no layout guidance.

## Capability Boundary: Auto-Layout Measured Not Viable

Measured on mature models containing feedback loops (same code, same inputs), auto-layout **improved nothing and made most things worse**: `arrangeSystem` on its own squeezes wide diagrams into tall ones, and the crossing count goes up rather than down; grid rearrangement with every layering strategy (topological depth / preserve original layers / center snapping) produced crossing counts several times that of the original drawing; even scoped tricks like "only move the Scope" left a net increase of dozens of fields.

**Why it necessarily fails**: these models contain structurally cross-column feedback — long-distance feedback edges spanning multiple columns, such as angle feedforward, the speed loop feeding into the current loop, or the load command. Hierarchical layout algorithms assume the graph is close to a DAG; a control-system model with cascaded feedback is not. Furthermore `routeLine` needs free canvas space to maneuver — when blocks fill the canvas, it will not change a single line.

**Conclusion: geometric layout is manual work only.** Edit `Position` in `build_*.m`, look at the diagram in Simulink, and adjust; the script is re-runnable, so one fix holds permanently. This skill provides no layout algorithm.

**When editing through the simulink-snapshot-edit toolchain, geometry originates only from the GUI** — the M snapshot **deliberately keeps** `Position`/`Points` (required for byte-exact rebuildability, D5); `snp_view_nogeom` strips the geometry lines only when an agent reads a model, producing a reading view (~35% fewer lines), and the view does not replace the M.

## When to Use

- Writing `build_*.m` to generate `.slx`, and needing to decide "does this function deserve its own subsystem"
- Adding a mask to a subsystem (description, parameters, color)
- Deciding whether a signal should be a direct line or Goto/From
- Deciding how Scope / To Workspace / Terminator should be wired
- Organizing multiple signals with Mux/Bus, or needing branches
- Reviewing a model against MAAB rules
- Generating an abbreviation legend

**Not for**: geometric layout, simulation behavior, solver settings.

## Editing (via the simulink-snapshot-edit toolchain)

The division of labor is fixed for this repository's models (`test/models/`, `test/lib/blocks/`): **humans edit the .slx only in the Simulink GUI**, and after editing, `snp_pull` flows the changes back into the M snapshot (handwritten comment regions are preserved line by line); **agents never touch the GUI — they edit only the M snapshot or the XML inside the .slx package** through the toolchain, never the GUI-side content of the original `.slx`. Machine-specific paths go through `snp_config()` reading `config_local.m` (gitignored, not committed); no machine-local values are hardcoded in scripts. The three-tier ladder on the agent side (plan D4):

1. **In-place XML editing** `snp_xml_edit`: edit `simulink/systems/system_*.xml` inside the .slx package and repackage — fastest, highest fidelity (unlisted parameters, Stateflow, physical connections are preserved as-is).
2. **XML→M backfill** `snp_sync_m`: translate the XML edits into M snapshot changes, keeping M and .slx consistent in both directions.
3. **Agent edits the M snapshot directly**: patched through `snp_patch` (the M snapshot keeps coordinates; when reading a model, `snp_view_nogeom` strips the geometry lines).

Iron rules that hold across all three tiers:

- **Geometry ownership (D5)**: block positions and line routing are adjusted by humans in the GUI, or — on the XML path — left to Simulink's auto-arrangement; agents never rearrange an existing layout. The M snapshot **must keep** `Position`/`Points` — that is the premise of byte-exact rebuildability; geometry stripping happens only in the `snp_view_nogeom` reading view.
- **New blocks in XML need only `BlockType`**; library paths are M-side knowledge (D6 — `snp_block_source` manages this), and the model file does not need them.
- **New XML blocks must be appended at the end of the blocks section** (after the last `</Block>`) — inserted after a line, they are silently dropped in document order.
- **Successful load ≠ correct edit**: an unknown BlockType degrades into a proxy block and loading reports no error. After editing you must read back the BlockType/parameters/connections and simulate; treat a failed check as a proxy-block error, never silently let it pass.
- **Acceptance = re-export to M and set-diff it** (the criterion of `test/scripts/verify_xml_*.m`), not "it opens". Acceptance of the human-machine collaboration chain is in `test/scripts/verify_collab.m` (pull comment preservation, dirty/during-simulation warnings, merge3 three-way merge over 8 scenarios).

## Subsystem Encapsulation (masking)

### What should become a subsystem

`db_0144`: group by **functional decomposition**, not to save space. Each subsystem represents one functional unit.

Judgment criterion: can you state in one sentence what this set of blocks does? If you cannot → split it. If you can, but the function is tangled with its neighbors → split it.

`db_0143`: each level is either **all subsystems** or **all basic blocks** — never mixed. (Routing blocks such as Inport/Outport/Mux/Goto/From/Sum/UnitDelay may appear at any level.)

### The four elements of masking

```matlab
lib_build.mask(blk, 'transform', ...
  'Clark transform: abc to alpha-beta (amplitude-invariant)', ...
  struct('Name','k','Type','edit','Value','2/3'));
```

1. **MaskType = functional class** — determines the color, drawn from a fixed palette
2. **MaskDescription = one-line description** — short name before the colon (goes on the icon), detail after it
3. **MaskVariables = named parameters** — default names like Parameter1/Parameter2 are forbidden
4. **MaskDisplay = short title** — the icon shows only the short name; the detail lives in MaskDescription

### Palette (fixed; do not invent your own)

| Functional class | Color | Use |
|---|---|---|
| `transform` | lightBlue | Clark / Park / inverse transforms |
| `estimator` | `[1 1 0.8]` light yellow | PLL / SMO / LDO / DSO |
| `control` | `[0.5 1 0.5]` light green | PI / control loops |
| `modulation` | `[1 0.75 1]` light purple | SVPWM / inverters |
| `signal` | orange | filtering / demodulation |
| `measure` | gray | measurement / operating conditions |
| `machine` | darkGreen | machine body |
| `aux` | white | constants / reuse |

Once the colors drift, "the same Clark is two different blues in two libraries", and the reader's color memory stops working.

### Subsystem interfaces must be fully displayed

**Every port name of a subsystem must be visible.** When a block is too short, port names crowd together or disappear entirely, and the reader cannot tell what the subsystem consumes and what it produces.

Criterion (`check_port_visibility`, L13): each port needs roughly 14 units of height, plus 8 units of margin above and below.

```
Minimum height = 16 + 14 × max(nIn, nOut)
```

A subsystem with 8 ports needs at least 128 units of height; the default 30 units is nowhere near enough. When the names do not fit: **stretch the block** — do not cope by hiding port names (`jm_0002` allows hiding only on the premise of "clearly labeling the signal lines next to the block", and that is a last resort, not the first choice).

### Port order

**This is the one thing that cannot be fixed automatically after the fact.** Given a subsystem with scrambled port order, every layout engine can only cross lines to reach the correct ports.

- Inports are ordered by importance to the signal flow: reference → feedback → rarely-changed parameters → diagnostics
- Outport order should read like the section headings of the algorithm
- Physical placement: Inports in the left column inside the subsystem, Outports in the right column (`db_0042`)

## Signal Flow

### Goto / From

`jc_0171`: the visual depiction of signal flow must be preserved. Conditions under which Goto/From are allowed:

- At least one drawn line connects two subsystems
- In a feed-forward + feedback loop, at least one drawn line for **each** direction

**Exceptions**: using Goto/From to assemble buses, or to feed the inputs of Merge blocks.

Test: if a diagram is entirely Goto/From, the reader sees no data flow at all — that violates `jc_0171`. Layers where Goto/From dominate must be reworked.

### Observation points: From → processing → Scope

An observation point that needs data processing has a fixed chain:

```
From ──► processing (Gain / Offset / BusSelector / Demux) ──► Scope
```

The "processing" block and the Scope it serves are one group. Do not run a line straight from the observed object into the Scope — that scatters gain offsets and unit conversions across the diagram.

**Scope / Goto / From / To Workspace generally do not serve as the main line** (they produce no data; they only forward or display it). Unless the layer has no other block that could serve as the main line.

### Signal labels

`na_0008`: signals leaving the following blocks **must** be labeled — Inport, From, Subsystem, Bus Selector, Demux, Selector, Data Store Read, Constant. Signals entering the following blocks **must** be labeled — Outport, Goto, Data Store Write, Bus Creator, Mux, Subsystem, Chart.

`na_0009`: **entered vs propagated** labels —

- Entered (typed directly) for: signals leaving a root-level Inport; outputs of **transformative** blocks (Bus Creator / Mux / Selector count as transformative)
- Propagated (using the `<` prefix) for: signals leaving an Inport in a nested subsystem; outputs of **non-transformative** blocks; outputs of a Subsystem/Chart

`db_0097`: labels sit **below** horizontal lines, close to the corresponding source or destination block, without overlapping other labels, signals, or blocks.

### Bus and Mux

- Inputs of a Mux follow port-number order, without crossings
- To merge the outputs of conditionally executed subsystems, prefer virtual buses (Bus Creator + Bus Selector) over a pile of Merge blocks
- Fan-out must not exceed 2 sub-branches (`db_0032`)
- With more than 5 destinations, use Goto/From or a bus instead of pulling 5 lines

### Dead blocks and empty signals: three different ailments

`db_0081` covers only the most superficial one. There are actually three classes, each detected differently:

| Class | Symptom | Detection |
|---|---|---|
| **Dangling port** | the port has no line connected | `check_unconnected` (L7) checks directly whether `get_param(port,'Line')` is -1 |
| **Empty From tag** | the From is wired, but its tag has no matching Goto on this level | `check_orphan_tags` (L11) compares the tag sets |
| **Isolated subchain** | internally fully connected, but unrelated to the main line as a whole | `check_islands` (L12) computes connected components |

The second class is the most hidden: judged by "is the port wired", it looks perfectly normal, yet it receives no signal at all. The third class is hidden too: every port is connected — nobody uses its result.

`check_islands` uses two complementary criteria:

- **No source, no sink**: the component contains neither a source (Inport/Constant/Step/From/Ground…) nor a sink (Outport/Scope/ToWorkspace/Terminator/Goto) → certainly a dead block
- **Relatively isolated**: when the level has a main component of ≥3 blocks, any component of only 1–2 blocks without an Inport/Outport is a suspicious side branch

Note the boundary of the criteria: a chain like `Constant → Terminator` — "has a source and a sink but is unrelated to everything else" — is not a dead block by definition (it is self-consistent) and will not be reported.

### Unconnected ports

`db_0081` (Mandatory): unconnected inputs, outputs, and signal lines are not allowed. Connect a spare input to `Ground` and a spare output to `Terminator`.

## Naming (naming conventions)

The four rule sets `jc_0201` / `jc_0211` / `jc_0221` / `jc_0231` carry consistent constraints and apply to subsystem names, port names, signal line names, and block names:

- Must not start with a digit; must not contain spaces or carriage returns
- Only `a-z A-Z 0-9 _` is allowed
- Underscores may separate words; not consecutive, not leading or trailing

Consequence: `theta_hat` is legal; `θ^` and `speed (rpm)` are not.

`jm_0010`: port names match the corresponding signal names, or use a consistent `_in` / `_out` prefix/suffix. `jc_0081`: set Inport/Outport *Icon display* to **Port number**. `db_0142`: the block name is displayed **below** the block.

## Abbreviation Legend

Place one annotation per level listing the full forms and meanings of the abbreviations visible on that level. Unexplained abbreviations are the reader's biggest reading cost.

```matlab
annotate_legend(mdl, 'Meanings', struct( ...
  'TH','electrical angle', ...
  'WE','electrical angular speed', ...
  'UA','a-phase voltage'));
```

Abbreviations with no filled-in meaning are listed first and marked `TODO`. Locate them with `Tag='ABBR_LEGEND'`; repeated calls overwrite, they do not stack.

Automatically collect the abbreviations visible on the level (Goto/From tags, port names, Scope names, To Workspace variable names, signal line names):

```matlab
abbr = legend_collect(mdl);   % returns a cell array; fill in the meanings by hand
```

## Bundled Tooling

Only scripts that are deterministic and **do not depend on auto-layout** are kept:

- `scripts/fit_block_text.m` — stretches Gain/Constant/Goto/From until their content is fully displayed. R2023b has no `resizeBlocksToFitContent`; this is the replacement implementation. Only grows, never shrinks.
- `scripts/annotate_legend.m` + `scripts/legend_collect.m` — abbreviation legend generation.
- `scripts/audit_layout.m` — **read-only** checks, 13 categories (`check_unconnected`, `check_orphan_tags`, `check_islands`, `check_port_visibility` and so on are its **internal subfunctions**, not exported independently; the L7/L11/L12/L13 numbers below refer to them):
  - L1 overlap / L2 off-screen / L3 elliptical Sum / L4 too-narrow blocks / L5 name placement / L6 font inconsistency
  - L7 dangling ports / **L11 empty From tags** / **L12 islands and isolated side branches** / **L13 incomplete subsystem interface display**
  - L8 lines crossing blocks / L9 line crossings / L10 flow direction — nothing modifies the model, so it is safe to run at any time.

No layout script is provided. See [Capability boundary](#capability-boundary-auto-layout-measured-not-viable).

## Additional Resources

- Full rule text, priorities, and Model Advisor check names → [references/maab-rules.md](references/maab-rules.md)
- R2023b measured API behavior (`arrangeSystem` / `routeLine` / `Simulink.Annotation` / `get_param` / `set_param`, including 4 discrepancies with current documentation) → [references/simulink-api-notes.md](references/simulink-api-notes.md)
