//! Bento - Zig port of the Flexbox layout library
//! Single-file pure Zig implementation, no allocations, compile-time max elements.

const std = @import("std");

/// Compile-time configurable max elements. Override before importing:
/// `pub const bento_max_elements = 256;` then `@import("bento").config_max`
pub const config_max = if (@hasDecl(@import("root"), "bento_max_elements"))
    @import("root").bento_max_elements
else
    64;
pub const EPSILON: f32 = 0.0001;

/// Axis along which children are laid out.
pub const LayoutDir = enum {
    left_to_right,
    top_to_bottom,
};

/// Determines how an element's preferred size (flex-basis) is computed.
pub const Basis = enum {
    /// Content-based (wrap children).
    auto,
    /// Explicit size in pixels.
    fixed,
    /// Fraction [0,1] of parent available size.
    percent,
};

/// Per-side inner padding in pixels. Reduces area available to children.
pub const Padding = struct {
    l: u16 = 0,
    r: u16 = 0,
    t: u16 = 0,
    b: u16 = 0,
};

/// Pixel clamps applied after grow/shrink distribution.
/// `max = 0` means unconstrained.
pub const MinMax = struct {
    min: f32 = 0,
    max: f32 = 0,
};

/// Sizing policy for one axis.
pub const AxisSizing = struct {
    /// How the preferred size is computed.
    basis: Basis = .auto,
    /// Preferred size value (interpreted according to `basis`).
    value: union {
        fixed: f32,
        percent: f32,
    } = .{ .fixed = 0 },
    /// Clamps applied after distribution.
    min_max: MinMax = .{},
    /// Weight for absorbing underflow (0 = does not grow).
    grow: f32 = 0,
    /// Weight for absorbing overflow (0 = does not shrink).
    shrink: f32 = 0,
};

/// Element configuration. Must be filled before calling `endLayoutElement`.
pub const LayoutElementDesc = struct {
    /// Axis along which children are stacked.
    layout_dir: LayoutDir = .left_to_right,
    /// Width sizing policy.
    sizing_w: AxisSizing = .{},
    /// Height sizing policy.
    sizing_h: AxisSizing = .{},
    /// Per-side inner padding.
    padding: Padding = .{},
    /// Gap between consecutive children along `layout_dir`.
    child_gap: u16 = 0,
    /// Extra pixels for splitter hover/drag detection.
    splitter_hit_area_padding: u8 = 0,
    /// Arbitrary pointer. Not read by the layout engine.
    userdata: ?*anyopaque = null,
};

/// Element type.
pub const LayoutElementType = enum {
    box,
    splitter,
};

/// Tree links for an element.
pub const LayoutElementLinks = struct {
    parent: ?*LayoutElement = null,
    first_child: ?*LayoutElement = null,
    prev_sibling: ?*LayoutElement = null,
    next_sibling: ?*LayoutElement = null,
};

/// Layout element node. The tree is built once and recomputed every frame.
/// Position and size are written by `computeLayout`.
pub const LayoutElement = struct {
    desc: LayoutElementDesc = .{},
    links: LayoutElementLinks = .{},
    type: LayoutElementType = .box,
    /// Computed horizontal position.
    x: f32 = 0,
    /// Computed vertical position.
    y: f32 = 0,
    /// Computed width.
    w: f32 = 0,
    /// Computed height.
    h: f32 = 0,
};

/// Global layout settings passed to `computeLayout`.
pub const LayoutConfig = struct {
    /// Snap grid size. `0` = 1px snapping (default). `< 0` = disabled.
    grid_snapping: f32 = 0,
};

/// Context used while building the element tree.
pub const LayoutSetupContext = struct {
    layout_elements_stack: LayoutElementBuffer = .{},
};

/// Context used while computing layout.
pub const LayoutBuildContext = struct {
    // internal state if needed
};

/// Tracks which splitter element is hovered or being dragged.
pub const SplitterState = struct {
    active_splitter: ?*LayoutElement = null,
    hovered: bool = false,
    dragged: bool = false,
};

/// Mouse state for splitter interactions.
pub const MouseInputs = struct {
    pos_x: f32,
    pos_y: f32,
    delta_x: f32,
    delta_y: f32,
    pressed: bool,
    held: bool,
    released: bool,
};

const LayoutElementBuffer = struct {
    data: [config_max]*LayoutElement = undefined,
    count: usize = 0,
};

// Internal stack helpers
fn stackClear(buf: *LayoutElementBuffer) void {
    buf.count = 0;
}

fn stackPush(buf: *LayoutElementBuffer, e: *LayoutElement) void {
    std.debug.assert(buf.count < config_max);
    buf.data[buf.count] = e;
    buf.count += 1;
}

fn stackPop(buf: *LayoutElementBuffer) *LayoutElement {
    std.debug.assert(buf.count > 0);
    buf.count -= 1;
    return buf.data[buf.count];
}

fn stackPeek(buf: *const LayoutElementBuffer) *LayoutElement {
    std.debug.assert(buf.count > 0);
    return buf.data[buf.count - 1];
}

fn stackIsEmpty(buf: *const LayoutElementBuffer) bool {
    return buf.count == 0;
}

fn arrayClear(buf: *LayoutElementBuffer) void {
    buf.count = 0;
}

fn arrayAdd(buf: *LayoutElementBuffer, e: *LayoutElement) void {
    std.debug.assert(buf.count < config_max);
    buf.data[buf.count] = e;
    buf.count += 1;
}

// ========================
// Public API
// ========================

/// Reset all tree links on an element. Call before rebuilding the tree.
pub fn clearLayoutElementLinks(e: *LayoutElement) void {
    e.links = .{};
}

