#!/usr/bin/env bash
# tests/tools/test-jq.sh
# Codified test script for jq on Android.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/tests/lib/common.sh"
source "$ROOT_DIR/tests/lib/adb-helpers.sh"

TARGET_DIR=""
JQ_BIN=""
SERIAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      TARGET_DIR="$2"
      shift 2
      ;;
    --bin)
      JQ_BIN="$2"
      shift 2
      ;;
    -s|--serial)
      SERIAL="$2"
      shift 2
      ;;
    *)
      if [ -z "$TARGET_DIR" ] && [ -z "$JQ_BIN" ]; then
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

if [ -z "$TARGET_DIR" ] && [ -z "$JQ_BIN" ]; then
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/jq/env.sh ]" 2>/dev/null; then
    TARGET_DIR="/data/local/tmp/bionic-pkgs/jq"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/env.sh ]" 2>/dev/null; then
    TARGET_DIR="/data/local/tmp/test-sysroot"
  else
    TARGET_DIR="/data/local/tmp/bionic-pkgs/jq"
  fi
fi

if [ -n "$TARGET_DIR" ]; then
  log_info "Testing jq via dir: ${TARGET_DIR}"
  JQ_CMD="${TARGET_DIR}/env.sh jq"
else
  log_info "Testing jq via: ${JQ_BIN}"
  JQ_CMD="${JQ_BIN}"
fi

# 1. Version check
output="$(adb_shell "${JQ_CMD} --version 2>&1" || true)"
assert_contains "$output" "jq-" "jq version check (--version)"

# 2. JSON property extraction
output="$(adb_shell "echo '{\"status\":\"ok\",\"code\":200}' | ${JQ_CMD} -r .status 2>&1" || true)"
assert_contains "$output" "ok" "jq JSON property extraction (.status)"

# 3. Array mapping and transformation
output="$(adb_shell "echo '[1, 2, 3]' | ${JQ_CMD} 'map(. * 2) | .[1]' 2>&1" || true)"
assert_contains "$output" "4" "jq array mapping/transformation (map(. * 2) | .[1])"

# 4. Oniguruma regex matching
output="$(adb_shell "echo '[\"apple\", \"banana\", \"cherry\"]' | ${JQ_CMD} 'map(test(\"^b\")) | any' 2>&1" || true)"
assert_contains "$output" "true" "jq Oniguruma regex matching (test(\"^b\"))"

print_summary
