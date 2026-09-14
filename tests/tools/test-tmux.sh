#!/usr/bin/env bash
# tests/tools/test-tmux.sh
# Codified test script for tmux on Android.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/tests/lib/common.sh"
source "$ROOT_DIR/tests/lib/adb-helpers.sh"

TMUX_BIN=""
SERIAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bin)
      TMUX_BIN="$2"
      shift 2
      ;;
    -s|--serial)
      SERIAL="$2"
      shift 2
      ;;
    *)
      if [ -z "$TMUX_BIN" ]; then
        TMUX_BIN="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

adb_wait_and_root

if [ -z "$TMUX_BIN" ]; then
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/tmux/run.sh ]" 2>/dev/null; then
    TMUX_BIN="/data/local/tmp/bionic-pkgs/tmux/run.sh"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/bin/tmux ]" 2>/dev/null; then
    TMUX_BIN="/data/local/tmp/test-sysroot/bin/tmux"
  else
    TMUX_BIN="/data/local/tmp/bionic-pkgs/tmux/run.sh"
  fi
fi

log_info "Testing tmux via: ${TMUX_BIN}"

# 1. Version check
output="$(adb_shell "${TMUX_BIN} -V 2>&1" || true)"
assert_contains "$output" "tmux 3.7" "tmux version check (-V)"

# 2. Start a detached session running a simple echo command
adb_shell "${TMUX_BIN} kill-server 2>/dev/null || true"
adb_shell "rm -f /data/local/tmp/tmux_test.out"

adb_shell "${TMUX_BIN} new-session -d -s bionic-test '/system/bin/sh -c \"echo tmux-alive > /data/local/tmp/tmux_test.out; sleep 2\"'"

# 3. Verify session was created
output="$(adb_shell "${TMUX_BIN} list-sessions 2>&1" || true)"
assert_contains "$output" "bionic-test" "tmux list-sessions check"

# 4. Verify executed command inside tmux pane wrote to output file
sleep 1
output="$(adb_shell "cat /data/local/tmp/tmux_test.out 2>/dev/null || true")"
assert_contains "$output" "tmux-alive" "tmux command execution verification"

# 5. Clean up server and test file
adb_shell "${TMUX_BIN} kill-server 2>/dev/null || true"
adb_shell "rm -f /data/local/tmp/tmux_test.out"

print_summary
