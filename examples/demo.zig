const std = @import("std");
const vaxis = @import("vaxis");
const bento = @import("bento");

const ENode = enum(u8) {
    Root,
    Sidebar,
    Splitter,
    Main,
    COUNT,
};

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    mouse: vaxis.Mouse,
    focus_in,
    focus_out,
    clipboard: []const u8,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.gpa;

    var buffer: [1024]u8 = undefined;
    var tty = try vaxis.Tty.init(io, &buffer);
    defer tty.deinit();

    var vx = try vaxis.init(io, alloc, init.environ_map, .{});
    defer vx.deinit(alloc, tty.writer());

    var loop: vaxis.Loop(Event) = .init(io, &tty, &vx);
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), .fromSeconds(1));

    // Bento state
    var nodes = [_]bento.LayoutElement{ .{}, .{}, .{}, .{} };
    var config: bento.LayoutConfig = .{};
    var splitter_state: bento.SplitterState = .{};
    var layout_initialized = false;
    var current_width: f32 = 80;
    var current_height: f32 = 24;

    setupLayout(&nodes, &layout_initialized);

    while (true) {
        const event = try loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) break;
                if (key.matches('q', .{})) break;
            },
            .winsize => |ws| {
                try vx.resize(alloc, tty.writer(), ws);
                current_width = @floatFromInt(ws.cols);
                current_height = @floatFromInt(ws.rows);
                var build: bento.LayoutBuildContext = .{};
                bento.computeLayout(&config, &build, &nodes[@intFromEnum(ENode.Root)], 0, 0, current_width, current_height);
            },
            .mouse => |mouse| {
                const bmouse = bento.MouseInputs{
                    .pos_x = @floatFromInt(mouse.col),
                    .pos_y = @floatFromInt(mouse.row),
                    .delta_x = if (mouse.button == .left and mouse.type == .drag) 1 else 0,
                    .delta_y = 0,
                    .pressed = mouse.button == .left and mouse.type == .press,
                    .held = mouse.button == .left and mouse.type == .drag,
                    .released = mouse.button == .left and mouse.type == .release,
                };
                var build: bento.LayoutBuildContext = .{};
                bento.processSplitterInteractions(&config, &build, &splitter_state, &nodes[@intFromEnum(ENode.Root)], &bmouse);
            },
            else => {},
        }

        if (!layout_initialized) {
            setupLayout(&nodes, &layout_initialized);
        }

        var build: bento.LayoutBuildContext = .{};
        bento.computeLayout(&config, &build, &nodes[@intFromEnum(ENode.Root)], 0, 0, current_width, current_height);

        const win = vx.window();
        win.clear();

        drawBentoPanels(win, &nodes);

        const status_win = win.child(.{
            .x_off = 0,
            .y_off = @as(u16, @intFromFloat(current_height)) - 1,
            .width = @as(u16, @intFromFloat(current_width)),
            .height = 1,
        });
        _ = status_win.print(&.{.{ .text = "Bento (Zig) + libvaxis Demo | Drag splitter | q/Ctrl+C quit" }}, .{});

        try vx.render(tty.writer());
    }
}