/// Start building a new layout tree. Call once at the start of setup.
pub fn beginLayout(ctx: *LayoutSetupContext) void {
    stackClear(&ctx.layout_elements_stack);
}

/// Finish layout tree setup. Call once at the end of setup.
pub fn endLayout(_: *LayoutSetupContext) void {
    // nothing for now
}

/// Start defining a new layout element. Push it onto the setup stack.
/// Returns `true` on success.
pub fn beginLayoutElement(ctx: *LayoutSetupContext, e: *LayoutElement) bool {
    if (stackIsEmpty(&ctx.layout_elements_stack)) {
        // root
        stackPush(&ctx.layout_elements_stack, e);
        return true;
    }

    const parent = stackPeek(&ctx.layout_elements_stack);
    e.links.parent = parent;
    e.links.prev_sibling = null;
    e.links.next_sibling = null;

    if (parent.links.first_child == null) {
        parent.links.first_child = e;
    } else {
        var last = parent.links.first_child.?;
        while (last.links.next_sibling) |next| {
            last = next;
        }
        last.links.next_sibling = e;
        e.links.prev_sibling = last;
    }

    stackPush(&ctx.layout_elements_stack, e);
    return true;
}

/// Finish defining the current layout element. Pop it from the setup stack.
pub fn endLayoutElement(ctx: *LayoutSetupContext) void {
    _ = stackPop(&ctx.layout_elements_stack);
}

/// Insert a draggable splitter element between siblings.
/// `size` is the thickness in pixels (width or height depending on parent direction).
/// `hit_padding` is the extra detection area on each side.
pub fn splitter(ctx: *LayoutSetupContext, e: *LayoutElement, size: f32, hit_padding: u8) void {
    e.type = .splitter;
    e.desc.splitter_hit_area_padding = hit_padding;

    // Determine orientation from parent layout direction
    var is_horizontal = true;
    if (!stackIsEmpty(&ctx.layout_elements_stack)) {
        const parent = stackPeek(&ctx.layout_elements_stack);
        is_horizontal = parent.desc.layout_dir == .left_to_right;
    }

    if (is_horizontal) {
        e.desc.sizing_w = AxisSizing{
            .basis = .fixed,
            .value = .{ .fixed = size },
            .grow = 0,
            .shrink = 0,
        };
        e.desc.sizing_h = AxisSizing{ .basis = .auto, .grow = 1, .shrink = 1 };
    } else {
        e.desc.sizing_w = AxisSizing{ .basis = .auto, .grow = 1, .shrink = 1 };
        e.desc.sizing_h = AxisSizing{
            .basis = .fixed,
            .value = .{ .fixed = size },
            .grow = 0,
            .shrink = 0,
        };
    }

    if (!stackIsEmpty(&ctx.layout_elements_stack)) {
        const parent = stackPeek(&ctx.layout_elements_stack);
        e.links.parent = parent;

        if (parent.links.first_child == null) {
            parent.links.first_child = e;
        } else {
            var last = parent.links.first_child.?;
            while (last.links.next_sibling) |next| last = next;
            last.links.next_sibling = e;
            e.links.prev_sibling = last;
        }
    }
}

// Core layout computation (ported logic)

fn computePreferredSize(e: *LayoutElement, parent_w: f32, parent_h: f32, dir: LayoutDir) f32 {
    const sizing = if (dir == .left_to_right) e.desc.sizing_w else e.desc.sizing_h;
    const padding = e.desc.padding;

    var preferred: f32 = 0;

    switch (sizing.basis) {
        .fixed => preferred = sizing.value.fixed,
        .percent => {
            const parent_avail = if (dir == .left_to_right) parent_w else parent_h;
            preferred = sizing.value.percent * parent_avail;
        },
        .auto => {
            var child = e.links.first_child;
            var total: f32 = 0;
            var first = true;
            while (child) |ch| {
                if (!first) total += @floatFromInt(e.desc.child_gap);
                first = false;
                const ch_dir = e.desc.layout_dir;
                // Recurse with current parent available size
                const ch_size = computePreferredSize(ch, parent_w, parent_h, ch_dir);
                total += ch_size;
                child = ch.links.next_sibling;
            }
            preferred = total;
        },
    }

    // Add padding on the current axis
    if (dir == .left_to_right) {
        preferred += @floatFromInt(padding.l + padding.r);
    } else {
        preferred += @floatFromInt(padding.t + padding.b);
    }

    return preferred;
}

