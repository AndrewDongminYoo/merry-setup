#!/usr/bin/env bash
set -euo pipefail

ACTION_CACHE_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ACTION_CACHE_TEST_DIR
# shellcheck source=test/test_helper.sh
source "${ACTION_CACHE_TEST_DIR}/test_helper.sh"

readonly RESOLVE_ADAPTER_PATH="${REPO_ROOT}/action/resolve.sh"
readonly SDK_ARCHIVE_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

setup_test_env
trap cleanup_test_env EXIT

action_root="${TEST_ROOT}/action root"
expected_output="${TEST_ROOT}/expected-output"
mkdir -p "${action_root}/action" "${TEST_ROOT}/runner temp"

# shellcheck disable=SC2016 # The generated stub expands the plan at runtime.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  '[[ ${1:-} == resolve ]] || exit 2' \
  'printf '\''%s\n'\'' "${MERRY_SETUP_TEST_PLAN}"' >"${action_root}/action/run.sh"
chmod +x "${action_root}/action/run.sh"

export GITHUB_ACTION_PATH="${action_root}"
export GITHUB_OUTPUT="${TEST_ROOT}/github-output"
export RUNNER_TEMP="${TEST_ROOT}/runner temp"
export RUNNER_OS=Linux
export RUNNER_ARCH=X64
export MERRY_SETUP_TEST_PLAN

run_cache_resolve() {
  : >"${GITHUB_OUTPUT}"
  set +e
  bash "${RESOLVE_ADAPTER_PATH}" >"${TEST_STDOUT}" 2>"${TEST_STDERR}"
  ACTUAL_STATUS=$?
  set -e
}

MERRY_SETUP_TEST_PLAN="$(printf '%s\n' \
  'sdk_family=dart' \
  'sdk_version=3.12.0' \
  "sdk_archive_sha256=${SDK_ARCHIVE_SHA256}" \
  "sdk_path=${MERRY_SETUP_HOME}/sdks/dart/3.12.0" \
  'precache=none' \
  'activation=none' \
  'bundle=none' \
  'bootstrap=none')"
export MERRY_SETUP_TEST_PLAN
run_cache_resolve
assert_status 0
printf '%s\n' \
  'sdk-family=dart' \
  'sdk-version=3.12.0' \
  "sdk-archive-sha256=${SDK_ARCHIVE_SHA256}" \
  "sdk-path=${MERRY_SETUP_HOME}/sdks/dart/3.12.0" \
  "archive-path=${RUNNER_TEMP}/merry-setup/sdk-archives/dart/3.12.0/sdk-archive" \
  "cache-key=merry-setup-sdk-archive-dart-3.12.0-Linux-X64-${SDK_ARCHIVE_SHA256}" \
  'sdk-present=false' >"${expected_output}"
assert_file_equals "${expected_output}" "${GITHUB_OUTPUT}"
assert_path_absent "${RUNNER_TEMP}/merry-setup"
assert_path_absent "${MERRY_SETUP_HOME}"
pass "resolve adapter emits an exact cache plan without creating paths"

baseline_key="$(sed -n 's/^cache-key=//p' "${GITHUB_OUTPUT}")"

MERRY_SETUP_TEST_PLAN="$(printf '%s\n' \
  'sdk_family=dart' \
  'sdk_version=3.12.0' \
  "sdk_archive_sha256=${SDK_ARCHIVE_SHA256}" \
  "sdk_path=${MERRY_SETUP_HOME}/sdks/dart/3.12.0" \
  'precache=android,web' \
  'activation=alpha@1.0.0' \
  'activation=zeta@latest' \
  'bundle=flutterfire' \
  'bundle_flutterfire_cli_version=latest' \
  'bundle_firebase_tools_version=latest' \
  'bootstrap=dart')"
export MERRY_SETUP_TEST_PLAN
run_cache_resolve
assert_status 0
[[ $(sed -n 's/^cache-key=//p' "${GITHUB_OUTPUT}") == "${baseline_key}" ]] || fail "non-archive plan fields changed the cache key"
pass "activation, bundle, precache, and bootstrap plans do not affect archive identity"

