#!/usr/bin/env bash
# scripts/adb-push.sh
# Standalone ADB staging and deployment script for Android 14+ (Bionic libc) packages.
#
# Features:
# - Strict runtime staging (excludes *.a static archives, *.la, include/, pkgconfig/)
# - Symlink preservation (avoids duplicating multi-call binaries or shared library symlinks)
# - Dependency closure .so library aggregation
# - Device staging and run.sh launcher generation
# - Supports CLI flags, environment overrides, dry-run mode, and direct execution

set -euo pipefail

usage() {
  cat << 'EOF'
Usage: adb-push.sh [OPTIONS] --pkg-path <STORE_OR_BUILD_PATH>

Options:
  -p, --pkg-path <PATH>     Path to the package directory / Nix store path (Required)
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
      if [ -z "$PKG_PATH" ] && [ -d "$1" ]; then
        PKG_PATH="$1"
        shift
      else
        echo "Error: Unknown argument: $1" >&2
        usage 1
      fi
      ;;
  esac
done

if [ -z "$PKG_PATH" ]; then
  echo "Error: --pkg-path is required." >&2
  usage 1
fi

if [ ! -d "$PKG_PATH" ]; then
  echo "Error: Package path does not exist or is not a directory: $PKG_PATH" >&2
  exit 1
fi

# Infer logical package name if not provided
if [ -z "$PKG_NAME" ]; then
  PKG_NAME="$(basename "$PKG_PATH" | sed -E 's/^[a-z0-9]{32}-//; s/-[0-9].*//; s/-(aarch64|x86_64|armv7a|i686)-unknown-linux-android//')"
fi

# Infer primary binary name if not provided
if [ -z "$BIN_NAME" ]; then
  if [ -d "$PKG_PATH/bin" ]; then
    # Look for a binary matching PKG_NAME, or take the first executable
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
echo "==> Source:    ${PKG_PATH}"
echo "==> Target:    ${DEST_DIR}"
echo "==> Binary:    ${BIN_NAME}"
[ -n "$SERIAL" ] && echo "==> Device:    ${SERIAL}"
echo "============================================================"

# Create local staging workspace
STAGE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/bionic_stage_${PKG_NAME}_XXXXXX")
STAGE_TAR=$(mktemp "${TMPDIR:-/tmp}/bionic_push_${PKG_NAME}_XXXXXX.tar")

cleanup() {
  if [ -d "$STAGE_DIR" ]; then
    chmod -R u+w "$STAGE_DIR" 2>/dev/null || true
    rm -rf "$STAGE_DIR"
  fi
  rm -f "$STAGE_TAR" 2>/dev/null || true
}
trap cleanup EXIT

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

  # Deduplicate already processed dependency paths
  if [[ -n "${seen_deps[$dep_path]:-}" ]]; then
    return 0
  fi
  seen_deps["$dep_path"]=1

  case "$dep_path" in
    *bionic-compat*|*bionic-prebuilt*|*android-prebuilts*|*android-headers*|*zlib*build*|*xgcc*|*gcc*|*glibc*)
      # Skip build-time libc linker script shims, platform stubs, and host compiler libraries
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

  # Include runtime subdirectories if present (e.g. Python stdlib)
  for py_dir in "$dep_path"/lib/python3.*; do
    if [ -d "$py_dir" ]; then
      local py_base
      py_base="$(basename "$py_dir")"
      if [ ! -d "$STAGE_DIR/lib/$py_base" ]; then
        cp -a "$py_dir" "$STAGE_DIR/lib/"
      fi
    fi
  done
}

for dep in "${DEPS[@]}"; do
  stage_dep_libs "$dep"
done

# If nix-store command is available, scan closure for target architecture shared libraries
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

# Ensure staging permissions and remove any leftover static archives
chmod -R u+wX "$STAGE_DIR" 2>/dev/null || true
find "$STAGE_DIR" -type f \( -name "*.a" -o -name "*.la" -o -name "*.o" \) -delete 2>/dev/null || true
find "$STAGE_DIR" -type d \( -name "pkgconfig" -o -name "cmake" \) -exec rm -rf {} + 2>/dev/null || true

