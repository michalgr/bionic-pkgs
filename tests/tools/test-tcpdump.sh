#!/usr/bin/env bash
# tests/tools/test-tcpdump.sh
# Codified test script for tcpdump on Android.

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
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/tcpdump/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/tcpdump"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/test-sysroot"
  else
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/tcpdump"
  fi
fi

log_info "Testing tcpdump via root: ${TARGET_ROOT}"
ENV_SH="${TARGET_ROOT}/env.sh"

# 1. Version check
output="$(adb_shell "${ENV_SH} tcpdump --version 2>&1" || true)"
assert_contains "$output" "tcpdump version" "tcpdump version check (--version)"
assert_contains "$output" "libpcap version" "tcpdump libpcap integration check"

# 2. Help output
output="$(adb_shell "${ENV_SH} tcpdump -h 2>&1" || true)"
assert_contains "$output" "Usage:" "tcpdump help banner"

# 3. Interface enumeration
output="$(adb_shell "${ENV_SH} tcpdump -D 2>&1" || true)"
assert_match "lo|any" "$output" "tcpdump interface enumeration (-D)"

# 4. BPF filter compilation
output="$(adb_shell "${ENV_SH} tcpdump -d 'ip and tcp' 2>&1" || true)"
assert_contains "$output" "(000)" "tcpdump BPF filter compilation (-d 'ip and tcp')"

print_summary
