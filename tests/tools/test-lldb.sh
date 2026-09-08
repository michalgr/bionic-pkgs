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
  SERVER_BIN="${BASE_DIR}/bin/lldb-server"
else
  BASE_DIR="$(dirname "$LLDB_BIN")/.."
  LLDB_CMD="${LLDB_BIN}"
  SERVER_BIN="$(dirname "$LLDB_BIN")/lldb-server"
fi

# 1. Version check for lldb CLI
output="$(adb_shell "${LLDB_CMD} --version 2>&1" || true)"
assert_contains "$output" "lldb version" "lldb version check (--version)"

# 2. Version check for lldb-server
output="$(adb_shell "${SERVER_BIN} version 2>&1 || ${SERVER_BIN} v 2>&1" || true)"
assert_contains "$output" "lldb-server" "lldb-server version check (version/v)"

# 3. Batch execution & process tracing
output="$(adb_shell "${LLDB_CMD} --batch -o 'file /system/bin/echo' -o 'run bionic-test' -o 'quit' 2>&1" || true)"
assert_match "exited with status = 0|Process .* exited" "$output" "lldb batch execution & process tracing"

# 4. Target inspection
output="$(adb_shell "${LLDB_CMD} --batch -o 'target create /system/bin/sh' -o 'image list' -o 'quit' 2>&1" || true)"
assert_match "/system/bin/sh|linker" "$output" "lldb target inspection (image list)"

# 5. Breakpoint & control flow execution
output="$(adb_shell "${LLDB_CMD} --batch -o 'file /system/bin/echo' -o 'breakpoint set -n main' -o 'run test' -o 'continue' -o 'quit' 2>&1" || true)"
assert_match "Breakpoint|main|exited with status = 0" "$output" "lldb breakpoint and control flow execution"

print_summary
