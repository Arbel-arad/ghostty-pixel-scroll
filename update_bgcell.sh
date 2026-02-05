#!/bin/bash
# Script to update all bgCell assignments to use the new CellBg struct format

set -e

FILE="src/renderer/generic.zig"

echo "Updating bgCell assignments in $FILE..."

# Read the file to find which sections need which offset
# We'll do this in multiple passes for different contexts

# Pass 1: Update the default background fill (line ~1597) - no offset
sed -i 's/self\.cells\.bgCell(y, x)\.\* = \.{ bg_r, bg_g, bg_b, 255 };/self.cells.bgCell(y, x).* = .{ .color = .{ bg_r, bg_g, bg_b, 255 }, .offset_y_fixed = 0, };/g' "$FILE"

# Pass 2: Update terminal mode bg cells (line ~3918) - no offset  
sed -i 's/self\.cells\.bgCell(y, x)\.\* = \.{$/self.cells.bgCell(y, x).* = .{ .color = .{/g' "$FILE"

# Pass 3: Update cursor bg cells (line ~4355, 4359) - no offset
sed -i 's/self\.cells\.bgCell(coord\.y, coord\.x)\.\* = \.{$/self.cells.bgCell(coord.y, coord.x).* = .{ .color = .{/g' "$FILE"
sed -i 's/self\.cells\.bgCell(coord\.y, coord\.x + 1)\.\* = \.{$/self.cells.bgCell(coord.y, coord.x + 1).* = .{ .color = .{/g' "$FILE"

# Pass 4: For the simple array assignments like `.* = .{ r, g, b, 255 };`
# We need to make these into struct format manually since context matters

echo "Simple replacements done. Now handling context-specific updates..."

# The remaining ones need manual handling because we need to know if they're in 
# scrollable region or not. Let me create a more sophisticated script.

echo "Done! Please review the changes."
