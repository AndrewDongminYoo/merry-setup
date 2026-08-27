#!/usr/bin/env bash
set -euo pipefail

ACTION_ADAPTER_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ACTION_ADAPTER_TEST_DIR
# shellcheck source=test/test_helper.sh
source "${ACTION_ADAPTER_TEST_DIR}/test_helper.sh"

readonly ADAPTER_PATH="${REPO_ROOT}/action/run.sh"

setup_test_env
trap cleanup_test_env EXIT

action_root="${TEST_ROOT}/action root"
argv_log="${TEST_ROOT}/argv.log"
expected_argv="${TEST_ROOT}/expected.argv"
mkdir -p "${action_root}/bin"
# shellcheck disable=SC2016 # The generated stub must expand ARGV_LOG when it runs.
printf '%s\n' '#!/usr/bin/env bash' 'printf '\''%s\n'\'' "$@" >"${ARGV_LOG}"' >"${action_root}/bin/merry-setup"
chmod +x "${action_root}/bin/merry-setup"

export GITHUB_ACTION_PATH="${action_root}"
export ARGV_LOG="${argv_log}"
export TRUNK_PATH="${TEST_ROOT}/trunk launcher"
export MERRY_SETUP_SDK=dart
export MERRY_SETUP_SDK_VERSION=stable
export MERRY_SETUP_MERRY=true
export MERRY_SETUP_MERRY_VERSION=""
export MERRY_SETUP_DART_PACKAGES=""
export MERRY_SETUP_BUNDLES=""
export MERRY_SETUP_FIREBASE_TOOLS_VERSION=""
export MERRY_SETUP_PRECACHE=""
export MERRY_SETUP_BOOTSTRAP=none
export MERRY_SETUP_PROJECT_DIR=.

run_adapter() {
  set +e
  "${ADAPTER_PATH}" >"${TEST_STDOUT}" 2>"${TEST_STDERR}"
  ACTUAL_STATUS=$?
  set -e
}

run_adapter
assert_status 0
printf '%s\n' \
  setup \
  --sdk dart \
  --sdk-version stable \
  --project-dir . \
  --persist-path github \
  --bootstrap none \
  --trunk-path "${TRUNK_PATH}" >"${expected_argv}"
assert_file_equals "${expected_argv}" "${argv_log}"
pass "base canonical argv"

export MERRY_SETUP_MERRY=false
export MERRY_SETUP_MERRY_VERSION='^2.0.0'
run_adapter
assert_status 0
printf '%s\n' \
  setup \
  --sdk dart \
  --sdk-version stable \
  --project-dir . \
  --persist-path github \
  --bootstrap none \
  --trunk-path "${TRUNK_PATH}" \
  --no-merry \
  --merry-version '^2.0.0' >"${expected_argv}"
assert_file_equals "${expected_argv}" "${argv_log}"
pass "canonical CLI receives Merry conflict"

export MERRY_SETUP_MERRY=true
export MERRY_SETUP_MERRY_VERSION=""
export MERRY_SETUP_DART_PACKAGES=$'alpha=^1.0.0\r\n\npackage with literal spaces\n'
export MERRY_SETUP_BUNDLES=$'flutterfire\r\n'
export MERRY_SETUP_FIREBASE_TOOLS_VERSION=14.2.1
export MERRY_SETUP_PRECACHE=$'web\nandroid\r\n'
run_adapter
assert_status 0
printf '%s\n' \
  setup \
  --sdk dart \
  --sdk-version stable \
  --project-dir . \
  --persist-path github \
  --bootstrap none \
  --trunk-path "${TRUNK_PATH}" \
  --firebase-tools-version 14.2.1 \
  --dart-package 'alpha=^1.0.0' \
  --dart-package 'package with literal spaces' \
  --bundle flutterfire \
  --precache web \
  --precache android >"${expected_argv}"
assert_file_equals "${expected_argv}" "${argv_log}"
pass "LF and CRLF multiline inputs remain single argv elements"

export MERRY_SETUP_MERRY=TRUE
: >"${argv_log}"
run_adapter
assert_nonzero
assert_stderr_contains "Input 'merry' must be 'true' or 'false'."
[[ ! -s ${argv_log} ]] || fail "invalid Merry input reached the CLI stub"
pass "invalid Merry adapter input"

export MERRY_SETUP_MERRY=true
unset TRUNK_PATH
: >"${argv_log}"
run_adapter
assert_nonzero
assert_stderr_contains "TRUNK_PATH was not set by the Trunk setup action."
[[ ! -s ${argv_log} ]] || fail "missing Trunk path reached the CLI stub"
pass "missing upstream Trunk path"
