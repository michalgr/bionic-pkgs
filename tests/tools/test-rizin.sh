#!/usr/bin/env bash
# tests/tools/test-rizin.sh
# Codified test script for rizin on Android.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/tests/lib/common.sh"
source "$ROOT_DIR/tests/lib/adb-helpers.sh"

RIZIN_BIN=""
SERIAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bin)
      RIZIN_BIN="$2"
      shift 2
      ;;
    -s|--serial)
      SERIAL="$2"
      shift 2
      ;;
    *)
      if [ -z "$RIZIN_BIN" ]; then
        RIZIN_BIN="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

if [ -z "$RIZIN_BIN" ]; then
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/rizin/run.sh ]" 2>/dev/null; then
    RIZIN_BIN="/data/local/tmp/bionic-pkgs/rizin/run.sh"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/bin/rizin ]" 2>/dev/null; then
    RIZIN_BIN="/data/local/tmp/test-sysroot/bin/rizin"
  else
    RIZIN_BIN="/data/local/tmp/bionic-pkgs/rizin/run.sh"
  fi
fi

log_info "Testing rizin via: ${RIZIN_BIN}"

# Determine base directory and companion tool invocation wrappers
BIN_NAME="$(basename "$RIZIN_BIN")"
if [ "$BIN_NAME" = "run.sh" ]; then
  BASE_DIR="$(dirname "$RIZIN_BIN")"
  RZ_CMD="${RIZIN_BIN}"
  RZ_ASM_CMD="LD_LIBRARY_PATH=${BASE_DIR}/lib:\${LD_LIBRARY_PATH:-} ${BASE_DIR}/bin/rz-asm"
  RZ_BIN_CMD="LD_LIBRARY_PATH=${BASE_DIR}/lib:\${LD_LIBRARY_PATH:-} ${BASE_DIR}/bin/rz-bin"
  RZ_HASH_CMD="LD_LIBRARY_PATH=${BASE_DIR}/lib:\${LD_LIBRARY_PATH:-} ${BASE_DIR}/bin/rz-hash"
else
  BASE_DIR="$(dirname "$RIZIN_BIN")/.."
  RZ_CMD="LD_LIBRARY_PATH=${BASE_DIR}/lib:\${LD_LIBRARY_PATH:-} ${RIZIN_BIN}"
  RZ_ASM_CMD="LD_LIBRARY_PATH=${BASE_DIR}/lib:\${LD_LIBRARY_PATH:-} ${BASE_DIR}/bin/rz-asm"
  RZ_BIN_CMD="LD_LIBRARY_PATH=${BASE_DIR}/lib:\${LD_LIBRARY_PATH:-} ${BASE_DIR}/bin/rz-bin"
  RZ_HASH_CMD="LD_LIBRARY_PATH=${BASE_DIR}/lib:\${LD_LIBRARY_PATH:-} ${BASE_DIR}/bin/rz-hash"
fi

# 1. Version check
output="$(adb_shell "${RZ_CMD} -v 2>&1" || true)"
assert_contains "$output" "rizin" "rizin version check (-v)"

# 2. Assembler/disassembler verification via rz-asm
arch="$(adb_get_arch)"
if [ "$arch" = "x86_64" ] || [ "$arch" = "i686" ]; then
  output="$(adb_shell "${RZ_ASM_CMD} -a x86 -b 64 'nop' 2>&1" || true)"
  assert_contains "$output" "90" "rz-asm assembly verification (x86_64 nop)"
else
  output="$(adb_shell "${RZ_ASM_CMD} -a arm -b 64 'nop' 2>&1" || true)"
  assert_contains "$output" "1f2003d5" "rz-asm assembly verification (arm64 nop)"
fi

# 3. Binary inspection via rz-bin
output="$(adb_shell "${RZ_BIN_CMD} -I /system/bin/sh 2>&1" || true)"
assert_contains "$output" "elf" "rz-bin binary inspection (-I /system/bin/sh)"

# 4. Headless analysis
output="$(adb_shell "${RZ_CMD} -q -c 'aa; afl' /system/bin/sh 2>&1" || true)"
assert_match "entry|main|sym" "$output" "rizin headless analysis (aa; afl /system/bin/sh)"

# 5. Entrypoint disassembly
output="$(adb_shell "${RZ_CMD} -q -c 'pdf' /system/bin/sh 2>&1" || true)"
assert_match "0x|entry" "$output" "rizin entrypoint disassembly (pdf)"

# 6. Checksum inspection via rz-hash
output="$(adb_shell "${RZ_HASH_CMD} -a sha256 /system/bin/sh 2>&1" || true)"
assert_match "[0-9a-f]{64}" "$output" "rz-hash SHA-256 calculation (/system/bin/sh)"

print_summary
