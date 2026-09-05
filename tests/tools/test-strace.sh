#!/usr/bin/env bash
# tests/tools/test-strace.sh
# Codified test script for strace on Android.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/tests/lib/common.sh"
source "$ROOT_DIR/tests/lib/adb-helpers.sh"

STRACE_BIN=""
SERIAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bin)
      STRACE_BIN="$2"
      shift 2
      ;;
    -s|--serial)
      SERIAL="$2"
      shift 2
      ;;
    *)
      if [ -z "$STRACE_BIN" ]; then
        STRACE_BIN="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

adb_wait_and_root

if [ -z "$STRACE_BIN" ]; then
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/strace/run.sh ]" 2>/dev/null; then
    STRACE_BIN="/data/local/tmp/bionic-pkgs/strace/run.sh"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/bin/strace ]" 2>/dev/null; then
    STRACE_BIN="/data/local/tmp/test-sysroot/bin/strace"
  else
    STRACE_BIN="/data/local/tmp/bionic-pkgs/strace/run.sh"
  fi
fi

log_info "Testing strace via: ${STRACE_BIN}"

# 1. Version check
output="$(adb_shell "${STRACE_BIN} -V 2>&1" || true)"
assert_contains "$output" "strace -- version" "strace version check (-V)"

# 2. Syscall interception
output="$(adb_shell "${STRACE_BIN} -e trace=write /system/bin/echo 'strace test' 2>&1" || true)"
assert_contains "$output" "write(" "strace syscall interception (-e trace=write)"

# 3. Child process following
output="$(adb_shell "${STRACE_BIN} -f /system/bin/sh -c '/system/bin/echo child_proc' 2>&1" || true)"
assert_contains "$output" "child_proc" "strace child process following (-f)"

# 4. File I/O tracing
output="$(adb_shell "${STRACE_BIN} -e trace=openat,write,close /system/bin/sh -c 'echo iotest > /data/local/tmp/strace_io.tmp && rm -f /data/local/tmp/strace_io.tmp' 2>&1" || true)"
assert_contains "$output" "openat(" "strace file I/O tracing (openat)"
assert_contains "$output" "write(" "strace file I/O tracing (write)"

print_summary
