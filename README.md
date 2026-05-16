# Bento

**Bento** is a small and partial implementation of the [Flexbox](https://developer.mozilla.org/en-US/docs/Web/CSS/Guides/Flexible_box_layout) layout, as a single header written in C99.

The aim of this library is to provide a **simple way to setup UI box elements that follow a FlexBox layout**.

The main inspiration for this library is Nic Barker's [Clay](https://github.com/nicbarker/clay) library.
There are however some differences with it such as:

* no text support
* no animation
* no scrolling containers
* the use of grow and shrink weights to handle underflow and overflow
* resizing splitter support
* no macro in public API*
* no allocations: a max number of layout elements is defined at compile time.

> (*) There is one macro: `BT_LITERAL(T, ...)` which abstracts struct initialization between C99 and C++:
> - C99: expands to `(T){ __VA_ARGS__ }` (compound literal)
> - C++: expands to `T{ __VA_ARGS__ }` (brace initialization)


## Include

Bento is a single-header library. The header contains both declarations and the implementation, guarded by a preprocessor define.

In exactly **one** translation unit, define `BT_IMPLEMENTATION` before including:

```c
#define BT_IMPLEMENTATION
#include "bento.h"
```

All other translation units include the header without the define (declarations only):

```c
#include "bento.h"
```

### Configuration macros

Optionally define these before the `#include "bento.h"`:

| Macro | Description |
|---|---|
| `BT_ASSERT` | Override the assertion macro (defaults to `assert()`). |
| `BT_DLL` | Define when using bento as a shared library (DLL). |
| `BT_DLL_BUILD` | Define when building the shared library itself (implies `BT_DLL`). |
| `BT_MAX_NUM_LAYOUT_ELEMENTS` | Compile-time cap on the number of tree nodes. Sets internal buffer sizes. |


## Concepts

Layout elements are nodes in a tree. Each element has a position (`x`, `y`) and size (`w`, `h`) computed by `bt_compute_layout()`.
<br/>The tree is built **once** at startup or when the tree structure changes (addition/removal of layout elements). The layout is recomputed **every frame**.
<br/>The layout element storage is provided by the user and must memory.
<br/>Zero-initialization is used for all API structs.

### Sizing modes (`BtAxisSizing.basis`)

| Mode | Behaviour |
|---|---|
| `BT_BASIS_AUTO` | Preferred size wraps content/children. `grow`/`shrink` control how underflow and overflow are absorbed. |
| `BT_BASIS_FIXED` | Preferred size = `value.fixed` (px). `shrink` allows compression; `grow` has no effect. |
| `BT_BASIS_PERCENT` | Preferred size = `value.percent` × parent size (without padding and gaps). `grow` and `shrink` have no effect. |

The **preferred size** is the size an element requests before underflow/overflow is resolved. For `BT_BASIS_FIXED` it is `value.fixed`; for `BT_BASIS_PERCENT` it is derived from the parent; for `BT_BASIS_AUTO` it is the element's intrinsic size (i.e. the minimum space needed to fit its children). The layout engine sums these preferred sizes and compares the total against the parent's available space to determine whether there is underflow or overflow to distribute.

**Underflow** occurs when children's preferred sizes sum to *less* than the parent's available space. The leftover space is distributed among elements that have `grow > 0`, proportionally to their `grow` weights. An element with `grow = 2` absorbs twice as much free space as one with `grow = 1`.

**Overflow** occurs when children's preferred sizes sum to *more* than the parent's available space. The excess is taken from elements that have `shrink > 0`, proportionally to their `shrink` weights. An element with `shrink = 2` gives up twice as much space as one with `shrink = 1`.

`min_max` clamps are applied after underflow/overflow is resolved: an element will never be sized below `min_max.min` or above `min_max.max` regardless of grow/shrink. Once a clamped element can no longer contribute, the remaining budget is re-distributed among the unclamped elements.

- `grow >= 0`: weight for absorbing underflow (0 = does not grow)
- `shrink >= 0`: weight for absorbing overflow (0 = does not shrink)
- `min_max.min` / `min_max.max`: pixel clamps applied after distribution (`max = 0`: unconstrained)

### Element configuration (`BtLayoutElementDesc`)

`bt_begin_layout_element()` returns a pointer to the element's `BtLayoutElementDesc`, which must be filled in before calling `bt_end_layout_element()`.

| Field | Type | Description |
|---|---|---|
| `layout_dir` | `BtLayoutDir` | Axis along which children are stacked: `BT_LAYOUT_DIR_LEFT_TO_RIGHT` or `BT_LAYOUT_DIR_TOP_TO_BOTTOM`. |
| `sizing_w` | `BtAxisSizing` | Width sizing policy (see sizing modes above). |
| `sizing_h` | `BtAxisSizing` | Height sizing policy (see sizing modes above). |
| `padding` | `BtPadding` | Per-side inner padding in pixels (`l`, `r`, `t`, `b`). Reduces the area available to children. |
| `child_gap` | `uint16_t` | Gap in pixels between consecutive children along `layout_dir`. |
| `splitter_hit_area_padding` | `uint8_t` | Extra pixels added to each side of a splitter for hover/drag detection. Does not affect layout geometry. Relevant only for splitter elements. |
| `userdata` | `void *` | Arbitrary pointer stored with the element. Not read or modified by the layout engine. |


### Splitters

A splitter element can be placed between two layout elements with `bt_splitter(...)` making them resizable.

When the user drags a splitter, its neighbour elements are converted to `BT_BASIS_FIXED` with `grow = 0` so they hold their new size on subsequent frames instead of being resized by grow/shrink; with the exception of `BT_BASIS_AUTO` elements.

`bt_can_splitter_resize(config, splitter, delta)` returns `true` if moving `splitter` by `delta` pixels would produce a non-zero actual displacement (i.e. at least one neighbour has room to give). It returns `false` when the splitter is fully blocked (both neighbours are at their `min_max` limits). This can be used visually indicate a blocked splitter during the UI rendering.


### Layout config (`BtLayoutConfig`)

`BtLayoutConfig` holds global settings passed to `bt_compute_layout()` and `bt_process_splitter_interactions()`. It is typically persisted across frames.

| Field | Type | Description |
|---|---|---|
| `grid_snapping` | `float` | Snap grid size in pixels. `0`: 1 px snapping (default). `< 0`: snapping disabled. |

Grid snapping rounds all computed sizes to the nearest multiple of `grid_snapping`. This can prevent border shimmering when resizing elements. With the default value of `0`, all sizes are rounded to the nearest integer pixel.


## Lifecycle

### Setup (once)

Declare element storage (must persist across frames):

```c
static BtLayoutElement nodes[N] = { 0 };
```

Clear existing tree links before (re-)building the tree:

```c
for (int i = 0; i < N; i++)
    bt_clear_layout_element_links(&nodes[i]);
```

Build the tree with nested begin/end pairs:

```c
BtLayoutSetupContext setup = { 0 };
bt_begin_layout(&setup);

BtLayoutElement * root = &nodes[0];
if(bt_begin_layout_element(&setup, root))
{
    root->desc.layout_dir = BT_LAYOUT_DIR_LEFT_TO_RIGHT; // or BT_LAYOUT_DIR_TOP_TO_BOTTOM
    root->desc.padding = BT_LITERAL(BtPadding, .l = 2, .r = 2, .b = 2, .t = 2);
    root->desc.child_gap = 4;

    // nest bt_begin_layout_element / bt_end_layout_element pairs here...
    // call bt_splitter() to insert a draggable resize handle between siblings

    bt_end_layout_element(&setup); // root
}

bt_end_layout(&setup);
```

The tree can be rebuilt at any time by clearing links and repeating setup.

### Update (per frame)

Compute layout and optionally handle mouse interactions with splitters.

```c
static BtLayoutConfig config = { 0 };   // persisted
BtLayoutBuildContext build = { 0 };
bt_compute_layout(&config, &build, &nodes[0], x, y, w, h);

// Optionally handle splitter interactions
static BtSplitterState splitter_state = { 0 }; // persisted
BtMouseInputs mouse = {
    .pos_x = mx, .pos_y = my,
    .delta_x = dx, .delta_y = dy,
    .pressed = lmb_pressed, .held = lmb_held, .released = lmb_released
};
bt_process_splitter_interactions(&config, &build, &splitter_state, &nodes[0], &mouse);
```

### Render (per frame)

Walk the tree and read the computed position and size from each element:

```c
void render(const BtLayoutElement * e)
{
    if(e->type == BT_LAYOUT_ELEMENT_TYPE_BOX)
        draw_panel(e->x, e->y, e->w, e->h);
    else if(e->type == BT_LAYOUT_ELEMENT_TYPE_SPLITTER)
        draw_splitter(e->x, e->y, e->w, e->h);
    for(BtLayoutElement *c = e->links.first_child; c; c = c->links.next_sibling)
        render(c);
}
```


## Examples

### 2-panel split

Left panel has a fixed width; right panel fills the remaining space.

```
+-----------+-------------------------------+
|           |                               |
|  Sidebar  |            Main               |
|  200 px   |        (fills rest)           |
|           |                               |
+-----------+-------------------------------+
```

```cpp
enum ENode
{
    ENode_Root,
    ENode_Sidebar,
    ENode_Main,

    ENode_COUNT
};

static BtLayoutElement nodes[ENode_COUNT] = { 0 };
static BtLayoutConfig  config             = { 0 };
static bool            initialized        = false;

// Setup layout (run once or when it changes)
if(!initialized)
{
    // Note: clearing the links is only needed when layout changes
    for(int i = 0; i < ENode_COUNT; i++)
        bt_clear_layout_element_links(&nodes[i]);

    BtLayoutSetupContext setup = { 0 };
    bt_begin_layout(&setup);

    BtLayoutElement * root = &nodes[ENode_Root];
    if(bt_begin_layout_element(&setup, root))
    {
        root->desc.layout_dir = BT_LAYOUT_DIR_LEFT_TO_RIGHT;
        root->desc.padding = BT_LITERAL(BtPadding, .l = 2, .r = 2, .b = 2, .t = 2);
        root->desc.child_gap = 4;

        BtLayoutElement * sidebar = &nodes[ENode_Sidebar];
        if(bt_begin_layout_element(&setup, sidebar))
        {
            sidebar->desc.sizing_w = BT_LITERAL(BtAxisSizing,
                .basis   = BT_BASIS_FIXED,
                .value   = { .fixed = 200.f },
                .min_max = { 80.f, 400.f },
                .shrink  = 1.f
            );
            sidebar->desc.sizing_h = BT_LITERAL(BtAxisSizing, .basis = BT_BASIS_AUTO, .grow = 1.f, .shrink = 1.f);
            bt_end_layout_element(&setup);
        }

        BtLayoutElement * main_panel = &nodes[ENode_Main];
        if(bt_begin_layout_element(&setup, main_panel))
        {
            main_panel->desc.sizing_w = BT_LITERAL(BtAxisSizing, .basis = BT_BASIS_AUTO, .grow = 1.f, .shrink = 1.f);
            main_panel->desc.sizing_h = BT_LITERAL(BtAxisSizing, .basis = BT_BASIS_AUTO, .grow = 1.f, .shrink = 1.f);
            bt_end_layout_element(&setup);
        }

        bt_end_layout_element(&setup); // root
    }

    bt_end_layout(&setup);

    initialized = true;
}

// Compute layout for an 800x600 canvas
{
    BtLayoutBuildContext build = { 0 };
    bt_compute_layout(&config, &build, &nodes[ENode_Root], 0.f, 0.f, 800.f, 600.f);
}
```

### 3-panel with draggable splitter

Same layout as A but with a splitter between the panels that the user can drag to resize.

```
+-----------+-+-------------------------------+
|           | |                               |
|  Sidebar  |S|            Main               |
|  200 px   | |        (fills rest)           |
|           | |                               |
+-----------+-+-------------------------------+
```

```cpp
enum ENode
{
    ENode_Root,
    ENode_Sidebar,
    ENode_Splitter,
    ENode_Main,

    ENode_COUNT
};

static BtLayoutElement nodes[ENode_COUNT] = { 0 };
static BtLayoutConfig  config             = { 0 };
static bool            initialized        = false;

// Setup layout (run once or when it changes)
if(!initialized)
{
    // Note: clearing the links is only needed when layout changes
    for(int i = 0; i < ENode_COUNT; i++)
        bt_clear_layout_element_links(&nodes[i]);

    BtLayoutSetupContext setup = { 0 };
    bt_begin_layout(&setup);

    BtLayoutElement * root = &nodes[ENode_Root];
    if(bt_begin_layout_element(&setup, root))
    {
        root->desc.layout_dir = BT_LAYOUT_DIR_LEFT_TO_RIGHT;
        root->desc.padding = BT_LITERAL(BtPadding, .l = 2, .r = 2, .b = 2, .t = 2);
        root->desc.child_gap = 4;

        BtLayoutElement * sidebar = &nodes[ENode_Sidebar];
        if(bt_begin_layout_element(&setup, sidebar))
        {
            sidebar->desc.sizing_w = BT_LITERAL(BtAxisSizing,
                .basis   = BT_BASIS_FIXED,
                .value   = { .fixed = 200.f },
                .min_max = { 80.f, 400.f },
                .shrink  = 1.f
            );
            sidebar->desc.sizing_h = BT_LITERAL(BtAxisSizing, .basis = BT_BASIS_AUTO, .grow = 1.f, .shrink = 1.f);
            bt_end_layout_element(&setup);
        }

        bt_splitter(&setup, &nodes[ENode_Splitter], 2.f, 4); // 2 px wide, 4 px hit-area padding per side

        BtLayoutElement * main_panel = &nodes[ENode_Main];
        if(bt_begin_layout_element(&setup, main_panel))
        {
            main_panel->desc.sizing_w = BT_LITERAL(BtAxisSizing, .basis = BT_BASIS_AUTO, .grow = 1.f, .shrink = 1.f);
            main_panel->desc.sizing_h = BT_LITERAL(BtAxisSizing, .basis = BT_BASIS_AUTO, .grow = 1.f, .shrink = 1.f);
            bt_end_layout_element(&setup);
        }

        bt_end_layout_element(&setup); // root
    }

    bt_end_layout(&setup);

    initialized = true;
}

// Per frame
BtLayoutBuildContext build = { 0 };
bt_compute_layout(&config, &build, &nodes[ENode_Root], viewport_x, viewport_y, viewport_w, viewport_h);

static BtSplitterState splitter_state = { 0 };
const BtMouseInputs mouse = {
    .pos_x = mx, .pos_y = my,
    .delta_x = dx, .delta_y = dy,
    .pressed = lmb_pressed, .held = lmb_held, .released = lmb_released
};
bt_process_splitter_interactions(&config, &build, &splitter_state, &nodes[ENode_Root], &mouse);
```

More examples [here](https://github.com/tcantenot/bento_examples).
