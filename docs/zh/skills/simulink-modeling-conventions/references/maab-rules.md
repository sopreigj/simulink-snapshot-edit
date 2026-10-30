# MAAB Rules（外观 / 结构 / 命名）

Extracted from *MathWorks Automotive Advisory Board Control Algorithm Modeling Guidelines Using MATLAB, Simulink, and Stateflow* (v3.1, 2015).收录与**外观、结构、命名**相关的规则；几何排版规则（如 db_0141 的左右流向）收录在此，但注意本仓库的模型实测无法通过自动排版满足它们——见SKILL.md「能力边界」。

Verbatim requirement text is paraphrased tightly; IDs and priorities are exact.

Priority meanings: **Mandatory** = essential, a violation may break the model, waiver must be documented. **Strongly recommended** = good practice, aim for it but 100% is not required. **Recommended** = appearance only.

---

## Signal flow and routing

### db_0141 — Signal flow in Simulink models (Strongly recommended)

The signal flow in a model is from left to right.

- Exception: feedback loops.
- Sequential blocks or subsystems are arranged from left to right.
- Parallel blocks or subsystems are arranged from top to bottom.

This is the single rule that dictates the whole drawing geometry. Everything else refines it.

### db_0032 — Simulink signal appearance (Strongly recommended)

Signal lines:

- Should not cross each other, if possible
- Are drawn with right angles
- Are not drawn one upon the other
- Do not cross any blocks
- Should not split into more than two sublines at a single branching point

"Right angles" means orthogonal segments only — no diagonal runs.

### jc_0171 — Maintaining signal flow when using Goto and From (Strongly recommended)

You must maintain the visual depiction of signal flow between subsystems. Goto/From are permitted only if:

- At least one signal line connects the subsystems, and
- Subsystems connected in a feed-forward **and** feedback loop have at least one signal line for **each** direction.

Exceptions: using Goto/From to create buses, or to connect inputs to Merge blocks.

Rationale: a diagram made entirely of Goto/From pairs hides the actual flow.

### jc_0111 — Direction of Subsystem (Strongly recommended)

Subsystems must not be reversed. `Orientation` should stay `'Right'`; a flipped subsystem is a readability defect even though it simulates identically.

---

## Blocks: placement, size, labels

### db_0042 — Port block in Simulink models (Strongly recommended)

- Place Inport blocks on the left side of the diagram; you may move them to prevent signal crossings.
- Place Outport blocks on the right side of the diagram; you may move them to prevent signal crossings.
- Duplicate Inport blocks are allowed at subsystem level, but avoid them.
- Do **not** use duplicate Inport blocks at the root level.

### jm_0002 — Block resizing (Mandatory)

All blocks must be sized so that the icon is completely visible and recognizable. In particular, any displayed text (tunable parameters, file names, equations) in the icon must be readable.

Blocks with variable icons or a variable number of ports must be resized. If a subsystem icon cannot show all port names legibly, hide the names via mask and label the signal lines close to the block instead.

**本仓库的执行口径（严于原文）**：子系统接口**必须完整展示**，显示不下就**拉伸放大**。隐藏端口名只作为最后手段，且必须同时在块旁清晰标注信号线。判据：`最小高度 = 16 + 14 × max(nIn, nOut)`（见 `audit_layout` 的 L13）。

### db_0142 — Position of block names (Strongly recommended)

If shown, place the name of a block **below** the block. Programmatically: `set_param(blk,'NamePlacement','normal')`.

### jc_0061 — Display of block names (Recommended)

- Display a block name when it provides descriptive information.
- Do not display a block name if the block's function is obvious from its appearance.

### na_0005 — Port block name visibility (Strongly recommended)

Pick one organization-wide convention and hold it:

- Inport/Outport names are **not** hidden, **or**
- Inport/Outport names **must** be hidden (exception: cannot hide inside library subsystem blocks).

### jm_0010 — Port block names (Strongly recommended)

Choose one consistent convention:

- Port block names match the corresponding signal or bus names, **or**
- Apply a consistent prefix/suffix (`_in` / `_out` are the suggested pair).

Exceptions: name collisions with other blocks; generic library/reusable subsystems; hidden port names (then use default names, the signal name, or a mangled form — consistently).

### jc_0081 — Icon display for Port block (Recommended)

Set Inport and Outport *Icon display* to **Port number**.

### db_0140 — Display of basic block parameters (Recommended)

Important block parameters that differ from default should be visible. Methods: the attribute string / block annotation tab, or masking the basic block (allowed if the base icon remains distinguishable).

### db_0143 — Similar block types on the model levels (Strongly recommended)

Every level of a model must be built from blocks of the **same type** — either only subsystems or only basic blocks. Do not mix. Routing blocks are exempt and may appear at any level: Action Port (not at root), Bus Creator, Bus Selector, Case, Data Store Memory, Data Type Conversion, Demux, Enable (R2011b+), From, Function-Call Generator, Function-Call Split, Goto, Ground, If, Inport, Merge, Mux, Outport, Rate Transition, Selector, Terminator, Trigger (R2009a+), Unit Delay.

### db_0144 — Use of Subsystems (Strongly recommended)

Group blocks into subsystems by **functional decomposition**, not to save space. Each subsystem should represent one unit of functionality. Use a virtual subsystem when a subsystem is needed purely for readability.

### db_0040 — Model hierarchy (Strongly recommended)

