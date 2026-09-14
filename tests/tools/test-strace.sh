#!/usr/bin/env bash
# tests/tools/test-strace.sh
# Codified test script for strace on Android.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/tests/lib/common.sh"
source "$ROOT_DIR/tests/lib/adb-helpers.sh"

TARGET_DIR=""
STRACE_BIN=""
SERIAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      TARGET_DIR="$2"
      shift 2
      ;;
    --bin)
      STRACE_BIN="$2"
      shift 2
      ;;
    -s|--serial)
      SERIAL="$2"
      shift 2
      ;;
    *)
      if [ -z "$TARGET_DIR" ] && [ -z "$STRACE_BIN" ]; then
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

if [ -z "$TARGET_DIR" ] && [ -z "$STRACE_BIN" ]; then
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/strace/env.sh ]" 2>/dev/null; then
    TARGET_DIR="/data/local/tmp/bionic-pkgs/strace"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/env.sh ]" 2>/dev/null; then
    TARGET_DIR="/data/local/tmp/test-sysroot"
  else
    TARGET_DIR="/data/local/tmp/bionic-pkgs/strace"
  fi
fi

if [ -n "$TARGET_DIR" ]; then
  log_info "Testing strace via dir: ${TARGET_DIR}"
  STRACE_CMD="${TARGET_DIR}/env.sh strace"
else
  log_info "Testing strace via: ${STRACE_BIN}"
  STRACE_CMD="${STRACE_BIN}"
fi

# 1. Version check
output="$(adb_shell "${STRACE_CMD} -V 2>&1" || true)"
assert_contains "$output" "strace -- version" "strace version check (-V)"

# 2. Basic execution & tracing banner
output="$(adb_shell "${STRACE_CMD} /system/bin/echo strace-test-banner 2>&1" || true)"
assert_contains "$output" "strace-test-banner" "strace inferior stdout output"
assert_match "execve\(|write\(" "$output" "strace tracing syscall output"

# 3. System call filtering (-e trace=write)
output="$(adb_shell "${STRACE_CMD} -e trace=write /system/bin/echo strace-filter-test 2>&1" || true)"
assert_contains "$output" "strace-filter-test" "strace filtered inferior stdout output"
assert_contains "$output" "write(" "strace syscall filter matching write()"

# 4. Summary statistics (-c)
output="$(adb_shell "${STRACE_CMD} -c /system/bin/true 2>&1" || true)"
assert_match "% time|syscall|calls" "$output" "strace syscall summary statistics (-c)"

print_summary
