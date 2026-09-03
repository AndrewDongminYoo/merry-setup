#!/usr/bin/env bash
set -euo pipefail

TRUNK_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TRUNK_TEST_DIR
# shellcheck source=test/test_helper.sh
# shellcheck disable=SC1091 # The test suite supplies this repository-local helper.
source "${TRUNK_TEST_DIR}/test_helper.sh"

readonly FIXTURE_DIR="${TRUNK_TEST_DIR}/fixtures"

setup_test_env
trap cleanup_test_env EXIT

export DART_VERSION_FIXTURE="${FIXTURE_DIR}/dart-version-3.12.0.json"
export FLUTTER_RELEASES_FIXTURE="${FIXTURE_DIR}/flutter-releases.json"
export TRUNK_LAUNCHER_FIXTURE="${TEST_ROOT}/launchers/downloaded-trunk"

readonly EXPLICIT_LAUNCHER="${TEST_ROOT}/launchers/trunk"
readonly PROJECT_DIR="${TEST_ROOT}/project"

reset_case() {
  : >"${TEST_COMMAND_LOG}"
  : >"${TEST_STDOUT}"
  : >"${TEST_STDERR}"
  rm -rf -- "${MERRY_SETUP_HOME:?}/bin" "${PROJECT_DIR:?}/.trunk" "${PROJECT_DIR}/tools" "${PROJECT_DIR}/trunk" "${HOME}/.bashrc"
  unset TRUNK_VERSION_STATUS CURL_FAIL_PATTERN GITHUB_ENV GITHUB_PATH || true
}

assert_trunk_download_count() {
  local expected_count="$1"
  local actual_count=0

  actual_count="$(grep -c -F 'ARG https://trunk.io/releases/trunk' "${TEST_COMMAND_LOG}" || true)"
  [[ ${actual_count} -eq ${expected_count} ]] || fail "expected ${expected_count} Trunk launcher downloads, received ${actual_count}"
}

assert_marker_count() {
  local expected_count="$1"
  local marker_text="$2"
  local actual_count=0

  actual_count="$(grep -c -F -- "${marker_text}" "${HOME}/.bashrc" || true)"
  [[ ${actual_count} -eq ${expected_count} ]] || fail "expected ${expected_count} '${marker_text}' lines in .bashrc, received ${actual_count}; file: $(<"${HOME}/.bashrc")"
}

run_setup() {
  local sdk_family="$1"
  local sdk_version="$2"
  local persistence_adapter="$3"
  shift 3

  run_cli setup --sdk "${sdk_family}" --sdk-version "${sdk_version}" --bootstrap none --persist-path "${persistence_adapter}" --no-merry --project-dir "${PROJECT_DIR}" "$@"
}

create_host_stub
create_metadata_stub
create_dart_sdk 3.12.0
create_dart_sdk 3.13.0
create_flutter_sdk 3.44.0 3.12.0
write_trunk_launcher_stub "${EXPLICIT_LAUNCHER}"
write_trunk_launcher_stub "${TRUNK_LAUNCHER_FIXTURE}"
printf 'name: fixture\n' >"${PROJECT_DIR}/pubspec.yaml"

# --- Trunk selection ---

reset_case
run_setup flutter 3.44.0 none --trunk-path "${EXPLICIT_LAUNCHER}"
assert_stdout_contains "Trunk launcher: ${EXPLICIT_LAUNCHER}"
assert_log_contains 'CALL trunk|version'
assert_trunk_download_count 0
pass "explicit trunk path is used and its version command runs"

reset_case
run_setup flutter 3.44.0 none --trunk-path "${TEST_ROOT}/launchers/missing"
assert_nonzero
assert_stderr_contains "Option '--trunk-path'"
assert_command_count 0 curl
assert_log_excludes 'CALL trunk'
pass "invalid explicit trunk path fails before SDK mutation"

reset_case
write_trunk_launcher_stub "${PROJECT_DIR}/.trunk/bin/trunk"
run_setup flutter 3.44.0 none
assert_stdout_contains "Trunk launcher: ${PROJECT_DIR}/.trunk/bin/trunk"
assert_log_contains 'CALL trunk|version'
assert_trunk_download_count 0
pass "repository-local .trunk/bin/trunk launcher is reused"

