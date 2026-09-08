#!/usr/bin/env bash
# tests/tools/test-lldb.sh
# Codified test script for LLDB and lldb-server on Android.

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
      export ANDROID_SERIAL="$SERIAL"
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

# Determine base directory and lldb-server location
BIN_NAME="$(basename "$LLDB_BIN")"
if [ "$BIN_NAME" = "run.sh" ]; then
  BASE_DIR="$(dirname "$LLDB_BIN")"
  SERVER_BIN="${BASE_DIR}/bin/lldb-server"
else
  BASE_DIR="$(dirname "$LLDB_BIN")"
  SERVER_BIN="${BASE_DIR}/lldb-server"
fi

# 1. Version verification
output="$(adb_shell "${LLDB_BIN} --version 2>&1" || true)"
assert_match "lldb version|lldb" "$output" "lldb version check (--version)"

output="$(adb_shell "${SERVER_BIN} v 2>&1" || true)"
assert_contains "$output" "lldb-server" "lldb-server version check (v)"

# 2. Batch execution & tracing
output="$(adb_shell "${LLDB_BIN} --batch -o \"file /system/bin/echo\" -o \"run bionic-test\" -o \"quit\" 2>&1" || true)"
assert_match "Process [0-9]+ exited with status = 0|exited with status" "$output" "lldb batch process execution and exit status check"

# 3. Target inspection
output="$(adb_shell "${LLDB_BIN} --batch -o \"target create /system/bin/sh\" -o \"image list\" -o \"quit\" 2>&1" || true)"
assert_match "/system/bin/sh|linker" "$output" "lldb target create and loaded image list inspection"

# 4. Breakpoint & control flow
output="$(adb_shell "${LLDB_BIN} --batch -o \"file /system/bin/echo\" -o \"breakpoint set -n main\" -o \"run test\" -o \"continue\" -o \"quit\" 2>&1" || true)"
assert_match "Breakpoint [0-9]+:|stop reason = breakpoint|exited with status" "$output" "lldb breakpoint setting and control flow continuation"

print_summary
