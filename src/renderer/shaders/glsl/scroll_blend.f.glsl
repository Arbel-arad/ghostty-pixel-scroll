#version 430 core

// Scroll blend fragment shader for Neovide-style smooth TUI scrolling.
//
// Key insight from Neovide:
// - The previous frame shows content at OLD positions (before scroll)
// - The current frame shows content at NEW positions (after scroll)
// - During animation, we shift the prev_frame content by scroll_offset_y
// - When shifted content leaves the scroll region, we reveal curr_frame content
//
// The animation works like this:
// - scroll_offset_y starts at the full scroll delta (in pixels)
// - It animates toward 0
// - At each frame, we sample prev_frame shifted by scroll_offset_y
// - Where the shifted sample goes outside the scroll region, show curr_frame

layout(origin_upper_left) in vec4 gl_FragCoord;

layout(location = 0) out vec4 out_FragColor;

// Scroll blend uniforms
layout(binding = 1, std140) uniform ScrollBlendUniforms {
    float blend_factor;       // Animation progress: 0.0 = start, 1.0 = done
    float scroll_offset_y;    // Current scroll offset in pixels (animates from delta toward 0)
    float screen_height;      // Total screen height in pixels
    float screen_width;       // Total screen width in pixels
    float cell_height;        // Height of one cell in pixels
    float scroll_region_top;  // Top of scroll region (in pixels from top of screen)
    float scroll_region_bot;  // Bottom of scroll region (in pixels from top of screen)
    float padding_top;        // Top padding in pixels
};

// The previous frame texture (texture unit 0)
layout(binding = 0) uniform sampler2D prev_frame;

// The current frame texture (texture unit 1)  
layout(binding = 1) uniform sampler2D curr_frame;

void main() {
    // Fragment position in pixels (origin upper-left due to layout qualifier)
    vec2 frag_pos = gl_FragCoord.xy;
    
    // Calculate normalized UV for texture sampling
    // OpenGL textures have origin at bottom-left, so we flip Y
    vec2 tex_size = vec2(textureSize(curr_frame, 0));
    
    // Use screen dimensions for coordinate conversion, not texture size
    // (they should match, but let's be explicit)
    vec2 screen_size = vec2(screen_width, screen_height);
    vec2 uv = frag_pos / screen_size;
    vec2 uv_flipped = vec2(uv.x, 1.0 - uv.y);
    
    // DEBUG: Uncomment to visualize regions
    bool debug_mode = true;
    // bool debug_mode = false;
    
    // EXTREME DEBUG: Show prev_frame as RED, curr_frame as GREEN
    // to clearly see which texture is being sampled
    bool extreme_debug = false;
    
    // If animation is complete, just show current frame
    if (blend_factor >= 0.999 || abs(scroll_offset_y) < 0.5) {
        out_FragColor = texture(curr_frame, uv_flipped);
        return;
    }
    
    // Check if this fragment is in the scroll region (between header and statusline)
    bool in_scroll_region = frag_pos.y >= scroll_region_top && frag_pos.y < scroll_region_bot;
    
    if (!in_scroll_region) {
        // BORDER REGION (header/statusline): Always show current frame
        // This keeps the UI chrome fixed in place
        vec4 color = texture(curr_frame, uv_flipped);
        if (debug_mode) {
            // RED tint for border regions (header/statusline)
            color.r = min(1.0, color.r + 0.3);
        }
        out_FragColor = color;
        return;
    }
    
    // SCROLLABLE REGION: We need to show the OLD content sliding to its new position
    //
    // Key insight: prev_frame shows content BEFORE scroll, curr_frame shows AFTER.
    // We sample prev_frame at a shifted position to show the old content "moving".
    //
    // Scroll direction and offset:
    // - Scrolling DOWN (content moves UP): scroll_offset_y is POSITIVE
    //   At position y, sample prev_frame at (y + offset) to get content from below
    // - Scrolling UP (content moves DOWN): scroll_offset_y is NEGATIVE
    //   At position y, sample prev_frame at (y + offset) to get content from above
    
    // The key insight: we want to show content smoothly transitioning from
    // its OLD position to its NEW position.
    //
    // prev_frame has content at OLD positions (before scroll)
    // curr_frame has content at NEW positions (after scroll)
    //
    // For smooth scrolling, we need to show the content at an INTERMEDIATE position.
    // We do this by sampling prev_frame at a shifted position.
    //
    // When scroll_offset_y = cell_height (full scroll distance), we show prev_frame
    // shifted by one cell - content appears at its OLD position.
    // When scroll_offset_y = 0, we want content at its NEW position, so show curr_frame.
    
    float prev_y = frag_pos.y + scroll_offset_y;
    
    // Sample current frame at this position (NEW content positions)
    vec4 curr_color = texture(curr_frame, uv_flipped);
    
    // Check if the shifted sample position is within the scroll region
    if (prev_y < scroll_region_top || prev_y >= scroll_region_bot) {
        // The prev_frame sample would be outside the scroll region
        // This is where NEW content should be revealed (at edge of scroll region)
        if (debug_mode) {
            // BLUE tint for edges where new content is revealed
            curr_color.b = min(1.0, curr_color.b + 0.3);
        }
        out_FragColor = curr_color;
        return;
    }
    
    // Sample from previous frame at the shifted position
    vec2 prev_uv = vec2(frag_pos.x / screen_size.x, 1.0 - (prev_y / screen_size.y));
    vec4 prev_color = texture(prev_frame, prev_uv);
    
    // The animation works by shifting the old content toward the new position.
    // But there's a problem: at the end of animation, even with shift=0,
    // prev_frame still has OLD content, not NEW content.
    //
    // To fix this, we need to cross-fade near the end of the animation.
    // When offset is small (near final position), start blending in curr_frame.
    //
    // Use a smooth transition: when offset < 1 cell, start blending
    float fade_threshold = cell_height * 0.5; // Start fading at half a cell
    float fade_progress = 0.0;
    if (abs(scroll_offset_y) < fade_threshold) {
        fade_progress = 1.0 - (abs(scroll_offset_y) / fade_threshold);
    }
    
    vec4 color = mix(prev_color, curr_color, fade_progress);
    
    if (extreme_debug) {
        // Show prev_frame content as RED, curr_frame content as GREEN
        // This makes it crystal clear which texture we're sampling from
        vec4 red = vec4(1.0, 0.0, 0.0, 1.0);
        vec4 green = vec4(0.0, 1.0, 0.0, 1.0);
        color = mix(red, green, fade_progress);
    } else if (debug_mode) {
        // GREEN tint for scroll region content (intensity shows fade progress)
        color.g = min(1.0, color.g + 0.2 * (1.0 - fade_progress));
    }
    out_FragColor = color;
}
