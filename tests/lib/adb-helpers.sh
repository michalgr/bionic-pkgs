#!/usr/bin/env bash
# tests/lib/adb-helpers.sh
# ADB interaction, device verification, and kernel tracing helpers.

set -euo pipefail

ADB_CMD="${ADB_CMD:-adb}"
SERIAL="${SERIAL:-${ANDROID_SERIAL:-${ADB_SERIAL:-}}}"

run_adb() {
  local flags=()
  if [ -n "${SERIAL:-}" ]; then
    flags+=(-s "$SERIAL")
  fi
  "$ADB_CMD" "${flags[@]}" "$@"
}

adb_shell() {
  run_adb shell "$@"
}

adb_wait_and_root() {
  log_info "Waiting for ADB device connection..."
  run_adb wait-for-device

  log_info "Elevating permissions via adb root..."
  run_adb root 2>/dev/null || true

  local count=0
  until [ "$(adb_shell "id -u 2>/dev/null | tr -d '\r\n'")" = "0" ]; do
    sleep 1
    count=$((count + 1))
    if [ "$count" -ge 15 ]; then
      log_info "Device did not report UID 0 after 15 seconds; continuing..."
      break
    fi
  done
  run_adb wait-for-device
}

adb_mount_tracefs() {
  log_info "Mounting kernel tracefs / debugfs..."
  adb_shell "setenforce 0 2>/dev/null || true"
  adb_shell "mount -t tracefs nodev /sys/kernel/tracing 2>/dev/null || true"
  adb_shell "mount -t debugfs nodev /sys/kernel/debug 2>/dev/null || true"
}

adb_get_arch() {
  local abi
  abi="$(adb_shell "getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r\n'")"
  if [ -z "$abi" ]; then
    abi="$(adb_shell "uname -m 2>/dev/null | tr -d '\r\n'")"
  fi
  case "$abi" in
    x86_64*) echo "x86_64" ;;
    arm64*|aarch64*) echo "aarch64" ;;
    x86*|i686*) echo "i686" ;;
    arm*|armeabi*) echo "armv7a" ;;
    *) echo "${abi:-x86_64}" ;;
  esac
}
