//! Neovim Key Input Converter
//!
//! Converts Ghostty key events to Neovim's key notation format.
//! Neovim uses a specific notation like <C-a>, <S-Tab>, <CR>, etc.
//!
//! Reference: https://neovim.io/doc/user/intro.html#keycodes

const std = @import("std");
const input = @import("../input.zig");

/// Convert a Ghostty key event to Neovim key notation.
/// Returns null if the key should not be sent to Neovim.
pub fn toNeovimKey(event: input.KeyEvent) ?[]const u8 {
    // Only handle press and repeat events
    if (event.action == .release) return null;

    // If we have UTF-8 text and no significant modifiers, send it directly
    if (event.utf8.len > 0 and !hasSignificantMods(event.mods)) {
        return event.utf8;
    }

    // Map the physical key to Neovim notation
    return mapKeyWithMods(event);
}

/// Check if there are modifiers that need special handling
fn hasSignificantMods(mods: input.Mods) bool {
    return mods.ctrl or mods.alt or mods.super;
}

/// Map a key with modifiers to Neovim notation
fn mapKeyWithMods(event: input.KeyEvent) ?[]const u8 {
    // First, get the base key name
    const base_name = getBaseKeyName(event) orelse return null;

    // If no modifiers, return the base name
    if (!hasSignificantMods(event.mods) and !event.mods.shift) {
        return base_name;
    }

    // For modifiers, we need to build a string like <C-S-a>
    // We use static buffers for common combinations
    return buildModifiedKey(base_name, event.mods);
}

/// Get the base key name for Neovim
fn getBaseKeyName(event: input.KeyEvent) ?[]const u8 {
    // Special keys first
    return switch (event.key) {
        // Function keys
        .f1 => "<F1>",
        .f2 => "<F2>",
        .f3 => "<F3>",
        .f4 => "<F4>",
        .f5 => "<F5>",
        .f6 => "<F6>",
        .f7 => "<F7>",
        .f8 => "<F8>",
        .f9 => "<F9>",
        .f10 => "<F10>",
        .f11 => "<F11>",
        .f12 => "<F12>",

        // Navigation keys
        .arrow_up => "<Up>",
        .arrow_down => "<Down>",
        .arrow_left => "<Left>",
        .arrow_right => "<Right>",
        .home => "<Home>",
        .end => "<End>",
        .page_up => "<PageUp>",
        .page_down => "<PageDown>",

        // Editing keys
        .enter => "<CR>",
        .tab => "<Tab>",
        .backspace => "<BS>",
        .delete => "<Del>",
        .insert => "<Insert>",
        .escape => "<Esc>",
        .space => "<Space>",

        // Letter keys - return lowercase
        .key_a => "a",
        .key_b => "b",
        .key_c => "c",
        .key_d => "d",
        .key_e => "e",
        .key_f => "f",
        .key_g => "g",
        .key_h => "h",
        .key_i => "i",
        .key_j => "j",
        .key_k => "k",
        .key_l => "l",
        .key_m => "m",
        .key_n => "n",
        .key_o => "o",
        .key_p => "p",
        .key_q => "q",
        .key_r => "r",
        .key_s => "s",
        .key_t => "t",
        .key_u => "u",
        .key_v => "v",
        .key_w => "w",
        .key_x => "x",
        .key_y => "y",
        .key_z => "z",

        // Number keys
        .digit_0 => "0",
        .digit_1 => "1",
        .digit_2 => "2",
        .digit_3 => "3",
        .digit_4 => "4",
        .digit_5 => "5",
        .digit_6 => "6",
        .digit_7 => "7",
        .digit_8 => "8",
        .digit_9 => "9",

        // Punctuation
        .minus => "-",
        .equal => "=",
        .bracket_left => "[",
        .bracket_right => "]",
        .backslash => "\\",
        .semicolon => ";",
        .quote => "'",
        .comma => ",",
        .period => ".",
        .slash => "/",
        .backquote => "`",

        // Numpad
        .numpad_0 => "<k0>",
        .numpad_1 => "<k1>",
        .numpad_2 => "<k2>",
        .numpad_3 => "<k3>",
        .numpad_4 => "<k4>",
        .numpad_5 => "<k5>",
        .numpad_6 => "<k6>",
        .numpad_7 => "<k7>",
        .numpad_8 => "<k8>",
        .numpad_9 => "<k9>",
        .numpad_add => "<kPlus>",
        .numpad_subtract => "<kMinus>",
        .numpad_multiply => "<kMultiply>",
        .numpad_divide => "<kDivide>",
        .numpad_enter => "<kEnter>",
        .numpad_decimal => "<kPoint>",

        else => null,
    };
}

