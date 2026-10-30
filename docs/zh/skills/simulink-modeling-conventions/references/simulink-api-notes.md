# Simulink API Notes (verified on R2023b)

Everything below was executed on MATLAB/Simulink **R2023b** while writing this skill. Where current MathWorks documentation (R2026b) disagrees with R2023b behaviour, the R2023b behaviour is stated and the discrepancy flagged.

> 体例说明：API 摘要保留英文原文（便于与 MathWorks 文档对照），部分实测笔记（如 arrangeSystem/routeLine 边界段）用中文书写——那是写作时的实测记录，结论与英文段落同等有效。

---

## Coordinate system

`Position` is `[left top right bottom]`.

- Origin is the **upper-left** of the canvas.
- x grows right, y grows **downward**.
- Negative values are legal (content may sit above/left of origin).
- Width `= p(3)-p(1)`, height `= p(4)-p(2)`.

```matlab
p = get_param(blk, 'Position');
width  = p(3) - p(1);
height = p(4) - p(2);
```

Helper to move/resize from derivatives, rather than retyping literals:

```matlab
p = get_param(blk,'Position');
w = p(3)-p(1);
set_param(blk,'Position', p + [-3*w 0 -3*w 0]);   % left by 3 widths
```

---

## Simulink.BlockDiagram.arrangeSystem

```matlab
Simulink.BlockDiagram.arrangeSystem(bd)
Simulink.BlockDiagram.arrangeSystem(bd, FullLayout=tf)
```

- Introduced **R2018a**. Equivalent to the *Auto Arrange* button.
- Realigns, resizes, and moves blocks; straightens signal lines.
- **Invalidates signal-line handles** on every call. Re-query afterwards.
- If the model is *open*, also zooms to fit. If only *loaded*, layout changes but zoom does not.
- `bd` accepts a model name, a subsystem path, or a handle. Given a subsystem path it arranges only that subsystem's interior; the parent is untouched.

> **R2023b deviation:** `FullLayout` must be a char/string — `'true'` or `'false'`. Passing logical `true` raises `参数 4 (Value)的输入无效: 值必须为字符向量或字符串标量` (invalid input for parameter 4; value must be a char vector or string scalar).

What it gets wrong (fix afterwards):

- `Sum` blocks get stretched into ellipses.
- Icon-only blocks can end up too narrow to render their value (`-K-`).
- Annotations are moved.
- Port order is never changed.

---

## Simulink.BlockDiagram.routeLine

```matlab
Simulink.BlockDiagram.routeLine(lines)          % numeric array of line handles
Simulink.BlockDiagram.routeLine('DeferredLines')
```

- Introduced **R2019a**.
- Routes so lines avoid overlapping with other lines, blocks, and annotations.
- **Requires empty canvas.** If there is no free space it may simply not improve anything — it does not error, it just does little. Leave margins.
- Can take minutes on models with many lines.
- The `'DeferredLines'` form flushes work deferred by `set_param(0,'LineUpdate','deferred')`. All three conditions must hold:
  1. `LineUpdate` is `'deferred'`
  2. the script changed line layout before this call
  3. if the script saved the model, the save happened *before* this call

Deferral pattern:

```matlab
set_param(0, 'LineUpdate', 'deferred');
% ... build / reposition ...
save_system(mdl);                          % optional, must precede the flush
Simulink.BlockDiagram.routeLine('DeferredLines');
set_param(0, 'LineUpdate', 'immediate');
```

> **R2023b:** `Simulink.BlockDiagram.resizeBlocksToFitContent` **does not exist** in R2023b (`类 Simulink.BlockDiagram 没有名为'resizeBlocksToFitContent' 的常量属性或静态方法`). It appears in current docs (R2026b). On R2023b, widen blocks manually:

```matlab
function widen(blk, dw)
  p = get_param(blk,'Position'); p(3) = p(3)+dw;
  set_param(blk,'Position',p);
end
```

The block types that display a parameter on the icon (and therefore need width) are: Constant, String Constant, Gain, Goto, From, Data Store Read, Data Store Write, Scan String.

---

## Simulink.Annotation

```matlab
a = Simulink.Annotation(sys, name)            % name becomes the displayed text
a = Simulink.Annotation(path, Name, Value)    % path = 'model/annotationName'
```

### The name *is* the text

`a.Name` and `a.Text` are the same property — both alias the displayed text. Consequences:

