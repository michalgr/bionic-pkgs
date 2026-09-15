#!/usr/bin/env bash
# tests/tools/test-strace.sh
# Codified test script for strace on Android.

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
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/strace/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/strace"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/test-sysroot"
  else
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/strace"
  fi
fi

log_info "Testing strace via root: ${TARGET_ROOT}"
ENV_SH="${TARGET_ROOT}/env.sh"

# 1. Version check
output="$(adb_shell "${ENV_SH} strace -V 2>&1" || true)"
assert_contains "$output" "strace -- version" "strace version check (-V)"

# 2. Basic execution & tracing banner
output="$(adb_shell "${ENV_SH} strace /system/bin/echo strace-test-banner 2>&1" || true)"
assert_contains "$output" "strace-test-banner" "strace inferior stdout output"
assert_match "execve\(|write\(" "$output" "strace tracing syscall output"

# 3. System call filtering (-e trace=write)
output="$(adb_shell "${ENV_SH} strace -e trace=write /system/bin/echo strace-filter-test 2>&1" || true)"
assert_contains "$output" "strace-filter-test" "strace filtered inferior stdout output"
assert_contains "$output" "write(" "strace syscall filter matching write()"

# 4. Summary statistics (-c)
output="$(adb_shell "${ENV_SH} strace -c /system/bin/true 2>&1" || true)"
assert_match "% time|syscall|calls" "$output" "strace syscall summary statistics (-c)"

print_summary
