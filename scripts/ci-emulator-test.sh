#!/usr/bin/env bash
set -e

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
    echo "Directory $DIR does not exist!"
    exit 1
fi

SYSROOT_TAR="$DIR/sysroot-x86_64.tar.gz"
BPFTRACE_TAR="$DIR/bpftrace-static-x86_64.tar.gz"

if [ ! -f "$SYSROOT_TAR" ]; then
    echo "Error: $SYSROOT_TAR not found!"
    exit 1
fi

if [ ! -f "$BPFTRACE_TAR" ]; then
    echo "Error: $BPFTRACE_TAR not found!"
    exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] Unpacking locally..."
    mkdir -p dry_run_out/test-bpftrace-static
    mkdir -p dry_run_out/test-sysroot
    tar xzf "$BPFTRACE_TAR" -C dry_run_out/test-bpftrace-static
    tar xzf "$SYSROOT_TAR" -C dry_run_out/test-sysroot
    echo "[dry-run] Done."
    exit 0
fi

echo "Waiting for ADB device..."
adb wait-for-device

echo "Elevating permissions and mounting tracefs/debugfs..."
adb root
adb wait-for-device
adb shell setenforce 0
adb shell "mount -t tracefs nodev /sys/kernel/tracing 2>/dev/null || true"
adb shell "mount -t debugfs nodev /sys/kernel/debug 2>/dev/null || true"

echo "Cleaning up previous deployments..."
adb shell "rm -rf /data/local/tmp/test-bpftrace-static /data/local/tmp/test-sysroot"
adb shell "mkdir -p /data/local/tmp/test-bpftrace-static"
adb shell "mkdir -p /data/local/tmp/test-sysroot"

# --- Deploy and verify bpftrace-static ---
echo "Deploying bpftrace-static-x86_64.tar.gz..."
adb push "$BPFTRACE_TAR" /data/local/tmp/
adb shell "cd /data/local/tmp/test-bpftrace-static && tar xzf /data/local/tmp/bpftrace-static-x86_64.tar.gz"

echo "Verifying bpftrace-static..."
adb shell "/data/local/tmp/test-bpftrace-static/bin/bpftrace -V"
adb shell "/data/local/tmp/test-bpftrace-static/bin/bpftrace --info"

echo "Running basic userspace BPF smoke test..."
adb shell "/data/local/tmp/test-bpftrace-static/bin/bpftrace -e 'BEGIN { printf(\"bpftrace-static smoke ok\n\"); exit(); }'"

echo "Running tracepoint probe..."
# Use || true to prevent set -e from killing the script if timeout exits with 124
timeout 15 adb shell "/data/local/tmp/test-bpftrace-static/bin/bpftrace -e 'tracepoint:raw_syscalls:sys_enter { @[comm] = count(); } interval:s:1 { exit(); }'" || true

echo "Checking syscount companion tool..."
adb shell "/data/local/tmp/test-bpftrace-static/bin/syscount --help" > /dev/null

# --- Deploy and verify sysroot ---
echo "Deploying sysroot-x86_64.tar.gz..."
adb push "$SYSROOT_TAR" /data/local/tmp/
adb shell "cd /data/local/tmp/test-sysroot && tar xzf /data/local/tmp/sysroot-x86_64.tar.gz"

echo "Verifying strace..."
adb shell "/data/local/tmp/test-sysroot/bin/strace -V"
adb shell "/data/local/tmp/test-sysroot/bin/strace -e trace=write /system/bin/echo 'strace ok'"
adb shell "/data/local/tmp/test-sysroot/bin/strace -e trace=openat /data/local/tmp/test-sysroot/python-launcher.sh -c \"import sys; print('strace+python ok')\""

echo "Verifying python3..."
adb shell "/data/local/tmp/test-sysroot/python-launcher.sh -c 'import sys, os; print(\"python stdlib ok:\", os.name)'"

echo "Verifying bcc..."
adb shell "/data/local/tmp/test-sysroot/bin/bps"
adb shell "/data/local/tmp/test-sysroot/python-launcher.sh -c \"import bcc; print(bcc.__version__)\""

echo "Verifying dynamic bpftrace..."
adb shell "/data/local/tmp/test-sysroot/bin/bpftrace -V"
adb shell "/data/local/tmp/test-sysroot/bin/bpftrace -e 'BEGIN { printf(\"dynamic bpftrace smoke ok\n\"); exit(); }'"

echo "Verifying elfutils (eu-readelf)..."
adb shell "/data/local/tmp/test-sysroot/bin/eu-readelf -h /data/local/tmp/test-sysroot/bin/strace"

echo "All tests passed successfully!"