fn distributeUnderflowOverflow(_: *LayoutElement, children: [] *LayoutElement, total_preferred: f32, available: f32, dir: LayoutDir) void {
    const is_underflow = total_preferred < available - EPSILON;
    const is_overflow = total_preferred > available + EPSILON;

    if (!is_underflow and !is_overflow) return;

    const budget = if (is_underflow) available - total_preferred else total_preferred - available;
    var total_weight: f32 = 0;

    for (children) |ch| {
        const s = if (dir == .left_to_right) ch.desc.sizing_w else ch.desc.sizing_h;
        total_weight += if (is_underflow) s.grow else s.shrink;
    }

    if (total_weight <= 0) return;

    // Multi-pass distribution with clamp and re-distribution
    var clamped = [_]bool{false} ** config_max;
    var remaining_budget = budget;
    var pass: usize = 0;

    while (pass < children.len and @abs(remaining_budget) > EPSILON) : (pass += 1) {
        var remaining_weight: f32 = 0;
        for (children, 0..) |ch, i| {
            if (clamped[i]) continue;
            const s = if (dir == .left_to_right) ch.desc.sizing_w else ch.desc.sizing_h;
            const weight = if (is_underflow) s.grow else s.shrink;
            if (weight > 0) remaining_weight += weight;
        }

        if (remaining_weight <= 0) break;

        // First, compute all deltas for this pass
        var deltas: [config_max]f32 = undefined;
        for (children, 0..) |ch, i| {
            if (clamped[i]) {
                deltas[i] = 0;
                continue;
            }
            const s = if (dir == .left_to_right) ch.desc.sizing_w else ch.desc.sizing_h;
            const weight = if (is_underflow) s.grow else s.shrink;
            if (weight <= 0) {
                deltas[i] = 0;
                continue;
            }
            deltas[i] = remaining_budget * (weight / remaining_weight);
        }

        // Then apply them
        for (children, 0..) |ch, i| {
            if (clamped[i]) continue;
            const s = if (dir == .left_to_right) &ch.desc.sizing_w else &ch.desc.sizing_h;
            const delta = deltas[i];
            if (delta == 0) continue;

            if (dir == .left_to_right) {
                const before = ch.w;
                if (is_underflow) ch.w += delta else ch.w -= delta;
                const mm = s.min_max;
                if (mm.max > 0 and ch.w > mm.max) {
                    ch.w = mm.max;
                    clamped[i] = true;
                } else if (ch.w < mm.min) {
                    ch.w = mm.min;
                    clamped[i] = true;
                }
                remaining_budget -= if (is_underflow) (ch.w - before) else (before - ch.w);
            } else {
                const before = ch.h;
                if (is_underflow) ch.h += delta else ch.h -= delta;
                const mm = s.min_max;
                if (mm.max > 0 and ch.h > mm.max) {
                    ch.h = mm.max;
                    clamped[i] = true;
                } else if (ch.h < mm.min) {
                    ch.h = mm.min;
                    clamped[i] = true;
                }
                remaining_budget -= if (is_underflow) (ch.h - before) else (before - ch.h);
            }
        }
    }
}

fn computeLayoutRecursive(e: *LayoutElement, x: f32, y: f32, w: f32, h: f32) void {
    e.x = x;
    e.y = y;
    e.w = w;
    e.h = h;

    if (e.type == .splitter) return;

    const pad = e.desc.padding;
    const inner_w = w - @as(f32, @floatFromInt(pad.l + pad.r));
    const inner_h = h - @as(f32, @floatFromInt(pad.t + pad.b));

    // Collect children
    var children: [config_max]*LayoutElement = undefined;
    var child_count: usize = 0;
    var child = e.links.first_child;
    while (child) |ch| {
        children[child_count] = ch;
        child_count += 1;
        child = ch.links.next_sibling;
    }
    if (child_count == 0) return;

    const dir = e.desc.layout_dir;
    const gap: f32 = @floatFromInt(e.desc.child_gap);
    const total_gap = if (child_count > 1) gap * @as(f32, @floatFromInt(child_count - 1)) else 0;

    // Preferred sizes (first pass)
    var total_preferred: f32 = 0;
    for (children[0..child_count]) |ch| {
        const pref = computePreferredSize(ch, inner_w, inner_h, dir);
        if (dir == .left_to_right) {
            ch.w = pref;
            total_preferred += pref;
        } else {
            ch.h = pref;
            total_preferred += pref;
        }
    }
    total_preferred += total_gap;

    const available = if (dir == .left_to_right) inner_w else inner_h;

    // Distribute extra / shrink
    distributeUnderflowOverflow(e, children[0..child_count], total_preferred, available, dir);

    // Compute cross-axis sizes for all children
    for (children[0..child_count]) |ch| {
        const cross_sizing = if (dir == .left_to_right) ch.desc.sizing_h else ch.desc.sizing_w;
        const cross_inner = if (dir == .left_to_right) inner_h else inner_w;
        const cross_padding = if (dir == .left_to_right)
            @as(f32, @floatFromInt(ch.desc.padding.t + ch.desc.padding.b))
        else
            @as(f32, @floatFromInt(ch.desc.padding.l + ch.desc.padding.r));

        var cross_size: f32 = switch (cross_sizing.basis) {
            .fixed => cross_sizing.value.fixed + cross_padding,
            .percent => cross_sizing.value.percent * cross_inner + cross_padding,
            .auto => cross_inner, // fill available in cross axis
        };

        // Apply grow/shrink on cross axis (simplified: fill available)
        if (cross_sizing.basis == .auto) {
            cross_size = cross_inner;
        }

        // Clamp
        const mm = cross_sizing.min_max;
        if (mm.max > 0 and cross_size > mm.max) cross_size = mm.max;
        if (cross_size < mm.min) cross_size = mm.min;

        if (dir == .left_to_right) {
            ch.h = cross_size;
        } else {
            ch.w = cross_size;
        }
    }

    // Position children
    var current: f32 = if (dir == .left_to_right) @as(f32, @floatFromInt(pad.l)) else @as(f32, @floatFromInt(pad.t));
    for (children[0..child_count], 0..) |ch, i| {
        if (dir == .left_to_right) {
            computeLayoutRecursive(ch, x + current, y + @as(f32, @floatFromInt(pad.t)), ch.w, ch.h);
            current += ch.w + if (i < child_count - 1) gap else 0;
        } else {
            computeLayoutRecursive(ch, x + @as(f32, @floatFromInt(pad.l)), y + current, ch.w, ch.h);
            current += ch.h + if (i < child_count - 1) gap else 0;
        }
    }
}

/// Compute the layout for the entire tree rooted at `root`.
/// Writes computed `x`, `y`, `w`, `h` into every element.
pub fn computeLayout(config: *const LayoutConfig, _: *LayoutBuildContext, root: *LayoutElement, x: f32, y: f32, w: f32, h: f32) void {
    computeLayoutRecursive(root, x, y, w, h);

    // Grid snapping
    if (config.grid_snapping > 0) {
        applyGridSnap(root, config.grid_snapping);
    } else if (config.grid_snapping == 0) {
        // default 1px snap
        applyGridSnap(root, 1.0);
    }
}