reset_case
write_trunk_launcher_stub "${PROJECT_DIR}/tools/trunk"
run_setup flutter 3.44.0 none
assert_stdout_contains "Trunk launcher: ${PROJECT_DIR}/tools/trunk"
assert_trunk_download_count 0
pass "repository-local tools/trunk launcher is reused"

reset_case
run_setup flutter 3.44.0 none
assert_stdout_contains "Trunk launcher: ${MERRY_SETUP_HOME}/bin/trunk"
assert_log_contains 'CALL trunk|version'
assert_trunk_download_count 1
assert_path_exists "${MERRY_SETUP_HOME}/bin/trunk"
[[ -x ${MERRY_SETUP_HOME}/bin/trunk ]] || fail "downloaded launcher is not executable"
run_setup flutter 3.44.0 none
assert_trunk_download_count 1
pass "official launcher fallback downloads once and is reused afterwards"

reset_case
export CURL_FAIL_PATTERN=trunk.io
run_setup flutter 3.44.0 none
assert_nonzero
assert_stderr_contains "Failed to download Trunk launcher"
assert_path_absent "${MERRY_SETUP_HOME}/bin/trunk"
pass "launcher download failure leaves no partial launcher"

reset_case
export TRUNK_VERSION_STATUS=3
run_setup flutter 3.44.0 none --trunk-path "${EXPLICIT_LAUNCHER}"
assert_nonzero
assert_stderr_contains "Trunk launcher failed to report its version"
assert_stdout_excludes 'setup completed'
pass "launcher version failure suppresses success"

# --- Persistence adapters ---

reset_case
run_setup flutter 3.44.0 none --trunk-path "${EXPLICIT_LAUNCHER}"
assert_path_absent "${HOME}/.bashrc"
pass "none adapter writes no persistence file"

reset_case
run_setup flutter 3.44.0 github --trunk-path "${EXPLICIT_LAUNCHER}"
assert_nonzero
assert_stderr_contains "GITHUB_ENV"
assert_command_count 0 curl
pass "github adapter fails before mutation when GITHUB_ENV is missing"

reset_case
export GITHUB_ENV="${TEST_ROOT}/github-env"
: >"${GITHUB_ENV}"
run_setup flutter 3.44.0 github --trunk-path "${EXPLICIT_LAUNCHER}"
assert_nonzero
assert_stderr_contains "GITHUB_PATH"
assert_command_count 0 curl
[[ ! -s ${GITHUB_ENV} ]] || fail "GITHUB_ENV was written despite a missing GITHUB_PATH"
pass "github adapter fails before mutation when GITHUB_PATH is missing"

reset_case
export GITHUB_ENV="${TEST_ROOT}/github-env"
export GITHUB_PATH="${TEST_ROOT}/github-path"
printf 'EXISTING=1\n' >"${GITHUB_ENV}"
printf '/preexisting/bin\n' >"${GITHUB_PATH}"
run_setup flutter 3.44.0 github --trunk-path "${EXPLICIT_LAUNCHER}"
printf '%s\n' 'EXISTING=1' "PUB_CACHE=${MERRY_SETUP_HOME}/pub-cache/flutter/3.44.0" >"${TEST_ROOT}/expected-env"
assert_file_equals "${TEST_ROOT}/expected-env" "${GITHUB_ENV}"
printf '%s\n' '/preexisting/bin' "${MERRY_SETUP_HOME}/bin" "${MERRY_SETUP_HOME}/pub-cache/flutter/3.44.0/bin" "${MERRY_SETUP_HOME}/sdks/flutter/3.44.0/bin" >"${TEST_ROOT}/expected-path"
assert_file_equals "${TEST_ROOT}/expected-path" "${GITHUB_PATH}"
pass "github adapter appends PUB_CACHE and PATH entries so the SDK wins precedence"

