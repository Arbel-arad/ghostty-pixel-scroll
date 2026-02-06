//! Cursor Renderer - Neovide-style cursor with trail effect
//!
//! Based on Neovide's cursor rendering:
//! - 4-corner cursor with independent spring animations
//! - Leading corners animate faster, trailing corners lag (creates trail)
//! - Smooth blink with fade

const std = @import("std");
const Animation = @import("animation.zig");

const log = std.log.scoped(.cursor_renderer);

/// Standard corner positions relative to cursor center (-0.5 to 0.5)
const STANDARD_CORNERS: [4][2]f32 = .{
    .{ -0.5, -0.5 }, // top-left
    .{ 0.5, -0.5 }, // top-right
    .{ 0.5, 0.5 }, // bottom-right
    .{ -0.5, 0.5 }, // bottom-left
};

/// A single corner of the cursor quad
pub const Corner = struct {
    /// Current rendered position in pixels
    current_x: f32 = 0,
    current_y: f32 = 0,

    /// Relative position within cursor (-0.5 to 0.5)
    relative_x: f32 = 0,
    relative_y: f32 = 0,

    /// Previous destination (to detect changes)
    prev_dest_x: f32 = -1000,
    prev_dest_y: f32 = -1000,

    /// Spring animations
    spring_x: Animation.CriticallyDampedSpring = .{},
    spring_y: Animation.CriticallyDampedSpring = .{},

    /// Animation length for this corner (varies for trail effect)
    animation_length: f32 = 0.15,

    pub fn update(self: *Corner, dest_x: f32, dest_y: f32, cursor_w: f32, cursor_h: f32, dt: f32, immediate: bool) bool {
        // Calculate this corner's destination
        const corner_dest_x = dest_x + self.relative_x * cursor_w;
        const corner_dest_y = dest_y + self.relative_y * cursor_h;

        // If destination changed, update spring
        if (corner_dest_x != self.prev_dest_x or corner_dest_y != self.prev_dest_y) {
            const delta_x = corner_dest_x - self.current_x;
            const delta_y = corner_dest_y - self.current_y;
            self.spring_x.position = delta_x;
            self.spring_y.position = delta_y;
            self.prev_dest_x = corner_dest_x;
            self.prev_dest_y = corner_dest_y;
        }

        if (immediate) {
            self.current_x = corner_dest_x;
            self.current_y = corner_dest_y;
            self.spring_x.position = 0;
            self.spring_y.position = 0;
            return false;
        }

        // Update springs
        const anim_x = self.spring_x.update(dt, self.animation_length, 0);
        const anim_y = self.spring_y.update(dt, self.animation_length, 0);

        // Current position = destination - remaining spring offset
        self.current_x = corner_dest_x - self.spring_x.position;
        self.current_y = corner_dest_y - self.spring_y.position;

        return anim_x or anim_y;
    }

    /// Calculate how aligned this corner is with movement direction
    pub fn calcDirectionAlignment(self: *const Corner, dest_x: f32, dest_y: f32, cursor_w: f32, cursor_h: f32) f32 {
        const corner_dest_x = dest_x + self.relative_x * cursor_w;
        const corner_dest_y = dest_y + self.relative_y * cursor_h;

        // Direction from current position to destination
        const dx = corner_dest_x - self.current_x;
        const dy = corner_dest_y - self.current_y;
        const dist = @sqrt(dx * dx + dy * dy);
        if (dist < 0.001) return 0;

        const travel_dir_x = dx / dist;
        const travel_dir_y = dy / dist;

        // Corner's relative direction (normalized)
        const rel_len = @sqrt(self.relative_x * self.relative_x + self.relative_y * self.relative_y);
        if (rel_len < 0.001) return 0;

        const corner_dir_x = self.relative_x / rel_len;
        const corner_dir_y = self.relative_y / rel_len;

        // Dot product = alignment
        return travel_dir_x * corner_dir_x + travel_dir_y * corner_dir_y;
    }
};

