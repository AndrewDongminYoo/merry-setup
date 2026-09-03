#!/usr/bin/env bash
set -euo pipefail

FLOW_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly FLOW_TEST_DIR
# shellcheck source=test/test_helper.sh
# shellcheck disable=SC1091 # The test suite supplies this repository-local helper.
source "${FLOW_TEST_DIR}/test_helper.sh"

readonly FIXTURE_DIR="${FLOW_TEST_DIR}/fixtures"

setup_test_env
trap cleanup_test_env EXIT

export DART_VERSION_FIXTURE="${FIXTURE_DIR}/dart-version-3.12.0.json"
export FLUTTER_RELEASES_FIXTURE="${FIXTURE_DIR}/flutter-releases.json"

readonly PROJECT_DIR="${TEST_ROOT}/project"
readonly LAUNCHER="${TEST_ROOT}/launchers/trunk"
readonly FLUTTER_CACHE="${TEST_ROOT}/managed/pub-cache/flutter/3.44.0"

reset_case() {
  : >"${TEST_COMMAND_LOG}"
  : >"${TEST_STDOUT}"
  : >"${TEST_STDERR}"
  rm -rf -- "${PROJECT_DIR:?}" "${TEST_ROOT:?}/managed/pub-cache" "${HOME:?}/.bashrc"
  mkdir -p "${PROJECT_DIR}"
  printf 'name: fixture\n' >"${PROJECT_DIR}/pubspec.yaml"
  unset PUB_GET_STATUS TOOL_COMMAND_STATUS || true
}

assert_log_order() {
  local earlier="$1"
  local later="$2"
  local earlier_line=0
  local later_line=0

  earlier_line="$(grep -n -F -- "${earlier}" "${TEST_COMMAND_LOG}" | head -n 1 | cut -d: -f1)"
  later_line="$(grep -n -F -- "${later}" "${TEST_COMMAND_LOG}" | tail -n 1 | cut -d: -f1)"
  [[ -n ${earlier_line} && -n ${later_line} && ${earlier_line} -lt ${later_line} ]] || fail "expected '${earlier}' before '${later}'; log: $(<"${TEST_COMMAND_LOG}")"
}

assert_line_count() {
  local expected_count="$1"
  local pattern="$2"
  local actual_count=0

  actual_count="$(grep -c -F -- "${pattern}" "${TEST_COMMAND_LOG}" || true)"
  [[ ${actual_count} -eq ${expected_count} ]] || fail "expected ${expected_count} lines matching '${pattern}', received ${actual_count}"
}

run_full_setup() {
  run_cli setup --sdk flutter --sdk-version 3.44.0 --bootstrap melos --persist-path bashrc --project-dir "${PROJECT_DIR}" --trunk-path "${LAUNCHER}" --precache android,web
}

create_host_stub
create_metadata_stub
create_dart_sdk 3.12.0
create_flutter_sdk 3.44.0 3.12.0
write_trunk_launcher_stub "${LAUNCHER}"

reset_case
run_full_setup
assert_status 0
assert_log_contains "CALL dart|pub global activate merry"
assert_log_contains "CALL dart|pub global activate melos"
assert_log_contains 'CALL flutter|precache --android --web'
assert_log_contains 'CALL trunk|version'
assert_log_contains 'CALL melos|bootstrap'
assert_log_order 'pub global activate melos' 'CALL flutter|precache'
assert_log_order 'CALL flutter|precache' 'CALL trunk|version'
assert_log_order 'CALL trunk|version' 'CALL melos|bootstrap'
assert_stdout_contains 'Persisted PUB_CACHE and PATH: adapter=bashrc'
assert_stdout_contains 'Merry setup completed: sdk=flutter version=3.44.0 bootstrap=melos persist=bashrc'
grep -Fq "${FLUTTER_CACHE}/bin" "${HOME}/.bashrc" || fail ".bashrc does not reference the managed pub cache"
pass "full setup orders activation, precache, Trunk, persistence, and bootstrap before success"

reset_case
run_full_setup
assert_status 0
run_full_setup
assert_status 0
assert_stdout_contains 'Reusing Flutter SDK 3.44.0'
assert_line_count 2 'pub global activate merry'
assert_line_count 2 'pub global activate melos'
[[ $(grep -c -F '# >>> merry-setup managed block >>>' "${HOME}/.bashrc") -eq 1 ]] || fail "expected exactly one managed block after two runs"
[[ -x ${FLUTTER_CACHE}/bin/melos ]] || fail "melos shim is not usable after setup"
assert_log_excludes 'flutter_linux_'
pass "repeated setup reuses the SDK, activates each package once per run, and keeps one profile block"

reset_case
export TOOL_COMMAND_STATUS=4
run_full_setup
assert_nonzero
assert_stderr_contains "Project bootstrap failed: strategy=melos"
assert_stdout_excludes 'Merry setup completed'
pass "a failing bootstrap propagates status and suppresses the final success"

reset_case
run_cli setup --sdk flutter --sdk-version 3.44.0 --bootstrap none --persist-path none --project-dir "${PROJECT_DIR}" --trunk-path "${LAUNCHER}" --no-merry
assert_status 0
assert_log_excludes 'pub get'
assert_log_excludes 'global activate'
assert_stdout_contains 'Merry setup completed: sdk=flutter version=3.44.0 bootstrap=none persist=none'
pass "bootstrap none with Merry opted out still completes SDK, Trunk, and persistence"

reset_case
printf 'packages: {}\n' >"${PROJECT_DIR}/pubspec.lock"
git -C "${PROJECT_DIR}" -c init.defaultBranch=main init -q
git -C "${PROJECT_DIR}" add pubspec.lock
run_cli setup --sdk dart --sdk-version 3.12.0 --bootstrap dart --persist-path none --project-dir "${PROJECT_DIR}" --trunk-path "${LAUNCHER}"
assert_status 0
assert_log_contains 'CALL dart|pub get --enforce-lockfile'
assert_log_order 'pub global activate merry' 'CALL dart|pub get --enforce-lockfile'
pass "dart setup with a tracked lockfile enforces it during bootstrap"

reset_case
rm -f "${PROJECT_DIR}/pubspec.yaml"
run_cli setup --sdk dart --sdk-version 3.12.0 --bootstrap dart --persist-path none --project-dir "${PROJECT_DIR}" --trunk-path "${LAUNCHER}"
assert_nonzero
assert_stderr_contains "does not contain pubspec.yaml"
assert_log_excludes 'CALL'
pass "a manifest deleted after any preflight still fails before mutation"
