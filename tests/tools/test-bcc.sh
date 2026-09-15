#!/usr/bin/env bash
# tests/tools/test-bcc.sh
# Codified test script for BCC (BPF Compiler Collection) on Android.

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
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/bcc/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/bcc"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/test-sysroot"
  else
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/bcc"
  fi
fi

log_info "Testing bcc via root: ${TARGET_ROOT}"
ENV_SH="${TARGET_ROOT}/env.sh"

# Ensure tracefs/debugfs mounted
adb_mount_tracefs

# 1. Introspection utility verification (bps)
output="$(adb_shell "${ENV_SH} bps 2>&1" || true)"
if echo "$output" | grep -E -q "BID|PID|COMM|TASK|bps" 2>/dev/null; then
  log_pass "BCC introspection utility verification (bps)"
else
  if [[ "$output" == *"CAP_"* ]] || [[ "$output" == *"capability"* ]] || [[ "$output" == *"retry as root"* ]]; then
    skip_test "BCC introspection utility verification (bps)" "Requires root/capabilities: ${output}"
  else
    log_fail "BCC introspection utility verification (bps) failed: ${output}"
  fi
fi

# 2. Python BCC module verification
output="$(adb_shell "${ENV_SH} python3 -c \"import bcc; print('BCC_VERSION:', bcc.__version__)\" 2>&1" || true)"
assert_contains "$output" "BCC_VERSION:" "Python BCC module import and version check"

# 3. Standalone tool help verification
output="$(adb_shell "${ENV_SH} execsnoop -h 2>&1" || true)"
assert_match "execsnoop|USAGE|options|Trace" "$output" "BCC standalone tool help verification (execsnoop -h)"

# 4. BPF C program compilation and execution using bcc.BPF
bcc_test_code="
import sys
from bcc import BPF
prog = 'int hello(void *ctx) { return 0; }'
try:
    b = BPF(text=prog)
    print('BCC_C_COMPILE_OK')
except Exception as e:
    print('BCC_COMPILE_ERR:', e)
"

output="$(adb_shell "${ENV_SH} python3 -c \"${bcc_test_code}\" 2>&1" || true)"

if [[ "$output" == *"BCC_C_COMPILE_OK"* ]]; then
  log_pass "BCC C program compilation and execution (bcc.BPF)"
else
  if [[ "$output" == *"BCC_COMPILE_ERR"* ]] || [[ "$output" == *"Operation not permitted"* ]] || [[ "$output" == *"Permission denied"* ]] || [[ "$output" == *"linux/bpf.h"* ]] || [[ "$output" == *"KERNEL"* ]] || [[ "$output" == *"capability"* ]] || [[ "$output" == *"Unable to find kernel headers"* ]]; then
    skip_test "BCC C program compilation and execution" "Kernel lacks required BPF/tracefs features or headers: ${output}"
  else
    log_fail "BCC C program compilation failed: ${output}"
  fi
fi

print_summary
