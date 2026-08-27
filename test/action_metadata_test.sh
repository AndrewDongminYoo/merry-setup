#!/usr/bin/env bash
set -euo pipefail

ACTION_METADATA_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ACTION_METADATA_TEST_DIR
# shellcheck source=test/test_helper.sh
source "${ACTION_METADATA_TEST_DIR}/test_helper.sh"

setup_test_env
trap cleanup_test_env EXIT

expected_inputs="${TEST_ROOT}/expected-inputs"
actual_inputs="${TEST_ROOT}/actual-inputs"

printf '%s\n' \
  sdk \
  sdk-version \
  merry \
  merry-version \
  dart-packages \
  bundles \
  firebase-tools-version \
  precache \
  bootstrap \
  project-dir \
  trunk-path >"${expected_inputs}"

validate_action_metadata() {
  local metadata_path="$1"
  local preflight_line=""
  local trunk_line=""
  local setup_line=""
  local uses_count=0
  local uses_value=""
  local required_true_count=0

  awk '
    /^inputs:$/ {
      inside_inputs = 1
      next
    }
    inside_inputs && /^[^[:space:]]/ {
      exit
    }
    inside_inputs && /^  [a-z0-9-]+:$/ {
      input_name = $0
      sub(/^  /, "", input_name)
      sub(/:$/, "", input_name)
      print input_name
    }
  ' "${metadata_path}" >"${actual_inputs}"

  cmp -s "${expected_inputs}" "${actual_inputs}" || return 1
  required_true_count="$(grep -c '^    required: true$' "${metadata_path}" || true)"
  [[ ${required_true_count} -eq 2 ]] || return 1
  awk '
    /^  sdk:$/ {
      inside_target = 1
      next
    }
    inside_target && /^  [a-z0-9-]+:$/ {
      exit
    }
    inside_target && /^    required: true$/ {
      found = 1
    }
    END {
      exit !found
    }
  ' "${metadata_path}" || return 1
  awk '
    /^  bootstrap:$/ {
      inside_target = 1
      next
    }
    inside_target && /^  [a-z0-9-]+:$/ {
      exit
    }
    inside_target && /^    required: true$/ {
      found = 1
    }
    END {
      exit !found
    }
  ' "${metadata_path}" || return 1
  grep -Fq 'name: Merry Setup' "${metadata_path}" || return 1
  grep -Fq 'using: composite' "${metadata_path}" || return 1
  grep -Fq 'trunk-io/trunk-action/setup@e1234e67a86010d61ddac8d8ebf4b783e2ffd2fa' "${metadata_path}" || return 1
  # shellcheck disable=SC2016 # Action expressions are literal metadata here.
  grep -Fq 'trunk-path: ${{ inputs.trunk-path }}' "${metadata_path}" || return 1
  # shellcheck disable=SC2016 # Action expressions are literal metadata here.
  grep -Fq 'MERRY_SETUP_SDK: ${{ inputs.sdk }}' "${metadata_path}" || return 1
  # shellcheck disable=SC2016 # Action expressions are literal metadata here.
  grep -Fq 'MERRY_SETUP_BOOTSTRAP: ${{ inputs.bootstrap }}' "${metadata_path}" || return 1

  if grep -Eq '^[[:space:]]*run:.*\$\{\{[[:space:]]*inputs\.' "${metadata_path}"; then
    return 1
  fi

  if grep -Eq '^(outputs|permissions):' "${metadata_path}"; then
    return 1
  fi

  while IFS= read -r uses_value; do
    ((uses_count += 1))
    [[ ${uses_value} =~ @[0-9a-f]{40}([[:space:]]+#[[:space:]].*)?$ ]] || return 1
  done < <(sed -n 's/^[[:space:]]*uses:[[:space:]]*//p' "${metadata_path}")
  [[ ${uses_count} -eq 1 ]] || return 1

  preflight_line="$(grep -n -F 'action/preflight.sh' "${metadata_path}" | cut -d: -f1)"
  trunk_line="$(grep -n -F 'trunk-io/trunk-action/setup@' "${metadata_path}" | cut -d: -f1)"
  setup_line="$(grep -n -F 'action/run.sh' "${metadata_path}" | cut -d: -f1)"
  [[ -n ${preflight_line} && -n ${trunk_line} && -n ${setup_line} ]] || return 1
  ((preflight_line < trunk_line && trunk_line < setup_line)) || return 1
}

canary_path="${TEST_ROOT}/action-canary.yml"
printf '%s\n' \
  '---' \
  'name: Merry Setup' \
  'inputs:' \
  '  sdk:' \
  'runs:' \
  '  using: composite' >"${canary_path}"

if validate_action_metadata "${canary_path}"; then
  fail "Action metadata validator accepted an incomplete public input surface"
fi
pass "Action metadata validator canary"

validate_action_metadata "${REPO_ROOT}/action.yml"
assert_path_absent "${REPO_ROOT}/action.yaml"
pass "Action metadata public contract"
