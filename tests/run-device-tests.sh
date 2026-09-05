#!/usr/bin/env bash
# tests/run-device-tests.sh
# Master test orchestrator for bionic-pkgs on-device verification.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$ROOT_DIR/tests/lib/common.sh"
source "$ROOT_DIR/tests/lib/adb-helpers.sh"

TOOLS_ARG="all"
DEPLOY_MODE="push"
SYSROOT_DIR="/data/local/tmp/test-sysroot"
SERIAL=""

usage() {
  cat << EOF
Usage: run-device-tests.sh [OPTIONS]

Options:
  --tools <list>          Comma-separated list of tools to test or 'all'
                          (Available: strace, python3, radare2, rizin, elfutils, bpftrace, bcc)
  --deploy-mode <mode>    Deployment mode: 'push' or 'sysroot' (default: push)
  --sysroot-dir <path>    Sysroot path on device when deploy-mode=sysroot (default: /data/local/tmp/test-sysroot)
  -s, --serial <serial>   ADB serial number
  -h, --help              Show this help message
EOF
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tools)
      TOOLS_ARG="$2"
      shift 2
      ;;
    --deploy-mode)
      DEPLOY_MODE="$2"
      shift 2
      ;;
    --sysroot-dir)
      SYSROOT_DIR="$2"
      shift 2
      ;;
    -s|--serial)
      SERIAL="$2"
      shift 2
      ;;
    -h|--help)
      usage 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage 1
      ;;
  esac
done

ALL_TOOLS=("strace" "python3" "radare2" "rizin" "elfutils" "bpftrace" "bcc")
SELECTED_TOOLS=()

if [ "$TOOLS_ARG" = "all" ]; then
  SELECTED_TOOLS=("${ALL_TOOLS[@]}")
else
  IFS=',' read -ra ADDR <<< "$TOOLS_ARG"
  for item in "${ADDR[@]}"; do
    cleaned="$(echo "$item" | tr -d ' ')"
    case "$cleaned" in
      python) cleaned="python3" ;;
      r2) cleaned="radare2" ;;
    esac
    [ -n "$cleaned" ] && SELECTED_TOOLS+=("$cleaned")
  done
fi

log_info "Starting On-Device Verification Suite"
log_info "Tools:        ${SELECTED_TOOLS[*]}"
log_info "Deploy Mode:  ${DEPLOY_MODE}"
[ "$DEPLOY_MODE" = "sysroot" ] && log_info "Sysroot Dir:  ${SYSROOT_DIR}"

adb_wait_and_root
adb_mount_tracefs

OVERALL_EXIT=0

for tool in "${SELECTED_TOOLS[@]}"; do
  log_info "------------------------------------------------------------"
  log_info "Running test suite for: ${tool}"

  TEST_SCRIPT="$ROOT_DIR/tests/tools/test-${tool}.sh"
  if [ ! -x "$TEST_SCRIPT" ]; then
    log_fail "Test script missing or not executable: ${TEST_SCRIPT}"
    OVERALL_EXIT=1
    continue
  fi

  TOOL_BIN=""
  if [ "$DEPLOY_MODE" = "push" ]; then
    TOOL_BIN="/data/local/tmp/bionic-pkgs/${tool}/run.sh"
  else
    case "$tool" in
      python3) TOOL_BIN="${SYSROOT_DIR}/python-launcher.sh" ;;
      elfutils) TOOL_BIN="${SYSROOT_DIR}/bin/eu-readelf" ;;
      bcc) TOOL_BIN="${SYSROOT_DIR}/python-launcher.sh" ;;
      *) TOOL_BIN="${SYSROOT_DIR}/bin/${tool}" ;;
    esac
  fi

  set +e
  "$TEST_SCRIPT" --bin "$TOOL_BIN" ${SERIAL:+-s "$SERIAL"}
  res=$?
  set -e

  if [ $res -ne 0 ]; then
    log_fail "Tool test suite for ${tool} encountered errors"
    OVERALL_EXIT=1
  fi
done

if [ "$DEPLOY_MODE" = "sysroot" ] && [ "$TOOLS_ARG" = "all" ]; then
  log_info "------------------------------------------------------------"
  log_info "Running Cross-Tool Integration Suite"
  set +e
  "$ROOT_DIR/tests/test-integration.sh" --sysroot-dir "$SYSROOT_DIR" ${SERIAL:+-s "$SERIAL"}
  res=$?
  set -e
  if [ $res -ne 0 ]; then
    log_fail "Cross-tool integration suite encountered errors"
    OVERALL_EXIT=1
  fi
fi

echo ""
if [ $OVERALL_EXIT -eq 0 ]; then
  log_info "All selected device tests completed successfully!"
else
  log_fail "On-device test suite execution failed!"
  exit 1
fi
