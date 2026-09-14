#!/usr/bin/env bash
# tests/tools/test-tcpdump.sh
# Codified test script for tcpdump on Android.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/tests/lib/common.sh"
source "$ROOT_DIR/tests/lib/adb-helpers.sh"

TARGET_DIR=""
TCPDUMP_BIN=""
SERIAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      TARGET_DIR="$2"
      shift 2
      ;;
    --bin)
      TCPDUMP_BIN="$2"
      shift 2
      ;;
    -s|--serial)
      SERIAL="$2"
      shift 2
      ;;
    *)
      if [ -z "$TARGET_DIR" ] && [ -z "$TCPDUMP_BIN" ]; then
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

if [ -z "$TARGET_DIR" ] && [ -z "$TCPDUMP_BIN" ]; then
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/tcpdump/env.sh ]" 2>/dev/null; then
    TARGET_DIR="/data/local/tmp/bionic-pkgs/tcpdump"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/env.sh ]" 2>/dev/null; then
    TARGET_DIR="/data/local/tmp/test-sysroot"
  else
    TARGET_DIR="/data/local/tmp/bionic-pkgs/tcpdump"
  fi
fi

if [ -n "$TARGET_DIR" ]; then
  log_info "Testing tcpdump via dir: ${TARGET_DIR}"
  TCPDUMP_CMD="${TARGET_DIR}/env.sh tcpdump"
else
  log_info "Testing tcpdump via: ${TCPDUMP_BIN}"
  TCPDUMP_CMD="${TCPDUMP_BIN}"
fi

# 1. Version check
output="$(adb_shell "${TCPDUMP_CMD} --version 2>&1" || true)"
assert_contains "$output" "tcpdump version" "tcpdump version check (--version)"
assert_contains "$output" "libpcap version" "tcpdump libpcap integration check"

# 2. Help output
output="$(adb_shell "${TCPDUMP_CMD} -h 2>&1" || true)"
assert_contains "$output" "Usage:" "tcpdump help banner"

# 3. Interface enumeration
output="$(adb_shell "${TCPDUMP_CMD} -D 2>&1" || true)"
assert_match "lo|any" "$output" "tcpdump interface enumeration (-D)"

# 4. BPF filter compilation
output="$(adb_shell "${TCPDUMP_CMD} -d 'ip and tcp' 2>&1" || true)"
assert_contains "$output" "(000)" "tcpdump BPF filter compilation (-d 'ip and tcp')"

print_summary
