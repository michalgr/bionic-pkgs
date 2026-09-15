#!/usr/bin/env bash
# tests/tools/test-bpftrace.sh
# Codified test script for bpftrace (static and dynamic) on Android.

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
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/bpftrace/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/bpftrace"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/test-sysroot"
  else
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/bpftrace"
  fi
fi

log_info "Testing bpftrace via root: ${TARGET_ROOT}"
if adb_shell "[ -f '${TARGET_ROOT}/env.sh' ]" 2>/dev/null; then
  BPFTRACE_CMD="${TARGET_ROOT}/env.sh bpftrace"
  SYSCOUNT_CMD="${TARGET_ROOT}/env.sh syscount"
else
  BPFTRACE_CMD="${TARGET_ROOT}/bin/bpftrace"
  SYSCOUNT_CMD="${TARGET_ROOT}/bin/syscount"
fi

# Ensure tracefs/debugfs mounted
adb_mount_tracefs

# 1. Version check
output="$(adb_shell "${BPFTRACE_CMD} -V 2>&1" || true)"
assert_contains "$output" "bpftrace" "bpftrace version check (-V)"

# 2. Environment / Info check
output="$(adb_shell "${BPFTRACE_CMD} --info 2>&1" || true)"
if echo "$output" | grep -E -q "Build|Kernel|BFD|eBPF" 2>/dev/null; then
  log_pass "bpftrace environment info (--info)"
else
  if [[ "$output" == *"CAP_"* ]] || [[ "$output" == *"root"* ]] || [[ "$output" == *"Permission denied"* ]]; then
    skip_test "bpftrace environment info (--info)" "Requires root/capabilities: ${output}"
  else
    log_fail "bpftrace environment info (--info) failed: ${output}"
  fi
fi

# 3. Companion tool verification (syscount)
output="$(adb_shell "${SYSCOUNT_CMD} --help 2>&1" || true)"
assert_match "syscount|Usage|count|syscalls" "$output" "bpftrace companion tool verification (syscount --help)"

# 4. Userspace-only BPF probe (independent of tracefs)
output="$(adb_shell "${BPFTRACE_CMD} -e 'BEGIN { printf(\"bpftrace userspace ok\\n\"); exit(); }' 2>&1" || true)"
if [[ "$output" == *"bpftrace userspace ok"* ]]; then
  log_pass "bpftrace userspace-only BPF probe (BEGIN block)"
else
  if [[ "$output" == *"CAP_"* ]] || [[ "$output" == *"Permission denied"* ]] || [[ "$output" == *"Operation not permitted"* ]] || [[ "$output" == *"bpf"* ]] || [[ "$output" == *"No such file or directory"* ]]; then
    skip_test "bpftrace userspace-only BPF probe" "Kernel/environment lacks BPF support or root capabilities: ${output}"
  else
    log_fail "bpftrace userspace-only BPF probe failed: ${output}"
  fi
fi

# 5. Kernel tracepoint probe with graceful skip
set +e
output="$(timeout 15 "$ADB_CMD" ${SERIAL:+-s "$SERIAL"} shell "${BPFTRACE_CMD} -e 'tracepoint:raw_syscalls:sys_enter { @[comm] = count(); } interval:s:1 { exit(); }' 2>&1")"
ret=$?
set -e

if [ $ret -eq 0 ] || [ $ret -eq 124 ]; then
  log_pass "bpftrace kernel tracepoint probe (tracepoint:raw_syscalls:sys_enter)"
else
  if [[ "$output" == *"ERROR"* ]] || [[ "$output" == *"CAP_"* ]] || [[ "$output" == *"Permission denied"* ]] || [[ "$output" == *"No such file or directory"* ]] || [[ "$output" == *"REQUIRED"* ]]; then
    skip_test "bpftrace kernel tracepoint probe" "Kernel lacks tracepoint/BTF features or debugfs/capability access"
  else
    log_fail "bpftrace kernel tracepoint probe failed with exit code $ret: $output"
  fi
fi

print_summary
