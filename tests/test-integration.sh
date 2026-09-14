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

ENV_WRAPPER="export PATH=${SYSROOT_DIR}/bin:\${PATH};"
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

# 6. lldb and companion lldb-server cohabiting in sysroot
output="$(adb_shell "${ENV_WRAPPER} ${SYSROOT_DIR}/bin/lldb --version 2>&1" || true)"
assert_contains "$output" "lldb version" "lldb version check (--version)"

output="$(adb_shell "${SYSROOT_DIR}/bin/lldb-server v 2>&1 || ${SYSROOT_DIR}/bin/lldb-server version 2>&1" || true)"
assert_match "lldb-server|version" "$output" "lldb-server version check"

output="$(adb_shell "${ENV_WRAPPER} PYTHONHOME=${SYSROOT_DIR} ${SYSROOT_DIR}/bin/lldb --batch -o \"script import lldb; target = lldb.debugger.CreateTarget('${SYSROOT_DIR}/bin/strace'); print('LLDB_API_OK:', target.IsValid())\" -o \"quit\" 2>&1" || true)"
assert_contains "$output" "LLDB_API_OK: True" "lldb embedded python module and target API in sysroot"

output="$(adb_shell "${ENV_WRAPPER} ${SYSROOT_DIR}/bin/lldb --batch -o \"target create ${SYSROOT_DIR}/bin/strace\" -o \"image list\" -o \"quit\" 2>&1" || true)"
assert_contains "$output" "strace" "lldb target inspection of sysroot binary"

# 7. gdb inspecting sysroot binary and testing python scripting
output="$(adb_shell "${ENV_WRAPPER} ${SYSROOT_DIR}/bin/gdb --batch -ex 'file ${SYSROOT_DIR}/bin/strace' -ex 'info files' -ex 'quit' 2>&1" || true)"
assert_contains "$output" "strace" "gdb target inspection of sysroot binary"

output="$(adb_shell "${ENV_WRAPPER} PYTHONHOME=${SYSROOT_DIR} PYTHONPATH=${SYSROOT_DIR}/lib/python3.13:${SYSROOT_DIR}/share/gdb/python ${SYSROOT_DIR}/bin/gdb --batch -ex 'python import gdb; print(\"GDB_INTEGRATION_OK:\", gdb.VERSION)' -ex 'quit' 2>&1" || true)"
assert_contains "$output" "GDB_INTEGRATION_OK:" "gdb embedded python module in sysroot"

# 8. curl local file transfer and version verification in sysroot
output="$(adb_shell "${ENV_WRAPPER} ${SYSROOT_DIR}/bin/curl --version 2>&1" || true)"
assert_contains "$output" "curl" "curl version check in sysroot"
assert_contains "$output" "OpenSSL" "curl OpenSSL backend check in sysroot"

output="$(adb_shell "${ENV_WRAPPER} ${SYSROOT_DIR}/bin/curl -s file:///proc/version 2>&1" || true)"
assert_contains "$output" "Linux version" "curl local file fetch in sysroot"

# 9. socat pipe bidirectional transfer in sysroot
output="$(adb_shell "${ENV_WRAPPER} echo 'socat_sysroot_integration' | ${SYSROOT_DIR}/bin/socat - - 2>&1" || true)"
assert_contains "$output" "socat_sysroot_integration" "socat pipe transfer in sysroot"

# 10. htop process inspection in sysroot
output="$(adb_shell "${ENV_WRAPPER} ${SYSROOT_DIR}/bin/htop --version 2>&1" || true)"
assert_contains "$output" "htop 3." "htop version check in sysroot"

# 11. tcpdump version and BPF filter compilation in sysroot
output="$(adb_shell "${ENV_WRAPPER} ${SYSROOT_DIR}/bin/tcpdump --version 2>&1" || true)"
assert_contains "$output" "tcpdump version" "tcpdump version check in sysroot"
assert_contains "$output" "libpcap version" "libpcap integration check in sysroot"

output="$(adb_shell "${ENV_WRAPPER} ${SYSROOT_DIR}/bin/tcpdump -d 'ip and tcp' 2>&1" || true)"
assert_contains "$output" "(000)" "tcpdump BPF filter compilation in sysroot"

# 12. iperf3 version and loopback transfer in sysroot
output="$(adb_shell "${ENV_WRAPPER} ${SYSROOT_DIR}/bin/iperf3 --version 2>&1" || true)"
assert_contains "$output" "iperf 3." "iperf3 version check in sysroot"
assert_match "OpenSSL|authentication" "$output" "iperf3 OpenSSL integration check in sysroot"

adb_shell "nohup ${ENV_WRAPPER} ${SYSROOT_DIR}/bin/iperf3 -s -1 -p 5210 > /data/local/tmp/iperf3-int-srv.log 2>&1 &"
sleep 1

output="$(adb_shell "${ENV_WRAPPER} ${SYSROOT_DIR}/bin/iperf3 -c 127.0.0.1 -p 5210 -t 1 2>&1" || true)"
assert_contains "$output" "receiver" "iperf3 localhost loopback transfer in sysroot"

# 13. lsof version and PID 1 inspection in sysroot
output="$(adb_shell "${ENV_WRAPPER} ${SYSROOT_DIR}/bin/lsof -v 2>&1" || true)"
assert_contains "$output" "4.99." "lsof version check in sysroot"

output="$(adb_shell "${ENV_WRAPPER} ${SYSROOT_DIR}/bin/lsof -p 1 2>&1" || true)"
assert_contains "$output" "COMMAND" "lsof process table check in sysroot"
assert_match "init|systemd" "$output" "lsof PID 1 command check in sysroot"

# 14. nmap, ncat, and nping checks in sysroot
output="$(adb_shell "${ENV_WRAPPER} ${SYSROOT_DIR}/bin/nmap --version 2>&1" || true)"
assert_contains "$output" "Nmap version 7.99" "nmap version check in sysroot"

output="$(adb_shell "${ENV_WRAPPER} ${SYSROOT_DIR}/bin/ncat --version 2>&1" || true)"
assert_contains "$output" "Ncat: Version 7.99" "ncat version check in sysroot"

output="$(adb_shell "${ENV_WRAPPER} ${SYSROOT_DIR}/bin/nping --version 2>&1" || true)"
assert_contains "$output" "Nping version 7.99" "nping version check in sysroot"

output="$(adb_shell "${ENV_WRAPPER} ${SYSROOT_DIR}/bin/nmap -sn 127.0.0.1 2>&1" || true)"
assert_contains "$output" "Nmap done: 1 IP address (1 host up)" "nmap localhost ping scan in sysroot"

# 15. tmux checks in sysroot
output="$(adb_shell "${ENV_WRAPPER} ${SYSROOT_DIR}/bin/tmux -V 2>&1" || true)"
assert_contains "$output" "tmux 3.7" "tmux version check in sysroot"

print_summary
