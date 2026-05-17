# Bento (Zig)

**Bento** is a small Flexbox layout engine, now rewritten in **pure Zig**.

This is a port of the original C99 single-header library [tcantenot/bento](https://github.com/tcantenot/bento), featuring:

- **Zero allocations** — all storage provided by the user
- **Compile-time configurable** max element count
- **Full Zig type safety** — no C FFI, no macros
- **12 built-in unit tests** covering grow, shrink, clamp, percent, nested layouts, splitters
- **libvaxis TUI demo** included for interactive terminal visualization

## Features

| Feature | Status |
|---|---|
| Flexbox layout (LEFT_TO_RIGHT / TOP_TO_BOTTOM) | ✅ |
| Sizing modes: AUTO, FIXED, PERCENT | ✅ |
| Grow / shrink weight distribution | ✅ |
| Min/max clamping with re-distribution | ✅ |
| Draggable splitters (horizontal + vertical) | ✅ |
| Grid snapping | ✅ |
| Nested layouts | ✅ |
| Unit tests | ✅ (12 tests) |

## Quick Start

```zig
const bento = @import("bento");

var nodes = [_]bento.LayoutElement{ .{}, .{}, .{} };

// Build tree
var setup: bento.LayoutSetupContext = .{};
bento.beginLayout(&setup);

const root = &nodes[0];
if (bento.beginLayoutElement(&setup, root)) {
    root.desc.layout_dir = .left_to_right;
    root.desc.padding = .{ .l = 2, .r = 2, .t = 2, .b = 2 };
    root.desc.child_gap = 4;

    const sidebar = &nodes[1];
    if (bento.beginLayoutElement(&setup, sidebar)) {
        sidebar.desc.sizing_w = .{
            .basis = .fixed,
            .value = .{ .fixed = 200 },
            .min_max = .{ .min = 80, .max = 400 },
        };
        sidebar.desc.sizing_h = .{ .basis = .auto, .grow = 1 };
        bento.endLayoutElement(&setup);
    }

    const main = &nodes[2];
    if (bento.beginLayoutElement(&setup, main)) {
        main.desc.sizing_w = .{ .basis = .auto, .grow = 1 };
        main.desc.sizing_h = .{ .basis = .auto, .grow = 1 };
        bento.endLayoutElement(&setup);
    }

    bento.endLayoutElement(&setup);
}
bento.endLayout(&setup);

// Compute layout
var config: bento.LayoutConfig = .{};
var build: bento.LayoutBuildContext = .{};
bento.computeLayout(&config, &build, &nodes[0], 0, 0, 800, 600);

// nodes[*].x, .y, .w, .h now contain computed geometry
```

## Run the TUI Demo

```bash
zig build run
```

An interactive terminal UI with colored panels and draggable splitters.

## Run Tests

```bash
zig test src/bento.zig
```

## Configuration

Override the max element count in your `root` module:

```zig
pub const bento_max_elements = 256;
```

## API Overview

| Function | Purpose |
|---|---|
| `beginLayout` / `endLayout` | Start / finish tree setup |
| `beginLayoutElement` / `endLayoutElement` | Push / pop element in tree |
| `splitter` | Insert draggable resize handle |
| `computeLayout` | Calculate all positions and sizes |
| `processSplitterInteractions` | Handle mouse drag on splitters |
| `canSplitterResize` | Check if splitter can move by delta |
| `clearLayoutElementLinks` | Reset tree links before rebuild |

## License

MIT (same as original C library)
