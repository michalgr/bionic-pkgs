#!/usr/bin/env bash
# tests/tools/test-elfutils.sh
# Codified test script for elfutils on Android.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/tests/lib/common.sh"
source "$ROOT_DIR/tests/lib/adb-helpers.sh"

TARGET_DIR=""
ELFUTILS_BIN=""
SERIAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      TARGET_DIR="$2"
      shift 2
      ;;
    --bin)
      ELFUTILS_BIN="$2"
      shift 2
      ;;
    -s|--serial)
      SERIAL="$2"
      shift 2
      ;;
    *)
      if [ -z "$TARGET_DIR" ] && [ -z "$ELFUTILS_BIN" ]; then
        TARGET_DIR="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

adb_wait_and_root

if [ -z "$TARGET_DIR" ] && [ -z "$ELFUTILS_BIN" ]; then
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/elfutils/env.sh ]" 2>/dev/null; then
    TARGET_DIR="/data/local/tmp/bionic-pkgs/elfutils"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/env.sh ]" 2>/dev/null; then
    TARGET_DIR="/data/local/tmp/test-sysroot"
  else
    TARGET_DIR="/data/local/tmp/bionic-pkgs/elfutils"
  fi
fi

if [ -n "$TARGET_DIR" ]; then
  log_info "Testing elfutils via dir: ${TARGET_DIR}"
  READELF_CMD="${TARGET_DIR}/env.sh eu-readelf"
  NM_CMD="${TARGET_DIR}/env.sh eu-nm"
  SIZE_CMD="${TARGET_DIR}/env.sh eu-size"
else
  log_info "Testing elfutils via: ${ELFUTILS_BIN}"
  BIN_NAME="$(basename "$ELFUTILS_BIN")"
  if [ "$BIN_NAME" = "run.sh" ]; then
    BASE_DIR="$(dirname "$ELFUTILS_BIN")"
    READELF_CMD="${ELFUTILS_BIN}"
    NM_CMD="${BASE_DIR}/bin/eu-nm"
    SIZE_CMD="${BASE_DIR}/bin/eu-size"
  else
    BASE_DIR="$(dirname "$ELFUTILS_BIN")/.."
    READELF_CMD="${ELFUTILS_BIN}"
    NM_CMD="${BASE_DIR}/bin/eu-nm"
    SIZE_CMD="${BASE_DIR}/bin/eu-size"
  fi
fi

TARGET_ELF="/system/bin/sh"

# 1. ELF header inspection
output="$(adb_shell "${READELF_CMD} -h ${TARGET_ELF} 2>&1" || true)"
assert_match "ELF Header|Magic:" "$output" "eu-readelf ELF header inspection (-h /system/bin/sh)"

# 2. Section header inspection
output="$(adb_shell "${READELF_CMD} -S ${TARGET_ELF} 2>&1" || true)"
assert_match "Section Headers|\.text" "$output" "eu-readelf section header inspection (-S /system/bin/sh)"

# 3. Dynamic entries inspection
output="$(adb_shell "${READELF_CMD} -d ${TARGET_ELF} 2>&1" || true)"
assert_match "Dynamic segment|NEEDED|RUNPATH|RPATH" "$output" "eu-readelf dynamic entries inspection (-d /system/bin/sh)"

# 4. Symbol extraction via eu-nm
output="$(adb_shell "${NM_CMD} -D ${TARGET_ELF} 2>&1" || true)"
assert_match " [A-Za-z_]" "$output" "eu-nm dynamic symbol extraction (-D /system/bin/sh)"

# 5. Segment sizes via eu-size
output="$(adb_shell "${SIZE_CMD} ${TARGET_ELF} 2>&1" || true)"
assert_match "text\s+data\s+bss" "$output" "eu-size segment sizes (/system/bin/sh)"

print_summary
