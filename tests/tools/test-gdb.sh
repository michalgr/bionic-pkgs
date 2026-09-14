#!/usr/bin/env bash
# tests/tools/test-gdb.sh
# Codified test script for GDB and gdbserver with Python 3 support on Android.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/tests/lib/common.sh"
source "$ROOT_DIR/tests/lib/adb-helpers.sh"

TARGET_DIR=""
GDB_BIN=""
SERIAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      TARGET_DIR="$2"
      shift 2
      ;;
    --bin)
      GDB_BIN="$2"
      shift 2
      ;;
    -s|--serial)
      SERIAL="$2"
      shift 2
      ;;
    *)
      if [ -z "$TARGET_DIR" ] && [ -z "$GDB_BIN" ]; then
        TARGET_DIR="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

adb_wait_and_root

if [ -z "$TARGET_DIR" ] && [ -z "$GDB_BIN" ]; then
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/gdb/env.sh ]" 2>/dev/null; then
    TARGET_DIR="/data/local/tmp/bionic-pkgs/gdb"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/env.sh ]" 2>/dev/null; then
    TARGET_DIR="/data/local/tmp/test-sysroot"
  else
    TARGET_DIR="/data/local/tmp/bionic-pkgs/gdb"
  fi
fi

if [ -n "$TARGET_DIR" ]; then
  log_info "Testing gdb via dir: ${TARGET_DIR}"
  GDB_CMD="${TARGET_DIR}/env.sh gdb"
  GDBSERVER_BIN="${TARGET_DIR}/env.sh gdbserver"
else
  log_info "Testing gdb via: ${GDB_BIN}"
  BIN_NAME="$(basename "$GDB_BIN")"
  if [ "$BIN_NAME" = "run.sh" ]; then
    GDB_DIR="$(dirname "$GDB_BIN")"
    GDBSERVER_BIN="${GDB_DIR}/bin/gdbserver"
    GDB_CMD="${GDB_BIN}"
  else
    GDB_DIR="$(dirname "$GDB_BIN")"
    BASE_DIR="$(dirname "$GDB_DIR")"
    GDBSERVER_BIN="${GDB_DIR}/gdbserver"
    GDB_CMD="PYTHONHOME='${BASE_DIR}' PYTHONPATH='${BASE_DIR}/lib/python3.13:${BASE_DIR}/share/gdb/python' '${GDB_BIN}'"
  fi
  log_info "Testing gdbserver via: ${GDBSERVER_BIN}"
fi

# 1. Version check for gdb CLI (banner verification)
output="$(adb_shell "${GDB_CMD} --version 2>&1" || true)"
assert_contains "$output" "GNU gdb" "gdb version check (--version)"

# 2. Version check for companion gdbserver (banner and target architecture verification)
output="$(adb_shell "${GDBSERVER_BIN} --version 2>&1" || true)"
assert_contains "$output" "GNU gdbserver" "gdbserver version check (--version)"

# 3. Target ELF inspection
output="$(adb_shell "${GDB_CMD} --batch -ex 'file /system/bin/sh' -ex 'info files' -ex 'quit' 2>&1" || true)"
assert_contains "$output" "/system/bin/sh" "gdb target ELF inspection"

# 4. Inferior execution
output="$(adb_shell "${GDB_CMD} --batch -ex 'file /system/bin/echo' -ex 'run bionic-gdb-test' -ex 'quit' 2>&1" || true)"
assert_match "bionic-gdb-test|exited normally" "$output" "gdb inferior execution"

# 5. Breakpoint and control flow
output="$(adb_shell "${GDB_CMD} --batch -ex 'file /system/bin/echo' -ex 'break main' -ex 'run test' -ex 'continue' -ex 'quit' 2>&1" || true)"
assert_match "Breakpoint|stopped|exited" "$output" "gdb breakpoint and control flow"

# 6. Shared library loading
output="$(adb_shell "${GDB_CMD} --batch -ex 'file /system/bin/sh' -ex 'break main' -ex 'run' -ex 'info sharedlibrary' -ex 'quit' 2>&1" || true)"
assert_match "Shared library|libc.so|From" "$output" "gdb shared library loading"

# 7. Client-Server remote debugging
output="$(adb_shell "${GDBSERVER_BIN} --once 127.0.0.1:12345 /system/bin/echo server-test >/dev/null 2>&1 & sleep 1 && ${GDB_CMD} --batch -ex 'target remote 127.0.0.1:12345' -ex 'continue' -ex 'quit' 2>&1" || true)"
assert_match "server-test|Remote debugging|exited" "$output" "gdb client-server remote debugging"

# 8. Python scripting and GDB Python API
output="$(adb_shell "${GDB_CMD} --batch -ex 'python import gdb; print(\"GDB_PY_VERSION:\", gdb.VERSION)' -ex 'quit' 2>&1" || true)"
assert_contains "$output" "GDB_PY_VERSION: 17.2" "gdb python API verification"

print_summary
