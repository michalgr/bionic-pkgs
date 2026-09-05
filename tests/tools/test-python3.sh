#!/usr/bin/env bash
# tests/tools/test-python3.sh
# Codified test script for python3 on Android.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/tests/lib/common.sh"
source "$ROOT_DIR/tests/lib/adb-helpers.sh"

PYTHON_BIN=""
SERIAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bin)
      PYTHON_BIN="$2"
      shift 2
      ;;
    -s|--serial)
      SERIAL="$2"
      shift 2
      ;;
    *)
      if [ -z "$PYTHON_BIN" ]; then
        PYTHON_BIN="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

adb_wait_and_root

if [ -z "$PYTHON_BIN" ]; then
  if adb_shell "[ -f /data/local/tmp/bionic-pkgs/python3/run.sh ]" 2>/dev/null; then
    PYTHON_BIN="/data/local/tmp/bionic-pkgs/python3/run.sh"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/python-launcher.sh ]" 2>/dev/null; then
    PYTHON_BIN="/data/local/tmp/test-sysroot/python-launcher.sh"
  elif adb_shell "[ -f /data/local/tmp/test-sysroot/bin/python3 ]" 2>/dev/null; then
    PYTHON_BIN="/data/local/tmp/test-sysroot/bin/python3"
  else
    PYTHON_BIN="/data/local/tmp/bionic-pkgs/python3/run.sh"
  fi
fi

log_info "Testing python3 via: ${PYTHON_BIN}"

# 1. Stdlib & platform check
output="$(adb_shell "${PYTHON_BIN} -c \"import sys, os; print('PLATFORM_OK:', sys.platform, os.name)\" 2>&1" || true)"
if echo "$output" | grep -E -q "PLATFORM_OK: (linux|android) posix" 2>/dev/null; then
  log_pass "python3 stdlib and platform check"
else
  log_fail "python3 stdlib and platform check (unexpected output: ${output})"
fi

# 2. Built-in HACL* hashes check
output="$(adb_shell "${PYTHON_BIN} -c \"import hashlib; print('SHA256:', hashlib.sha256(b'bionic').hexdigest(), 'MD5:', hashlib.md5(b'bionic').hexdigest())\" 2>&1" || true)"
assert_contains "$output" "SHA256: 1a0a" "python3 built-in hashlib sha256 check"
assert_contains "$output" "MD5:" "python3 built-in hashlib md5 check"

# 3. Dynamic C-extensions check
output="$(adb_shell "${PYTHON_BIN} -c \"import ctypes, lzma, bz2; print('C_EXT_OK')\" 2>&1" || true)"
assert_contains "$output" "C_EXT_OK" "python3 dynamic C-extensions (_ctypes, _lzma, _bz2)"

# 4. Bionic ctypes foreign function calls
output="$(adb_shell "${PYTHON_BIN} -c \"import ctypes; libc = ctypes.CDLL('libc.so'); pid = libc.getpid(); t = libc.time(None); print('CTYPES_BIONIC_OK:', pid > 0, t > 1000000000)\" 2>&1" || true)"
assert_contains "$output" "CTYPES_BIONIC_OK: True True" "python3 Bionic ctypes libc calls (getpid, time)"

# 5. In-memory compression round-trip
output="$(adb_shell "${PYTHON_BIN} -c \"import lzma, bz2; data = b'bionic'*100; assert lzma.decompress(lzma.compress(data)) == data; assert bz2.decompress(bz2.compress(data)) == data; print('COMPRESS_OK')\" 2>&1" || true)"
assert_contains "$output" "COMPRESS_OK" "python3 in-memory compression round-trip (lzma, bz2)"

print_summary
