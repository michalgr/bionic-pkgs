#!/usr/bin/env bash
# tests/tools/test-rizin.sh
# Codified test script for rizin on Android.

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
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/rizin/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/rizin"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/test-sysroot"
  else
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/rizin"
  fi
fi

log_info "Testing rizin via root: ${TARGET_ROOT}"
RZ_CMD="${TARGET_ROOT}/env.sh rizin"
RZ_ASM_CMD="${TARGET_ROOT}/env.sh rz-asm"
RZ_BIN_CMD="${TARGET_ROOT}/env.sh rz-bin"
RZ_HASH_CMD="${TARGET_ROOT}/env.sh rz-hash"

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
