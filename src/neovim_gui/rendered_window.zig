//! Rendered Window - Per-window state for Neovim GUI
//!
//! This is a faithful port of Neovide's RenderedWindow concept. Each Neovim window
//! (grid) has its own:
//! - Ring buffer for scrollback (2x viewport height) for smooth scroll animation
//! - scroll_animation: Critically damped spring for pixel-perfect smooth scrolling
//! - viewport_margins: Fixed rows at top/bottom (tabline, statusline, etc.)
//!
//! Key insight from Neovide:
//! - The scroll animation position represents the OFFSET from the current view
//! - Position 0 = content is at its final position
//! - Position -2.5 = content needs to move DOWN 2.5 lines to reach final position
//! - The spring animates position toward 0
//! - Sub-line offset = (floor(position) - position) * line_height for pixel-perfect rendering

const std = @import("std");
const Allocator = std.mem.Allocator;
const Animation = @import("animation.zig");

const log = std.log.scoped(.rendered_window);

/// Scroll command parameters from grid_scroll event
pub const ScrollCommand = struct {
    top: u64,
    bottom: u64,
    left: u64,
    right: u64,
    rows: i64,
    cols: i64,
};

/// A cell in the grid - stores text and highlight info
pub const GridCell = struct {
    /// UTF-8 text content (can be empty, single char, or multi-byte grapheme)
    text: [16]u8 = .{0} ** 16,
    text_len: u8 = 0,
    /// Highlight group ID
    hl_id: u64 = 0,
    /// Double-width flag (this cell is the left half of a wide char)
    double_width: bool = false,
    /// This cell is the right half of a wide char (continuation)
    is_continuation: bool = false,

    pub fn setText(self: *GridCell, str: []const u8) void {
        const len = @min(str.len, 16);
        @memcpy(self.text[0..len], str[0..len]);
        self.text_len = @intCast(len);
    }

    pub fn getText(self: *const GridCell) []const u8 {
        return self.text[0..self.text_len];
    }

    pub fn clear(self: *GridCell) void {
        self.text_len = 0;
        self.hl_id = 0;
        self.double_width = false;
        self.is_continuation = false;
    }

    pub fn copyFrom(self: *GridCell, other: *const GridCell) void {
        self.* = other.*;
    }
};

/// A single line of cells (row in the grid)
pub const GridLine = struct {
    cells: []GridCell,
    dirty: bool = true,

    pub fn init(alloc: Allocator, width: u32) !GridLine {
        const cells = try alloc.alloc(GridCell, width);
        for (cells) |*cell| {
            cell.* = GridCell{};
        }
        return .{ .cells = cells };
    }

    pub fn deinit(self: *GridLine, alloc: Allocator) void {
        if (self.cells.len > 0) {
            alloc.free(self.cells);
        }
    }

    pub fn clear(self: *GridLine) void {
        for (self.cells) |*cell| {
            cell.clear();
        }
        self.dirty = true;
    }

    pub fn copyFrom(self: *GridLine, other: *const GridLine) void {
        const len = @min(self.cells.len, other.cells.len);
        for (0..len) |i| {
            self.cells[i].copyFrom(&other.cells[i]);
        }
        self.dirty = true;
    }
};

/// Ring buffer for efficient scrolling - O(1) rotation via index adjustment
/// Supports negative indexing via euclidean modulo (like Neovide)
pub fn RingBuffer(comptime T: type) type {
    return struct {
        const Self = @This();

        elements: []T,
        /// Logical index 0 maps to this array index
        current_index: isize = 0,
        alloc: Allocator,

        pub fn init(alloc: Allocator, size: usize) !Self {
            const elements = try alloc.alloc(T, size);
            return .{
                .elements = elements,
                .current_index = 0,
                .alloc = alloc,
            };
        }

        pub fn deinit(self: *Self) void {
            self.alloc.free(self.elements);
        }

        /// O(1) rotation - just adjust the logical index
        pub fn rotate(self: *Self, amount: isize) void {
            self.current_index += amount;
        }

        /// Get array index from logical index using euclidean modulo
        fn getArrayIndex(self: *const Self, logical_index: isize) usize {
            const len: isize = @intCast(self.elements.len);
            // Euclidean modulo handles negative indices correctly
            return @intCast(@mod(self.current_index + logical_index, len));
        }

        pub fn get(self: *const Self, logical_index: isize) *T {
            return &self.elements[self.getArrayIndex(logical_index)];
        }

        pub fn getConst(self: *const Self, logical_index: isize) *const T {
            return &self.elements[self.getArrayIndex(logical_index)];
        }

        pub fn length(self: *const Self) usize {
            return self.elements.len;
        }

        /// Reset to initial state
        pub fn reset(self: *Self) void {
            self.current_index = 0;
        }
    };
}

