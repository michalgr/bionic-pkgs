#!/usr/bin/env bash
# tests/tools/test-iperf3.sh
# Codified test script for iperf3 on Android.

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
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/iperf3/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/iperf3"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/test-sysroot"
  else
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/iperf3"
  fi
fi

log_info "Testing iperf3 via root: ${TARGET_ROOT}"
IPERF3_CMD="${TARGET_ROOT}/env.sh iperf3"

# 1. Version check
output="$(adb_shell "${IPERF3_CMD} --version 2>&1" || true)"
assert_contains "$output" "iperf 3." "iperf3 version check (--version)"
assert_match "OpenSSL|authentication" "$output" "iperf3 OpenSSL crypto check"

# 2. Help output
output="$(adb_shell "${IPERF3_CMD} -h 2>&1" || true)"
assert_contains "$output" "Usage: iperf3" "iperf3 help banner"

# 3. Local loopback 1-second throughput test
# Start background one-off server on localhost port 5209
adb_shell "nohup ${IPERF3_CMD} -s -1 -p 5209 > /data/local/tmp/iperf3-srv.log 2>&1 &"
sleep 1

output="$(adb_shell "${IPERF3_CMD} -c 127.0.0.1 -p 5209 -t 1 2>&1" || true)"
assert_contains "$output" "sender" "iperf3 client localhost transfer sender summary"
assert_contains "$output" "receiver" "iperf3 client localhost transfer receiver summary"

print_summary
