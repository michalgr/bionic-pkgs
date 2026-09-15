#!/usr/bin/env bash
# tests/tools/test-socat.sh
# Codified test script for socat on Android.

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
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/socat/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/socat"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/test-sysroot"
  else
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/socat"
  fi
fi

log_info "Testing socat via root: ${TARGET_ROOT}"
SOCAT_CMD="${TARGET_ROOT}/env.sh socat"

# 1. Version check
output="$(adb_shell "${SOCAT_CMD} -V 2>&1" || true)"
assert_contains "$output" "socat version 1." "socat version check (-V)"
assert_contains "$output" "features:" "socat features list"
assert_contains "$output" "OPENSSL" "socat OpenSSL support"
assert_contains "$output" "READLINE" "socat Readline support"

# 2. Help output
output="$(adb_shell "${SOCAT_CMD} -h 2>&1" || true)"
assert_contains "$output" "Usage:" "socat help usage banner"

# 3. Standard I/O / Pipe bidirectional transfer
output="$(adb_shell "echo 'socat_pipe_test' | ${SOCAT_CMD} - - 2>&1" || true)"
assert_contains "$output" "socat_pipe_test" "socat stdin/stdout pipe transfer"

# 4. TCP loopback relay transfer
TCP_PORT=19999
adb_shell "${SOCAT_CMD} TCP4-LISTEN:${TCP_PORT},bind=127.0.0.1,reuseaddr SYSTEM:'echo socat_tcp_relay_ok' >/dev/null 2>&1 &"
sleep 1
output="$(adb_shell "${SOCAT_CMD} - TCP4:127.0.0.1:${TCP_PORT} 2>&1" || true)"
assert_contains "$output" "socat_tcp_relay_ok" "socat TCP loopback relay"

# 5. UNIX domain socket relay transfer
SOCK_PATH="/data/local/tmp/test_socat.sock"
adb_shell "rm -f ${SOCK_PATH}"
adb_shell "${SOCAT_CMD} UNIX-LISTEN:${SOCK_PATH},reuseaddr SYSTEM:'echo socat_unix_relay_ok' >/dev/null 2>&1 &"
sleep 1
output="$(adb_shell "${SOCAT_CMD} - UNIX-CONNECT:${SOCK_PATH} 2>&1" || true)"
assert_contains "$output" "socat_unix_relay_ok" "socat UNIX domain socket relay"
adb_shell "rm -f ${SOCK_PATH}"

print_summary
