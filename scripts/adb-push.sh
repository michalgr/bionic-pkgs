#!/usr/bin/env bash
# scripts/adb-push.sh
# Standalone ADB staging and deployment script for Android 14+ (Bionic libc) packages.
#
# Features:
# - Supports prebuilt runtime archives (--archive) or legacy host staging (--pkg-path)
# - Direct deployment of prebuilt Nix runtime archives via ADB
# - Strict runtime staging (excludes *.a static archives, *.la, include/, pkgconfig/)
# - Symlink preservation (avoids duplicating multi-call binaries or shared library symlinks)
# - Device staging and run.sh launcher execution
# - Supports CLI flags, environment overrides, dry-run mode, and direct execution

set -euo pipefail

usage() {
  cat << 'EOF'
Usage: adb-push.sh [OPTIONS]

Options:
  -a, --archive <PATH>      Path to prebuilt package archive (.tar.gz)
  -p, --pkg-path <PATH>     Path to the package directory / Nix store path (Legacy)
  -n, --pkg-name <NAME>     Logical package name (e.g. rizin, strace, python3)
  -t, --target <TARGET>     Target architecture (e.g. aarch64-android, x86_64-android)
  -b, --bin-name <NAME>     Primary binary executable name (default: derived from package)
  -d, --dest-dir <PATH>     Target directory on device (default: /data/local/tmp/bionic-pkgs/<pkgName>)
  -s, --serial <SERIAL>     Target ADB device serial (or $ANDROID_SERIAL / $ADB_SERIAL)
      --dep <PATH>          Additional dependency store path to scan for shared libraries (repeatable)
      --adb <PATH>          Path to adb binary (default: adb)
      --dry-run             Stage files and display payload summary without pushing via ADB
      --run [ARGS...]       Execute the binary on device after pushing
  -h, --help                Show this help message
EOF
  exit "${1:-0}"
}

ARCHIVE_PATH=""
PKG_PATH=""
PKG_NAME=""
TARGET="aarch64-android"
BIN_NAME=""
DEST_DIR=""
SERIAL=""
ADB_CMD="adb"
DRY_RUN=0
RUN_AFTER=0
RUN_ARGS=()
DEPS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--archive)
      ARCHIVE_PATH="$2"
      shift 2
      ;;
    -p|--pkg-path)
      PKG_PATH="$2"
      shift 2
      ;;
    -n|--pkg-name)
      PKG_NAME="$2"
      shift 2
      ;;
    -t|--target)
      TARGET="$2"
      shift 2
      ;;
    -b|--bin-name)
      BIN_NAME="$2"
      shift 2
      ;;
    -d|--dest-dir)
      DEST_DIR="$2"
      shift 2
      ;;
    -s|--serial)
      SERIAL="$2"
      shift 2
      ;;
    --adb)
      ADB_CMD="$2"
      shift 2
      ;;
    --dep)
      DEPS+=("$2")
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --run)
      RUN_AFTER=1
      shift
      RUN_ARGS=("$@")
      break
      ;;
    -h|--help)
      usage 0
      ;;
    *)
      if [ -z "$ARCHIVE_PATH" ] && [ -z "$PKG_PATH" ] && [ -f "$1" ]; then
        ARCHIVE_PATH="$1"
        shift
      elif [ -z "$ARCHIVE_PATH" ] && [ -z "$PKG_PATH" ] && [ -d "$1" ]; then
        PKG_PATH="$1"
        shift
      else
        echo "Error: Unknown argument: $1" >&2
        usage 1
      fi
      ;;
  esac
done

if [ -z "$ARCHIVE_PATH" ] && [ -z "$PKG_PATH" ]; then
  echo "Error: Either --archive or --pkg-path is required." >&2
  usage 1
fi

if [ -n "$ARCHIVE_PATH" ] && [ ! -f "$ARCHIVE_PATH" ]; then
  echo "Error: Archive path does not exist or is not a file: $ARCHIVE_PATH" >&2
  exit 1
fi

