#!/usr/bin/env bash
# tests/tools/test-jq.sh
# Codified test script for jq on Android.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/tests/lib/common.sh"
source "$ROOT_DIR/tests/lib/adb-helpers.sh"

JQ_BIN=""
SERIAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bin)
      JQ_BIN="$2"
      shift 2
      ;;
    -s|--serial)
      SERIAL="$2"
      shift 2
      ;;
    *)
      if [ -z "$JQ_BIN" ]; then
        JQ_BIN="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

adb_wait_and_root

if [ -z "$JQ_BIN" ]; then
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/jq/run.sh ]" 2>/dev/null; then
    JQ_BIN="/data/local/tmp/bionic-pkgs/jq/run.sh"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/bin/jq ]" 2>/dev/null; then
    JQ_BIN="/data/local/tmp/test-sysroot/bin/jq"
  else
    JQ_BIN="/data/local/tmp/bionic-pkgs/jq/run.sh"
  fi
fi

log_info "Testing jq via: ${JQ_BIN}"

# 1. Version check
output="$(adb_shell "${JQ_BIN} --version 2>&1" || true)"
assert_contains "$output" "jq-" "jq version check (--version)"

# 2. Simple object property extraction
output="$(adb_shell "echo '{\"status\":\"ok\",\"code\":200}' | ${JQ_BIN} -r .status 2>&1" || true)"
assert_contains "$output" "ok" "jq object property extraction (.status)"

# 3. Array filtering / transformation
output="$(adb_shell "echo '[1, 2, 3]' | ${JQ_BIN} 'map(. * 2) | .[1]' 2>&1" || true)"
assert_contains "$output" "4" "jq array filtering and transformation"

# 4. Regex matching with Oniguruma
output="$(adb_shell "echo '[\"apple\", \"banana\", \"cherry\"]' | ${JQ_BIN} 'map(test(\"^b\")) | any' 2>&1" || true)"
assert_contains "$output" "true" "jq regex matching with Oniguruma"

print_summary
