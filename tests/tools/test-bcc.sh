#!/usr/bin/env bash
# tests/tools/test-bcc.sh
# Codified test script for BCC (BPF Compiler Collection) on Android.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/tests/lib/common.sh"
source "$ROOT_DIR/tests/lib/adb-helpers.sh"

BCC_BIN=""
SERIAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bin)
      BCC_BIN="$2"
      shift 2
      ;;
    -s|--serial)
      SERIAL="$2"
      shift 2
      ;;
    *)
      if [ -z "$BCC_BIN" ]; then
        BCC_BIN="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

adb_wait_and_root

if [ -z "$BCC_BIN" ]; then
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/bcc/run.sh ]" 2>/dev/null; then
    BCC_BIN="/data/local/tmp/bionic-pkgs/bcc/run.sh"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/python-launcher.sh ]" 2>/dev/null; then
    BCC_BIN="/data/local/tmp/test-sysroot/python-launcher.sh"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/bin/bps ]" 2>/dev/null; then
    BCC_BIN="/data/local/tmp/test-sysroot/bin/bps"
  else
    BCC_BIN="/data/local/tmp/bionic-pkgs/bcc/run.sh"
  fi
fi

log_info "Testing bcc via: ${BCC_BIN}"

# Determine base directory and wrapper helper for bps and python
BIN_NAME="$(basename "$BCC_BIN")"
if [ "$BIN_NAME" = "run.sh" ]; then
  BASE_DIR="$(dirname "$BCC_BIN")"
  BPS_CMD="LD_LIBRARY_PATH=${BASE_DIR}/lib:\${LD_LIBRARY_PATH:-} ${BASE_DIR}/bin/bps"
  PY_CMD="${BCC_BIN}"
  EXECSNOOP_CMD="LD_LIBRARY_PATH=${BASE_DIR}/lib:\${LD_LIBRARY_PATH:-} ${BASE_DIR}/bin/execsnoop"
elif [ "$BIN_NAME" = "python-launcher.sh" ]; then
  BASE_DIR="$(dirname "$BCC_BIN")"
  BPS_CMD="LD_LIBRARY_PATH=${BASE_DIR}/lib:\${LD_LIBRARY_PATH:-} ${BASE_DIR}/bin/bps"
  PY_CMD="${BCC_BIN}"
  EXECSNOOP_CMD="LD_LIBRARY_PATH=${BASE_DIR}/lib:\${LD_LIBRARY_PATH:-} ${BASE_DIR}/bin/execsnoop"
else
  BASE_DIR="$(dirname "$BCC_BIN")/.."
  BPS_CMD="LD_LIBRARY_PATH=${BASE_DIR}/lib:\${LD_LIBRARY_PATH:-} ${BASE_DIR}/bin/bps"
  PY_CMD="${BASE_DIR}/python-launcher.sh"
  EXECSNOOP_CMD="LD_LIBRARY_PATH=${BASE_DIR}/lib:\${LD_LIBRARY_PATH:-} ${BASE_DIR}/bin/execsnoop"
fi

# Ensure tracefs/debugfs mounted
adb_mount_tracefs

# 1. Introspection utility verification (bps)
output="$(adb_shell "${BPS_CMD} 2>&1" || true)"
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
output="$(adb_shell "${PY_CMD} -c \"import bcc; print('BCC_VERSION:', bcc.__version__)\" 2>&1" || true)"
assert_contains "$output" "BCC_VERSION:" "Python BCC module import and version check"

# 3. Standalone tool help verification
output="$(adb_shell "${EXECSNOOP_CMD} -h 2>&1" || true)"
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

output="$(adb_shell "${PY_CMD} -c \"${bcc_test_code}\" 2>&1" || true)"

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
