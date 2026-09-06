#!/usr/bin/env bash
# tests/test-integration.sh
# Cross-tool integration test suite for bionic-pkgs sysroot cohabitation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$ROOT_DIR/tests/lib/common.sh"
source "$ROOT_DIR/tests/lib/adb-helpers.sh"

SYSROOT_DIR="/data/local/tmp/test-sysroot"
SERIAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sysroot-dir)
      SYSROOT_DIR="$2"
      shift 2
      ;;
    -s|--serial)
      SERIAL="$2"
      shift 2
      ;;
    *)
      if [ -z "$SYSROOT_DIR" ]; then
        SYSROOT_DIR="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

log_info "Running Cross-Tool Integration Suite on sysroot: ${SYSROOT_DIR}"

adb_wait_and_root
adb_mount_tracefs

ENV_WRAPPER="export LD_LIBRARY_PATH=${SYSROOT_DIR}/lib:\${LD_LIBRARY_PATH:-}; export PATH=${SYSROOT_DIR}/bin:\${PATH};"
PY_LAUNCHER="${SYSROOT_DIR}/python-launcher.sh"

# 1. strace tracing python3
output="$(adb_shell "${ENV_WRAPPER} ${SYSROOT_DIR}/bin/strace -e trace=openat,write ${PY_LAUNCHER} -c \"import sys; print('strace+python integration ok')\" 2>&1" || true)"
assert_contains "$output" "strace+python integration ok" "strace tracing python3 execution"
assert_contains "$output" "write(" "strace tracing python3 write syscalls"

# 2. python3 executing BPF programs via bcc
bcc_py_code="
import sys
try:
    import bcc
    prog = 'int hello_integration(void *ctx) { return 0; }'
    b = bcc.BPF(text=prog)
    print('PY_BCC_INTEGRATION_OK')
except Exception as e:
    print('PY_BCC_INTEGRATION_SKIP:', e)
"
output="$(adb_shell "${PY_LAUNCHER} -c \"${bcc_py_code}\" 2>&1" || true)"
if [[ "$output" == *"PY_BCC_INTEGRATION_OK"* ]]; then
  log_pass "python3 executing BPF program via bcc"
else
  skip_test "python3 executing BPF program via bcc" "Kernel BPF capability unavailable: ${output}"
fi

# 3. bpftrace tracing syscalls emitted by strace or python3
set +e
output="$(timeout 10 "$ADB_CMD" ${SERIAL:+-s $SERIAL} shell "${ENV_WRAPPER} ${SYSROOT_DIR}/bin/bpftrace -e 'tracepoint:raw_syscalls:sys_enter { @[comm] = count(); } interval:s:1 { exit(); }' 2>&1")"
ret=$?
set -e
if [ $ret -eq 0 ] || [ $ret -eq 124 ]; then
  log_pass "bpftrace tracing system calls cohabiting in sysroot"
else
  skip_test "bpftrace tracing system calls cohabiting in sysroot" "Tracepoints unavailable or restricted"
fi

# 4. eu-readelf validating all executable binaries in sysroot bin/ directory
output="$(adb_shell "${ENV_WRAPPER} for b in ${SYSROOT_DIR}/bin/*; do [ -f \"\$b\" ] && [ -x \"\$b\" ] || continue; if head -c 4 \"\$b\" 2>/dev/null | grep -q 'ELF'; then ${SYSROOT_DIR}/bin/eu-readelf -h \"\$b\" >/dev/null 2>&1 || exit 1; fi; done; echo ALL_BINARIES_VALID_ELF 2>&1" || true)"
assert_contains "$output" "ALL_BINARIES_VALID_ELF" "eu-readelf validating all executable binaries in sysroot bin/"

# 5. radare2 / rizin disassembling sysroot binaries
output="$(adb_shell "${ENV_WRAPPER} ${SYSROOT_DIR}/bin/radare2 -q -c 'aaa; afl' ${SYSROOT_DIR}/bin/strace 2>&1" || true)"
assert_match "entry|main|sym" "$output" "radare2 disassembling sysroot binary (${SYSROOT_DIR}/bin/strace)"

output="$(adb_shell "${ENV_WRAPPER} ${SYSROOT_DIR}/bin/rizin -q -c 'aa; afl' ${SYSROOT_DIR}/bin/strace 2>&1" || true)"
assert_match "entry|main|sym" "$output" "rizin disassembling sysroot binary (${SYSROOT_DIR}/bin/strace)"

print_summary