fn applyGridSnap(e: *LayoutElement, snap: f32) void {
    e.x = @round(e.x / snap) * snap;
    e.y = @round(e.y / snap) * snap;
    e.w = @round(e.w / snap) * snap;
    e.h = @round(e.h / snap) * snap;

    var child = e.links.first_child;
    while (child) |ch| {
        applyGridSnap(ch, snap);
        child = ch.links.next_sibling;
    }
}

fn getSplitterAxis(e: *LayoutElement) LayoutDir {
    const parent = e.links.parent orelse return .left_to_right;
    return parent.desc.layout_dir;
}

fn applySplitterResize(e: *LayoutElement, delta: f32) void {
    const prev = e.links.prev_sibling orelse return;
    const next = e.links.next_sibling orelse return;
    const axis = getSplitterAxis(e);

    const prev_sizing = if (axis == .left_to_right) &prev.desc.sizing_w else &prev.desc.sizing_h;
    const next_sizing = if (axis == .left_to_right) &next.desc.sizing_w else &next.desc.sizing_h;

    if (prev_sizing.basis != .fixed or next_sizing.basis != .fixed) return;

    // Clamp delta so neighbors stay within min_max
    var clamped_delta = delta;

    if (axis == .left_to_right) {
        if (delta > 0) {
            // prev grows, next shrinks
            const prev_room = if (prev_sizing.min_max.max > 0) prev_sizing.min_max.max - prev_sizing.value.fixed else std.math.inf(f32);
            const next_room = next_sizing.value.fixed - next_sizing.min_max.min;
            clamped_delta = @min(delta, @min(prev_room, next_room));
        } else {
            // prev shrinks, next grows
            const prev_room = prev_sizing.value.fixed - prev_sizing.min_max.min;
            const next_room = if (next_sizing.min_max.max > 0) next_sizing.min_max.max - next_sizing.value.fixed else std.math.inf(f32);
            clamped_delta = @max(delta, -@min(prev_room, next_room));
        }
    } else {
        if (delta > 0) {
            const prev_room = if (prev_sizing.min_max.max > 0) prev_sizing.min_max.max - prev_sizing.value.fixed else std.math.inf(f32);
            const next_room = next_sizing.value.fixed - next_sizing.min_max.min;
            clamped_delta = @min(delta, @min(prev_room, next_room));
        } else {
            const prev_room = prev_sizing.value.fixed - prev_sizing.min_max.min;
            const next_room = if (next_sizing.min_max.max > 0) next_sizing.min_max.max - next_sizing.value.fixed else std.math.inf(f32);
            clamped_delta = @max(delta, -@min(prev_room, next_room));
        }
    }

    prev_sizing.value.fixed += clamped_delta;
    next_sizing.value.fixed -= clamped_delta;
}

/// Process mouse input for splitter drag/resize.
/// Updates `state` and modifies neighbour sizing policies in place.
pub fn processSplitterInteractions(
    _: *const LayoutConfig,
    _: *LayoutBuildContext,
    state: *SplitterState,
    root: *LayoutElement,
    mouse: *const MouseInputs,
) void {
    if (mouse.pressed or mouse.held) {
        // Find splitter under mouse
        var current: ?*LayoutElement = root;
        while (current) |cur| {
            if (cur.type == .splitter) {
                const axis = getSplitterAxis(cur);
                const hit_padding = @as(f32, @floatFromInt(cur.desc.splitter_hit_area_padding));
                const in_hit_area = if (axis == .left_to_right)
                    (mouse.pos_x >= cur.x - hit_padding and mouse.pos_x <= cur.x + cur.w + hit_padding)
                else
                    (mouse.pos_y >= cur.y - hit_padding and mouse.pos_y <= cur.y + cur.h + hit_padding);

                if (in_hit_area) {
                    state.active_splitter = cur;
                    state.dragged = mouse.held;

                    // Convert neighbors to FIXED on first drag
                    if (mouse.pressed and cur.links.prev_sibling != null) {
                        const prev = cur.links.prev_sibling.?;
                        const prev_w_sizing = &prev.desc.sizing_w;
                        const prev_h_sizing = &prev.desc.sizing_h;
                        if (axis == .left_to_right) {
                            if (prev_w_sizing.basis == .auto or prev_w_sizing.basis == .percent) {
                                prev_w_sizing.basis = .fixed;
                                prev_w_sizing.value = .{ .fixed = prev.w };
                                prev_w_sizing.grow = 0;
                            }
                        } else {
                            if (prev_h_sizing.basis == .auto or prev_h_sizing.basis == .percent) {
                                prev_h_sizing.basis = .fixed;
                                prev_h_sizing.value = .{ .fixed = prev.h };
                                prev_h_sizing.grow = 0;
                            }
                        }
                        if (cur.links.next_sibling) |next| {
                            const next_w_sizing = &next.desc.sizing_w;
                            const next_h_sizing = &next.desc.sizing_h;
                            if (axis == .left_to_right) {
                                if (next_w_sizing.basis == .auto or next_w_sizing.basis == .percent) {
                                    next_w_sizing.basis = .fixed;
                                    next_w_sizing.value = .{ .fixed = next.w };
                                    next_w_sizing.grow = 0;
                                }
                            } else {
                                if (next_h_sizing.basis == .auto or next_h_sizing.basis == .percent) {
                                    next_h_sizing.basis = .fixed;
                                    next_h_sizing.value = .{ .fixed = next.h };
                                    next_h_sizing.grow = 0;
                                }
                            }
                        }
                    }

                    // Apply delta during drag
                    if (mouse.held) {
                        const delta = if (axis == .left_to_right) mouse.delta_x else mouse.delta_y;
                        applySplitterResize(cur, delta);
                    }
                    break;
                }
            }
            current = cur.links.first_child;
        }
    } else if (mouse.released) {
        state.dragged = false;
        state.active_splitter = null;
    }
}

