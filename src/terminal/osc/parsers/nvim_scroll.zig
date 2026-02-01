const std = @import("std");
const mem = std.mem;

const Parser = @import("../../osc.zig").Parser;
const Command = @import("../../osc.zig").Command;

/// Parse OSC 9999 - Neovim scroll hint
/// Format: 9999;scroll=<delta>;grid=<grid>
/// Where delta is signed integer (lines scrolled) and grid is the nvim grid ID
pub fn parse(parser: *Parser, _: ?u8) ?*Command {
    const writer = parser.writer orelse {
        parser.state = .invalid;
        return null;
    };
    writer.writeByte(0) catch {
        parser.state = .invalid;
        return null;
    };
    const data = writer.buffered();
    if (data.len == 0) {
        parser.state = .invalid;
        return null;
    }

    // Parse the key=value pairs from the data
    // Expected format: "scroll=<int>;grid=<int>"
    var scroll_delta: ?i32 = null;
    var grid: ?i32 = null;

    // Split by ';' and parse each key=value pair
    var iter = mem.splitScalar(u8, data[0 .. data.len - 1], ';');
    while (iter.next()) |part| {
        if (mem.startsWith(u8, part, "scroll=")) {
            const value_str = part["scroll=".len..];
            scroll_delta = std.fmt.parseInt(i32, value_str, 10) catch null;
        } else if (mem.startsWith(u8, part, "grid=")) {
            const value_str = part["grid=".len..];
            grid = std.fmt.parseInt(i32, value_str, 10) catch null;
        }
    }

    // Both values are required
    if (scroll_delta == null or grid == null) {
        parser.state = .invalid;
        return null;
    }

    parser.command = .{
        .nvim_scroll_hint = .{
            .scroll_delta = scroll_delta.?,
            .grid = grid.?,
        },
    };
    return &parser.command;
}

test "OSC 9999: scroll down" {
    const testing = std.testing;

    var p: Parser = .init(null);

    const input = "9999;scroll=5;grid=1";
    for (input) |ch| p.next(ch);

    const cmd = p.end(null).?.*;
    try testing.expect(cmd == .nvim_scroll_hint);
    try testing.expectEqual(@as(i32, 5), cmd.nvim_scroll_hint.scroll_delta);
    try testing.expectEqual(@as(i32, 1), cmd.nvim_scroll_hint.grid);
}

test "OSC 9999: scroll up" {
    const testing = std.testing;

    var p: Parser = .init(null);

    const input = "9999;scroll=-3;grid=1";
    for (input) |ch| p.next(ch);

    const cmd = p.end(null).?.*;
    try testing.expect(cmd == .nvim_scroll_hint);
    try testing.expectEqual(@as(i32, -3), cmd.nvim_scroll_hint.scroll_delta);
    try testing.expectEqual(@as(i32, 1), cmd.nvim_scroll_hint.grid);
}

test "OSC 9999: different grid" {
    const testing = std.testing;

    var p: Parser = .init(null);

    const input = "9999;scroll=10;grid=2";
    for (input) |ch| p.next(ch);

    const cmd = p.end(null).?.*;
    try testing.expect(cmd == .nvim_scroll_hint);
    try testing.expectEqual(@as(i32, 10), cmd.nvim_scroll_hint.scroll_delta);
    try testing.expectEqual(@as(i32, 2), cmd.nvim_scroll_hint.grid);
}

test "OSC 9999: missing scroll" {
    const testing = std.testing;

    var p: Parser = .init(null);

    const input = "9999;grid=1";
    for (input) |ch| p.next(ch);

    try testing.expect(p.end(null) == null);
}

test "OSC 9999: missing grid" {
    const testing = std.testing;

    var p: Parser = .init(null);

    const input = "9999;scroll=5";
    for (input) |ch| p.next(ch);

    try testing.expect(p.end(null) == null);
}