- Creating `Simulink.Annotation([mdl '/note_sumAlpha'])` renders the literal string `note_sumAlpha` on the diagram.
- You cannot use the annotation name as an internal identifier.
- To track an annotation, hold the object in a variable, use `Tag`, or resolve it later with `find_system(mdl,'FindAll','on','Type','annotation')` and match on position/text.

### Position is a minimum unless you fix the size

```matlab
a.Position = [10 10 200 40];
% → reads back [10 10 57 25]  (snapped to fit text)
```

```matlab
a.FixedWidth  = 'on';
a.FixedHeight = 'on';
a.Position = [10 10 200 40];
% → reads back [10 10 200 40]
```

**Order matters: set the fixed flags before `Position`.**

### Properties that matter for layout

| Property | Values | Note |
|---|---|---|
| `Position` | `[l t r b]` | min-size unless fixed |
| `FixedWidth` / `FixedHeight` | `'on'`/`'off'` | set before `Position` |
| `Text` / `Name` | char/string | identical aliases |
| `Interpreter` | `'off'` / `'rich'` / `'tex'` | `'rich'` for bold-inline |
| `FontName` | `'auto'` or font name | plain text only |
| `FontSize` | `-1` (auto) or points | plain text only |
| `FontWeight` | `'auto'`/`'normal'`/`'bold'`/`'light'`/`'demi'` | |
| `FontAngle` | `'auto'`/`'normal'`/`'italic'`/`'oblique'` | |
| `HorizontalAlignment` | `'left'`/`'center'`/`'right'` | |
| `VerticalAlignment` | `'top'`/`'middle'`/`'bottom'`/`'cap'`/`'baseline'` | |
| `BackgroundColor` | `'white'`, `'automatic'` (transparent), RGB | |
| `ForegroundColor` | `'black'`, RGB | |
| `DropShadow` | `'off'`/`'on'` | |
| `AnnotationType` | **read-only**: `'note_annotation'`/`'area_annotation'`/`'image_annotation'` | |
| `InternalMargins` | `[0 0 0 0]` | |

`AnnotationType` is **read-only** on R2023b — assigning it errors with `参数 'AnnotationType' 为只读`. You cannot promote a note to an area annotation after creation.

### Creating an area annotation

Not achievable via `AnnotationType` on R2023b. `add_block('built-in/Area', ...)` creates a block-shaped object that still reports `note_annotation`. For a visually grouped region, the reliable approach is a note annotation with a background colour and `FixedWidth`/`FixedHeight`:

```matlab
a = Simulink.Annotation([mdl '/grp']);
a.Name = 'Current loop';
a.BackgroundColor = [0.93 0.96 1.00];
a.FixedWidth = 'on'; a.FixedHeight = 'on';
a.Position = [20 60 420 260];
```

### Enumerating annotations

```matlab
hAnno = find_system(mdl, 'FindAll','on', 'Type','annotation');
get_param(hAnno, 'Name')
get_param(hAnno, 'Position')
```

`set_param(handle,'Position',...)` works on annotation handles too, and shares the same minimum-size rule.

---

## get_param / set_param

```matlab
value = get_param(obj, 'ParamName')
set_param(obj, Param1=Value1, ..., ParamN=ValueN)
```

- `obj` may be a model name/handle, block path/handle, line handle, port handle.
- Setting multiple parameters in **one** `set_param` call is faster and atomic: if any name/value is invalid, nothing is set.
- `set_param` dirties the model even when the value is unchanged.

### Discover the allowed values of a parameter

```matlab
get_param(blk, 'options@IconShape')      % e.g. {'rectangular'} {'round'}
get_param(blk, 'options@OutputSignalType')
```

### Batch reads return cell arrays

```matlab
p = cell2mat(get_param(handlesInVector, 'Position'));   % N×4
set_param(handlesInVector, 'Position', ... )            % not valid per-row
```

For per-element writes, loop or `arrayfun`:

```matlab
myFun = @(i) set_param(h(i), 'Position', p(i,:));
arrayfun(myFun, 1:numel(h));
```

### Layout-relevant parameters

