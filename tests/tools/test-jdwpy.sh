#!/usr/bin/env bash
# tests/tools/test-jdwpy.sh
# Codified test script for jdwpy on Android.

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
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/jdwpy/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/jdwpy"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/test-sysroot"
  else
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/jdwpy"
  fi
fi

log_info "Testing jdwpy via root: ${TARGET_ROOT}"
ENV_SH="${TARGET_ROOT}/env.sh"

# 1. Python module import check
output="$(adb_shell "${ENV_SH} python3 -c \"import jdwpy; print('JDWPY_IMPORT_OK')\" 2>&1" || true)"
assert_contains "$output" "JDWPY_IMPORT_OK" "jdwpy Python module import check"

# 2. Protocol structures, packet serialization, and exports check
output="$(adb_shell "${ENV_SH} python3 -c \"import jdwpy; from jdwpy import JdwpConnection, JdwpTag, JdwpErrorCode, JdwpEventKind, IdSizesSpec; assert JdwpTag.INT == 73; assert JdwpErrorCode.NONE == 0; print('JDWPY_SPEC_OK')\" 2>&1" || true)"
assert_contains "$output" "JDWPY_SPEC_OK" "jdwpy protocol structures and exports check"

print_summary
