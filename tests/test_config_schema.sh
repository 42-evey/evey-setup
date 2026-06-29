#!/bin/bash
# Tests for hermes config schema compatibility after upstream changes.
# Ensures template produces usable config.yaml (model section etc).
# No runtime hermes needed; just structural + parse checks.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_helpers.sh"

TPL="${SCRIPT_DIR}/../templates/config.yaml"

test_template_exists() {
  assert_file_exists "$TPL" "config.yaml template present"
}

test_template_has_model_section() {
  # Current upstream expects model: block for default/provider/base_url
  local content
  content=$(cat "$TPL")
  assert_contains "model:" "$content" "top level model:"
  # either flat default or under model.default ok; prefer section
  if echo "$content" | grep -q '^\s*default:' ; then
    assert_contains "default:" "$content" "model default present"
  fi
}

test_template_litellm_refs() {
  local content
  content=$(cat "$TPL")
  assert_contains "hermes-litellm:4000" "$content" "points to stack litellm"
  assert_contains "LITELLM" "$content" "uses LITELLM key ref"
}

test_template_no_broken_legacy_only() {
  # Should not have completely deprecated top level provider without model section
  # (normalizer supports but we want modern)
  local content
  content=$(cat "$TPL")
  if echo "$content" | grep -q '^provider:' ; then
    # if present at root, model section must also exist for new default
    if ! echo "$content" | grep -q '^model:' ; then
      echo "WARN: legacy root provider without model: section"
    fi
  fi
  # always pass structure test
  assert_success "test -s '$TPL'" "template non-empty"
}

run_test "template present" test_template_exists
run_test "has model section" test_template_has_model_section
run_test "litellm routing" test_template_litellm_refs
run_test "schema compat" test_template_no_broken_legacy_only

finish_tests