/// Returns `true` if moving `splitter` by `delta` pixels would produce
/// a non-zero actual displacement (i.e. at least one neighbour has room).
pub fn canSplitterResize(_: *const LayoutConfig, _: *LayoutBuildContext, e: *LayoutElement, delta: f32) bool {
    const prev = e.links.prev_sibling orelse return false;
    const next = e.links.next_sibling orelse return false;
    const axis = getSplitterAxis(e);

    const prev_sizing = if (axis == .left_to_right) prev.desc.sizing_w else prev.desc.sizing_h;
    const next_sizing = if (axis == .left_to_right) next.desc.sizing_w else next.desc.sizing_h;

    var can_move = false;

    if (delta > 0) {
        if (prev_sizing.basis == .fixed) {
            const new_prev = prev_sizing.value.fixed + delta;
            if (prev_sizing.min_max.max == 0 or new_prev <= prev_sizing.min_max.max) can_move = true;
        } else if (prev_sizing.grow > 0) {
            can_move = true;
        }
        if (next_sizing.basis == .fixed) {
            const new_next = next_sizing.value.fixed - delta;
            if (new_next >= next_sizing.min_max.min) can_move = true;
        } else if (next_sizing.shrink > 0) {
            can_move = true;
        }
    } else if (delta < 0) {
        if (prev_sizing.basis == .fixed) {
            const new_prev = prev_sizing.value.fixed + delta;
            if (new_prev >= prev_sizing.min_max.min) can_move = true;
        } else if (prev_sizing.shrink > 0) {
            can_move = true;
        }
        if (next_sizing.basis == .fixed) {
            const new_next = next_sizing.value.fixed - delta;
            if (next_sizing.min_max.max == 0 or new_next <= next_sizing.min_max.max) can_move = true;
        } else if (next_sizing.grow > 0) {
            can_move = true;
        }
    }

    return can_move;
}

// ========================
// Tests
// ========================

test "basic 2-panel layout" {
    var nodes = [_]LayoutElement{ .{}, .{}, .{} };

    var setup: LayoutSetupContext = .{};
    beginLayout(&setup);

    const root = &nodes[0];
    if (beginLayoutElement(&setup, root)) {
        root.desc.layout_dir = .left_to_right;
        root.desc.padding = .{ .l = 2, .r = 2, .t = 2, .b = 2 };
        root.desc.child_gap = 4;

        const sidebar = &nodes[1];
        if (beginLayoutElement(&setup, sidebar)) {
            sidebar.desc.sizing_w = .{ .basis = .fixed, .value = .{ .fixed = 200 }, .min_max = .{ .min = 80, .max = 400 }, .shrink = 1 };
            sidebar.desc.sizing_h = .{ .basis = .auto, .grow = 1, .shrink = 1 };
            endLayoutElement(&setup);
        }

        const main_panel = &nodes[2];
        if (beginLayoutElement(&setup, main_panel)) {
            main_panel.desc.sizing_w = .{ .basis = .auto, .grow = 1, .shrink = 1 };
            main_panel.desc.sizing_h = .{ .basis = .auto, .grow = 1, .shrink = 1 };
            endLayoutElement(&setup);
        }

        endLayoutElement(&setup);
    }
    endLayout(&setup);

    var config: LayoutConfig = .{};
    var build_ctx: LayoutBuildContext = .{};
    computeLayout(&config, &build_ctx, &nodes[0], 0, 0, 800, 600);

    // Root should fill viewport
    try std.testing.expectApproxEqAbs(nodes[0].w, 800, EPSILON);
    try std.testing.expectApproxEqAbs(nodes[0].h, 600, EPSILON);

    // Sidebar should be fixed 200px wide
    try std.testing.expectApproxEqAbs(nodes[1].w, 200, EPSILON);

    // Main panel should fill remaining width: 800 - 2 - 200 - 4 - 2 = 592
    try std.testing.expectApproxEqAbs(nodes[2].w, 592, EPSILON);
}

test "3-panel with splitter" {
    var nodes = [_]LayoutElement{ .{}, .{}, .{}, .{} };

    var setup: LayoutSetupContext = .{};
    beginLayout(&setup);

    const root = &nodes[0];
    if (beginLayoutElement(&setup, root)) {
        root.desc.layout_dir = .left_to_right;
        root.desc.padding = .{ .l = 1, .r = 1, .t = 1, .b = 1 };
        root.desc.child_gap = 0;

        const sidebar = &nodes[1];
        if (beginLayoutElement(&setup, sidebar)) {
            sidebar.desc.sizing_w = .{ .basis = .fixed, .value = .{ .fixed = 22 }, .min_max = .{ .min = 12, .max = 40 }, .shrink = 1 };
            sidebar.desc.sizing_h = .{ .basis = .auto, .grow = 1, .shrink = 1 };
            endLayoutElement(&setup);
        }

        splitter(&setup, &nodes[2], 1, 2);

        const mainp = &nodes[3];
        if (beginLayoutElement(&setup, mainp)) {
            mainp.desc.sizing_w = .{ .basis = .auto, .grow = 1, .shrink = 1 };
            mainp.desc.sizing_h = .{ .basis = .auto, .grow = 1, .shrink = 1 };
            endLayoutElement(&setup);
        }

        endLayoutElement(&setup);
    }
    endLayout(&setup);

    var config: LayoutConfig = .{};
    var build_ctx: LayoutBuildContext = .{};
    computeLayout(&config, &build_ctx, &nodes[0], 0, 0, 80, 24);

    // Verify layout structure
    try std.testing.expect(nodes[2].type == .splitter);
    try std.testing.expectApproxEqAbs(nodes[2].w, 1, EPSILON);
}

