#!/usr/bin/env bash
# scripts/fix-linker-scripts.sh
# Replaces non-ELF GNU ld script stubs (e.g. libc++.so containing INPUT(...))
# in a library directory with symlinks to their versioned .so ELF equivalents,
# or removes them if no versioned ELF library exists.

set -euo pipefail

TARGET_DIR="${1:-.}"

if [ -d "$TARGET_DIR/lib" ]; then
  LIB_DIR="$TARGET_DIR/lib"
elif [ -d "$TARGET_DIR" ]; then
  LIB_DIR="$TARGET_DIR"
else
  echo "Error: Directory '$TARGET_DIR' does not exist." >&2
  exit 1
fi

for so_file in "$LIB_DIR"/*.so; do
  [ -e "$so_file" ] || continue
  # Only inspect regular files that are not already symbolic links
  if [ -f "$so_file" ] && [ ! -L "$so_file" ]; then
    # Check if the file starts with ELF magic bytes (0x7f 'E' 'L' 'F')
    magic="$(od -An -N4 -tx1 "$so_file" 2>/dev/null | tr -d ' \n')"
    if [ "$magic" != "7f454c46" ]; then
      if [ -f "${so_file}.1" ] || [ -L "${so_file}.1" ]; then
        ln -sf "$(basename "${so_file}.1")" "$so_file"
      else
        rm -f "$so_file"
      fi
    fi
  fi
done
