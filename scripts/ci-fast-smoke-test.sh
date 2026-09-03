#!/usr/bin/env bash
set -euo pipefail

echo "============================================================"
echo "==> Starting Fast Android Emulator Smoke Test (strace + python3)"
echo "============================================================"

echo "Waiting for ADB device..."
adb wait-for-device

echo "Elevating permissions..."
adb root || true
until [ "$(adb shell id -u 2>/dev/null)" = "0" ]; do
  sleep 1
done
adb wait-for-device

echo "==> Deploying strace..."
nix run .#push-x86_64-android-strace

echo "==> Deploying python3..."
nix run .#push-x86_64-android-python3

echo "==> Verifying strace version..."
adb shell "/data/local/tmp/bionic-pkgs/strace/run.sh -V"

echo "==> Verifying strace syscall tracing smoke..."
adb shell "/data/local/tmp/bionic-pkgs/strace/run.sh -e trace=write /system/bin/echo 'strace smoke ok'"

echo "==> Verifying python3 standard library and platform inspection..."
adb shell "/data/local/tmp/bionic-pkgs/python3/run.sh -c \"import sys, os; print('python stdlib ok:', os.name, sys.version)\""

echo "==> Verifying python3 dynamic C-extensions (_ctypes, _lzma, _bz2)..."
adb shell "/data/local/tmp/bionic-pkgs/python3/run.sh -c \"import ctypes, lzma, bz2; print('python c-extensions ok')\""

echo "==> Verifying python3 built-in hashes..."
adb shell "/data/local/tmp/bionic-pkgs/python3/run.sh -c \"import hashlib; print('hashlib sha256 ok:', hashlib.sha256(b'bionic').hexdigest())\""

echo "==> Verifying strace+python integration (strace tracing python3)..."
adb shell "/data/local/tmp/bionic-pkgs/strace/run.sh -e trace=openat,write /data/local/tmp/bionic-pkgs/python3/run.sh -c \"import sys; print('strace+python integration ok')\""

echo "==> Cleaning up staging directories on device..."
adb shell "rm -rf /data/local/tmp/bionic-pkgs/strace /data/local/tmp/bionic-pkgs/python3"

echo "============================================================"
echo "==> Fast Android Emulator Smoke Test completed successfully!"
echo "============================================================"
