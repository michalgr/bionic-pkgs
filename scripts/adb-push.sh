#!/usr/bin/env bash
# scripts/adb-push.sh
# Deployment script for pushing prebuilt bionic-pkgs runtime archives to Android devices.

set -euo pipefail

usage() {
  cat << 'EOF'
Usage: adb-push.sh [OPTIONS] --archive <PATH>

Options:
  -a, --archive <PATH>      Path to prebuilt package archive (.tar.gz) (Required)
  -n, --pkg-name <NAME>     Logical package name (e.g. rizin, strace, python3)
  -t, --target <TARGET>     Target architecture (e.g. aarch64-android, x86_64-android)
  -b, --bin-name <NAME>     Primary binary executable name (default: derived from package)
  -d, --dest-dir <PATH>     Target directory on device (default: /data/local/tmp/bionic-pkgs/<pkgName>)
  -s, --serial <SERIAL>     Target ADB device serial (or $ANDROID_SERIAL / $ADB_SERIAL)
      --adb <PATH>          Path to adb binary (default: adb)
      --dry-run             Display payload summary without pushing via ADB
      --run [ARGS...]       Execute the binary on device after pushing
  -h, --help                Show this help message
EOF
  exit "${1:-0}"
}

ARCHIVE_PATH=""
PKG_NAME=""
TARGET="aarch64-android"
BIN_NAME=""
DEST_DIR=""
SERIAL=""
ADB_CMD="adb"
DRY_RUN=0
RUN_AFTER=0
RUN_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--archive)
      ARCHIVE_PATH="$2"
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
      if [ -z "$ARCHIVE_PATH" ] && [ -f "$1" ]; then
        ARCHIVE_PATH="$1"
        shift
      else
        echo "Error: Unknown argument: $1" >&2
        usage 1
      fi
      ;;
  esac
done

if [ -z "$ARCHIVE_PATH" ]; then
  echo "Error: --archive is required." >&2
  usage 1
fi

if [ ! -f "$ARCHIVE_PATH" ]; then
  echo "Error: Archive path does not exist or is not a file: $ARCHIVE_PATH" >&2
  exit 1
fi

# Infer logical package name if not provided
if [ -z "$PKG_NAME" ]; then
  PKG_NAME="$(basename "$ARCHIVE_PATH" | sed -E 's/\.tar\.(gz|zst)$//; s/-(aarch64|x86_64|armv7a|i686)(-android)?.*//')"
fi

# Infer primary binary name if not provided
if [ -z "$BIN_NAME" ]; then
  BIN_NAME="$PKG_NAME"
fi

if [ -z "$DEST_DIR" ]; then
  DEST_DIR="/data/local/tmp/bionic-pkgs/${PKG_NAME}"
fi

SERIAL="${SERIAL:-${ANDROID_SERIAL:-${ADB_SERIAL:-}}}"

echo "============================================================"
echo "==> Deploying: ${PKG_NAME} (${TARGET})"
echo "==> Archive:   ${ARCHIVE_PATH}"
echo "==> Target:    ${DEST_DIR}"
echo "==> Binary:    ${BIN_NAME}"
[ -n "$SERIAL" ] && echo "==> Device:    ${SERIAL}"
echo "============================================================"

PAYLOAD_SIZE=$(du -h "$ARCHIVE_PATH" | cut -f1)

echo "==> Payload Summary:"
echo "    - Total archive size: ${PAYLOAD_SIZE}"

if [ "$DRY_RUN" -eq 1 ]; then
  echo ""
  echo "==> [Dry-Run] Archive contents:"
  tar -tvf "$ARCHIVE_PATH"
  echo ""
  echo "==> [Dry-Run] Completed without connecting to device."
  exit 0
fi

# Verify ADB tool
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
RUN_SH_REMOTE_ESC="$(shell_escape "$DEST_DIR/run.sh")"

echo "==> Creating staging directory on device ($DEST_DIR)..."
run_adb shell "rm -rf ${DEST_DIR_ESC} && mkdir -p ${DEST_DIR_ESC}"

echo "==> Pushing package archive (${PAYLOAD_SIZE})..."
run_adb push "$ARCHIVE_PATH" "$DEST_DIR/stage.tar.gz"

echo "==> Unpacking payload on device..."
run_adb shell "cd ${DEST_DIR_ESC} && tar xzf stage.tar.gz && rm -f stage.tar.gz && chmod 755 ${RUN_SH_REMOTE_ESC} 2>/dev/null || true"

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
