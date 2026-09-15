#!/usr/bin/env bash
# tests/tools/test-jq.sh
# Codified test script for jq on Android.

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
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/jq/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/jq"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/test-sysroot"
  else
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/jq"
  fi
fi

log_info "Testing jq via root: ${TARGET_ROOT}"
ENV_SH="${TARGET_ROOT}/env.sh"

# 1. Version check
output="$(adb_shell "${ENV_SH} jq --version 2>&1" || true)"
assert_contains "$output" "jq-" "jq version check (--version)"

# 2. JSON property extraction
output="$(adb_shell "echo '{\"status\":\"ok\",\"code\":200}' | ${ENV_SH} jq -r .status 2>&1" || true)"
assert_contains "$output" "ok" "jq JSON property extraction (.status)"

# 3. Array mapping and transformation
output="$(adb_shell "echo '[1, 2, 3]' | ${ENV_SH} jq 'map(. * 2) | .[1]' 2>&1" || true)"
assert_contains "$output" "4" "jq array mapping/transformation (map(. * 2) | .[1])"

# 4. Oniguruma regex matching
output="$(adb_shell "echo '[\"apple\", \"banana\", \"cherry\"]' | ${ENV_SH} jq 'map(test(\"^b\")) | any' 2>&1" || true)"
assert_contains "$output" "true" "jq Oniguruma regex matching (test(\"^b\"))"

print_summary
