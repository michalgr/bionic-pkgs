#!/usr/bin/env bash
# tests/tools/test-lsof.sh
# Codified test script for lsof on Android.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/tests/lib/common.sh"
source "$ROOT_DIR/tests/lib/adb-helpers.sh"

TARGET_DIR=""
LSOF_BIN=""
SERIAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      TARGET_DIR="$2"
      shift 2
      ;;
    --bin)
      LSOF_BIN="$2"
      shift 2
      ;;
    -s|--serial)
      SERIAL="$2"
      shift 2
      ;;
    *)
      if [ -z "$TARGET_DIR" ] && [ -z "$LSOF_BIN" ]; then
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

if [ -z "$TARGET_DIR" ] && [ -z "$LSOF_BIN" ]; then
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/lsof/env.sh ]" 2>/dev/null; then
    TARGET_DIR="/data/local/tmp/bionic-pkgs/lsof"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/env.sh ]" 2>/dev/null; then
    TARGET_DIR="/data/local/tmp/test-sysroot"
  else
    TARGET_DIR="/data/local/tmp/bionic-pkgs/lsof"
  fi
fi

if [ -n "$TARGET_DIR" ]; then
  log_info "Testing lsof via dir: ${TARGET_DIR}"
  LSOF_CMD="${TARGET_DIR}/env.sh lsof"
else
  log_info "Testing lsof via: ${LSOF_BIN}"
  LSOF_CMD="${LSOF_BIN}"
fi

# 1. Version check (-v prints version and repository URL to stderr)
output="$(adb_shell "${LSOF_CMD} -v 2>&1" || true)"
assert_contains "$output" "4.99." "lsof version check (-v)"
assert_contains "$output" "revision:" "lsof revision check (-v)"

# 2. Help output (-h prints usage banner to stderr)
output="$(adb_shell "${LSOF_CMD} -h 2>&1" || true)"
assert_contains "$output" "usage:" "lsof usage banner (-h)"

# 3. Process file inspection on PID 1 (init)
output="$(adb_shell "${LSOF_CMD} -p 1 2>&1" || true)"
assert_contains "$output" "COMMAND" "lsof process file table header"
assert_match "init|systemd" "$output" "lsof PID 1 command inspection"

# 4. Terse PID output (-t)
output="$(adb_shell "${LSOF_CMD} -t -p 1 2>&1" || true)"
assert_contains "$output" "1" "lsof terse PID output (-t)"

print_summary