pub const WindowType = enum {
    editor,
    message,
    floating,
};

/// Anchor info - if present, window is floating; if null, window is a root window
pub const AnchorInfo = struct {
    anchor_grid_id: u64,
    anchor_left: f32,
    anchor_top: f32,
    z_index: u64,
};

/// Viewport margins - fixed rows/cols that don't scroll (winbar, borders, etc.)
pub const ViewportMargins = struct {
    top: u32 = 0,
    bottom: u32 = 0,
    left: u32 = 0,
    right: u32 = 0,
};

/// Scroll animation settings
pub const ScrollSettings = struct {
    /// Animation duration in seconds
    /// Shorter = snappier feel, longer = smoother but may feel laggy
    /// Neovide default is 0.3s, but we use 0.15s for a snappier feel
    animation_length: f32 = 0.15,
    /// For "far" scrolls (> buffer capacity), show this many lines of animation
    far_lines: u32 = 1,
};

/// Per-window rendering state - faithful port of Neovide's RenderedWindow
pub const RenderedWindow = struct {
    const Self = @This();

    alloc: Allocator,

    /// Grid ID from Neovim
    id: u64,

    /// Whether this window is valid/visible
    valid: bool = false,
    hidden: bool = false,

    /// Window type
    window_type: WindowType = .editor,

    /// Grid dimensions
    grid_width: u32 = 0,
    grid_height: u32 = 0,

    /// Position in grid coordinates (col, row)
    grid_position: [2]f32 = .{ 0, 0 },

    /// Target position for animation
    target_position: [2]f32 = .{ 0, 0 },

    /// Position animation springs
    position_spring_x: Animation.CriticallyDampedSpring = .{},
    position_spring_y: Animation.CriticallyDampedSpring = .{},

    /// Z-index for floating windows (higher = on top)
    zindex: u64 = 0,

    /// Anchor info - if not null, this is a floating window
    anchor_info: ?AnchorInfo = null,

    /// The actual grid of cells (current viewport content)
    cells: []GridCell = &.{},

    /// Scrollback buffer - 2x viewport height for smooth scroll animation
    /// This allows us to show content that has scrolled off-screen
    scrollback_lines: ?RingBuffer(?*GridLine) = null,

    /// Pool of GridLine objects for reuse
    line_pool: std.ArrayList(*GridLine),

    /// Pending scroll delta from Neovim (accumulated between flushes)
    scroll_delta: i32 = 0,

    /// Last scroll region (from grid_scroll event)
    last_scroll_region: struct {
        top: u32 = 0,
        bot: u32 = 0,
        left: u32 = 0,
        right: u32 = 0,
    } = .{},

    /// Fixed rows/cols at edges (winbar, borders, etc.)
    viewport_margins: ViewportMargins = .{},

    /// Whether this window is external (separate OS window)
    is_external: bool = false,

    /// Scroll animation using critically damped spring (Neovide-style)
    /// Position represents offset from final position:
    /// - 0 = at final position
    /// - negative = content needs to move down
    /// - positive = content needs to move up
    scroll_animation: Animation.CriticallyDampedSpring = .{},

    /// Scroll settings
    scroll_settings: ScrollSettings = .{},

    /// Position animation length
    position_animation_length: f32 = 0.15,

    /// Dirty flag - set when content changes
    dirty: bool = true,

    pub fn init(alloc: Allocator, id: u64) Self {
        return .{
            .alloc = alloc,
            .id = id,
            .line_pool = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.cells.len > 0) {
            self.alloc.free(self.cells);
        }

        // Free scrollback buffer
        if (self.scrollback_lines) |*sb| {
            sb.deinit();
        }

        // Free line pool
        for (self.line_pool.items) |line| {
            line.deinit(self.alloc);
            self.alloc.destroy(line);
        }
        self.line_pool.deinit(self.alloc);
    }

    pub fn resize(self: *Self, width: u32, height: u32) !void {
        if (width == self.grid_width and height == self.grid_height) return;

        log.debug("Window {} resize: {}x{} -> {}x{}", .{
            self.id,
            self.grid_width,
            self.grid_height,
            width,
            height,
        });

        // Free old cells
        if (self.cells.len > 0) {
            self.alloc.free(self.cells);
        }

        // Allocate new grid
        const cell_count = @as(usize, width) * @as(usize, height);
        self.cells = try self.alloc.alloc(GridCell, cell_count);

        // Initialize all cells
        for (self.cells) |*cell| {
            cell.* = GridCell{};
        }

        // Resize scrollback buffer (2x height for smooth scrolling)
        if (self.scrollback_lines) |*sb| {
            sb.deinit();
        }
        const scrollback_size = @as(usize, height) * 2;
        self.scrollback_lines = try RingBuffer(?*GridLine).init(self.alloc, scrollback_size);

        // Initialize scrollback with nulls
        for (0..scrollback_size) |i| {
            self.scrollback_lines.?.get(@intCast(i)).* = null;
        }

        self.grid_width = width;
        self.grid_height = height;
        self.scroll_delta = 0;
        self.scroll_animation.reset();
        self.last_scroll_region = .{
            .top = 0,
            .bot = height,
            .left = 0,
            .right = width,
        };
        self.valid = true;
        self.dirty = true;
    }

    pub fn clear(self: *Self) void {
        for (self.cells) |*cell| {
            cell.clear();
        }
        self.dirty = true;
    }

    /// Set a single cell's content
    pub fn setCell(self: *Self, row: u32, col: u32, text: []const u8, hl_id: u64) void {
        if (row >= self.grid_height or col >= self.grid_width) return;
        const idx = row * self.grid_width + col;
        if (idx >= self.cells.len) return;

        self.cells[idx].setText(text);
        self.cells[idx].hl_id = hl_id;
        self.dirty = true;
    }

    pub fn setPosition(self: *Self, row: u64, col: u64, _: u64, _: u64) void {
        self.grid_position = .{ @floatFromInt(col), @floatFromInt(row) };
        self.target_position = self.grid_position;
        self.position_spring_x.position = 0;
        self.position_spring_y.position = 0;

        self.valid = true;
        self.hidden = false;
        self.zindex = 0;
        self.anchor_info = null;
        self.window_type = .editor;
    }

    pub fn setFloatPosition(self: *Self, row: u64, col: u64, zindex: u64) void {
        const new_x: f32 = @floatFromInt(col);
        const new_y: f32 = @floatFromInt(row);

        // Set position immediately - no animation for floating windows (LSP popups etc)
        self.grid_position = .{ new_x, new_y };
        self.target_position = .{ new_x, new_y };
        self.position_spring_x.position = 0;
        self.position_spring_y.position = 0;

        self.valid = true;
        self.hidden = false;
        self.zindex = zindex;
        self.window_type = .floating;
        self.anchor_info = .{
            .anchor_grid_id = 1,
            .anchor_left = new_x,
            .anchor_top = new_y,
            .z_index = zindex,
        };
    }

    pub fn setMessagePosition(self: *Self, row: u64, zindex: u64, parent_width: u32) void {
        _ = parent_width;
        const new_y: f32 = @floatFromInt(row);

        self.grid_position = .{ 0, new_y };
        self.target_position = .{ 0, new_y };
        self.position_spring_x.position = 0;
        self.position_spring_y.position = 0;

        self.valid = true;
        self.hidden = false;
        self.zindex = zindex;
        self.window_type = .message;
        self.anchor_info = .{
            .anchor_grid_id = 1,
            .anchor_left = 0,
            .anchor_top = new_y,
            .z_index = zindex,
        };
    }

    pub fn setViewport(self: *Self, topline: u64, botline: u64, scroll_delta: i64) void {
        _ = topline;
        _ = botline;
        // win_viewport provides scroll_delta directly
        self.scroll_delta = @intCast(scroll_delta);
    }

    /// Handle grid_scroll event - scroll cells and accumulate delta for animation
    pub fn handleScroll(self: *Self, cmd: ScrollCommand) void {
        const top = @as(u32, @intCast(cmd.top));
        const bot = @as(u32, @intCast(cmd.bottom));
        const left = @as(u32, @intCast(cmd.left));
        const right = @as(u32, @intCast(cmd.right));
        const rows = cmd.rows;

        if (rows == 0) return;
        if (self.grid_width == 0 or self.grid_height == 0) return;

        // Save scroll region
        self.last_scroll_region = .{
            .top = top,
            .bot = bot,
            .left = left,
            .right = right,
        };

        // Scroll the cells
        if (rows > 0) {
            // Scrolling up - content moves up, new content appears at bottom
            const scroll_amount: u32 = @intCast(rows);
            var y: u32 = top;
            while (y + scroll_amount < bot) : (y += 1) {
                const dest_row = y;
                const src_row = y + scroll_amount;
                var x: u32 = left;
                while (x < right) : (x += 1) {
                    const dest_idx = dest_row * self.grid_width + x;
                    const src_idx = src_row * self.grid_width + x;
                    if (dest_idx < self.cells.len and src_idx < self.cells.len) {
                        self.cells[dest_idx] = self.cells[src_idx];
                    }
                }
            }
            // Clear newly exposed rows at bottom
            y = bot - scroll_amount;
            while (y < bot) : (y += 1) {
                var x: u32 = left;
                while (x < right) : (x += 1) {
                    const idx = y * self.grid_width + x;
                    if (idx < self.cells.len) {
                        self.cells[idx].clear();
                    }
                }
            }
        } else {
            // Scrolling down - content moves down, new content appears at top
            const scroll_amount: u32 = @intCast(-rows);
            var y: u32 = bot;
            while (y > top + scroll_amount) {
                y -= 1;
                const dest_row = y;
                const src_row = y - scroll_amount;
                var x: u32 = left;
                while (x < right) : (x += 1) {
                    const dest_idx = dest_row * self.grid_width + x;
                    const src_idx = src_row * self.grid_width + x;
                    if (dest_idx < self.cells.len and src_idx < self.cells.len) {
                        self.cells[dest_idx] = self.cells[src_idx];
                    }
                }
            }
            // Clear newly exposed rows at top
            y = top;
            while (y < top + scroll_amount) : (y += 1) {
                var x: u32 = left;
                while (x < right) : (x += 1) {
                    const idx = y * self.grid_width + x;
                    if (idx < self.cells.len) {
                        self.cells[idx].clear();
                    }
                }
            }
        }

        // Accumulate scroll delta for animation
        self.scroll_delta += @intCast(rows);
        self.dirty = true;
    }

    /// Draw a line of cells from grid_line event
    pub fn drawLine(self: *Self, row: u64, col_start: u64, cells: anytype) void {
        if (row >= self.grid_height) return;

        var col: u64 = col_start;
        for (cells) |cell| {
            const repeat = if (@hasField(@TypeOf(cell), "repeat")) cell.repeat else 1;

            var i: u64 = 0;
            while (i < repeat) : (i += 1) {
                if (col >= self.grid_width) break;

                const idx = row * self.grid_width + col;
                if (idx < self.cells.len) {
                    self.cells[idx].setText(cell.text);
                    self.cells[idx].hl_id = cell.hl_id;
                }
                col += 1;
            }
        }
        self.dirty = true;
    }

    /// Get cell at position
    pub fn getCell(self: *const Self, row: u32, col: u32) ?*const GridCell {
        if (row >= self.grid_height or col >= self.grid_width) return null;
        const idx = row * self.grid_width + col;
        if (idx >= self.cells.len) return null;
        return &self.cells[idx];
    }

    /// Get mutable cell at position
    pub fn getCellMut(self: *Self, row: u32, col: u32) ?*GridCell {
        if (row >= self.grid_height or col >= self.grid_width) return null;
        const idx = row * self.grid_width + col;
        if (idx >= self.cells.len) return null;
        return &self.cells[idx];
    }

    /// Flush pending updates - called after Neovim's "flush" event
    /// This is where we update the scroll animation (Neovide-style)
    pub fn flush(self: *Self, cell_height: f32) void {
        _ = cell_height;
        if (!self.valid) return;

        const scroll_delta = self.scroll_delta;
        self.scroll_delta = 0;

        if (scroll_delta != 0) {
            const delta_f: f32 = @floatFromInt(scroll_delta);

            // Maximum visual scroll offset we allow
            // Since we don't have a full scrollback buffer rendering yet,
            // we limit the animation to a small number of lines for a smooth feel
            // This matches Neovide's behavior when scrolling rapidly
            const max_visual_offset: f32 = 3.0; // Max lines of visual animation

            var scroll_offset = self.scroll_animation.position;

            // Accumulate the scroll delta
            scroll_offset -= delta_f;

            // Clamp to prevent runaway accumulation during rapid scrolling
            // This gives a smooth "catching up" feel without huge offsets
            scroll_offset = std.math.clamp(scroll_offset, -max_visual_offset, max_visual_offset);

            log.info("FLUSH scroll: delta={} new_offset={d:.3}", .{
                scroll_delta,
                scroll_offset,
            });

            self.scroll_animation.position = scroll_offset;
        }
    }

    /// Animate the window, returns true if still animating
    pub fn animate(self: *Self, dt: f32) bool {
        var animating = false;

        // Animate scroll using critically damped spring
        if (self.scroll_animation.update(dt, self.scroll_settings.animation_length, 0)) {
            animating = true;
        }

        // Animate position (window movement)
        const snap_threshold: f32 = 10.0;

        if (@abs(self.position_spring_x.position) > snap_threshold) {
            self.position_spring_x.reset();
        } else if (self.position_spring_x.update(dt, self.position_animation_length, 0)) {
            animating = true;
        }

        if (@abs(self.position_spring_y.position) > snap_threshold) {
            self.position_spring_y.reset();
        } else if (self.position_spring_y.update(dt, self.position_animation_length, 0)) {
            animating = true;
        }

        // Update grid_position from springs
        self.grid_position[0] = self.target_position[0] + self.position_spring_x.position;
        self.grid_position[1] = self.target_position[1] + self.position_spring_y.position;

        return animating;
    }

    /// Get scroll offset in whole lines (for determining which lines to read from scrollback)
    pub fn getScrollOffsetLines(self: *const Self) i32 {
        return @intFromFloat(@floor(self.scroll_animation.position));
    }

    /// Get pixel offset for smooth scroll rendering
    /// Returns the full scroll offset in pixels (not just fractional)
    ///
    /// Since we render the CURRENT content (after Neovim has already scrolled the cells),
    /// we need to offset the entire viewport by the animation position.
    ///
    /// Example: if scroll_animation.position = -2.7 and cell_height = 20
    /// - pixel_offset = -2.7 * 20 = -54 pixels
    /// - Content renders 54 pixels HIGHER than final position
    /// - As position animates to 0, content slides down to final position
    pub fn getSubLineOffset(self: *const Self, cell_height: f32) f32 {
        return self.scroll_animation.position * cell_height;
    }

    /// Get the scrollable region bounds (excluding viewport margins)
    pub fn getScrollableRegion(self: *const Self) struct { top: u32, bottom: u32 } {
        return .{
            .top = self.viewport_margins.top,
            .bottom = self.grid_height -| self.viewport_margins.bottom,
        };
    }

    /// Check if a row is in the scrollable region (not a margin row)
    pub fn isRowScrollable(self: *const Self, row: u32) bool {
        return row >= self.viewport_margins.top and
            row < (self.grid_height -| self.viewport_margins.bottom);
    }

    /// Check if window is currently animating
    pub fn isAnimating(self: *const Self) bool {
        return self.scroll_animation.position != 0.0 or
            self.position_spring_x.position != 0.0 or
            self.position_spring_y.position != 0.0;
    }

    /// Get the current scroll animation position (in lines, can be fractional)
    pub fn getScrollPosition(self: *const Self) f32 {
        return self.scroll_animation.position;
    }
};
