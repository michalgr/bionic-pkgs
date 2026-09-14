#!/usr/bin/env bash
# scripts/stage-runtime.sh
# Staging helper for Android runtime packages and sysroots.
#
# Usage:
#   stage-runtime.sh --stage <dir> [--launcher <bin>] [--launcher-name <name>] [--env-script <path>] <pkg-path>...

set -euo pipefail

usage() {
  echo "Usage: $0 --stage <dir> [--launcher <bin>] [--launcher-name <name>] [--env-script <path>] <pkg-path>..." >&2
  exit 1
}

STAGE_DIR=""
LAUNCHER_BIN=""
LAUNCHER_NAME=""
ENV_SCRIPT=""
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
    --env-script)
      ENV_SCRIPT="$2"
      shift 2
      ;;
    --generate-launcher)
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

ENV_SCRIPT="${ENV_SCRIPT:-$SCRIPT_DIR/env.sh}"

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
        man|doc|info|locale|aclocal|pkgconfig)
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

# Clean up empty directories
[ -d "$STAGE_DIR/bin" ] && [ -z "$(ls -A "$STAGE_DIR/bin")" ] && rmdir "$STAGE_DIR/bin" || true
[ -d "$STAGE_DIR/lib" ] && [ -z "$(ls -A "$STAGE_DIR/lib")" ] && rmdir "$STAGE_DIR/lib" || true
[ -d "$STAGE_DIR/share" ] && [ -z "$(ls -A "$STAGE_DIR/share")" ] && rmdir "$STAGE_DIR/share" || true

# Install root env.sh launcher and compatibility symlink
if [ -f "$ENV_SCRIPT" ]; then
  cp "$ENV_SCRIPT" "$STAGE_DIR/env.sh"
  chmod 755 "$STAGE_DIR/env.sh"
  mkdir -p "$STAGE_DIR/bin"
  ln -sf ../env.sh "$STAGE_DIR/bin/env.sh"
fi

# Generate launcher wrapper script if requested
if [ -n "$LAUNCHER_BIN" ]; then
  if [ -z "$LAUNCHER_NAME" ]; then
    LAUNCHER_NAME="${LAUNCHER_BIN}-launcher.sh"
  fi
  cat << LAUNCHER_EOF > "$STAGE_DIR/$LAUNCHER_NAME"
#!/system/bin/sh
SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
exec "\$SCRIPT_DIR/env.sh" "$LAUNCHER_BIN" "\$@"
LAUNCHER_EOF
  chmod 755 "$STAGE_DIR/$LAUNCHER_NAME"
fi
