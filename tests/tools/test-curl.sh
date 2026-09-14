#!/usr/bin/env bash
# tests/tools/test-curl.sh
# Codified test script for curl on Android.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/tests/lib/common.sh"
source "$ROOT_DIR/tests/lib/adb-helpers.sh"

TARGET_DIR=""
CURL_BIN=""
SERIAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      TARGET_DIR="$2"
      shift 2
      ;;
    --bin)
      CURL_BIN="$2"
      shift 2
      ;;
    -s|--serial)
      SERIAL="$2"
      shift 2
      ;;
    *)
      if [ -z "$TARGET_DIR" ] && [ -z "$CURL_BIN" ]; then
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

if [ -z "$TARGET_DIR" ] && [ -z "$CURL_BIN" ]; then
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/curl/env.sh ]" 2>/dev/null; then
    TARGET_DIR="/data/local/tmp/bionic-pkgs/curl"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/env.sh ]" 2>/dev/null; then
    TARGET_DIR="/data/local/tmp/test-sysroot"
  else
    TARGET_DIR="/data/local/tmp/bionic-pkgs/curl"
  fi
fi

if [ -n "$TARGET_DIR" ]; then
  log_info "Testing curl via dir: ${TARGET_DIR}"
  CURL_CMD="${TARGET_DIR}/env.sh curl"
else
  log_info "Testing curl via: ${CURL_BIN}"
  CURL_CMD="${CURL_BIN}"
fi

# 1. Version check
output="$(adb_shell "${CURL_CMD} --version 2>&1" || true)"
assert_contains "$output" "curl 8." "curl version check (--version)"
assert_contains "$output" "OpenSSL/" "curl OpenSSL TLS backend check"
assert_contains "$output" "zlib/" "curl zlib compression support"
assert_contains "$output" "zstd/" "curl zstd compression support"

# 2. Protocol support
assert_contains "$output" "Protocols:" "curl protocols header"
assert_contains "$output" "http" "curl HTTP protocol support"
assert_contains "$output" "https" "curl HTTPS protocol support"
assert_contains "$output" "file" "curl FILE protocol support"

# 3. Local file retrieval
output="$(adb_shell "${CURL_CMD} -s file:///proc/version 2>&1" || true)"
assert_contains "$output" "Linux version" "curl local file fetch (file:///proc/version)"

# 4. Command-line options & status formatting
output="$(adb_shell "${CURL_CMD} -s -o /dev/null -w '%{http_code}' file:///proc/version 2>&1" || true)"
assert_match "200|000" "$output" "curl status code extraction (-w '%{http_code}')"

# 5. CA certificates trust directory presence on Android
output="$(adb_shell "[ -d /system/etc/security/cacerts ] && echo CACERTS_DIR_EXISTS 2>&1" || true)"
assert_contains "$output" "CACERTS_DIR_EXISTS" "Android system CA certificates directory presence"

print_summary
