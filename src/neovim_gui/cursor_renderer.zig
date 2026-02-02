//! Cursor Renderer - Neovide-style cursor with trail effect and particles
//!
//! This implements the iconic Neovide cursor features:
//! - 4-corner cursor with independent animation (creates trail/smear effect)
//! - Particle effects (railgun, torpedo, pixiedust, sonicboom, ripple, wireframe)
//! - Smooth blink with fade in/out

const std = @import("std");
const Animation = @import("animation.zig");

const log = std.log.scoped(.cursor_renderer);

/// Cursor particle effect mode
pub const VfxMode = enum {
    none,
    railgun,
    torpedo,
    pixiedust,
    sonicboom,
    ripple,
    wireframe,
};

/// A single corner of the cursor quad
pub const Corner = struct {
    /// Current rendered position in pixels
    current_x: f32 = 0,
    current_y: f32 = 0,
    /// Target position in pixels
    target_x: f32 = 0,
    target_y: f32 = 0,
    /// Relative position within cursor (-0.5 to 0.5 for each axis)
    relative_x: f32 = 0,
    relative_y: f32 = 0,
    /// Spring animation for this corner
    spring_x: Animation.CriticallyDampedSpring = .{},
    spring_y: Animation.CriticallyDampedSpring = .{},
    /// Animation length for this corner (varies based on trail effect)
    animation_length: f32 = 0.15,

    pub fn update(self: *Corner, dt: f32) bool {
        const animating_x = self.spring_x.update(dt, self.animation_length, 0);
        const animating_y = self.spring_y.update(dt, self.animation_length, 0);

        self.current_x = self.target_x - self.spring_x.position;
        self.current_y = self.target_y - self.spring_y.position;

        return animating_x or animating_y;
    }

    pub fn setTarget(self: *Corner, x: f32, y: f32) void {
        const dx = x - self.current_x;
        const dy = y - self.current_y;
        self.spring_x.position = -dx;
        self.spring_y.position = -dy;
        self.target_x = x;
        self.target_y = y;
    }

    pub fn snap(self: *Corner, x: f32, y: f32) void {
        self.current_x = x;
        self.current_y = y;
        self.target_x = x;
        self.target_y = y;
        self.spring_x.reset();
        self.spring_y.reset();
    }
};

/// A particle emitted by the cursor
pub const Particle = struct {
    x: f32 = 0,
    y: f32 = 0,
    velocity_x: f32 = 0,
    velocity_y: f32 = 0,
    lifetime: f32 = 0,
    max_lifetime: f32 = 0.5,
    color_r: u8 = 255,
    color_g: u8 = 255,
    color_b: u8 = 255,

    pub fn update(self: *Particle, dt: f32) bool {
        self.lifetime -= dt;
        if (self.lifetime <= 0) return false;

        self.x += self.velocity_x * dt;
        self.y += self.velocity_y * dt;

        // Apply friction
        self.velocity_x *= 0.95;
        self.velocity_y *= 0.95;

        return true;
    }

    pub fn getAlpha(self: *const Particle) u8 {
        const t = self.lifetime / self.max_lifetime;
        return @intFromFloat(t * 255);
    }
};