test "grow distribution" {
    var nodes = [_]LayoutElement{ .{}, .{}, .{} };

    var setup: LayoutSetupContext = .{};
    beginLayout(&setup);

    const root = &nodes[0];
    if (beginLayoutElement(&setup, root)) {
        root.desc.layout_dir = .left_to_right;
        root.desc.padding = .{ .l = 0, .r = 0, .t = 0, .b = 0 };

        const left = &nodes[1];
        if (beginLayoutElement(&setup, left)) {
            left.desc.sizing_w = .{ .basis = .auto, .grow = 1, .shrink = 1 };
            left.desc.sizing_h = .{ .basis = .auto, .grow = 1, .shrink = 1 };
            endLayoutElement(&setup);
        }

        const right = &nodes[2];
        if (beginLayoutElement(&setup, right)) {
            right.desc.sizing_w = .{ .basis = .auto, .grow = 2, .shrink = 1 };
            right.desc.sizing_h = .{ .basis = .auto, .grow = 1, .shrink = 1 };
            endLayoutElement(&setup);
        }

        endLayoutElement(&setup);
    }
    endLayout(&setup);

    var config: LayoutConfig = .{};
    var build_ctx: LayoutBuildContext = .{};
    computeLayout(&config, &build_ctx, &nodes[0], 0, 0, 300, 100);

    // Both should have 0 preferred size (no children, no padding)
    // Left gets 1/3 of 300, right gets 2/3 of 300
    try std.testing.expectApproxEqAbs(nodes[1].w, 100, EPSILON);
    try std.testing.expectApproxEqAbs(nodes[2].w, 200, EPSILON);
}

test "grid snapping" {
    var nodes = [_]LayoutElement{ .{}, .{}, .{} };

    var setup: LayoutSetupContext = .{};
    beginLayout(&setup);

    const root = &nodes[0];
    if (beginLayoutElement(&setup, root)) {
        root.desc.layout_dir = .left_to_right;

        const child = &nodes[1];
        if (beginLayoutElement(&setup, child)) {
            child.desc.sizing_w = .{ .basis = .fixed, .value = .{ .fixed = 33.3 } };
            endLayoutElement(&setup);
        }

        endLayoutElement(&setup);
    }
    endLayout(&setup);

    var config: LayoutConfig = .{ .grid_snapping = 10 };
    var build_ctx: LayoutBuildContext = .{};
    computeLayout(&config, &build_ctx, &nodes[0], 0, 0, 100, 100);

    // 33.3 should snap to 30 (nearest multiple of 10)
    try std.testing.expectApproxEqAbs(nodes[1].w, 30, EPSILON);
}

test "clear links" {
    var node: LayoutElement = .{};
    node.links.parent = &node;
    node.links.first_child = &node;

    clearLayoutElementLinks(&node);
    try std.testing.expect(node.links.parent == null);
    try std.testing.expect(node.links.first_child == null);
}

test "overflow shrink" {
    var nodes = [_]LayoutElement{ .{}, .{}, .{} };

    var setup: LayoutSetupContext = .{};
    beginLayout(&setup);

    const root = &nodes[0];
    if (beginLayoutElement(&setup, root)) {
        root.desc.layout_dir = .left_to_right;
        root.desc.padding = .{ .l = 0, .r = 0, .t = 0, .b = 0 };

        const left = &nodes[1];
        if (beginLayoutElement(&setup, left)) {
            left.desc.sizing_w = .{ .basis = .fixed, .value = .{ .fixed = 200 }, .shrink = 1 };
            left.desc.sizing_h = .{ .basis = .auto, .grow = 1 };
            endLayoutElement(&setup);
        }

        const right = &nodes[2];
        if (beginLayoutElement(&setup, right)) {
            right.desc.sizing_w = .{ .basis = .fixed, .value = .{ .fixed = 200 }, .shrink = 2 };
            right.desc.sizing_h = .{ .basis = .auto, .grow = 1 };
            endLayoutElement(&setup);
        }

        endLayoutElement(&setup);
    }
    endLayout(&setup);

    var config: LayoutConfig = .{};
    var build_ctx: LayoutBuildContext = .{};
    computeLayout(&config, &build_ctx, &nodes[0], 0, 0, 300, 100);

    // Total preferred = 400, available = 300, overflow = 100
    // left shrinks by 1/3 * 100 = 33.33, right shrinks by 2/3 * 100 = 66.67
    try std.testing.expectApproxEqAbs(nodes[1].w, 166.6667, 0.5);
    try std.testing.expectApproxEqAbs(nodes[2].w, 133.3333, 0.5);
}

test "percent basis" {
    var nodes = [_]LayoutElement{ .{}, .{}, .{} };

    var setup: LayoutSetupContext = .{};
    beginLayout(&setup);

    const root = &nodes[0];
    if (beginLayoutElement(&setup, root)) {
        root.desc.layout_dir = .left_to_right;
        root.desc.padding = .{ .l = 0, .r = 0, .t = 0, .b = 0 };

        const left = &nodes[1];
        if (beginLayoutElement(&setup, left)) {
            left.desc.sizing_w = .{ .basis = .percent, .value = .{ .percent = 0.3 } };
            left.desc.sizing_h = .{ .basis = .auto, .grow = 1 };
            endLayoutElement(&setup);
        }

        const right = &nodes[2];
        if (beginLayoutElement(&setup, right)) {
            right.desc.sizing_w = .{ .basis = .percent, .value = .{ .percent = 0.7 } };
            right.desc.sizing_h = .{ .basis = .auto, .grow = 1 };
            endLayoutElement(&setup);
        }

        endLayoutElement(&setup);
    }
    endLayout(&setup);

    var config: LayoutConfig = .{};
    var build_ctx: LayoutBuildContext = .{};
    computeLayout(&config, &build_ctx, &nodes[0], 0, 0, 1000, 100);

    try std.testing.expectApproxEqAbs(nodes[1].w, 300, EPSILON);
    try std.testing.expectApproxEqAbs(nodes[2].w, 700, EPSILON);
}

