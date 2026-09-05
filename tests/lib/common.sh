#!/usr/bin/env bash
# tests/lib/common.sh
# Common test framework and assertion helpers for on-device bionic-pkgs test suite.

set -euo pipefail

# Test statistics counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Color definitions
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  COLOR_RESET=$'\033[0m'
  COLOR_RED=$'\033[0;31m'
  COLOR_GREEN=$'\033[0;32m'
  COLOR_YELLOW=$'\033[0;33m'
  COLOR_BLUE=$'\033[0;34m'
  COLOR_BOLD=$'\033[1m'
else
  COLOR_RESET=""
  COLOR_RED=""
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_BLUE=""
  COLOR_BOLD=""
fi

log_info() {
  echo "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"
}

log_pass() {
  local desc="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo "${COLOR_GREEN}[PASS]${COLOR_RESET} ${desc}"
}

log_fail() {
  local desc="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo "${COLOR_RED}[FAIL]${COLOR_RESET} ${desc}" >&2
}

log_skip() {
  local desc="$1"
  local reason="${2:-"unsupported environment or missing dependency"}"
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
  echo "${COLOR_YELLOW}[SKIP]${COLOR_RESET} ${desc} (${reason})"
}

skip_test() {
  local desc="$1"
  local reason="${2:-"skipped"}"
  log_skip "$desc" "$reason"
}

assert_ok() {
  local desc="$1"
  shift
  local status=0
  set +e
  "$@"
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    log_pass "$desc"
    return 0
  else
    log_fail "$desc (command failed with exit code $status: $*)"
    return "$status"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local desc="${3:-"Output contains expected substring '$needle'"}"
  if [[ "$haystack" == *"$needle"* ]]; then
    log_pass "$desc"
    return 0
  else
    log_fail "$desc (substring '$needle' not found in output)"
    return 1
  fi
}

assert_match() {
  local pattern="$1"
  local string="$2"
  local desc="${3:-"Output matches pattern '$pattern'"}"
  if echo "$string" | grep -E -q "$pattern" 2>/dev/null; then
    log_pass "$desc"
    return 0
  else
    log_fail "$desc (pattern '$pattern' did not match string: '$string')"
    return 1
  fi
}

assert_exit_code() {
  local expected="$1"
  local desc="$2"
  shift 2
  local status=0
  set +e
  "$@"
  status=$?
  set -e
  if [ "$status" -eq "$expected" ]; then
    log_pass "$desc"
    return 0
  else
    log_fail "$desc (expected exit code $expected, got $status: $*)"
    return 1
  fi
}

print_summary() {
  echo ""
  echo "${COLOR_BOLD}============================================================${COLOR_RESET}"
  echo "${COLOR_BOLD}Test Execution Summary:${COLOR_RESET}"
  echo "  Total Run:  ${TESTS_RUN}"
  echo "  ${COLOR_GREEN}Passed:     ${TESTS_PASSED}${COLOR_RESET}"
  echo "  ${COLOR_YELLOW}Skipped:    ${TESTS_SKIPPED}${COLOR_RESET}"
  echo "  ${COLOR_RED}Failed:     ${TESTS_FAILED}${COLOR_RESET}"
  echo "${COLOR_BOLD}============================================================${COLOR_RESET}"
  if [ "$TESTS_FAILED" -gt 0 ]; then
    return 1
  fi
  return 0
}
