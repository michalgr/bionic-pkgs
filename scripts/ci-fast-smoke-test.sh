#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> Deploying fast smoke packages..."
nix run .#push-x86_64-android-strace
nix run .#push-x86_64-android-python3

echo "==> Executing smoke tests via test orchestrator..."
exec "$ROOT_DIR/tests/run-device-tests.sh" --tools strace,python3
