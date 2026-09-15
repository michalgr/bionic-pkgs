#!/usr/bin/env bash
# tests/tools/test-elfutils.sh
# Codified test script for elfutils (eu-readelf, eu-nm, eu-size) on Android.

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
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/elfutils/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/elfutils"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/env.sh ]" 2>/dev/null; then
    TARGET_ROOT="/data/local/tmp/test-sysroot"
  else
    TARGET_ROOT="/data/local/tmp/bionic-pkgs/elfutils"
  fi
fi

log_info "Testing elfutils via root: ${TARGET_ROOT}"
READELF_CMD="${TARGET_ROOT}/env.sh eu-readelf"
NM_CMD="${TARGET_ROOT}/env.sh eu-nm"
SIZE_CMD="${TARGET_ROOT}/env.sh eu-size"

# Target test binary on Android device
TARGET_BIN="/system/bin/sh"

# 1. Header inspection (eu-readelf -h)
output="$(adb_shell "${READELF_CMD} -h ${TARGET_BIN} 2>&1" || true)"
assert_contains "$output" "ELF Header:" "eu-readelf header banner"
assert_contains "$output" "Magic:" "eu-readelf magic number check"
assert_match "Class:[[:space:]]+ELF(32|64)" "$output" "eu-readelf ELF class (32/64-bit)"

# 2. Section headers inspection (eu-readelf -S)
output="$(adb_shell "${READELF_CMD} -S ${TARGET_BIN} 2>&1" || true)"
assert_contains "$output" "There are" "eu-readelf section headers section count"
assert_match "\.text|\.data|\.rodata|\.dynsym" "$output" "eu-readelf standard ELF sections presence"

# 3. Dynamic entries and RUNPATH/RPATH (eu-readelf -d)
output="$(adb_shell "${READELF_CMD} -d ${TARGET_BIN} 2>&1" || true)"
assert_contains "$output" "Dynamic segment at offset" "eu-readelf dynamic segment header"
assert_contains "$output" "NEEDED" "eu-readelf DT_NEEDED tag check"

# 4. Dynamic symbol table extraction (eu-nm -D)
output="$(adb_shell "${NM_CMD} -D ${TARGET_BIN} 2>&1" || true)"
assert_match "U main|T main|t main|U printf|T printf|U exit" "$output" "eu-nm dynamic symbols extraction"

# 5. Section sizes (eu-size)
output="$(adb_shell "${SIZE_CMD} ${TARGET_BIN} 2>&1" || true)"
assert_contains "$output" "text" "eu-size text section column"
assert_contains "$output" "data" "eu-size data section column"
assert_contains "$output" "bss" "eu-size bss section column"
assert_match "[0-9]+" "$output" "eu-size numeric output"

print_summary
