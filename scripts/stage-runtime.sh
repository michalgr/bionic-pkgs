#!/usr/bin/env bash
# scripts/stage-runtime.sh
# Staging helper for Android runtime packages and sysroots.
#
# Usage:
#   stage-runtime.sh --stage <dir> [--launcher <bin>] [--launcher-name <name>] [--fix-linker-scripts <path>] [--generate-launcher <path>] <pkg-path>...

set -euo pipefail

usage() {
  echo "Usage: $0 --stage <dir> [--launcher <bin>] [--launcher-name <name>] [--fix-linker-scripts <path>] [--generate-launcher <path>] <pkg-path>..." >&2
  exit 1
}

STAGE_DIR=""
LAUNCHER_BIN=""
LAUNCHER_NAME=""
FIX_LINKER_SCRIPTS=""
GENERATE_LAUNCHER=""
PKG_PATHS=()

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage)
      STAGE_DIR="$2"
      shift 2
      ;;
    --launcher)
      LAUNCHER_BIN="$2"
      shift 2
      ;;
    --launcher-name)
      LAUNCHER_NAME="$2"
      shift 2
      ;;
    --fix-linker-scripts)
      FIX_LINKER_SCRIPTS="$2"
      shift 2
      ;;
    --generate-launcher)
      GENERATE_LAUNCHER="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      PKG_PATHS+=("$1")
      shift
      ;;
  esac
done

if [ -z "$STAGE_DIR" ] || [ "${#PKG_PATHS[@]}" -eq 0 ]; then
  usage
fi

FIX_LINKER_SCRIPTS="${FIX_LINKER_SCRIPTS:-$SCRIPT_DIR/fix-linker-scripts.sh}"
GENERATE_LAUNCHER="${GENERATE_LAUNCHER:-$SCRIPT_DIR/generate-launcher.sh}"

mkdir -p "$STAGE_DIR/bin" "$STAGE_DIR/lib" "$STAGE_DIR/share"

for pkg in "${PKG_PATHS[@]}"; do
  [ -d "$pkg" ] || continue

  if [ -d "$pkg/bin" ]; then
    cp -a "$pkg/bin/." "$STAGE_DIR/bin/"
  fi

  if [ -d "$pkg/lib" ]; then
    for item in "$pkg"/lib/*; do
      [ -e "$item" ] || continue
      base="$(basename "$item")"
      case "$base" in
        *.a|*.la|*.o|pkgconfig|cmake)
          ;;
        *)
          cp -a "$item" "$STAGE_DIR/lib/"
          ;;
      esac
    done
  fi

  if [ -d "$pkg/share" ]; then
    for item in "$pkg"/share/*; do
      [ -e "$item" ] || continue
      base="$(basename "$item")"
      case "$base" in
        man|doc|info|locale|aclocal|pkgconfig|gdb)
          ;;
        *)
          cp -a "$item" "$STAGE_DIR/share/"
          ;;
      esac
    done
  fi

  chmod -R u+w "$STAGE_DIR" 2>/dev/null || true
done

# Clean up unwanted static archives or pkgconfig/cmake inside staging
find "$STAGE_DIR" -type f \( -name "*.a" -o -name "*.la" -o -name "*.o" \) -delete 2>/dev/null || true
find "$STAGE_DIR" -type d \( -name "pkgconfig" -o -name "cmake" \) -exec rm -rf {} + 2>/dev/null || true

# Fix GNU linker script stubs
if [ -d "$STAGE_DIR/lib" ]; then
  bash "$FIX_LINKER_SCRIPTS" "$STAGE_DIR/lib"
fi

# Clean up empty directories
[ -d "$STAGE_DIR/bin" ] && [ -z "$(ls -A "$STAGE_DIR/bin")" ] && rmdir "$STAGE_DIR/bin" || true
[ -d "$STAGE_DIR/lib" ] && [ -z "$(ls -A "$STAGE_DIR/lib")" ] && rmdir "$STAGE_DIR/lib" || true
[ -d "$STAGE_DIR/share" ] && [ -z "$(ls -A "$STAGE_DIR/share")" ] && rmdir "$STAGE_DIR/share" || true

# Generate launcher script if requested
if [ -n "$LAUNCHER_BIN" ]; then
  if [ -z "$LAUNCHER_NAME" ]; then
    LAUNCHER_NAME="${LAUNCHER_BIN}-launcher.sh"
  fi
  bash "$GENERATE_LAUNCHER" "$LAUNCHER_BIN" > "$STAGE_DIR/$LAUNCHER_NAME"
  chmod 755 "$STAGE_DIR/$LAUNCHER_NAME"
fi