| Param | On | Meaning |
|---|---|---|
| `Position` | block/annotation | `[l t r b]` |
| `NamePlacement` | block | `'normal'` = name below |
| `ShowName` | block | `'on'`/`'off'` |
| `Orientation` | block | `'Right'`(default)/`'Left'`/`'Up'`/`'Down'` |
| `IconShape` | Sum/Product etc. | `'rectangular'`/`'round'` |
| `Inputs` | Sum | `'++'`, `'+-'`, `'|++'` (bar = rectangular) |
| `Ports` | block | `[in out enable trigger state lconn rconn ifaction reset event]` |
| `PortHandles` | block | struct of port handles |
| `LineHandles` | block | struct: `.Inport`/`.Outport` line handles |
| `Points` | line | N×2 vertices |
| `LineParent` | line | handle of parent segment, `-1` if root |
| `SrcPortHandle`/`DstPortHandle` | line | port handles (Dst is an array on fan-out) |
| `Name` | line | signal label |
| `DefaultBlockFontName` | model | default font |
| `DefaultBlockFontSize` | model | default size |
| `LineUpdate` | **root (`0`)** | `'immediate'`/`'deferred'` |

### arrangeSystem / routeLine 的实测边界

文档说它们"改进布局"，但在含反馈回路的成熟模型上**实测无效甚至更差**（同一份代码同一份输入）：`arrangeSystem` 把横图压成竖图、交叉数不降反升；网格重排 + 拓扑深度分层、网格重排 + 保留原分层等策略交叉数都是原图的数倍。

根因：模型有结构性跨列回授（角度前馈、转速环进电流环这一类长距离反馈边），层次布局算法假设图接近 DAG，带级联回授的控制系统不是。且 `routeLine` 需要空白画布腾挪，块挤满时它一条线都不改。

**结论：几何排版只能人工改 `build_*.m` 里的 `Position`。**这两个 API 仍可用于"新建模型后的第一次粗略排列"（比手工摆占位坐标强），但不要期待它们能排好一个已成熟的模型。

## `Position` quirks

- `Sum` with `IconShape='round'` renders **elliptical** unless the box is square.
- R2023b **snaps a Sum to a 40x40 minimum**. Requesting 32x32 or 34x34 reads back as 40x40 (verified). 40x40 is square, so the circle still comes out right — but do not assume the size you asked for. Always read `Position` back and judge by `w == h`, not by the literal you passed.

  ```matlab
  set_param(blk,'IconShape','round');
  p = get_param(blk,'Position');
  cx = (p(1)+p(3))/2; cy = (p(2)+p(4))/2;
  set_param(blk,'Position',[cx-20 cy-20 cx+20 cy+20]);  % 40x40 survives the snap
  p = get_param(blk,'Position');
  assert(p(3)-p(1) == p(4)-p(2));                        % verify square
  ```
- Flip/rotate via `Orientation` does **not** mirror the block *icon* — it only repositions ports and the name. Documentation is explicit about this.

---

## Signal lines: structure

A fan-out is **one logical line with many destinations**, represented as a parent plus child segments:

```matlab
lh = get_param(blk,'LineHandles');       % lh.Outport = parent line handle
get_param(lh.Outport,'DstPortHandle')    % array — one entry per destination
get_param(lh.Outport,'Points')           % parent vertices only
```

Child ("branch") segments appear as separate entries in `find_system(sys,'FindAll','on','Type','line')` and carry a non-`-1` `LineParent`. To enumerate every segment:

```matlab
allLines = find_system(mdl,'FindAll','on','SearchDepth',1,'Type','line');
```

### Manually setting `Points`

`set_param(lineH,'Points',newPts)` **is** supported (verified). Supplying a 3-point path where 2 existed adds a bend, though Simulink may split your 3 points into 4:

```matlab
set_param(lineH,'Points',[155 110; 165 80; 205 110; 215 110]);
```

Use sparingly — `routeLine` is the supported path. Manual `Points` is an escape hatch, and any subsequent arrange/route will overwrite it.

---

## Fonts

```matlab
set_param(mdl, 'DefaultBlockFontName', 'Microsoft YaHei');
set_param(mdl, 'DefaultBlockFontSize', '10');
```

The defaults apply to **newly created** blocks; existing blocks keep their own `FontName`/`FontSize`, so apply per block when retrofitting:

```matlab
blks = find_system(mdl,'LookUnderMasks','all','FollowLinks','off','Type','block');
for i = 1:numel(blks)
  try
    set_param(blks{i}, 'FontName','Microsoft YaHei', 'FontSize','10');
  catch
  end
end
```

Some blocks (e.g. Stateflow charts, certain masked blocks) reject font parameters — wrap in `try`.

---

## Rendering a check image

```matlab
print(['-s' mdl], '-dpng', '-r60', 'layout_check.png');
```

Prints the system named `mdl` without opening a figure. Do not call `print('-s', mdl, ...)` with a separate `-s` argument — `-s<name>` is one token.