RUNNER_ARCH=ARM64 run_cache_resolve
assert_status 0
[[ $(sed -n 's/^cache-key=//p' "${GITHUB_OUTPUT}") != "${baseline_key}" ]] || fail "runner architecture did not change the cache key"
pass "runner architecture changes archive identity"

MERRY_SETUP_TEST_PLAN="$(printf '%s\n' \
  'sdk_family=dart' \
  'sdk_version=3.12.0' \
  'sdk_archive_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
  "sdk_path=${MERRY_SETUP_HOME}/sdks/dart/3.12.0" \
  'precache=none' \
  'activation=none' \
  'bundle=none' \
  'bootstrap=none')"
export MERRY_SETUP_TEST_PLAN
run_cache_resolve
assert_status 0
checksum_key="$(sed -n 's/^cache-key=//p' "${GITHUB_OUTPUT}")"
[[ ${checksum_key} != "${baseline_key}" ]] || fail "official checksum did not change the cache key"
pass "official checksum changes archive identity"

MERRY_SETUP_TEST_PLAN="$(printf '%s\n' \
  'sdk_family=dart' \
  'sdk_version=3.13.0' \
  "sdk_archive_sha256=${SDK_ARCHIVE_SHA256}" \
  "sdk_path=${MERRY_SETUP_HOME}/sdks/dart/3.13.0" \
  'precache=none' \
  'activation=none' \
  'bundle=none' \
  'bootstrap=none')"
export MERRY_SETUP_TEST_PLAN
run_cache_resolve
assert_status 0
[[ $(sed -n 's/^cache-key=//p' "${GITHUB_OUTPUT}") != "${baseline_key}" ]] || fail "resolved version and checksum did not change the cache key"
pass "resolved version changes archive identity"

mkdir -p "${MERRY_SETUP_HOME}/sdks/dart"
ln -s "${TEST_ROOT}/missing-sdk" "${MERRY_SETUP_HOME}/sdks/dart/3.12.0"
MERRY_SETUP_TEST_PLAN="$(printf '%s\n' \
  'sdk_family=dart' \
  'sdk_version=3.12.0' \
  "sdk_archive_sha256=${SDK_ARCHIVE_SHA256}" \
  "sdk_path=${MERRY_SETUP_HOME}/sdks/dart/3.12.0" \
  'precache=none' \
  'activation=none' \
  'bundle=none' \
  'bootstrap=none')"
export MERRY_SETUP_TEST_PLAN
run_cache_resolve
assert_status 0
grep -Fqx 'sdk-present=true' "${GITHUB_OUTPUT}" || fail "dangling SDK symlink was treated as absent"
assert_path_absent "${RUNNER_TEMP}/merry-setup"
pass "a dangling final SDK symlink skips archive restore and defers rejection to the CLI"

MERRY_SETUP_TEST_PLAN="$(printf '%s\n' \
  'sdk_family=dart' \
  'sdk_version=3.12.0' \
  "sdk_archive_sha256=${SDK_ARCHIVE_SHA256}" \
  'sdk_archive_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
  "sdk_path=${MERRY_SETUP_HOME}/sdks/dart/3.12.0" \
  'precache=none' \
  'activation=none' \
  'bundle=none' \
  'bootstrap=none')"
export MERRY_SETUP_TEST_PLAN
run_cache_resolve
assert_nonzero
assert_stderr_contains "duplicate resolved-plan key 'sdk_archive_sha256'"
[[ ! -s ${GITHUB_OUTPUT} ]] || fail "malformed plan wrote partial Action outputs"
pass "resolve adapter rejects duplicate scalar plan keys before cache restore"

MERRY_SETUP_TEST_PLAN="$(printf '%s\n' \
  'sdk_family=dart' \
  'sdk_version=3.12.0' \
  "sdk_archive_sha256=${SDK_ARCHIVE_SHA256}" \
  'precache=none' \
  'activation=none' \
  'bundle=none' \
  'bootstrap=none')"
export MERRY_SETUP_TEST_PLAN
run_cache_resolve
assert_nonzero
assert_stderr_contains "resolved plan is missing 'sdk_path'"
[[ ! -s ${GITHUB_OUTPUT} ]] || fail "incomplete plan wrote partial Action outputs"
pass "resolve adapter rejects a missing final SDK path before cache restore"
