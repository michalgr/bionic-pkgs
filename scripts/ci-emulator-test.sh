#!/usr/bin/env bash
# scripts/ci-emulator-test.sh
# Full sysroot and static bpftrace on-device integration test runner.

set -euo pipefail

DRY_RUN=0
DIR="dist/"

for arg in "$@"; do
  if [ "$arg" == "--dry-run" ]; then
    DRY_RUN=1
  elif [[ "$arg" != -* ]]; then
    DIR="$arg"
  fi
done

if [ ! -d "$DIR" ]; then
  echo "Error: Directory $DIR does not exist!" >&2
  exit 1
fi

SYSROOT_TAR="$DIR/sysroot-x86_64.tar.gz"
BPFTRACE_TAR="$DIR/bpftrace-static-x86_64.tar.gz"

if [ ! -f "$SYSROOT_TAR" ]; then
  echo "Error: $SYSROOT_TAR not found!" >&2
  exit 1
fi

if [ ! -f "$BPFTRACE_TAR" ]; then
  echo "Error: $BPFTRACE_TAR not found!" >&2
  exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] Unpacking archives locally to verify structure..."
  mkdir -p dry_run_out/test-bpftrace-static
  mkdir -p dry_run_out/test-sysroot
  tar xzf "$BPFTRACE_TAR" -C dry_run_out/test-bpftrace-static
  tar xzf "$SYSROOT_TAR" -C dry_run_out/test-sysroot
  echo "[dry-run] Verifying unpacked sysroot binaries..."
  test -x dry_run_out/test-sysroot/bin/strace || test -f dry_run_out/test-sysroot/bin/strace
  test -x dry_run_out/test-bpftrace-static/bin/bpftrace || test -f dry_run_out/test-bpftrace-static/bin/bpftrace
  rm -rf dry_run_out
  echo "[dry-run] Integration archive structure verification succeeded!"
  exit 0
fi

echo "============================================================"
echo "==> Deploying Full Sysroot and Static bpftrace Archives"
echo "============================================================"

echo "Waiting for ADB device..."
adb wait-for-device

echo "Elevating permissions and mounting tracefs/debugfs..."
adb root 2>/dev/null || true
until [ "$(adb shell id -u 2>/dev/null | tr -d '\r\n')" = "0" ]; do
  sleep 1
done
adb wait-for-device
adb shell setenforce 0 2>/dev/null || true
adb shell "mount -t tracefs nodev /sys/kernel/tracing 2>/dev/null || true"
adb shell "mount -t debugfs nodev /sys/kernel/debug 2>/dev/null || true"

echo "Cleaning up previous test deployments..."
adb shell "rm -rf /data/local/tmp/test-bpftrace-static /data/local/tmp/test-sysroot"
adb shell "mkdir -p /data/local/tmp/test-bpftrace-static /data/local/tmp/test-sysroot"

echo "Deploying bpftrace-static-x86_64.tar.gz..."
adb push "$BPFTRACE_TAR" /data/local/tmp/
adb shell "cd /data/local/tmp/test-bpftrace-static && tar xzf /data/local/tmp/bpftrace-static-x86_64.tar.gz && rm -f /data/local/tmp/bpftrace-static-x86_64.tar.gz"
adb shell "chmod -R 755 /data/local/tmp/test-bpftrace-static 2>/dev/null || true"

echo "Deploying sysroot-x86_64.tar.gz..."
adb push "$SYSROOT_TAR" /data/local/tmp/
adb shell "cd /data/local/tmp/test-sysroot && tar xzf /data/local/tmp/sysroot-x86_64.tar.gz && rm -f /data/local/tmp/sysroot-x86_64.tar.gz"
adb shell "chmod -R 755 /data/local/tmp/test-sysroot 2>/dev/null || true"

echo "============================================================"
echo "==> 1. Testing Standalone bpftrace-static"
echo "============================================================"
./tests/tools/test-bpftrace.sh --bin /data/local/tmp/test-bpftrace-static/bin/bpftrace

echo "============================================================"
echo "==> 2. Testing Master Sysroot Orchestrator"
echo "============================================================"
./tests/run-device-tests.sh --deploy-mode sysroot --sysroot-dir /data/local/tmp/test-sysroot

echo "============================================================"
echo "==> 3. Testing Cross-Tool Integration Suite"
echo "============================================================"
./tests/test-integration.sh --sysroot-dir /data/local/tmp/test-sysroot

echo "============================================================"
echo "==> Full Archive Integration Test completed successfully!"
echo "============================================================"