if [ -n "$PKG_PATH" ] && [ ! -d "$PKG_PATH" ]; then
  echo "Error: Package path does not exist or is not a directory: $PKG_PATH" >&2
  exit 1
fi

# Infer logical package name if not provided
if [ -z "$PKG_NAME" ]; then
  if [ -n "$ARCHIVE_PATH" ]; then
    PKG_NAME="$(basename "$ARCHIVE_PATH" | sed -E 's/\.tar\.(gz|zst)$//; s/-(aarch64|x86_64|armv7a|i686)(-android)?.*//')"
  else
    PKG_NAME="$(basename "$PKG_PATH" | sed -E 's/^[a-z0-9]{32}-//; s/-[0-9].*//; s/-(aarch64|x86_64|armv7a|i686)-unknown-linux-android//')"
  fi
fi

# Infer primary binary name if not provided
if [ -z "$BIN_NAME" ]; then
  if [ -n "$PKG_PATH" ] && [ -d "$PKG_PATH/bin" ]; then
    if [ -x "$PKG_PATH/bin/$PKG_NAME" ] || [ -L "$PKG_PATH/bin/$PKG_NAME" ]; then
      BIN_NAME="$PKG_NAME"
    else
      first_bin="$(find "$PKG_PATH/bin" -maxdepth 1 -type f -o -type l | head -n 1)"
      if [ -n "$first_bin" ]; then
        BIN_NAME="$(basename "$first_bin")"
      else
        BIN_NAME="$PKG_NAME"
      fi
    fi
  else
    BIN_NAME="$PKG_NAME"
  fi
fi

if [ -z "$DEST_DIR" ]; then
  DEST_DIR="/data/local/tmp/bionic-pkgs/${PKG_NAME}"
fi

SERIAL="${SERIAL:-${ANDROID_SERIAL:-${ADB_SERIAL:-}}}"

echo "============================================================"
echo "==> Deploying: ${PKG_NAME} (${TARGET})"
[ -n "$ARCHIVE_PATH" ] && echo "==> Archive:   ${ARCHIVE_PATH}"
[ -n "$PKG_PATH" ] && echo "==> Source:    ${PKG_PATH}"
echo "==> Target:    ${DEST_DIR}"
echo "==> Binary:    ${BIN_NAME}"
[ -n "$SERIAL" ] && echo "==> Device:    ${SERIAL}"
echo "============================================================"

STAGE_DIR=""
TMP_STAGE_TAR=""

