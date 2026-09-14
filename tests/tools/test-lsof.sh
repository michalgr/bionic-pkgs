#!/usr/bin/env bash
# tests/tools/test-lsof.sh
# Codified test script for lsof on Android.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/tests/lib/common.sh"
source "$ROOT_DIR/tests/lib/adb-helpers.sh"

LSOF_BIN=""
SERIAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bin)
      LSOF_BIN="$2"
      shift 2
      ;;
    -s|--serial)
      SERIAL="$2"
      shift 2
      ;;
    *)
      if [ -z "$LSOF_BIN" ]; then
        LSOF_BIN="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

adb_wait_and_root

if [ -z "$LSOF_BIN" ]; then
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/lsof/run.sh ]" 2>/dev/null; then
    LSOF_BIN="/data/local/tmp/bionic-pkgs/lsof/run.sh"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/bin/lsof ]" 2>/dev/null; then
    LSOF_BIN="/data/local/tmp/test-sysroot/bin/lsof"
  else
    LSOF_BIN="/data/local/tmp/bionic-pkgs/lsof/run.sh"
  fi
fi

log_info "Testing lsof via: ${LSOF_BIN}"

# 1. Version check (-v prints version and repository URL to stderr)
output="$(adb_shell "${LSOF_BIN} -v 2>&1" || true)"
assert_contains "$output" "4.99." "lsof version check (-v)"
assert_contains "$output" "revision:" "lsof revision check (-v)"

# 2. Help output (-h prints usage banner to stderr)
output="$(adb_shell "${LSOF_BIN} -h 2>&1" || true)"
assert_contains "$output" "usage:" "lsof usage banner (-h)"

# 3. Process file inspection on PID 1 (init)
output="$(adb_shell "${LSOF_BIN} -p 1 2>&1" || true)"
assert_contains "$output" "COMMAND" "lsof process file table header"
assert_match "init|systemd" "$output" "lsof PID 1 command inspection"

# 4. Terse PID output (-t)
output="$(adb_shell "${LSOF_BIN} -t -p 1 2>&1" || true)"
assert_contains "$output" "1" "lsof terse PID output (-t)"

print_summary