fn setupLayout(nodes: *[4]bento.LayoutElement, initialized: *bool) void {
    if (initialized.*) return;

    for (0..@intFromEnum(ENode.COUNT)) |i| {
        bento.clearLayoutElementLinks(&nodes[i]);
    }

    var setup: bento.LayoutSetupContext = .{};
    bento.beginLayout(&setup);

    const root = &nodes[@intFromEnum(ENode.Root)];
    if (bento.beginLayoutElement(&setup, root)) {
        root.desc.layout_dir = .left_to_right;
        root.desc.padding = .{ .l = 1, .r = 1, .t = 1, .b = 1 };
        root.desc.child_gap = 0;

        const sidebar = &nodes[@intFromEnum(ENode.Sidebar)];
        if (bento.beginLayoutElement(&setup, sidebar)) {
            sidebar.desc.sizing_w = .{
                .basis = .fixed,
                .value = .{ .fixed = 22.0 },
                .min_max = .{ .min = 12.0, .max = 40.0 },
                .grow = 0,
                .shrink = 1,
            };
            sidebar.desc.sizing_h = .{ .basis = .auto, .grow = 1, .shrink = 1 };
            bento.endLayoutElement(&setup);
        }

        bento.splitter(&setup, &nodes[@intFromEnum(ENode.Splitter)], 1.0, 2);

        const mainp = &nodes[@intFromEnum(ENode.Main)];
        if (bento.beginLayoutElement(&setup, mainp)) {
            mainp.desc.sizing_w = .{ .basis = .auto, .grow = 1, .shrink = 1 };
            mainp.desc.sizing_h = .{ .basis = .auto, .grow = 1, .shrink = 1 };
            bento.endLayoutElement(&setup);
        }

        bento.endLayoutElement(&setup);
    }
    bento.endLayout(&setup);
    initialized.* = true;
}

fn drawBentoPanels(win: vaxis.Window, nodes: *[4]bento.LayoutElement) void {
    const root_e = &nodes[@intFromEnum(ENode.Root)];
    const root_win = win.child(.{
        .x_off = @intFromFloat(root_e.x),
        .y_off = @intFromFloat(root_e.y),
        .width = @intFromFloat(root_e.w),
        .height = @intFromFloat(root_e.h),
    });
    root_win.fill(.{ .style = .{ .bg = .{ .rgb = .{ 20, 20, 30 } } } });

    const sb = &nodes[@intFromEnum(ENode.Sidebar)];
    const sb_win = root_win.child(.{
        .x_off = @intFromFloat(sb.x),
        .y_off = @intFromFloat(sb.y),
        .width = @intFromFloat(sb.w),
        .height = @intFromFloat(sb.h),
    });
    sb_win.fill(.{ .style = .{ .bg = .{ .rgb = .{ 40, 60, 120 } } } });
    _ = sb_win.print(&.{.{ .text = "Sidebar (Zig Bento)", .style = .{ .fg = .{ .rgb = .{ 200, 220, 255 } } } }}, .{ .col_offset = 1, .row_offset = 1 });
    _ = sb_win.print(&.{.{ .text = "Pure Zig port", .style = .{} }}, .{ .col_offset = 1, .row_offset = 3 });

    const sp = &nodes[@intFromEnum(ENode.Splitter)];
    const sp_win = root_win.child(.{
        .x_off = @intFromFloat(sp.x),
        .y_off = @intFromFloat(sp.y),
        .width = @intFromFloat(sp.w),
        .height = @intFromFloat(sp.h),
    });
    sp_win.fill(.{ .style = .{ .bg = .{ .rgb = .{ 80, 80, 90 } } } });
    for (0..@intFromFloat(sp.h)) |r| {
        _ = sp_win.print(&.{.{ .text = "│", .style = .{ .fg = .{ .rgb = .{ 150, 150, 160 } } } }}, .{ .col_offset = 0, .row_offset = @intCast(r) });
    }

    const mp = &nodes[@intFromEnum(ENode.Main)];
    const mp_win = root_win.child(.{
        .x_off = @intFromFloat(mp.x),
        .y_off = @intFromFloat(mp.y),
        .width = @intFromFloat(mp.w),
        .height = @intFromFloat(mp.h),
    });
    mp_win.fill(.{ .style = .{ .bg = .{ .rgb = .{ 30, 70, 50 } } } });
    _ = mp_win.print(&.{.{ .text = "Main (Zig Bento)", .style = .{ .fg = .{ .rgb = .{ 180, 255, 200 } } } }}, .{ .col_offset = 2, .row_offset = 1 });
    _ = mp_win.print(&.{.{ .text = "Flexbox in pure Zig!", .style = .{} }}, .{ .col_offset = 2, .row_offset = 3 });
}
