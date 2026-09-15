#!/usr/bin/env bash
# tests/tools/test-radare2.sh
# Codified test script for radare2 on Android.

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
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/radare2/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/radare2"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/test-sysroot"
  else
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/radare2"
  fi
fi

log_info "Testing radare2 via root: ${TARGET_ROOT}"
R2_CMD="${TARGET_ROOT}/env.sh radare2"
RASM2_CMD="${TARGET_ROOT}/env.sh rasm2"
RABIN2_CMD="${TARGET_ROOT}/env.sh rabin2"

# 1. Version check
output="$(adb_shell "${R2_CMD} -v 2>&1" || true)"
assert_contains "$output" "radare2" "radare2 version check (-v)"

# 2. Assembler/disassembler verification via rasm2
arch="$(adb_get_arch)"
if [ "$arch" = "x86_64" ] || [ "$arch" = "i686" ]; then
  output="$(adb_shell "${RASM2_CMD} -a x86 -b 64 'nop' 2>&1" || true)"
  assert_contains "$output" "90" "rasm2 assembly verification (x86_64 nop)"
else
  output="$(adb_shell "${RASM2_CMD} -a arm -b 64 'nop' 2>&1" || true)"
  assert_contains "$output" "1f2003d5" "rasm2 assembly verification (arm64 nop)"
fi

# 3. Binary inspection via rabin2
output="$(adb_shell "${RABIN2_CMD} -I /system/bin/sh 2>&1" || true)"
assert_contains "$output" "elf" "rabin2 binary inspection (-I /system/bin/sh)"

# 4. Headless analysis
output="$(adb_shell "${R2_CMD} -q -c 'aaa; afl' /system/bin/sh 2>&1" || true)"
assert_match "entry|main|sym" "$output" "radare2 headless analysis (aaa; afl /system/bin/sh)"

# 5. Function disassembly
output="$(adb_shell "${R2_CMD} -q -c 's entry0; pdf' /system/bin/sh 2>&1" || true)"
assert_match "0x|entry" "$output" "radare2 function disassembly (s entry0; pdf)"

print_summary
