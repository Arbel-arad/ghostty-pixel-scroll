#include "common.glsl"

// Position the origin to the upper left
layout(origin_upper_left) in vec4 gl_FragCoord;

// Must declare this output for some versions of OpenGL.
layout(location = 0) out vec4 out_FragColor;

layout(binding = 1, std430) readonly buffer bg_cells {
    uint cells[];
};

vec4 cell_bg() {
    uvec2 grid_size = unpack2u16(grid_size_packed_2u16);
    bool use_linear_blending = (bools & USE_LINEAR_BLENDING) != 0;
    
    // Determine effective scroll region (bot = 0 means use grid height)
    uint effective_scroll_bot = scroll_region_bot == 0u ? grid_size.y : scroll_region_bot;
    
    // Calculate grid position from fragment coordinates
    // We apply pixel_scroll_offset_y here to match the vertex shader shift
    // This is for base grid alignment (terminal scrollback), NOT TUI scroll animation
    vec2 adjusted_coord = gl_FragCoord.xy;
    adjusted_coord.y += pixel_scroll_offset_y;
    
    // For TUI scroll animation: determine if this fragment is in the scroll region
    // and apply the inverse offset to find which cell's background to draw.
    // The text cells are shifted by tui_scroll_offset_y, so we need to shift the
    // background sampling in the opposite direction to match.
    ivec2 grid_pos = ivec2(floor((adjusted_coord - grid_padding.wx) / cell_size));
    
    // Check if this grid position is in the scroll region BEFORE applying TUI offset
    bool in_scroll_region = grid_pos.y >= int(scroll_region_top) && grid_pos.y < int(effective_scroll_bot);
    
    // Apply TUI scroll offset to the coordinate for sampling
    // Since text is shifted by +offset (vertex shader), we need to shift the background sampling
    // to match.
    // If offset is negative (text moves UP), we want to see the background that was originally
    // BELOW this pixel. So we need to add a positive amount to the Y coord.
    // coordinate - offset = coordinate - (-amount) = coordinate + amount (DOWN)
    if (tui_scroll_offset_y != 0.0 && in_scroll_region) {
        adjusted_coord.y -= tui_scroll_offset_y;
        grid_pos = ivec2(floor((adjusted_coord - grid_padding.wx) / cell_size));
    }

    vec4 bg = vec4(0.0);

    // Clamp x position, extends edge bg colors in to padding on sides.
    if (grid_pos.x < 0) {
        if ((padding_extend & EXTEND_LEFT) != 0) {
            grid_pos.x = 0;
        } else {
            return bg;
        }
    } else if (grid_pos.x > grid_size.x - 1) {
        if ((padding_extend & EXTEND_RIGHT) != 0) {
            grid_pos.x = int(grid_size.x) - 1;
        } else {
            return bg;
        }
    }

    // Clamp y position if we should extend, otherwise discard if out of bounds.
    if (grid_pos.y < 0) {
        if ((padding_extend & EXTEND_UP) != 0) {
            grid_pos.y = 0;
        } else {
            return bg;
        }
    } else if (grid_pos.y > grid_size.y - 1) {
        if ((padding_extend & EXTEND_DOWN) != 0) {
            grid_pos.y = int(grid_size.y) - 1;
        } else {
            return bg;
        }
    }

    // Load the color for the cell.
    vec4 cell_color = load_color(
            unpack4u8(cells[grid_pos.y * grid_size.x + grid_pos.x]),
            use_linear_blending
        );

    return cell_color;
}

void main() {
    out_FragColor = cell_bg();
}