The model hierarchy should correspond to the functional structure of the control system.

---

## Signals and labels

### na_0008 — Display of labels on signals (Recommended)

A label **must** be displayed on a signal originating from: Inport, From, Subsystem or Stateflow chart, Bus Selector, Demux, Selector, Data Store Read, Constant.

A label **must** be displayed on any signal connected to: Outport, Goto, Data Store Write, Bus Creator, Mux, Subsystem, Chart.

*Block icon exception:* if the label is already visible in the originating block's icon, the signal line needs no label — unless a destination-based rule still requires it.

### na_0009 — Entry versus propagation of signal labels (Strongly recommended)

- **Entered** (typed on that line) for signals originating from: a root-level Inport; a basic block performing a **transformative** operation (Bus Creator, Mux and Selector count as transformative here).
- **Propagated** (using the `<` prefix) for signals originating from: an Inport in a nested subsystem; a basic block performing a **nontransformative** operation; a Subsystem or Stateflow chart.

Exceptions for library subsystems/blocks, to accommodate reuse.

### db_0097 — Position of labels for signals and busses (Strongly recommended)

Labels must be visually associated with their signal and must not overlap other labels, signals, or blocks. Labels should sit consistently **below** horizontal lines and close to the corresponding source or destination block.

### db_0081 — Unconnected signals, block inputs and block outputs (Mandatory)

A system must not have unconnected subsystem/basic-block inputs, unconnected outputs, or unconnected signal lines. An otherwise unconnected input should be connected to a Ground block; an unconnected output to a Terminator.

---

## Diagram-wide appearance

### na_0004 — Simulink model appearance (Recommended)

At release, appearance settings should be:

| View | Setting |
|---|---|
| Model Browser | unchecked |
| Screen color | White |
| Status Bar | checked |
| Toolbar | checked |
| Zoom | Normal (100%) |

| Block display | Setting |
|---|---|
| Background Color | White |
| Foreground Color | Black |
| Execution Context Indicator | unchecked |
| Library Link Display | None |
| Linearization Indicators | checked |
| Model/Block I/O Mismatch | unchecked |
| Model Block Version | unchecked |
| Sample Time Colors | unchecked |
| Sorted Order | unchecked |

| Signal display | Setting |
|---|---|
| Port Data Types | unchecked |
| Signal Dimensions | unchecked |
| Storage Class | unchecked |
| Test point Indicators | checked |
| Viewer Indicators | checked |
| Wide Nonscalar Lines | checked |

### db_0043 — Simulink font and font size (Strongly recommended)

All text elements — block names, block annotations, signal labels — must share the same font style and size, chosen for legibility. Free-text annotations are exempt. Use a portable font (Simulink/Stateflow default, Arial, Helvetica 12 pt).

### db_0146 — Triggered, enabled, conditional Subsystems (Strongly recommended)

The blocks that make a subsystem conditional or iterative must sit at a consistent location at the **top** of the subsystem diagram: Action Port, Enable, For Iterator, Switch Case Action, Trigger, While Iterator.

---

## Block-specific

### jc_0121 — Use of the Sum block (Recommended)

- Use the **rectangular** shape.
- Size it so input signals do not overlap.
- No more than three inputs.
- Inputs at 90°, 180°, 270°; output at 0°.
- Round shape is permitted in feedback loops.

### jc_0141 — Use of the Switch block (Strongly recommended)

- The switch condition (input 2) must be Boolean.
- Set *Criteria for passing first input* to `u2 ~= 0`.

### jc_0131 — Use of Relational Operator block (Recommended)

When comparing a signal to a constant, the constant should be the **second** (lower) input.

---

## Naming (affects legibility of the diagram)

### jc_0201 / jc_0211 / jc_0221 / jc_0231 — Usable characters

Applies to Subsystem names, Inport/Outport names, signal line names, and block names respectively. Same constraints in all four:

- Must not start with a digit
- Must not contain spaces or carriage returns
- Allowed: `a-z A-Z 0-9 _`
- Underscores may separate parts; no two consecutive; not leading or trailing

Practical consequence: an identifier like `theta_hat` is legal; `θ^` and `speed (rpm)` are not.

---

## J-MAAB model architecture (governs what the layout must express)

### jc_0301 — Controller model (Mandatory)

Control models use a fixed hierarchy: Top layer (root) → optional Trigger layer → Structure layer → Data flow layer.

### jc_0311 — Top layer/root level (Mandatory)

The root layer describes: an **overview** of the model feature, its **inputs**, and its **outputs**. Nothing else — detail belongs below.

### jc_0321 — Trigger layer (Mandatory)

Expresses processing timing via Triggered or Function-Call Subsystems. Set Priority where needed and **display it as a block annotation**, so the priority-based order is readable without opening the block.

### jc_0331 — Structure layer (Mandatory)

Subsystems of the structure layer should be **atomic** subsystems. Where sample time defines a task, specify it on the Inport or Subsystem block and display it in a block annotation.

### jc_0341 — Data flow layer (Mandatory)

Where execution timing matters, display sample time as a block annotation on the Inport block.

---

## Appendix A — compliance levels

If you build a checker, the MAAB-suggested compliance vocabulary is: **Correction** (auto-fixes), **Check** (flags, human fixes), **Partial** (checks part, detail states what is and isn't covered), **None**.

`scripts/audit_layout.m` covers a subset of these at the **Partial** level and prints which rules it checked.
