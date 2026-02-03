#!/usr/bin/env bash
# Run Ghostty with full logging to file

LOGFILE="/home/parkersettle/projects/ghostty-pixel-scroll/ghostty-debug.log"

echo "Starting Ghostty with logging to: $LOGFILE"
echo "===== Ghostty Debug Log - $(date) =====" > "$LOGFILE"

# Run Ghostty and redirect both stdout and stderr to log file
./zig-out/bin/ghostty --neovim-gui=spawn --pixel-scroll=true 2>&1 | tee -a "$LOGFILE"
