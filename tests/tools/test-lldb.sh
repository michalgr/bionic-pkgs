#!/usr/bin/env bash
# tests/tools/test-lldb.sh
# Codified test script for lldb and lldb-server on Android.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/tests/lib/common.sh"
source "$ROOT_DIR/tests/lib/adb-helpers.sh"

LLDB_BIN=""
SERIAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bin)
      LLDB_BIN="$2"
      shift 2
      ;;
    -s|--serial)
      SERIAL="$2"
      shift 2
      ;;
    *)
      if [ -z "$LLDB_BIN" ]; then
        LLDB_BIN="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

adb_wait_and_root

if [ -z "$LLDB_BIN" ]; then
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/lldb/run.sh ]" 2>/dev/null; then
    LLDB_BIN="/data/local/tmp/bionic-pkgs/lldb/run.sh"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/bin/lldb ]" 2>/dev/null; then
    LLDB_BIN="/data/local/tmp/test-sysroot/bin/lldb"
  else
    LLDB_BIN="/data/local/tmp/bionic-pkgs/lldb/run.sh"
  fi
fi

log_info "Testing lldb via: ${LLDB_BIN}"

# Determine base directory and companion tool invocation wrappers
BIN_NAME="$(basename "$LLDB_BIN")"
if [ "$BIN_NAME" = "run.sh" ]; then
  BASE_DIR="$(dirname "$LLDB_BIN")"
  LLDB_CMD="${LLDB_BIN}"
  LLDB_SERVER_CMD="${BASE_DIR}/bin/lldb-server"
else
  BASE_DIR="$(dirname "$LLDB_BIN")/.."
  LLDB_CMD="${LLDB_BIN}"
  LLDB_SERVER_CMD="${BASE_DIR}/bin/lldb-server"
fi

# 1. Version check for lldb CLI
output="$(adb_shell "${LLDB_CMD} --version 2>&1" || true)"
assert_contains "$output" "lldb version" "lldb CLI version check (--version)"

# 2. Version check for companion lldb-server
output="$(adb_shell "${LLDB_SERVER_CMD} v 2>&1 || ${LLDB_SERVER_CMD} version 2>&1" || true)"
assert_match "lldb-server|version" "$output" "lldb-server version check"

# 3. Batch execution & process tracing
output="$(adb_shell "${LLDB_CMD} --batch -o 'file /system/bin/echo' -o 'run bionic-test' -o 'quit' 2>&1" || true)"
assert_contains "$output" "bionic-test" "lldb batch execution & process tracing"

# 4. Target image inspection
output="$(adb_shell "${LLDB_CMD} --batch -o 'target create /system/bin/sh' -o 'image list' -o 'quit' 2>&1" || true)"
assert_contains "$output" "/system/bin/sh" "lldb target image inspection"

# 5. Breakpoint and control flow
output="$(adb_shell "${LLDB_CMD} --batch -o 'file /system/bin/echo' -o 'breakpoint set -n main' -o 'run test' -o 'continue' -o 'quit' 2>&1" || true)"
assert_contains "$output" "Breakpoint" "lldb breakpoint setting and control flow"

print_summary
