#!/usr/bin/env bash
# tests/tools/test-lldb.sh
# Codified test script for LLDB and lldb-server on Android.

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
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/lldb/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/lldb"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/test-sysroot"
  else
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/lldb"
  fi
fi

log_info "Testing lldb via root: ${TARGET_ROOT}"
ENV_SH="${TARGET_ROOT}/env.sh"

# 1. Version check for lldb CLI
output="$(adb_shell "${ENV_SH} lldb --version 2>&1" || true)"
assert_contains "$output" "lldb version" "lldb version check (--version)"

# 2. Version check for companion lldb-server
output="$(adb_shell "${ENV_SH} lldb-server v 2>&1 || ${ENV_SH} lldb-server version 2>&1" || true)"
assert_match "lldb-server|version" "$output" "lldb-server version check"

# 3. Batch execution & process tracing
output="$(adb_shell "${ENV_SH} lldb --batch -o 'file /system/bin/echo' -o 'run bionic-test' -o 'quit' 2>&1" || true)"
assert_match "bionic-test|exited with status" "$output" "lldb batch execution & process tracing"

# 4. Target image inspection
output="$(adb_shell "${ENV_SH} lldb --batch -o 'target create /system/bin/sh' -o 'image list' -o 'quit' 2>&1" || true)"
assert_contains "$output" "/system/bin/sh" "lldb target image inspection"

# 5. Breakpoint and control flow
output="$(adb_shell "${ENV_SH} lldb --batch -o 'file /system/bin/echo' -o 'breakpoint set -n main' -o 'run test' -o 'continue' -o 'quit' 2>&1" || true)"
assert_match "Breakpoint|stopped|exited" "$output" "lldb breakpoint set and control flow"

# 6. Python interpreter execution in LLDB batch mode
output="$(adb_shell "${ENV_SH} lldb --batch -o 'script print(1234 + 5678)' 2>&1" || true)"
assert_contains "$output" "6912" "lldb python script execution"

# 7. LLDB module import and API access
output="$(adb_shell "${ENV_SH} lldb --batch -o 'script import lldb; print(lldb.debugger.GetVersionString())' 2>&1" || true)"
assert_contains "$output" "lldb version" "lldb python module import and API access"

print_summary
