#!/bin/bash
# Minimal test helpers for evey-setup. Pure bash, no external deps.
# Usage: source tests/test_helpers.sh ; run_test "name" func

set -euo pipefail

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TEST_OUTPUT=""

# Colors if tty
if [ -t 1 ]; then
  T_GREEN='\033[0;32m'
  T_RED='\033[0;31m'
  T_YELLOW='\033[1;33m'
  T_NC='\033[0m'
else
  T_GREEN=''; T_RED=''; T_YELLOW=''; T_NC=''
fi

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  TESTS_RUN=$((TESTS_RUN+1))
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: ${msg}"
    TESTS_PASSED=$((TESTS_PASSED+1))
  else
    echo "  FAIL: ${msg}  expected='${expected}' got='${actual}'" >&2
    TESTS_FAILED=$((TESTS_FAILED+1))
  fi
}

assert_contains() {
  local needle="$1" hay="$2" msg="${3:-}"
  TESTS_RUN=$((TESTS_RUN+1))
  local gres; gres=$(printf "%s\n" "$hay" | grep -F -c -- "$needle" 2>/dev/null || echo 0)
  if [ "$gres" -gt 0 ]; then
    echo "  PASS: ${msg}"
    TESTS_PASSED=$((TESTS_PASSED+1))
  else
    echo "  FAIL: ${msg}  (missing: ${needle})" >&2
    TESTS_FAILED=$((TESTS_FAILED+1))
  fi
}

assert_file_exists() {
  local f="$1" msg="${2:-file exists: $1}"
  TESTS_RUN=$((TESTS_RUN+1))
  if [ -f "$f" ]; then
    echo "  PASS: ${msg}"
    TESTS_PASSED=$((TESTS_PASSED+1))
  else
    echo "  FAIL: ${msg}" >&2
    TESTS_FAILED=$((TESTS_FAILED+1))
  fi
}

assert_success() {
  local cmd="$1" msg="${2:-cmd succeeds}"
  TESTS_RUN=$((TESTS_RUN+1))
  if ( eval "$cmd" ) >/dev/null 2>&1; then
    echo "  PASS: ${msg}"
    TESTS_PASSED=$((TESTS_PASSED+1))
  else
    echo "  FAIL: ${msg} (cmd: $cmd)" >&2
    TESTS_FAILED=$((TESTS_FAILED+1))
  fi
}

assert_not_contains() {
  local needle="$1" hay="$2" msg="${3:-}"
  TESTS_RUN=$((TESTS_RUN+1))
  if echo "$hay" | grep -q -- "$needle"; then
    echo "  FAIL: ${msg} (unexpected: ${needle})" >&2
    TESTS_FAILED=$((TESTS_FAILED+1))
  else
    echo "  PASS: ${msg}"
    TESTS_PASSED=$((TESTS_PASSED+1))
  fi
}

assert_dir_exists() {
  local d="$1" msg="${2:-dir exists: $1}"
  TESTS_RUN=$((TESTS_RUN+1))
  if [ -d "$d" ]; then
    echo "  PASS: ${msg}"
    TESTS_PASSED=$((TESTS_PASSED+1))
  else
    echo "  FAIL: ${msg}" >&2
    TESTS_FAILED=$((TESTS_FAILED+1))
  fi
}

assert_dir_not_exists() {
  local d="$1" msg="${2:-dir not exists: $1}"
  TESTS_RUN=$((TESTS_RUN+1))
  if [ -d "$d" ]; then
    echo "  FAIL: ${msg}" >&2
    TESTS_FAILED=$((TESTS_FAILED+1))
  else
    echo "  PASS: ${msg}"
    TESTS_PASSED=$((TESTS_PASSED+1))
  fi
}

# count occurrences of needle in hay for numeric asserts
count_matches() {
  local needle="$1" hay="$2"
  echo "$hay" | grep -o -- "$needle" | wc -l | tr -d ' '
}

run_test() {
  local name="$1"; shift
  echo ""
  echo "[TEST] $name"
  "$@"
}

finish_tests() {
  echo ""
  echo "========================================"
  echo "Tests: ${TESTS_RUN}  Passed: ${TESTS_PASSED}  Failed: ${TESTS_FAILED}"
  echo "========================================"
  if [ "${TESTS_FAILED}" -gt 0 ]; then
    exit 1
  fi
  exit 0
}

# Mock helper: run a script snippet with injected env/args and capture output
run_with_env() {
  local envstr="$1" script="$2" args="${3:-}"
  env -i HOME=/tmp/test HOME="${HOME:-/tmp}" PATH="${PATH}" bash -c "
    set -euo pipefail
    ${envstr}
    # shellcheck disable=SC1090
    source \"${script}\"
  " -- ${args} 2>&1 || true
}
