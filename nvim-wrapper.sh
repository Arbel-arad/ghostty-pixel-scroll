#!/usr/bin/env bash
# Wrapper for nvim that launches Neovim GUI mode in Ghostty
# Add this to your shell: alias nvim='~/projects/ghostty-pixel-scroll/nvim-wrapper.sh'

# Check if we're running in Ghostty terminal
if [[ -n "$GHOSTTY_RESOURCES_DIR" ]]; then
    # We're in Ghostty - launch a new window with Neovim GUI
    exec ~/projects/ghostty-pixel-scroll/zig-out/bin/ghostty --neovim-gui=spawn "$@"
else
    # Not in Ghostty - run regular nvim
    exec /usr/bin/env nvim "$@"
fi
