//! Animation utilities for Neovim GUI
//!
//! Includes the critically damped spring animation used for smooth scrolling,
//! matching Neovide's implementation exactly.

const std = @import("std");

/// Critically damped spring animation (matches Neovide exactly)
///
/// This simulates a PD controller / critically damped harmonic oscillator.
/// The spring animates from an initial position toward 0.
///
/// Key properties:
/// - Zeta = 1.0 (critically damped - no oscillation)
/// - Omega calculated so destination reached within animation_length
/// - Position approaches 0 asymptotically
pub const CriticallyDampedSpring = struct {
    const Self = @This();

    /// Current position (in lines). Negative = showing old content.
    position: f32 = 0,
    /// Current velocity
    velocity: f32 = 0,

    /// Update the spring animation.
    /// Returns true if still animating, false if reached destination.
    pub fn update(self: *Self, dt: f32, animation_length: f32, target: f32) bool {
        _ = target;

        if (animation_length <= dt) {
            self.reset();
            return false;
        }

        if (self.position == 0.0) {
            return false;
        }

        // Critically damped spring (zeta = 1)
        // Omega calculated so destination reached with 2% tolerance in animation_length
        const zeta: f32 = 1.0;
        const omega = 4.0 / (zeta * animation_length);

        // Analytical solution for critically damped harmonic oscillator
        // Initial conditions: a = position, b = position * omega + velocity
        const a = self.position;
        const b = self.position * omega + self.velocity;

        const c = @exp(-omega * dt);

        self.position = (a + b * dt) * c;
        self.velocity = c * (-a * omega - b * dt * omega + b);

        // Check if we've effectively reached the destination
        // Use 0.01 like Neovide (not 0.001)
        // NOTE: Don't reset to 0 here! Just stop animating and let the small residual
        // value remain. This prevents visual jumps when new scroll events arrive.
        if (@abs(self.position) < 0.01) {
            // Don't reset - just indicate we're done animating
            // The position will be overwritten by the next scroll event anyway
            return false;
        }

        return true;
    }

    /// Reset the animation to rest state
    pub fn reset(self: *Self) void {
        self.position = 0;
        self.velocity = 0;
    }
};

/// Linear interpolation
pub fn lerp(start: f32, end: f32, t: f32) f32 {
    return start + (end - start) * t;
}

/// Ease out exponential
pub fn easeOutExpo(t: f32) f32 {
    if ((t - 1.0) >= -std.math.floatEps(f32) and (t - 1.0) <= std.math.floatEps(f32)) {
        return 1.0;
    }
    return 1.0 - std.math.pow(f32, 2.0, -10.0 * t);
}

/// Ease with custom function
pub fn ease(ease_func: *const fn (f32) f32, start: f32, end: f32, t: f32) f32 {
    return lerp(start, end, ease_func(t));
}

test "CriticallyDampedSpring basic" {
    var spring = CriticallyDampedSpring{};
    spring.position = -1.0;

    // Should animate toward 0
    var iterations: usize = 0;
    while (spring.update(1.0 / 60.0, 0.3, 0.0)) {
        iterations += 1;
        if (iterations > 1000) break; // Safety limit
    }

    try std.testing.expect(spring.position == 0.0);
    try std.testing.expect(iterations > 0);
    try std.testing.expect(iterations < 100); // Should converge relatively quickly
}

test "CriticallyDampedSpring no oscillation" {
    var spring = CriticallyDampedSpring{};
    spring.position = -5.0;

    var prev_pos = spring.position;
    var crossed_zero = false;

    while (spring.update(1.0 / 60.0, 0.3, 0.0)) {
        // Position should monotonically approach 0 (no oscillation)
        if (spring.position > 0 and prev_pos < 0) {
            crossed_zero = true;
        }
        if (spring.position < 0 and prev_pos > 0) {
            crossed_zero = true;
        }
        prev_pos = spring.position;
    }

    // Critically damped should not oscillate
    try std.testing.expect(!crossed_zero);
}
