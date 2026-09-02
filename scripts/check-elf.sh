#!/usr/bin/env bash
# scripts/check-elf.sh
# ELF property verification script for Android (Bionic libc) packages.
#
# Verifies:
# 1. Target architecture machine header
# 2. Dynamic linker interpreter path
# 3. 16 KB page alignment on LOAD segments
# 4. Absence of forbidden glibc library dependencies
# 5. Absence of host /nix/store paths in RUNPATH

set -euo pipefail

PKG_PATH="${1:-}"
TARGET_NAME="${2:-}"
PKG_NAME="${3:-}"
OUT_DIR="${4:-${out:-}}"

if [ -z "$PKG_PATH" ] || [ -z "$TARGET_NAME" ]; then
  echo "Usage: check-elf.sh <pkg_path> <target_name> [pkg_name] [out_dir]" >&2
  exit 1
fi

if [ -z "$PKG_NAME" ]; then
  PKG_NAME="$(basename "$PKG_PATH")"
fi

echo "==> Verifying ELF properties for ${PKG_NAME} (${TARGET_NAME})..."

found_elf=0
mapfile -t elf_files < <(find -L "${PKG_PATH}" -type f)

for elf_file in "${elf_files[@]}"; do
  if [ -f "$elf_file" ] && [ "$(od -An -N4 -tx1 "$elf_file" 2>/dev/null | tr -d ' \n')" = "7f454c46" ]; then
    found_elf=$((found_elf + 1))
    rel_path="${elf_file#${PKG_PATH}/}"
    echo "--- Checking ELF artifact: $rel_path ---"
    file "$elf_file"

    # 1. Verify Target Architecture / Machine Header
    machine=$(llvm-readelf -h "$elf_file" 2>/dev/null | awk -F: '/Machine:/ {print $2}' | xargs || true)
    echo "ELF Machine: $machine"
    case "${TARGET_NAME}" in
      aarch64-android)
        if [ "$machine" != "AArch64" ]; then
          echo "ERROR: Expected AArch64 machine, got: $machine" >&2
          exit 1
        fi
        ;;
      x86_64-android)
        if [ "$machine" != "Advanced Micro Devices X86-64" ]; then
          echo "ERROR: Expected Advanced Micro Devices X86-64 machine, got: $machine" >&2
          exit 1
        fi
        ;;
      armv7a-android)
        if [ "$machine" != "ARM" ]; then
          echo "ERROR: Expected ARM machine, got: $machine" >&2
          exit 1
        fi
        ;;
      i686-android)
        if [ "$machine" != "Intel 80386" ]; then
          echo "ERROR: Expected Intel 80386 machine, got: $machine" >&2
          exit 1
        fi
        ;;
    esac

    # 2. Check Dynamic Linker Interpreter (for executables)
    interp=$(llvm-readelf -l "$elf_file" 2>/dev/null | grep 'program interpreter' | tr -d '[]' | awk '{print $NF}' || true)
    case "$rel_path" in
      bin/*|sbin/*|libexec/*)
        if [ -n "$interp" ]; then
          echo "Dynamic interpreter: $interp"
          case "${TARGET_NAME}" in
            aarch64-android|x86_64-android)
              if [ "$interp" != "/system/bin/linker64" ]; then
                echo "ERROR: Expected 64-bit dynamic linker /system/bin/linker64, got $interp" >&2
                exit 1
              fi
              ;;
            armv7a-android|i686-android)
              if [ "$interp" != "/system/bin/linker" ]; then
                echo "ERROR: Expected 32-bit dynamic linker /system/bin/linker, got $interp" >&2
                exit 1
              fi
              ;;
          esac
        fi
        ;;
    esac

    # 3. Check 16 KB Page Alignment on LOAD segments
    echo "Checking LOAD segment alignments..."
    load_count=0
    for align in $(llvm-readelf -l "$elf_file" | awk '$1 == "LOAD" {print $NF}'); do
      load_count=$((load_count + 1))
      align_dec=$((align))
      if [ "$align_dec" -lt 16384 ]; then
        echo "ERROR: LOAD segment alignment $align ($align_dec bytes) is less than 16 KB (16384 bytes) in $rel_path" >&2
        exit 1
      fi
    done
    if [ "$load_count" -eq 0 ]; then
      echo "ERROR: No LOAD segments found in $rel_path" >&2
      exit 1
    fi

    # 4. Check Forbidden glibc dependencies
    for forbidden in libpthread.so librt.so libutil.so libresolv.so libcrypt.so libnsl.so libanl.so libc.so.6 libm.so.6 ld-linux libz.so.1; do
      if llvm-readelf -d "$elf_file" 2>/dev/null | grep NEEDED | grep -q "$forbidden"; then
        echo "ERROR: Binary links forbidden glibc library: $forbidden" >&2
        exit 1
      fi
    done

    # 5. Check Relative RUNPATH ($ORIGIN/...)
    rpath=$(llvm-readelf -d "$elf_file" 2>/dev/null | grep RUNPATH || true)
    if [ -n "$rpath" ]; then
      echo "RUNPATH: $rpath"
      if echo "$rpath" | grep -q "/nix/store"; then
        echo "ERROR: Binary RUNPATH contains host /nix/store path!" >&2
        exit 1
      fi
    fi
  fi
done

if [ "$found_elf" -eq 0 ]; then
  echo "ERROR: No ELF binaries or libraries found in ${PKG_PATH}" >&2
  exit 1
fi

echo "==> Successfully verified $found_elf ELF artifact(s) for ${PKG_NAME} (${TARGET_NAME})."
if [ -n "$OUT_DIR" ]; then
  mkdir -p "$OUT_DIR"
  echo "ELF verification passed for ${PKG_NAME} (${TARGET_NAME}) ($found_elf artifacts)" > "$OUT_DIR/result"
fi