/// Neovide-style cursor renderer
pub const CursorRenderer = struct {
    const Self = @This();
    const MAX_PARTICLES = 256;

    /// The 4 corners of the cursor quad
    /// Order: top-left, top-right, bottom-right, bottom-left
    corners: [4]Corner = .{
        .{ .relative_x = -0.5, .relative_y = -0.5 }, // TL
        .{ .relative_x = 0.5, .relative_y = -0.5 }, // TR
        .{ .relative_x = 0.5, .relative_y = 0.5 }, // BR
        .{ .relative_x = -0.5, .relative_y = 0.5 }, // BL
    },

    /// Current cursor grid position
    grid_x: u16 = 0,
    grid_y: u16 = 0,

    /// Previous position for detecting movement
    prev_grid_x: u16 = 0,
    prev_grid_y: u16 = 0,

    /// Cursor destination in pixels (center of cursor)
    dest_x: f32 = 0,
    dest_y: f32 = 0,

    /// Cursor size in pixels
    width: f32 = 0,
    height: f32 = 0,

    /// Animation settings
    animation_length: f32 = 0.15,
    short_animation_length: f32 = 0.04,
    trail_size: f32 = 0.7, // 0.0 = no trail, 1.0 = maximum trail

    /// Particle effect settings
    vfx_mode: VfxMode = .none,
    vfx_opacity: f32 = 200.0,
    vfx_particle_lifetime: f32 = 0.5,
    vfx_particle_density: f32 = 0.7,
    vfx_particle_speed: f32 = 10.0,

    /// Particles
    particles: [MAX_PARTICLES]Particle = undefined,
    particle_count: usize = 0,

    /// Blink state
    blink_phase: f32 = 0, // 0.0 to 1.0, used for smooth blink
    blink_on: bool = true,
    blink_rate: f32 = 0.5, // seconds per blink cycle

    /// Whether cursor is currently animating
    animating: bool = false,

    pub fn init() Self {
        var self = Self{};
        // Initialize particles
        for (&self.particles) |*p| {
            p.* = Particle{};
        }
        return self;
    }

    /// Update cursor position (called when Neovim sends cursor_goto)
    pub fn setCursorPosition(self: *Self, grid_x: u16, grid_y: u16, cell_width: f32, cell_height: f32) void {
        self.prev_grid_x = self.grid_x;
        self.prev_grid_y = self.grid_y;
        self.grid_x = grid_x;
        self.grid_y = grid_y;

        self.width = cell_width;
        self.height = cell_height;

        // Calculate pixel destination (center of cursor cell)
        const new_dest_x = @as(f32, @floatFromInt(grid_x)) * cell_width + cell_width / 2;
        const new_dest_y = @as(f32, @floatFromInt(grid_y)) * cell_height + cell_height / 2;

        if (new_dest_x != self.dest_x or new_dest_y != self.dest_y) {
            self.onCursorMoved(new_dest_x, new_dest_y, cell_width);
        }

        self.dest_x = new_dest_x;
        self.dest_y = new_dest_y;
    }

    fn onCursorMoved(self: *Self, new_x: f32, new_y: f32, cell_width: f32) void {
        const dx = new_x - self.dest_x;
        const dy = new_y - self.dest_y;
        const distance = @sqrt(dx * dx + dy * dy);

        // Determine if this is a short jump (typing) or long jump
        const is_short_jump = @abs(dx) <= cell_width * 2.5 and @abs(dy) < 1.0;

        // Calculate animation lengths for each corner based on trail_size
        // Front corners move faster, back corners move slower (creates trail)
        const base_length = if (is_short_jump) self.short_animation_length else self.animation_length;
        const leading_length = base_length * (1.0 - self.trail_size);
        const trailing_length = base_length;

        // Determine which corners are "leading" based on movement direction
        const dir_x = if (distance > 0) dx / distance else 0;
        const dir_y = if (distance > 0) dy / distance else 0;

        for (&self.corners, 0..) |*corner, i| {
            // Calculate how aligned this corner is with movement direction
            const alignment = corner.relative_x * dir_x + corner.relative_y * dir_y;

            // Leading corners (aligned with movement) animate faster
            // Trailing corners animate slower
            if (alignment > 0.3) {
                corner.animation_length = leading_length;
            } else if (alignment < -0.3) {
                corner.animation_length = trailing_length;
            } else {
                corner.animation_length = (leading_length + trailing_length) / 2;
            }

            // Calculate corner destination
            const corner_x = new_x + corner.relative_x * self.width;
            const corner_y = new_y + corner.relative_y * self.height;
            corner.setTarget(corner_x, corner_y);

            _ = i;
        }

        self.animating = true;

        // Spawn particles if VFX enabled
        if (self.vfx_mode != .none) {
            self.spawnParticles(self.dest_x, self.dest_y, dx, dy);
        }
    }

    fn spawnParticles(self: *Self, x: f32, y: f32, dx: f32, dy: f32) void {
        const distance = @sqrt(dx * dx + dy * dy);
        const num_particles: usize = @intFromFloat(distance * self.vfx_particle_density / 10.0);

        for (0..@min(num_particles, 20)) |_| {
            if (self.particle_count >= MAX_PARTICLES) break;

            var p = &self.particles[self.particle_count];
            p.x = x;
            p.y = y;
            p.lifetime = self.vfx_particle_lifetime;
            p.max_lifetime = self.vfx_particle_lifetime;

            // Velocity based on VFX mode
            var prng = std.Random.DefaultPrng.init(@bitCast(std.time.timestamp()));
            const rand = prng.random();

            switch (self.vfx_mode) {
                .railgun => {
                    // Particles spread perpendicular to movement
                    const perp_x = -dy / (distance + 0.001);
                    const perp_y = dx / (distance + 0.001);
                    const spread = (rand.float(f32) - 0.5) * self.vfx_particle_speed * 2;
                    p.velocity_x = perp_x * spread - dx * 0.5;
                    p.velocity_y = perp_y * spread - dy * 0.5;
                },
                .torpedo => {
                    // Particles trail behind
                    p.velocity_x = -dx * rand.float(f32) * 0.5;
                    p.velocity_y = -dy * rand.float(f32) * 0.5;
                },
                .pixiedust => {
                    // Random sparkle
                    p.velocity_x = (rand.float(f32) - 0.5) * self.vfx_particle_speed;
                    p.velocity_y = (rand.float(f32) - 0.5) * self.vfx_particle_speed;
                },
                else => {
                    p.velocity_x = 0;
                    p.velocity_y = 0;
                },
            }

            self.particle_count += 1;
        }
    }

    /// Update animation state, returns true if still animating
    pub fn update(self: *Self, dt: f32) bool {
        var still_animating = false;

        // Update corners
        for (&self.corners) |*corner| {
            if (corner.update(dt)) {
                still_animating = true;
            }
        }

        // Update particles
        var write_idx: usize = 0;
        for (0..self.particle_count) |read_idx| {
            if (self.particles[read_idx].update(dt)) {
                if (write_idx != read_idx) {
                    self.particles[write_idx] = self.particles[read_idx];
                }
                write_idx += 1;
            }
        }
        self.particle_count = write_idx;
        if (self.particle_count > 0) still_animating = true;

        // Update blink
        self.blink_phase += dt / self.blink_rate;
        if (self.blink_phase >= 1.0) {
            self.blink_phase -= 1.0;
            self.blink_on = !self.blink_on;
        }

        self.animating = still_animating;
        return still_animating;
    }

    /// Get the current cursor quad corners for rendering
    pub fn getCorners(self: *const Self) [4][2]f32 {
        return .{
            .{ self.corners[0].current_x, self.corners[0].current_y },
            .{ self.corners[1].current_x, self.corners[1].current_y },
            .{ self.corners[2].current_x, self.corners[2].current_y },
            .{ self.corners[3].current_x, self.corners[3].current_y },
        };
    }

    /// Get blink opacity (0.0 to 1.0) for smooth blink effect
    pub fn getBlinkOpacity(self: *const Self) f32 {
        // Smooth sine wave blink
        const phase = self.blink_phase * std.math.pi * 2;
        return (@sin(phase) + 1.0) / 2.0;
    }

    /// Snap cursor to position immediately (no animation)
    pub fn snap(self: *Self, grid_x: u16, grid_y: u16, cell_width: f32, cell_height: f32) void {
        self.grid_x = grid_x;
        self.grid_y = grid_y;
        self.prev_grid_x = grid_x;
        self.prev_grid_y = grid_y;
        self.width = cell_width;
        self.height = cell_height;

        self.dest_x = @as(f32, @floatFromInt(grid_x)) * cell_width + cell_width / 2;
        self.dest_y = @as(f32, @floatFromInt(grid_y)) * cell_height + cell_height / 2;

        for (&self.corners) |*corner| {
            const corner_x = self.dest_x + corner.relative_x * self.width;
            const corner_y = self.dest_y + corner.relative_y * self.height;
            corner.snap(corner_x, corner_y);
        }

        self.animating = false;
    }
};
