#!/usr/bin/env bash
# tests/tools/test-tmux.sh
# Codified test script for tmux on Android.

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
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/tmux/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/tmux"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/test-sysroot"
  else
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/tmux"
  fi
fi

log_info "Testing tmux via root: ${TARGET_ROOT}"
TMUX_CMD="${TARGET_ROOT}/env.sh tmux"

# 1. Version check
output="$(adb_shell "${TMUX_CMD} -V 2>&1" || true)"
assert_contains "$output" "tmux 3.7" "tmux version check (-V)"

# 2. Help output
output="$(adb_shell "${TMUX_CMD} -h 2>&1" || true)"
assert_contains "$output" "usage: tmux" "tmux help usage banner"

# 3. Headless session creation & command execution
SESSION_NAME="bionic_tmux_test_$$"
adb_shell "${TMUX_CMD} kill-session -t ${SESSION_NAME} >/dev/null 2>&1 || true"
adb_shell "${TMUX_CMD} new-session -d -s ${SESSION_NAME} 'echo tmux_session_ok > /data/local/tmp/tmux_test_out.txt'"
sleep 1

output="$(adb_shell "cat /data/local/tmp/tmux_test_out.txt 2>&1" || true)"
assert_contains "$output" "tmux_session_ok" "tmux detached session command execution"

adb_shell "${TMUX_CMD} kill-session -t ${SESSION_NAME} >/dev/null 2>&1 || true"
adb_shell "rm -f /data/local/tmp/tmux_test_out.txt"

print_summary