/// Build a key string with modifiers
/// Uses thread-local static buffer for efficiency
fn buildModifiedKey(base: []const u8, mods: input.Mods) ?[]const u8 {
    // Static buffers for common modifier combinations
    // This avoids allocation for the most common cases
    const State = struct {
        threadlocal var buffer: [64]u8 = undefined;
    };

    var buf = &State.buffer;
    var pos: usize = 0;

    // Start with <
    buf[pos] = '<';
    pos += 1;

    // Add modifiers
    if (mods.ctrl) {
        buf[pos] = 'C';
        pos += 1;
        buf[pos] = '-';
        pos += 1;
    }
    if (mods.alt) {
        buf[pos] = 'A';
        pos += 1;
        buf[pos] = '-';
        pos += 1;
    }
    if (mods.super) {
        buf[pos] = 'D';
        pos += 1;
        buf[pos] = '-';
        pos += 1;
    }
    if (mods.shift) {
        buf[pos] = 'S';
        pos += 1;
        buf[pos] = '-';
        pos += 1;
    }

    // If base already has <>, strip them
    const key_part = if (base.len > 2 and base[0] == '<' and base[base.len - 1] == '>')
        base[1 .. base.len - 1]
    else
        base;

    // Copy key name
    if (pos + key_part.len + 1 > buf.len) return null;
    @memcpy(buf[pos..][0..key_part.len], key_part);
    pos += key_part.len;

    // End with >
    buf[pos] = '>';
    pos += 1;

    return buf[0..pos];
}

/// Convert mouse button to Neovim notation
pub fn toNeovimMouseButton(button: input.MouseButton) ?[]const u8 {
    return switch (button) {
        .left => "left",
        .middle => "middle",
        .right => "right",
        .four => "x1",
        .five => "x2",
        else => null,
    };
}

/// Convert mouse action to Neovim notation
pub fn toNeovimMouseAction(pressed: bool, count: u8) []const u8 {
    if (pressed) {
        return switch (count) {
            1 => "press",
            2 => "double",
            3 => "triple",
            else => "press",
        };
    } else {
        return "release";
    }
}

/// Convert modifier keys to Neovim mouse modifier string
pub fn toNeovimMouseMods(mods: input.Mods) []const u8 {
    // Neovim uses modifier strings like "C" for Ctrl, "S" for Shift, etc.
    // Combined modifiers are concatenated
    const State = struct {
        threadlocal var buffer: [16]u8 = undefined;
    };

    var buf = &State.buffer;
    var pos: usize = 0;

    if (mods.shift) {
        buf[pos] = 'S';
        pos += 1;
    }
    if (mods.ctrl) {
        buf[pos] = 'C';
        pos += 1;
    }
    if (mods.alt) {
        buf[pos] = 'A';
        pos += 1;
    }
    if (mods.super) {
        buf[pos] = 'D';
        pos += 1;
    }

    return buf[0..pos];
}

test "basic key conversion" {
    const testing = std.testing;

    // Simple key without mods
    {
        const event = input.KeyEvent{
            .key = .key_a,
            .utf8 = "a",
        };
        try testing.expectEqualStrings("a", toNeovimKey(event).?);
    }

    // Ctrl+A
    {
        const event = input.KeyEvent{
            .key = .key_a,
            .mods = .{ .ctrl = true },
        };
        try testing.expectEqualStrings("<C-a>", toNeovimKey(event).?);
    }

    // Escape
    {
        const event = input.KeyEvent{
            .key = .escape,
        };
        try testing.expectEqualStrings("<Esc>", toNeovimKey(event).?);
    }
}
