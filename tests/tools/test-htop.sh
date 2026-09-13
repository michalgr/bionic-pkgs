#!/usr/bin/env bash
# tests/tools/test-htop.sh
# Codified test script for htop on Android.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/tests/lib/common.sh"
source "$ROOT_DIR/tests/lib/adb-helpers.sh"

HTOP_BIN=""
SERIAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bin)
      HTOP_BIN="$2"
      shift 2
      ;;
    -s|--serial)
      SERIAL="$2"
      shift 2
      ;;
    *)
      if [ -z "$HTOP_BIN" ]; then
        HTOP_BIN="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

adb_wait_and_root

if [ -z "$HTOP_BIN" ]; then
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/htop/run.sh ]" 2>/dev/null; then
    HTOP_BIN="/data/local/tmp/bionic-pkgs/htop/run.sh"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/bin/htop ]" 2>/dev/null; then
    HTOP_BIN="/data/local/tmp/test-sysroot/bin/htop"
  else
    HTOP_BIN="/data/local/tmp/bionic-pkgs/htop/run.sh"
  fi
fi

log_info "Testing htop via: ${HTOP_BIN}"

# 1. Version check
output="$(adb_shell "${HTOP_BIN} --version 2>&1" || true)"
assert_contains "$output" "htop 3." "htop version check (--version)"

# 2. Help output
output="$(adb_shell "${HTOP_BIN} --help 2>&1" || true)"
assert_contains "$output" "Usage:" "htop help banner"
assert_contains "$output" "-n, --iterations" "htop iterations option check"

# 3. Single iteration procfs scanning & display test
output="$(adb_shell "TERM=vt100 ${HTOP_BIN} -n 1 2>&1" || true)"
assert_match "PID|CPU%|MEM%" "$output" "htop single iteration procfs scanning (-n 1)"

print_summary