cleanup() {
  if [ -n "$STAGE_DIR" ] && [ -d "$STAGE_DIR" ]; then
    chmod -R u+w "$STAGE_DIR" 2>/dev/null || true
    rm -rf "$STAGE_DIR"
  fi
  if [ -n "$TMP_STAGE_TAR" ] && [ -f "$TMP_STAGE_TAR" ]; then
    rm -f "$TMP_STAGE_TAR" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [ -n "$ARCHIVE_PATH" ]; then
  STAGE_TAR="$ARCHIVE_PATH"
  PAYLOAD_SIZE=$(du -h "$STAGE_TAR" | cut -f1)
else
  # Create local staging workspace for legacy mode
  STAGE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/bionic_stage_${PKG_NAME}_XXXXXX")
  TMP_STAGE_TAR=$(mktemp "${TMPDIR:-/tmp}/bionic_push_${PKG_NAME}_XXXXXX.tar")
  STAGE_TAR="$TMP_STAGE_TAR"

  echo "==> Staging runtime files from package..."
  mkdir -p "$STAGE_DIR/bin" "$STAGE_DIR/lib"

  # 1. Stage binaries (preserving relative symlinks and hard links)
  if [ -d "$PKG_PATH/bin" ]; then
    cp -a "$PKG_PATH/bin/." "$STAGE_DIR/bin/"
  fi

  # 2. Stage shared libraries and runtime modules from package
  if [ -d "$PKG_PATH/lib" ]; then
    for item in "$PKG_PATH"/lib/*; do
      [ -e "$item" ] || continue
      base="$(basename "$item")"
      case "$base" in
        *.a|*.la|*.o|pkgconfig|cmake)
          # Skip static archives, build artifacts, and package-config files
          ;;
        python3*)
          # Stage Python runtime standard library
          cp -a "$item" "$STAGE_DIR/lib/"
          find "$STAGE_DIR/lib/$base" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
          ;;
        *.so*)
          # Stage shared libraries (preserving symlinks)
          cp -a "$item" "$STAGE_DIR/lib/"
          ;;
        *)
          if [ -d "$item" ]; then
            cp -a "$item" "$STAGE_DIR/lib/"
          fi
          ;;
      esac
    done
  fi

  # 3. Stage runtime share assets (excluding doc, man, info, locale)
  if [ -d "$PKG_PATH/share" ]; then
    mkdir -p "$STAGE_DIR/share"
    for item in "$PKG_PATH"/share/*; do
      [ -e "$item" ] || continue
      base="$(basename "$item")"
      case "$base" in
        man|doc|info|locale|aclocal|pkgconfig|gdb)
          # Skip non-runtime metadata and documentation
          ;;
        *)
          cp -a "$item" "$STAGE_DIR/share/"
          ;;
      esac
    done
  fi

  # Ensure staging directory is writable before processing dependencies
  chmod -R u+wX "$STAGE_DIR" 2>/dev/null || true

  # 4. Stage dynamic libraries from dependency closure
  declare -A seen_deps

  stage_dep_libs() {
    local dep_path="$1"
    [ -d "$dep_path/lib" ] || return 0

    if [[ -n "${seen_deps[$dep_path]:-}" ]]; then
      return 0
    fi
    seen_deps["$dep_path"]=1

    case "$dep_path" in
      *bionic*|*android-headers*|*zlib*build*|*xgcc*|*gcc*|*glibc*)
        return 0
        ;;
    esac

    mkdir -p "$STAGE_DIR/lib"
    chmod u+w "$STAGE_DIR/lib" 2>/dev/null || true

    for so_file in "$dep_path"/lib/*.so*; do
      if [ -e "$so_file" ] || [ -L "$so_file" ]; then
        cp -a --remove-destination "$so_file" "$STAGE_DIR/lib/" 2>/dev/null || cp -af "$so_file" "$STAGE_DIR/lib/"
      fi
    done

    for py_dir in "$dep_path"/lib/python3.*; do
      if [ -d "$py_dir" ]; then
        local py_base
        py_base="$(basename "$py_dir")"
        mkdir -p "$STAGE_DIR/lib/$py_base"
        cp -a "$py_dir/." "$STAGE_DIR/lib/$py_base/"
      fi
    done
  }

  for dep in "${DEPS[@]}"; do
    stage_dep_libs "$dep"
  done

  if command -v nix-store >/dev/null 2>&1; then
    closure_paths=$(nix-store -qR "$PKG_PATH" 2>/dev/null || true)
    if [ -n "$closure_paths" ]; then
      while IFS= read -r req; do
        if [ "$req" != "$PKG_PATH" ] && [ -d "$req/lib" ]; then
          case "$req" in
            *"${TARGET}"*|*"-android-"*|*"-android"*)
              stage_dep_libs "$req"
              ;;
          esac
        fi
      done <<< "$closure_paths"
    fi
  fi

  chmod -R u+wX "$STAGE_DIR" 2>/dev/null || true
  find "$STAGE_DIR" -type f \( -name "*.a" -o -name "*.la" -o -name "*.o" \) -delete 2>/dev/null || true
  find "$STAGE_DIR" -type d \( -name "pkgconfig" -o -name "cmake" \) -exec rm -rf {} + 2>/dev/null || true

  [ -d "$STAGE_DIR/lib" ] && [ -z "$(ls -A "$STAGE_DIR/lib")" ] && rmdir "$STAGE_DIR/lib" || true
  [ -d "$STAGE_DIR/share" ] && [ -z "$(ls -A "$STAGE_DIR/share")" ] && rmdir "$STAGE_DIR/share" || true

  tar --hard-dereference -cf "$STAGE_TAR" -C "$STAGE_DIR" .
  PAYLOAD_SIZE=$(du -h "$STAGE_TAR" | cut -f1)
fi

echo "==> Staged Payload Summary:"
echo "    - Total archive size: ${PAYLOAD_SIZE}"
if [ -n "$STAGE_DIR" ] && [ -d "$STAGE_DIR/bin" ]; then
  echo "    - Binaries in bin/:   $(find "$STAGE_DIR/bin" -maxdepth 1 -type f -o -type l 2>/dev/null | wc -l) item(s)"
fi
if [ -n "$STAGE_DIR" ] && [ -d "$STAGE_DIR/lib" ]; then
  echo "    - Shared libraries:   $(find "$STAGE_DIR/lib" -maxdepth 1 -name '*.so*' 2>/dev/null | wc -l) library/symlink item(s)"
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo ""
  echo "==> [Dry-Run] Staging contents:"
  tar -tvf "$STAGE_TAR"
  echo ""
  echo "==> [Dry-Run] Completed without connecting to device."
  exit 0
fi

# 6. Verify ADB tool
ADB_BIN="$(command -v "$ADB_CMD" 2>/dev/null || true)"
if [ -z "$ADB_BIN" ]; then
  echo "Error: adb command not found (searched for: $ADB_CMD)." >&2
  exit 1
fi

ADB_FLAGS=()
if [ -n "$SERIAL" ]; then
  ADB_FLAGS+=(-s "$SERIAL")
fi

shell_escape() {
  local arg="$1"
  printf "'%s'" "${arg//\'/\'\\\'\'}"
}

run_adb() {
  "$ADB_BIN" "${ADB_FLAGS[@]}" "$@"
}

echo "==> Checking device connection..."
if ! run_adb get-state >/dev/null 2>&1; then
  echo "Error: ADB device not connected or unauthorized." >&2
  exit 1
fi

DEST_DIR_ESC="$(shell_escape "$DEST_DIR")"
STAGE_TAR_REMOTE_ESC="$(shell_escape "$DEST_DIR/stage.tar")"
RUN_SH_REMOTE_ESC="$(shell_escape "$DEST_DIR/run.sh")"

echo "==> Creating staging directory on device ($DEST_DIR)..."
run_adb shell "rm -rf ${DEST_DIR_ESC} && mkdir -p ${DEST_DIR_ESC}"

echo "==> Pushing package archive (${PAYLOAD_SIZE})..."
run_adb push "$STAGE_TAR" "$DEST_DIR/stage.tar"

echo "==> Unpacking payload on device..."
run_adb shell "cd ${DEST_DIR_ESC} && tar xf stage.tar && rm -f stage.tar"

# 7. Generate launcher wrapper script if legacy staging was used
if [ -z "$ARCHIVE_PATH" ]; then
  LAUNCHER_TMP=$(mktemp "${TMPDIR:-/tmp}/bionic_run_${PKG_NAME}_XXXXXX.sh")
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  "$SCRIPT_DIR/generate-launcher.sh" "${BIN_NAME}" > "$LAUNCHER_TMP"

  run_adb push "$LAUNCHER_TMP" "$DEST_DIR/run.sh" >/dev/null
  rm -f "$LAUNCHER_TMP"
fi

run_adb shell "chmod 755 ${RUN_SH_REMOTE_ESC} 2>/dev/null || true"

echo ""
echo "==> Deployment complete!"
echo "==> Run on device via ADB:"
echo "    adb shell ${RUN_SH_REMOTE_ESC}"
echo "    # Or directly:"
echo "    adb shell $(shell_escape "$DEST_DIR/bin/${BIN_NAME}")"

if [ "$RUN_AFTER" -eq 1 ]; then
  echo ""
  echo "==> Running $BIN_NAME on device..."
  RUN_CMD="${RUN_SH_REMOTE_ESC}"
  for arg in "${RUN_ARGS[@]}"; do
    RUN_CMD+=" $(shell_escape "$arg")"
  done
  run_adb shell "$RUN_CMD"
fi
