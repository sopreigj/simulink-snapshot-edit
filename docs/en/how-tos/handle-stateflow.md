# How-To: Stateflow — charts and MATLAB Function blocks

The task: the model contains Stateflow content. Two things look similar but are handled completely differently: **standalone charts** (state machines) and **MATLAB Function blocks** (function bodies).

## First, tell which one you have

| | Standalone chart (`sflib/Chart`) | MATLAB Function block |
|---|---|---|
| Content | Graphical state machine (states + transitions) | Text function body (`Script` property) |
| BlockType | `SubSystem` | `S-Function` (`sf_sfun`) |
| How content is exported | **Structured export** of State/Transition | `Script` text pulled back |

## Standalone charts: structured export (built in, you usually don't need to care)

When `snp_export` detects a standalone chart it automatically:
1. creates the block with `sflib/Chart`;
2. serializes the chart's **states** (`Name` / `LabelString`) and **transitions** (`Source` / `Destination` / `LabelString`; those without a Source are default transitions) into the snapshot one by one;
3. rebuilds them at rebuild time with `Stateflow.State` / `Stateflow.Transition` objects.

**Key detail** (if you hand-edit chart content inside the snapshot): newlines in `LabelString` are written as a literal `\n` in the snapshot, but the rebuild code **must** wrap them in `sprintf('...')` — a single-quoted literal `\n` is not restored to a real newline, and Stateflow parses the literal backslash into the state name. The generated snapshot already does this; just follow its format when you edit.

**State name takes the first line**: the Stateflow `Name` property can contain `\n` parsing residue (e.g. a label `A\nen: ...` yields the Name `A<newline>en:`), so the export takes the first line as the clean name.

## MATLAB Function blocks: Script pull-back

The content of a MATLAB Function block lives in the `Script` property of the Stateflow **EMChart**. `snp_export` collects it into a trailing section of the snapshot and writes it after `save` + `reload` — **the port signature matches the original after rebuild** (Stateflow parses the function signature and adapts the interface automatically).

Pitfall (hit in this project): the multi-line `Script` text must be written the right way — use `strjoin(lines, sprintf('\n'))` to write a real-newline char array into `rtc.Script`; `char("...\n...")` turns the multi-line string into a character matrix, of which Stateflow recognizes only the first line, and the interface gets inferred wrong.

## Editing a chart / editing a function body

- **Editing a chart's state machine** (adding states, changing transition conditions): the safest route is to edit in the GUI → pull back with `snp_pull` (the puller's block-section merge handles chart lines). Editing the chart via the XML route (tier ①) also works — editing XML requires no structural knowledge of the chart.
- **Editing a MATLAB Function block's body**: edit the corresponding Script line directly in the snapshot's trailing section, or edit in the GUI and pull.
- **`snp_patch` refuses to delete a MATLAB Function block** — its chart script section would be left dangling.

## Verification

- Chart export is verified end to end (2 states + 2 transitions including a default transition; the rebuild matches item by item, `skip=0`, no `INCOMPLETE`).
- After rebuild, compare the functional-level checksum with `snp_collab_check`, or run `test/scripts/verify_rebuild_all`.

## A useful shortcut (non-self-contained scenarios)

If the **source model is present**, `add_block('srcModel/Chart', 'dstModel/C1')` copies the chart including the whole state machine (verified: 2 states and 2 transitions all carried over); `sfclipboard` `copy` + `pasteTo` works too. This is fine for **verification or quick rebuilds**; the **self-contained snapshot `.m` function** still has to go through structured export — only the text serialization is the cross-version-portable carrier.