test "nested layout" {
    var nodes = [_]LayoutElement{ .{}, .{}, .{}, .{}, .{} };

    var setup: LayoutSetupContext = .{};
    beginLayout(&setup);

    const root = &nodes[0];
    if (beginLayoutElement(&setup, root)) {
        root.desc.layout_dir = .left_to_right;
        root.desc.padding = .{ .l = 0, .r = 0, .t = 0, .b = 0 };

        const sidebar = &nodes[1];
        if (beginLayoutElement(&setup, sidebar)) {
            sidebar.desc.sizing_w = .{ .basis = .fixed, .value = .{ .fixed = 100 } };
            sidebar.desc.sizing_h = .{ .basis = .auto, .grow = 1 };

            // Nested button inside sidebar
            const button = &nodes[2];
            if (beginLayoutElement(&setup, button)) {
                button.desc.sizing_w = .{ .basis = .fixed, .value = .{ .fixed = 80 } };
                button.desc.sizing_h = .{ .basis = .fixed, .value = .{ .fixed = 20 } };
                endLayoutElement(&setup);
            }

            endLayoutElement(&setup);
        }

        const main = &nodes[3];
        if (beginLayoutElement(&setup, main)) {
            main.desc.sizing_w = .{ .basis = .auto, .grow = 1 };
            main.desc.sizing_h = .{ .basis = .auto, .grow = 1 };
            endLayoutElement(&setup);
        }

        endLayoutElement(&setup);
    }
    endLayout(&setup);

    var config: LayoutConfig = .{};
    var build_ctx: LayoutBuildContext = .{};
    computeLayout(&config, &build_ctx, &nodes[0], 0, 0, 500, 300);

    // Root fills viewport
    try std.testing.expectApproxEqAbs(nodes[0].w, 500, EPSILON);
    try std.testing.expectApproxEqAbs(nodes[0].h, 300, EPSILON);

    // Sidebar is fixed 100
    try std.testing.expectApproxEqAbs(nodes[1].w, 100, EPSILON);

    // Button inside sidebar
    try std.testing.expectApproxEqAbs(nodes[2].w, 80, EPSILON);
    try std.testing.expectApproxEqAbs(nodes[2].h, 20, EPSILON);

    // Main fills rest
    try std.testing.expectApproxEqAbs(nodes[3].w, 400, EPSILON);
}

test "vertical splitter" {
    var nodes = [_]LayoutElement{ .{}, .{}, .{}, .{} };

    var setup: LayoutSetupContext = .{};
    beginLayout(&setup);

    const root = &nodes[0];
    if (beginLayoutElement(&setup, root)) {
        root.desc.layout_dir = .top_to_bottom;
        root.desc.padding = .{ .l = 1, .r = 1, .t = 1, .b = 1 };
        root.desc.child_gap = 0;

        const top = &nodes[1];
        if (beginLayoutElement(&setup, top)) {
            top.desc.sizing_h = .{ .basis = .fixed, .value = .{ .fixed = 10 }, .min_max = .{ .min = 5, .max = 15 }, .shrink = 1 };
            top.desc.sizing_w = .{ .basis = .auto, .grow = 1 };
            endLayoutElement(&setup);
        }

        splitter(&setup, &nodes[2], 1, 2);

        const bottom = &nodes[3];
        if (beginLayoutElement(&setup, bottom)) {
            bottom.desc.sizing_h = .{ .basis = .auto, .grow = 1, .shrink = 1 };
            bottom.desc.sizing_w = .{ .basis = .auto, .grow = 1 };
            endLayoutElement(&setup);
        }

        endLayoutElement(&setup);
    }
    endLayout(&setup);

    var config: LayoutConfig = .{};
    var build_ctx: LayoutBuildContext = .{};
    computeLayout(&config, &build_ctx, &nodes[0], 0, 0, 80, 24);

    // Top panel should be fixed 10px high
    try std.testing.expectApproxEqAbs(nodes[1].h, 10, EPSILON);
    // Splitter should be 1px high
    try std.testing.expectApproxEqAbs(nodes[2].h, 1, EPSILON);
    // Bottom fills rest: 24 - 1(top pad) - 10 - 1(splitter) - 1(bottom pad) = 11
    try std.testing.expectApproxEqAbs(nodes[3].h, 11, EPSILON);

    // Test splitter axis detection
    try std.testing.expect(getSplitterAxis(&nodes[2]) == .top_to_bottom);
}

