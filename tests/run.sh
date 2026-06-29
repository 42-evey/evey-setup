#!/bin/bash
# Run all evey-setup unit tests. Pure logic only. Skips docker-dependent if needed.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

echo "=== evey-setup tests ==="
bash ./test_noninteractive.sh || FAIL=1
bash ./test_config_schema.sh || FAIL=1
# verify test has mocks, run it
bash ./test_verify.sh || FAIL=1
# identity/customize engine (Task 002)
bash ./test_customize.sh || FAIL=1

if [ "${FAIL:-0}" = 1 ]; then
  echo "Some tests failed"
  exit 1
fi
echo "All tests passed"
exit 0
