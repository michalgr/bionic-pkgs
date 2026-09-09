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

# Determine lldb-server binary path and launcher command relative to LLDB_BIN
BIN_NAME="$(basename "$LLDB_BIN")"
if [ "$BIN_NAME" = "run.sh" ]; then
  LLDB_DIR="$(dirname "$LLDB_BIN")"
  LLDB_SERVER_BIN="${LLDB_DIR}/bin/lldb-server"
  LLDB_CMD="${LLDB_BIN}"
else
  LLDB_DIR="$(dirname "$LLDB_BIN")"
  BASE_DIR="$(dirname "$LLDB_DIR")"
  LLDB_SERVER_BIN="${LLDB_DIR}/lldb-server"
  LLDB_CMD="PYTHONHOME='${BASE_DIR}' PYTHONPATH='${BASE_DIR}/lib/python3.13/site-packages' '${LLDB_BIN}'"
fi

log_info "Testing lldb via: ${LLDB_BIN}"
log_info "Testing lldb-server via: ${LLDB_SERVER_BIN}"

# 1. Version check for lldb CLI
output="$(adb_shell "${LLDB_CMD} --version 2>&1" || true)"
assert_contains "$output" "lldb version" "lldb version check (--version)"

# 2. Version check for companion lldb-server
output="$(adb_shell "${LLDB_SERVER_BIN} v 2>&1 || ${LLDB_SERVER_BIN} version 2>&1" || true)"
assert_match "lldb-server|version" "$output" "lldb-server version check"

# 3. Batch execution & process tracing
output="$(adb_shell "${LLDB_CMD} --batch -o 'file /system/bin/echo' -o 'run bionic-test' -o 'quit' 2>&1" || true)"
assert_match "bionic-test|exited with status" "$output" "lldb batch execution & process tracing"

# 4. Target image inspection
output="$(adb_shell "${LLDB_CMD} --batch -o 'target create /system/bin/sh' -o 'image list' -o 'quit' 2>&1" || true)"
assert_contains "$output" "/system/bin/sh" "lldb target image inspection"

# 5. Breakpoint and control flow
output="$(adb_shell "${LLDB_CMD} --batch -o 'file /system/bin/echo' -o 'breakpoint set -n main' -o 'run test' -o 'continue' -o 'quit' 2>&1" || true)"
assert_match "Breakpoint|stopped|exited" "$output" "lldb breakpoint set and control flow"

# 6. Python interpreter execution in LLDB batch mode
output="$(adb_shell "${LLDB_CMD} --batch -o 'script print(1234 + 5678)' 2>&1" || true)"
assert_contains "$output" "6912" "lldb python script execution"

# 7. LLDB module import and API access
output="$(adb_shell "${LLDB_CMD} --batch -o 'script import lldb; print(lldb.debugger.GetVersionString())' 2>&1" || true)"
assert_contains "$output" "lldb version" "lldb python module import and API access"

print_summary
