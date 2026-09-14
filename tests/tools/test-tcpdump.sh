#!/usr/bin/env bash
# tests/tools/test-tcpdump.sh
# Codified test script for tcpdump on Android.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/tests/lib/common.sh"
source "$ROOT_DIR/tests/lib/adb-helpers.sh"

TCPDUMP_BIN=""
SERIAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bin)
      TCPDUMP_BIN="$2"
      shift 2
      ;;
    -s|--serial)
      SERIAL="$2"
      shift 2
      ;;
    *)
      if [ -z "$TCPDUMP_BIN" ]; then
        TCPDUMP_BIN="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

adb_wait_and_root

if [ -z "$TCPDUMP_BIN" ]; then
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/tcpdump/run.sh ]" 2>/dev/null; then
    TCPDUMP_BIN="/data/local/tmp/bionic-pkgs/tcpdump/run.sh"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/bin/tcpdump ]" 2>/dev/null; then
    TCPDUMP_BIN="/data/local/tmp/test-sysroot/bin/tcpdump"
  else
    TCPDUMP_BIN="/data/local/tmp/bionic-pkgs/tcpdump/run.sh"
  fi
fi

log_info "Testing tcpdump via: ${TCPDUMP_BIN}"

# 1. Version check
output="$(adb_shell "${TCPDUMP_BIN} --version 2>&1" || true)"
assert_contains "$output" "tcpdump version 4." "tcpdump version check (--version)"
assert_contains "$output" "libpcap version 1." "libpcap version check"
assert_contains "$output" "OpenSSL" "tcpdump OpenSSL support check"

# 2. Help output
output="$(adb_shell "${TCPDUMP_BIN} -h 2>&1" || true)"
assert_contains "$output" "Usage:" "tcpdump help banner"

# 3. Interface enumeration
output="$(adb_shell "${TCPDUMP_BIN} -D 2>&1" || true)"
assert_match "lo|any" "$output" "tcpdump interface enumeration (-D)"

# 4. BPF filter compilation
output="$(adb_shell "${TCPDUMP_BIN} -d 'ip and tcp' 2>&1" || true)"
assert_contains "$output" "(000)" "tcpdump BPF filter assembly dump (-d)"

print_summary
