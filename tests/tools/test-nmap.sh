#!/usr/bin/env bash
# tests/tools/test-nmap.sh
# Codified test script for nmap, ncat, and nping on Android.

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
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/nmap/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/nmap"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/test-sysroot"
  else
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/nmap"
  fi
fi

log_info "Testing nmap via root: ${TARGET_ROOT}"
NMAP_CMD="${TARGET_ROOT}/env.sh nmap"
NCAT_CMD="${TARGET_ROOT}/env.sh ncat"
NPING_CMD="${TARGET_ROOT}/env.sh nping"

# 1. Nmap version check
output="$(adb_shell "${NMAP_CMD} --version 2>&1" || true)"
assert_contains "$output" "Nmap version 7.99" "nmap version check (--version)"

# 2. Ncat version check
output="$(adb_shell "${NCAT_CMD} --version 2>&1" || true)"
assert_contains "$output" "Ncat: Version 7.99" "ncat version check (--version)"

# 3. Nping version check
output="$(adb_shell "${NPING_CMD} --version 2>&1" || true)"
assert_contains "$output" "Nping version 7.99" "nping version check (--version)"

# 4. Nmap ping sweep on localhost
output="$(adb_shell "${NMAP_CMD} -sn 127.0.0.1 2>&1" || true)"
assert_contains "$output" "Nmap done: 1 IP address (1 host up)" "nmap localhost ping scan (-sn)"

# 5. Nping ICMP echo probe on localhost
output="$(adb_shell "${NPING_CMD} --tcp -c 1 -p 80 127.0.0.1 2>&1" || true)"
assert_contains "$output" "Nping done: 1 IP address pinged" "nping TCP probe to localhost"

print_summary
