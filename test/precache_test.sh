#!/usr/bin/env bash
set -euo pipefail

PRECACHE_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PRECACHE_TEST_DIR
# shellcheck source=test/test_helper.sh
# shellcheck disable=SC1091 # The test suite supplies this repository-local helper.
source "${PRECACHE_TEST_DIR}/test_helper.sh"

readonly FIXTURE_DIR="${PRECACHE_TEST_DIR}/fixtures"

setup_test_env
trap cleanup_test_env EXIT

export DART_VERSION_FIXTURE="${FIXTURE_DIR}/dart-version-3.12.0.json"
export FLUTTER_RELEASES_FIXTURE="${FIXTURE_DIR}/flutter-releases.json"

reset_case() {
  : >"${TEST_COMMAND_LOG}"
  : >"${TEST_STDOUT}"
  : >"${TEST_STDERR}"
  unset FLUTTER_PRECACHE_STATUS || true
}

assert_precache_call_count() {
  local expected_count="$1"
  local actual_count=0

  actual_count="$(grep -c -F 'CALL flutter|precache' "${TEST_COMMAND_LOG}" || true)"
  [[ ${actual_count} -eq ${expected_count} ]] || fail "expected ${expected_count} precache calls, received ${actual_count}; log: $(<"${TEST_COMMAND_LOG}")"
}

run_flutter_setup() {
  run_cli setup --sdk flutter --sdk-version 3.44.0 --bootstrap none --persist-path none --no-merry --trunk-path "${TEST_ROOT}/launchers/trunk" "$@"
}

create_host_stub
create_metadata_stub
create_dart_sdk 3.12.0
create_flutter_sdk 3.44.0 3.12.0
write_trunk_launcher_stub "${TEST_ROOT}/launchers/trunk"

reset_case
run_flutter_setup
assert_precache_call_count 0
assert_stderr_excludes "precache"
pass "no precache target skips Flutter precache entirely"

reset_case
run_flutter_setup --precache android
assert_precache_call_count 1
assert_log_contains 'CALL flutter|precache --android'
pass "android maps to --android"

reset_case
run_flutter_setup --precache web,android
assert_precache_call_count 1
assert_log_contains 'CALL flutter|precache --android --web'
pass "web,android normalizes to canonical --android --web order"

reset_case
run_flutter_setup --precache linux --precache android,web --precache android
assert_precache_call_count 1
assert_log_contains 'CALL flutter|precache --android --web --linux'
pass "repeated mixed targets deduplicate into one canonical invocation"

reset_case
run_cli setup --sdk dart --sdk-version 3.12.0 --bootstrap none --persist-path none --no-merry --precache web
assert_nonzero
assert_stderr_contains "Option '--precache' is invalid when '--sdk dart' is selected."
assert_command_count 0 curl
assert_precache_call_count 0
pass "dart precache conflict fails before SDK or precache mutation"

for invalid_target in 'android,' ',web' 'android,,web' 'none' 'ios' 'all' 'android_maven'; do
  reset_case
  run_flutter_setup --precache "${invalid_target}"
  assert_nonzero
  assert_stderr_contains "Option '--precache'"
  assert_stderr_contains "${invalid_target}"
  assert_command_count 0 curl
  assert_precache_call_count 0
  pass "invalid precache target '${invalid_target}' fails before mutation"
done

reset_case
export FLUTTER_PRECACHE_STATUS=7
run_flutter_setup --precache linux
assert_nonzero
assert_stderr_contains "Flutter precache failed"
assert_precache_call_count 1
assert_stdout_excludes 'setup completed'
pass "failing precache propagates status and suppresses success"
