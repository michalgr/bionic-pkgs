#!/usr/bin/env bash
# tests/tools/test-nmap.sh
# Codified test script for nmap, ncat, and nping on Android.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/tests/lib/common.sh"
source "$ROOT_DIR/tests/lib/adb-helpers.sh"

NMAP_BIN=""
SERIAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bin)
      NMAP_BIN="$2"
      shift 2
      ;;
    -s|--serial)
      SERIAL="$2"
      shift 2
      ;;
    *)
      if [ -z "$NMAP_BIN" ]; then
        NMAP_BIN="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

adb_wait_and_root

if [ -z "$NMAP_BIN" ]; then
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/nmap/run.sh ]" 2>/dev/null; then
    NMAP_BIN="/data/local/tmp/bionic-pkgs/nmap/run.sh"
    BIN_DIR="/data/local/tmp/bionic-pkgs/nmap/bin"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/bin/nmap ]" 2>/dev/null; then
    NMAP_BIN="/data/local/tmp/test-sysroot/bin/nmap"
    BIN_DIR="/data/local/tmp/test-sysroot/bin"
  else
    NMAP_BIN="/data/local/tmp/bionic-pkgs/nmap/run.sh"
    BIN_DIR="/data/local/tmp/bionic-pkgs/nmap/bin"
  fi
else
  BIN_DIR="$(dirname "$NMAP_BIN")"
fi

log_info "Testing nmap via: ${NMAP_BIN} (BIN_DIR=${BIN_DIR})"

# 1. Nmap version check
output="$(adb_shell "${NMAP_BIN} --version 2>&1" || true)"
assert_contains "$output" "Nmap version 7.99" "nmap version check (--version)"

# 2. Ncat version check
output="$(adb_shell "PATH=\"${BIN_DIR}:\$PATH\" ${BIN_DIR}/ncat --version 2>&1" || true)"
assert_contains "$output" "Ncat: Version 7.99" "ncat version check (--version)"

# 3. Nping version check
output="$(adb_shell "PATH=\"${BIN_DIR}:\$PATH\" ${BIN_DIR}/nping --version 2>&1" || true)"
assert_contains "$output" "Nping version 0.7.99" "nping version check (--version)"

# 4. Nmap ping sweep on localhost
output="$(adb_shell "${NMAP_BIN} -sn 127.0.0.1 2>&1" || true)"
assert_contains "$output" "Nmap done: 1 IP address (1 host up)" "nmap localhost ping scan (-sn)"

# 5. Nping ICMP echo probe on localhost
output="$(adb_shell "PATH=\"${BIN_DIR}:\$PATH\" ${BIN_DIR}/nping --tcp -c 1 -p 80 127.0.0.1 2>&1" || true)"
assert_contains "$output" "Nping done: 1 IP address pinged" "nping TCP probe to localhost"

print_summary