/// Neovide-style cursor renderer
pub const CursorRenderer = struct {
    const Self = @This();

    /// The 4 corners of the cursor quad
    corners: [4]Corner = undefined,

    /// Current cursor destination in pixels (top-left of cursor cell)
    dest_x: f32 = 0,
    dest_y: f32 = 0,

    /// Previous destination for jump detection
    prev_dest_x: f32 = -1000,
    prev_dest_y: f32 = -1000,

    /// Previous grid ID - for detecting window changes (like Neovide's previous_cursor_position)
    prev_grid: u64 = 0,

    /// Cursor size
    width: f32 = 10,
    height: f32 = 20,

    /// Animation settings
    animation_length: f32 = 0.06, // 60ms for longer jumps
    short_animation_length: f32 = 0.015, // 15ms for typing (nearly instant)
    trail_size: f32 = 0.5, // 0 = no trail, 1 = max trail

    /// Blink state
    blink_time: f32 = 0,
    /// Time to wait before starting to blink (ms converted to seconds)
    blink_wait: f32 = 0.7,
    /// Time cursor is on during blink (ms converted to seconds)
    blink_on: f32 = 0.4,
    /// Time cursor is off during blink (ms converted to seconds)
    blink_off: f32 = 0.25,
    /// Whether blinking is enabled
    blink_enabled: bool = true,
    /// Current blink opacity (for smooth transitions)
    blink_opacity: f32 = 1.0,
    /// Target blink opacity
    blink_target: f32 = 1.0,
    /// Whether we're in the initial wait period
    in_blink_wait: bool = true,
    /// Smooth blink transition speed (higher = faster)
    blink_smooth_speed: f32 = 8.0,

    /// Whether animating
    animating: bool = false,

    /// Whether a jump just happened
    jumped: bool = false,

    pub fn init() Self {
        var self = Self{};
        // Initialize corners with standard positions
        for (&self.corners, 0..) |*corner, i| {
            corner.* = Corner{
                .relative_x = STANDARD_CORNERS[i][0],
                .relative_y = STANDARD_CORNERS[i][1],
            };
        }
        return self;
    }

    /// Set cursor position with grid tracking (called from renderer)
    /// Following Neovide: if grid changes, snap immediately; otherwise animate
    /// col/row are SCREEN coordinates (already includes window offset)
    pub fn setCursorPositionWithGrid(self: *Self, grid: u64, col: u16, row: u16, cell_w: f32, cell_h: f32) void {
        self.width = cell_w;
        self.height = cell_h;

        // Destination is top-left of cursor cell (like Neovide)
        const new_dest_x = @as(f32, @floatFromInt(col)) * cell_w;
        const new_dest_y = @as(f32, @floatFromInt(row)) * cell_h;

        // If grid changed, snap immediately (don't animate across windows)
        // This matches Neovide's behavior where previous_cursor_position includes window ID
        if (grid != self.prev_grid) {
            self.prev_grid = grid;
            self.snap(col, row, cell_w, cell_h);
            return;
        }

        // Only mark as jumped if position actually changed
        if (new_dest_x != self.dest_x or new_dest_y != self.dest_y) {
            self.prev_dest_x = self.dest_x;
            self.prev_dest_y = self.dest_y;
            self.dest_x = new_dest_x;
            self.dest_y = new_dest_y;
            self.jumped = true;
        }
    }

    /// Update animation state
    pub fn update(self: *Self, dt: f32) bool {
        // Update blink timing
        self.updateBlink(dt);

        // Center destination for corners
        const center_x = self.dest_x + self.width / 2;
        const center_y = self.dest_y + self.height / 2;

        // If jumped, calculate corner ranks and set animation lengths
        if (self.jumped) {
            self.setupCornerAnimations(center_x, center_y);
            self.jumped = false;
            // Reset blink when cursor moves (like Neovide)
            self.resetBlink();
        }

        // Update each corner
        var any_animating = false;
        for (&self.corners) |*corner| {
            if (corner.update(center_x, center_y, self.width, self.height, dt, false)) {
                any_animating = true;
            }
        }

        self.animating = any_animating;
        return any_animating;
    }

    fn setupCornerAnimations(self: *Self, center_x: f32, center_y: f32) void {
        // Calculate movement distance
        const dx = self.dest_x - self.prev_dest_x;
        const dy = self.dest_y - self.prev_dest_y;
        const dist = @sqrt(dx * dx + dy * dy);

        // Short jump = typing (use short animation for all)
        const is_short_jump = @abs(dx) <= self.width * 2.5 and @abs(dy) < 1.0;

        if (is_short_jump or dist < 0.001) {
            // All corners animate at same speed for typing
            for (&self.corners) |*corner| {
                corner.animation_length = self.short_animation_length;
            }
            return;
        }

        // Calculate alignment for each corner and rank them
        var alignments: [4]f32 = undefined;
        for (&self.corners, 0..) |*corner, i| {
            alignments[i] = corner.calcDirectionAlignment(center_x, center_y, self.width, self.height);
        }

        // Sort indices by alignment (lowest first = trailing)
        var indices: [4]usize = .{ 0, 1, 2, 3 };
        for (0..4) |i| {
            for (i + 1..4) |j| {
                if (alignments[indices[i]] > alignments[indices[j]]) {
                    const tmp = indices[i];
                    indices[i] = indices[j];
                    indices[j] = tmp;
                }
            }
        }

        // Assign animation lengths based on rank
        // Rank 0 (most trailing) = full animation length
        // Rank 3 (most leading) = leading animation length (faster)
        const leading = self.animation_length * (1.0 - self.trail_size);
        const trailing = self.animation_length;

        for (indices, 0..) |corner_idx, rank| {
            self.corners[corner_idx].animation_length = switch (rank) {
                0 => trailing, // Most trailing - slowest
                1 => (leading + trailing) / 2, // Middle
                2, 3 => leading, // Leading - fastest
                else => self.animation_length,
            };
        }
    }

    /// Get the 4 corner positions for rendering
    pub fn getCorners(self: *const Self) [4][2]f32 {
        return .{
            .{ self.corners[0].current_x, self.corners[0].current_y },
            .{ self.corners[1].current_x, self.corners[1].current_y },
            .{ self.corners[2].current_x, self.corners[2].current_y },
            .{ self.corners[3].current_x, self.corners[3].current_y },
        };
    }

    /// Update blink state with smooth transitions
    fn updateBlink(self: *Self, dt: f32) void {
        if (!self.blink_enabled) {
            self.blink_opacity = 1.0;
            return;
        }

        self.blink_time += dt;

        // Determine target opacity based on blink cycle
        if (self.in_blink_wait) {
            // During wait period, cursor is always visible
            self.blink_target = 1.0;
            if (self.blink_time >= self.blink_wait) {
                self.blink_time -= self.blink_wait;
                self.in_blink_wait = false;
            }
        } else {
            // Blinking cycle: on -> off -> on -> off...
            const cycle_time = self.blink_on + self.blink_off;
            const cycle_pos = @mod(self.blink_time, cycle_time);

            if (cycle_pos < self.blink_on) {
                self.blink_target = 1.0; // Cursor on
            } else {
                self.blink_target = 0.0; // Cursor off
            }
        }

        // Smooth transition to target opacity
        const diff = self.blink_target - self.blink_opacity;
        if (@abs(diff) < 0.01) {
            self.blink_opacity = self.blink_target;
        } else {
            self.blink_opacity += diff * self.blink_smooth_speed * dt;
            self.blink_opacity = std.math.clamp(self.blink_opacity, 0.0, 1.0);
        }
    }

    /// Reset blink state (called when cursor moves)
    pub fn resetBlink(self: *Self) void {
        self.blink_time = 0;
        self.in_blink_wait = true;
        self.blink_opacity = 1.0;
        self.blink_target = 1.0;
    }

    /// Set blink timing from Neovim mode_info
    /// Times are in milliseconds, 0 means disabled
    pub fn setBlinkTiming(self: *Self, blinkwait: ?u64, blinkon: ?u64, blinkoff: ?u64) void {
        // Convert from ms to seconds, use defaults if not specified
        self.blink_wait = if (blinkwait) |w| @as(f32, @floatFromInt(w)) / 1000.0 else 0.7;
        self.blink_on = if (blinkon) |on| @as(f32, @floatFromInt(on)) / 1000.0 else 0.4;
        self.blink_off = if (blinkoff) |off| @as(f32, @floatFromInt(off)) / 1000.0 else 0.25;

        // Blinking is disabled if any timing is 0
        self.blink_enabled = self.blink_on > 0 and self.blink_off > 0;

        // Reset blink state when timing changes
        self.resetBlink();
    }

    /// Snap cursor to position immediately (no animation)
    pub fn snap(self: *Self, col: u16, row: u16, cell_w: f32, cell_h: f32) void {
        self.width = cell_w;
        self.height = cell_h;
        self.dest_x = @as(f32, @floatFromInt(col)) * cell_w;
        self.dest_y = @as(f32, @floatFromInt(row)) * cell_h;
        self.prev_dest_x = self.dest_x;
        self.prev_dest_y = self.dest_y;

        // Corners are positioned relative to CENTER of cursor
        const center_x = self.dest_x + self.width / 2;
        const center_y = self.dest_y + self.height / 2;

        for (&self.corners) |*corner| {
            // Each corner position = center + relative_offset * dimensions
            corner.current_x = center_x + corner.relative_x * self.width;
            corner.current_y = center_y + corner.relative_y * self.height;
            corner.prev_dest_x = corner.current_x;
            corner.prev_dest_y = corner.current_y;
            corner.spring_x.position = 0;
            corner.spring_y.position = 0;
            corner.spring_x.velocity = 0;
            corner.spring_y.velocity = 0;
        }

        self.jumped = false;
        self.animating = false;
    }
};
