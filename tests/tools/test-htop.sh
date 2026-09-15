#!/usr/bin/env bash
# tests/tools/test-htop.sh
# Codified test script for htop on Android.

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
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/htop/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/htop"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/test-sysroot"
  else
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/htop"
  fi
fi

log_info "Testing htop via root: ${TARGET_ROOT}"
HTOP_CMD="${TARGET_ROOT}/env.sh htop"

# 1. Version check
output="$(adb_shell "${HTOP_CMD} --version 2>&1" || true)"
assert_contains "$output" "htop 3." "htop version check (--version)"

# 2. Help output
output="$(adb_shell "${HTOP_CMD} --help 2>&1" || true)"
assert_contains "$output" "Print this help screen" "htop help banner"
assert_contains "$output" "--max-iterations" "htop iterations option check"

# 3. Single iteration procfs scanning & display test
output="$(adb_shell "TERM=vt100 ${HTOP_CMD} -n 1 2>&1" || true)"
assert_match "PID|CPU%|MEM%" "$output" "htop single iteration procfs scanning (-n 1)"

print_summary
