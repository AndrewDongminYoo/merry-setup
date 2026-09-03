#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
readonly tests=(
  "${TEST_DIR}/cli_validation_test.sh"
  "${TEST_DIR}/action_preflight_test.sh"
  "${TEST_DIR}/action_adapter_test.sh"
  "${TEST_DIR}/action_metadata_test.sh"
  "${TEST_DIR}/sdk_installation_test.sh"
  "${TEST_DIR}/tools_and_bundles_test.sh"
  "${TEST_DIR}/precache_test.sh"
)

for test_path in "${tests[@]}"; do
  /usr/bin/env bash "${test_path}"
done
