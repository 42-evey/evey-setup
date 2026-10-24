#!/bin/bash
# Regression test for issue #2: the hermes data volume must be mounted where
# HERMES_HOME points, or sessions, memories, skills and cron state land in the
# container layer and vanish on every recreate.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_helpers.sh"

# Print the hermes-agent service block of a compose file.
hermes_block() {
  awk '/^  hermes-agent:/{on=1; next} on && /^  [^ #]/{exit} on' "$1"
}

check_tier() {
  local f="$1" block target home
  block=$(hermes_block "$f")
  target=$(printf '%s\n' "$block" | sed -n 's|^ *- \./data/hermes:\([^:]*\).*|\1|p' | head -1)
  home=$(printf '%s\n' "$block" | sed -n 's|^ *HERMES_HOME: *"\{0,1\}\([^"]*\)"\{0,1\} *$|\1|p' | head -1)
  assert_eq "/opt/data" "$home" "$(basename "$f"): HERMES_HOME is the image's state dir"
  assert_eq "$home" "$target" "$(basename "$f"): ./data/hermes is mounted at HERMES_HOME"
}

for f in "${SCRIPT_DIR}"/../templates/docker-compose.*.yml; do
  run_test "$(basename "$f")" check_tier "$f"
done

finish_tests