test "zero size handling" {
    var nodes = [_]LayoutElement{ .{}, .{}, .{} };

    var setup: LayoutSetupContext = .{};
    beginLayout(&setup);

    const root = &nodes[0];
    if (beginLayoutElement(&setup, root)) {
        root.desc.layout_dir = .left_to_right;
        root.desc.padding = .{ .l = 0, .r = 0, .t = 0, .b = 0 };

        const left = &nodes[1];
        if (beginLayoutElement(&setup, left)) {
            left.desc.sizing_w = .{ .basis = .fixed, .value = .{ .fixed = 0 } };
            left.desc.sizing_h = .{ .basis = .auto, .grow = 1 };
            endLayoutElement(&setup);
        }

        const right = &nodes[2];
        if (beginLayoutElement(&setup, right)) {
            right.desc.sizing_w = .{ .basis = .auto, .grow = 1 };
            right.desc.sizing_h = .{ .basis = .auto, .grow = 1 };
            endLayoutElement(&setup);
        }

        endLayoutElement(&setup);
    }
    endLayout(&setup);

    var config: LayoutConfig = .{};
    var build_ctx: LayoutBuildContext = .{};
    computeLayout(&config, &build_ctx, &nodes[0], 0, 0, 100, 10);

    // Left is 0, right gets all 100
    try std.testing.expectApproxEqAbs(nodes[1].w, 0, EPSILON);
    try std.testing.expectApproxEqAbs(nodes[2].w, 100, EPSILON);
}

test "deeply nested layout" {
    var nodes = [_]LayoutElement{ .{}, .{}, .{}, .{}, .{}, .{} };

    var setup: LayoutSetupContext = .{};
    beginLayout(&setup);

    const root = &nodes[0];
    if (beginLayoutElement(&setup, root)) {
        root.desc.layout_dir = .left_to_right;
        root.desc.padding = .{ .l = 2, .r = 2, .t = 2, .b = 2 };

        const sidebar = &nodes[1];
        if (beginLayoutElement(&setup, sidebar)) {
            sidebar.desc.sizing_w = .{ .basis = .fixed, .value = .{ .fixed = 20 } };
            sidebar.desc.sizing_h = .{ .basis = .auto, .grow = 1 };

            const menu = &nodes[2];
            if (beginLayoutElement(&setup, menu)) {
                menu.desc.layout_dir = .top_to_bottom;
                menu.desc.sizing_w = .{ .basis = .auto, .grow = 1 };
                menu.desc.sizing_h = .{ .basis = .auto, .grow = 1 };

                const item1 = &nodes[3];
                if (beginLayoutElement(&setup, item1)) {
                    item1.desc.sizing_h = .{ .basis = .fixed, .value = .{ .fixed = 3 } };
                    item1.desc.sizing_w = .{ .basis = .auto, .grow = 1 };
                    endLayoutElement(&setup);
                }

                const item2 = &nodes[4];
                if (beginLayoutElement(&setup, item2)) {
                    item2.desc.sizing_h = .{ .basis = .fixed, .value = .{ .fixed = 3 } };
                    item2.desc.sizing_w = .{ .basis = .auto, .grow = 1 };
                    endLayoutElement(&setup);
                }

                endLayoutElement(&setup);
            }

            endLayoutElement(&setup);
        }

        const main = &nodes[5];
        if (beginLayoutElement(&setup, main)) {
            main.desc.sizing_w = .{ .basis = .auto, .grow = 1 };
            main.desc.sizing_h = .{ .basis = .auto, .grow = 1 };
            endLayoutElement(&setup);
        }

        endLayoutElement(&setup);
    }
    endLayout(&setup);

    var config: LayoutConfig = .{};
    var build_ctx: LayoutBuildContext = .{};
    computeLayout(&config, &build_ctx, &nodes[0], 0, 0, 50, 20);

    // Root: 50x20
    try std.testing.expectApproxEqAbs(nodes[0].w, 50, EPSILON);
    try std.testing.expectApproxEqAbs(nodes[0].h, 20, EPSILON);

    // Sidebar: fixed 20 wide
    try std.testing.expectApproxEqAbs(nodes[1].w, 20, EPSILON);

    // Menu inside sidebar fills sidebar
    try std.testing.expectApproxEqAbs(nodes[2].w, 20, EPSILON);

    // Item1 and item2 each 3px high
    try std.testing.expectApproxEqAbs(nodes[3].h, 3, EPSILON);
    try std.testing.expectApproxEqAbs(nodes[4].h, 3, EPSILON);

    // Main: 50 - 2(l) - 20(sidebar) - 2(r) = 26
    try std.testing.expectApproxEqAbs(nodes[5].w, 26, EPSILON);
}

test "min_max clamp" {
    var nodes = [_]LayoutElement{ .{}, .{}, .{} };

    var setup: LayoutSetupContext = .{};
    beginLayout(&setup);

    const root = &nodes[0];
    if (beginLayoutElement(&setup, root)) {
        root.desc.layout_dir = .left_to_right;
        root.desc.padding = .{ .l = 0, .r = 0, .t = 0, .b = 0 };

        const left = &nodes[1];
        if (beginLayoutElement(&setup, left)) {
            left.desc.sizing_w = .{ .basis = .auto, .grow = 1, .min_max = .{ .min = 50, .max = 80 } };
            left.desc.sizing_h = .{ .basis = .auto, .grow = 1 };
            endLayoutElement(&setup);
        }

        const right = &nodes[2];
        if (beginLayoutElement(&setup, right)) {
            right.desc.sizing_w = .{ .basis = .auto, .grow = 1 };
            right.desc.sizing_h = .{ .basis = .auto, .grow = 1 };
            endLayoutElement(&setup);
        }

        endLayoutElement(&setup);
    }
    endLayout(&setup);

    var config: LayoutConfig = .{};
    var build_ctx: LayoutBuildContext = .{};
    computeLayout(&config, &build_ctx, &nodes[0], 0, 0, 200, 100);

    // Both have 0 preferred, grow=1 each, budget=200
    // Without clamp: each would get 100
    // With clamp: left max=80, so left gets 80, right gets 120
    try std.testing.expectApproxEqAbs(nodes[1].w, 80, EPSILON);
    try std.testing.expectApproxEqAbs(nodes[2].w, 120, EPSILON);
}
