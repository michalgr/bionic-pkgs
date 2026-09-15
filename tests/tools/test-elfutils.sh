#!/usr/bin/env bash
# tests/tools/test-elfutils.sh
# Codified test script for elfutils on Android.

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
ENV_SH="${TARGET_ROOT}/env.sh"

TARGET_ELF="/system/bin/sh"

# 1. ELF header inspection
output="$(adb_shell "${ENV_SH} eu-readelf -h ${TARGET_ELF} 2>&1" || true)"
assert_match "ELF Header|Magic:" "$output" "eu-readelf ELF header inspection (-h /system/bin/sh)"

# 2. Section header inspection
output="$(adb_shell "${ENV_SH} eu-readelf -S ${TARGET_ELF} 2>&1" || true)"
assert_match "Section Headers|\.text" "$output" "eu-readelf section header inspection (-S /system/bin/sh)"

# 3. Dynamic entries inspection
output="$(adb_shell "${ENV_SH} eu-readelf -d ${TARGET_ELF} 2>&1" || true)"
assert_match "Dynamic segment|NEEDED|RUNPATH|RPATH" "$output" "eu-readelf dynamic entries inspection (-d /system/bin/sh)"

# 4. Symbol extraction via eu-nm
output="$(adb_shell "${ENV_SH} eu-nm -D ${TARGET_ELF} 2>&1" || true)"
assert_match " [A-Za-z_]" "$output" "eu-nm dynamic symbol extraction (-D /system/bin/sh)"

# 5. Segment sizes via eu-size
output="$(adb_shell "${ENV_SH} eu-size ${TARGET_ELF} 2>&1" || true)"
assert_match "text\s+data\s+bss" "$output" "eu-size segment sizes (/system/bin/sh)"

print_summary
