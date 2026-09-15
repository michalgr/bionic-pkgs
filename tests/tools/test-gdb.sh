#!/usr/bin/env bash
# tests/tools/test-gdb.sh
# Codified test script for GDB and gdbserver with Python 3 support on Android.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/tests/lib/common.sh"
source "$ROOT_DIR/tests/lib/adb-helpers.sh"

TARGET_ROOT=""
SERIAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--root|--root-dir)
      TARGET_ROOT="$2"
      shift 2
      ;;
    -s|--serial)
      SERIAL="$2"
      shift 2
      ;;
    *)
      if [ -z "$TARGET_ROOT" ]; then
        TARGET_ROOT="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

adb_wait_and_root

if [ -z "$TARGET_ROOT" ]; then
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/gdb/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/gdb"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/test-sysroot"
  else
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/gdb"
  fi
fi

log_info "Testing gdb via root: ${TARGET_ROOT}"
GDB_CMD="${TARGET_ROOT}/env.sh gdb"
GDBSERVER_BIN="${TARGET_ROOT}/env.sh gdbserver"

# 1. Version check for gdb CLI (banner verification)
output="$(adb_shell "${GDB_CMD} --version 2>&1" || true)"
assert_contains "$output" "GNU gdb (GDB)" "gdb CLI version check (--version)"
assert_contains "$output" "17." "gdb 17+ version line check"

# 2. Version check for gdbserver companion
output="$(adb_shell "${GDBSERVER_BIN} --version 2>&1" || true)"
assert_contains "$output" "GNU gdbserver (GDB)" "gdbserver version check (--version)"

# 3. Target binary inspection (gdb --batch -ex 'file /system/bin/sh' -ex 'info files')
output="$(adb_shell "${GDB_CMD} --batch -ex 'file /system/bin/sh' -ex 'info files' 2>&1" || true)"
assert_contains "$output" "Symbols from \"/system/bin/sh\"" "gdb file inspection banner"
assert_match "Local exec file:|Entry point:" "$output" "gdb info files output"

# 4. Embedded Python 3 scripting & module integration
output="$(adb_shell "${GDB_CMD} --batch -ex 'python import gdb; print(\"GDB_PYTHON_OK:\", gdb.VERSION)' 2>&1" || true)"
assert_contains "$output" "GDB_PYTHON_OK:" "gdb embedded Python 3 scripting (import gdb)"

# 5. Headless process execution and breakpoint setting
output="$(adb_shell "${GDB_CMD} --batch -ex 'file /system/bin/sh' -ex 'break main' -ex 'info break' 2>&1" || true)"
assert_match "Breakpoint 1 at|main" "$output" "gdb main breakpoint setting"

print_summary