# Replace GNU linker script stubs (e.g. libc++.so -> INPUT(libc++.so.1 ...)) with symlinks to their versioned .so
if [ -d "$STAGE_DIR/lib" ]; then
  for so_file in "$STAGE_DIR"/lib/*.so; do
    if [ -f "$so_file" ] && [ ! -L "$so_file" ]; then
      if [ "$(od -An -N4 -tx1 "$so_file" 2>/dev/null | tr -d ' \n')" != "7f454c46" ]; then
        if [ -f "${so_file}.1" ] || [ -L "${so_file}.1" ]; then
          ln -sf "$(basename "${so_file}.1")" "$so_file"
        else
          rm -f "$so_file"
        fi
      fi
    fi
  done
fi

# Remove empty directories
[ -d "$STAGE_DIR/lib" ] && [ -z "$(ls -A "$STAGE_DIR/lib")" ] && rmdir "$STAGE_DIR/lib" || true
[ -d "$STAGE_DIR/share" ] && [ -z "$(ls -A "$STAGE_DIR/share")" ] && rmdir "$STAGE_DIR/share" || true

# 5. Pack archive preserving symbolic links while dereferencing hard links
tar --hard-dereference -cf "$STAGE_TAR" -C "$STAGE_DIR" .
PAYLOAD_SIZE=$(du -h "$STAGE_TAR" | cut -f1)

echo "==> Staged Payload Summary:"
echo "    - Total archive size: ${PAYLOAD_SIZE}"
echo "    - Binaries in bin/:   $(find "$STAGE_DIR/bin" -maxdepth 1 -type f -o -type l 2>/dev/null | wc -l) item(s)"
if [ -d "$STAGE_DIR/lib" ]; then
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

run_adb() {
  "$ADB_BIN" "${ADB_FLAGS[@]}" "$@"
}

echo "==> Checking device connection..."
if ! run_adb get-state >/dev/null 2>&1; then
  echo "Error: ADB device not connected or unauthorized." >&2
  exit 1
fi

echo "==> Creating staging directory on device ($DEST_DIR)..."
run_adb shell "rm -rf '$DEST_DIR' && mkdir -p '$DEST_DIR'"

echo "==> Pushing package archive (${PAYLOAD_SIZE})..."
run_adb push "$STAGE_TAR" "$DEST_DIR/stage.tar"

echo "==> Unpacking payload on device..."
run_adb shell "tar -xf '$DEST_DIR/stage.tar' -C '$DEST_DIR' && rm -f '$DEST_DIR/stage.tar' && chmod -R u+w '$DEST_DIR' 2>/dev/null && chmod 755 '$DEST_DIR/bin/'* 2>/dev/null || true"

# 7. Generate launcher wrapper script
LAUNCHER_TMP=$(mktemp "${TMPDIR:-/tmp}/bionic_run_${PKG_NAME}_XXXXXX.sh")
cat << EOF > "$LAUNCHER_TMP"
#!/system/bin/sh
SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
export LD_LIBRARY_PATH="\$SCRIPT_DIR/lib:\$SCRIPT_DIR/../lib:\$LD_LIBRARY_PATH"
export PATH="\$SCRIPT_DIR/bin:\$PATH"
for py_dir in "\$SCRIPT_DIR"/lib/python3.*; do
  if [ -d "\$py_dir" ]; then
    export PYTHONHOME="\$SCRIPT_DIR"
    if [ -d "\$py_dir/site-packages" ]; then
      export PYTHONPATH="\$py_dir/site-packages:\''${PYTHONPATH:-}"
    fi
    break
  fi
done
if [ -x "\$SCRIPT_DIR/bin/${BIN_NAME}" ]; then
  exec "\$SCRIPT_DIR/bin/${BIN_NAME}" "\$@"
else
  echo "Executable \$SCRIPT_DIR/bin/${BIN_NAME} not found" >&2
  exit 1
fi
EOF

run_adb push "$LAUNCHER_TMP" "$DEST_DIR/run.sh" >/dev/null
run_adb shell "chmod 755 '$DEST_DIR/run.sh'"
rm -f "$LAUNCHER_TMP"

echo ""
echo "==> Deployment complete!"
echo "==> Run on device via ADB:"
echo "    adb shell \"$DEST_DIR/run.sh\""
echo "    # Or directly:"
echo "    adb shell \"$DEST_DIR/bin/${BIN_NAME}\""

# 8. Execute if requested
if [ "$RUN_AFTER" -eq 1 ]; then
  echo ""
  echo "==> Running $BIN_NAME on device..."
  run_adb shell "$DEST_DIR/run.sh" "${RUN_ARGS[@]}"
fi