reset_case
printf '# user line\nexport USER_VAR=1\n' >"${HOME}/.bashrc"
run_setup dart 3.12.0 bashrc --trunk-path "${EXPLICIT_LAUNCHER}"
assert_marker_count 1 '# >>> merry-setup managed block >>>'
assert_marker_count 1 '# <<< merry-setup managed block <<<'
assert_marker_count 1 '# user line'
run_setup dart 3.13.0 bashrc --trunk-path "${EXPLICIT_LAUNCHER}"
assert_marker_count 1 '# >>> merry-setup managed block >>>'
assert_marker_count 1 '# <<< merry-setup managed block <<<'
assert_marker_count 1 '# user line'
assert_marker_count 0 'sdks/dart/3.12.0/bin'
assert_marker_count 1 'sdks/dart/3.13.0/bin'
# shellcheck disable=SC2016 # The inner shell expands the sourced values.
resolved_env="$(env -i HOME="${HOME}" PATH=/usr/bin:/bin /usr/bin/env bash -c 'source "${HOME}/.bashrc"; printf "%s\n%s\n%s\n" "${PUB_CACHE}" "${PATH}" "${USER_VAR}"')"
printf '%s\n' "${MERRY_SETUP_HOME}/pub-cache/dart/3.13.0" "${MERRY_SETUP_HOME}/sdks/dart/3.13.0/bin:${MERRY_SETUP_HOME}/pub-cache/dart/3.13.0/bin:${MERRY_SETUP_HOME}/bin:/usr/bin:/bin" '1' >"${TEST_ROOT}/expected-resolved"
printf '%s\n' "${resolved_env}" >"${TEST_ROOT}/actual-resolved"
assert_file_equals "${TEST_ROOT}/expected-resolved" "${TEST_ROOT}/actual-resolved"
pass "bashrc adapter keeps one managed block, replaces stale versions, and preserves user lines"

reset_case
quoted_home="${TEST_ROOT}/it's managed"
mkdir -p "${quoted_home}/sdks/dart"
cp -R "${MERRY_SETUP_HOME}/sdks/dart/3.12.0" "${quoted_home}/sdks/dart/3.12.0"
MERRY_SETUP_HOME="${quoted_home}" run_setup dart 3.12.0 bashrc --trunk-path "${EXPLICIT_LAUNCHER}"
# shellcheck disable=SC2016 # The inner shell expands the sourced values.
resolved_env="$(env -i HOME="${HOME}" PATH=/usr/bin:/bin /usr/bin/env bash -c 'source "${HOME}/.bashrc"; printf "%s\n%s\n" "${PUB_CACHE}" "${PATH}"')"
printf '%s\n' "${quoted_home}/pub-cache/dart/3.12.0" "${quoted_home}/sdks/dart/3.12.0/bin:${quoted_home}/pub-cache/dart/3.12.0/bin:${quoted_home}/bin:/usr/bin:/bin" >"${TEST_ROOT}/expected-resolved"
printf '%s\n' "${resolved_env}" >"${TEST_ROOT}/actual-resolved"
assert_file_equals "${TEST_ROOT}/expected-resolved" "${TEST_ROOT}/actual-resolved"
pass "bashrc adapter quotes paths containing spaces and single quotes"

reset_case
printf '# >>> merry-setup managed block >>>\nexport BROKEN=1\n' >"${HOME}/.bashrc"
run_setup dart 3.12.0 bashrc --trunk-path "${EXPLICIT_LAUNCHER}"
assert_nonzero
assert_stderr_contains "managed block"
assert_marker_count 1 'export BROKEN=1'
pass "bashrc adapter refuses to rewrite a block without an end marker"

reset_case
printf '# <<< merry-setup managed block <<<\nexport BEFORE=1\n# >>> merry-setup managed block >>>\nexport AFTER=1\n' >"${HOME}/.bashrc"
cp "${HOME}/.bashrc" "${TEST_ROOT}/misordered-bashrc"
run_setup dart 3.12.0 bashrc --trunk-path "${EXPLICIT_LAUNCHER}"
assert_nonzero
assert_stderr_contains "managed block"
assert_file_equals "${TEST_ROOT}/misordered-bashrc" "${HOME}/.bashrc"
pass "bashrc adapter refuses misordered markers and leaves the file untouched"

reset_case
printf '# >>> merry-setup managed block >>>\nexport OLD=1\n# <<< merry-setup managed block <<<\n# >>> merry-setup managed block >>>\nexport OLD=2\n# <<< merry-setup managed block <<<\n' >"${HOME}/.bashrc"
run_setup dart 3.12.0 bashrc --trunk-path "${EXPLICIT_LAUNCHER}"
assert_nonzero
assert_stderr_contains "managed block"
assert_marker_count 1 'export OLD=1'
pass "bashrc adapter refuses duplicated blocks"
