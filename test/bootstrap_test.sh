#!/usr/bin/env bash
set -euo pipefail

BOOTSTRAP_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BOOTSTRAP_TEST_DIR
# shellcheck source=test/test_helper.sh
# shellcheck disable=SC1091 # The test suite supplies this repository-local helper.
source "${BOOTSTRAP_TEST_DIR}/test_helper.sh"

readonly FIXTURE_DIR="${BOOTSTRAP_TEST_DIR}/fixtures"

setup_test_env
trap cleanup_test_env EXIT

export DART_VERSION_FIXTURE="${FIXTURE_DIR}/dart-version-3.12.0.json"
export FLUTTER_RELEASES_FIXTURE="${FIXTURE_DIR}/flutter-releases.json"

readonly PROJECT_DIR="${TEST_ROOT}/project"
readonly DART_BIN="${TEST_ROOT}/managed/sdks/dart/3.12.0/bin"
readonly OLD_DART_BIN="${TEST_ROOT}/managed/sdks/dart/3.11.4/bin"
readonly FLUTTER_BIN="${TEST_ROOT}/managed/sdks/flutter/3.44.0/bin"
readonly DART_CACHE="${TEST_ROOT}/managed/pub-cache/dart/3.12.0"

reset_case() {
  : >"${TEST_COMMAND_LOG}"
  : >"${TEST_STDOUT}"
  : >"${TEST_STDERR}"
  rm -rf -- "${PROJECT_DIR:?}" "${TEST_ROOT:?}/managed/pub-cache"
  mkdir -p "${PROJECT_DIR}"
  printf 'name: fixture\n' >"${PROJECT_DIR}/pubspec.yaml"
  unset PUB_GET_STATUS TOOL_COMMAND_STATUS || true
}

track_lockfile() {
  printf 'packages: {}\n' >"${PROJECT_DIR}/pubspec.lock"
  git -C "${PROJECT_DIR}" -c init.defaultBranch=main init -q
  git -C "${PROJECT_DIR}" add pubspec.lock
}

run_bootstrap() {
  local sdk_bin="$1"
  shift

  # The PATH is closed to the stub directory, the running Bash, and system binaries so a real SDK on this machine cannot leak in.
  PATH="${sdk_bin}:${TEST_ROOT}/commands:${BASH%/*}:/usr/bin:/bin" run_cli bootstrap --persist-path none --project-dir "${PROJECT_DIR}" "$@"
}

assert_no_setup_mutation() {
  assert_command_count 0 curl
  assert_log_excludes '|global|activate'
}

create_host_stub
create_metadata_stub
create_dart_sdk 3.12.0
create_dart_sdk 3.11.4
create_flutter_sdk 3.44.0 3.12.0

reset_case
run_bootstrap "${DART_BIN}" --sdk dart --bootstrap dart
assert_status 0
assert_log_contains 'CALL dart|pub get'
assert_log_excludes '--enforce-lockfile'
assert_stdout_contains "Resolved PUB_CACHE: ${DART_CACHE}"
assert_stdout_contains 'Merry bootstrap completed'
assert_no_setup_mutation
pass "bootstrap with an absent lockfile runs plain dart pub get from the PATH SDK"

reset_case
printf 'packages: {}\n' >"${PROJECT_DIR}/pubspec.lock"
run_bootstrap "${DART_BIN}" --sdk dart --bootstrap dart
assert_status 0
assert_log_contains 'CALL dart|pub get'
assert_log_excludes '--enforce-lockfile'
pass "an untracked lockfile does not enable --enforce-lockfile"

reset_case
track_lockfile
run_bootstrap "${DART_BIN}" --sdk dart --bootstrap dart
assert_status 0
assert_log_contains 'CALL dart|pub get --enforce-lockfile'
pass "a tracked lockfile enables --enforce-lockfile"

reset_case
track_lockfile
# shellcheck disable=SC2016 # The generated stub expands its runtime environment.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "fatal: detected dubious ownership in repository at %s\n" "${PWD}" >&2' \
  'exit 128' >"${TEST_ROOT}/commands/git"
chmod +x "${TEST_ROOT}/commands/git"
run_bootstrap "${DART_BIN}" --sdk dart --bootstrap dart
assert_nonzero
assert_stderr_contains "dubious ownership"
assert_log_excludes 'CALL dart|pub get'
rm -f "${TEST_ROOT}/commands/git"
pass "an unreadable git checkout aborts instead of silently dropping --enforce-lockfile"

reset_case
run_bootstrap "${FLUTTER_BIN}" --sdk flutter --bootstrap flutter
assert_status 0
assert_log_contains 'CALL flutter|pub get'
assert_stdout_contains "Resolved PUB_CACHE: ${TEST_ROOT}/managed/pub-cache/flutter/3.44.0"
assert_no_setup_mutation
pass "flutter bootstrap derives the managed cache from the located Flutter version"

reset_case
run_bootstrap "${DART_BIN}" --sdk dart --sdk-version 3.13.0 --bootstrap dart
assert_nonzero
assert_stderr_contains "does not match requested version 3.13.0"
assert_log_excludes 'CALL dart|pub get'
pass "an explicit version mismatch fails before bootstrap mutation"

reset_case
run_bootstrap "${DART_BIN}" --sdk dart --sdk-version 3.12.0 --bootstrap dart
assert_status 0
assert_log_contains 'CALL dart|pub get'
pass "an explicit matching version bootstraps"

reset_case
run_bootstrap "${TEST_ROOT}/no-sdk-here" --sdk flutter --bootstrap flutter
assert_nonzero
assert_stderr_contains "flutter executable was not found on PATH"
assert_no_setup_mutation
pass "a missing PATH SDK fails without downloading anything"

reset_case
run_bootstrap "${OLD_DART_BIN}" --sdk dart --bootstrap dart
assert_nonzero
assert_stderr_contains "Effective Dart runtime 3.11.4 is below the minimum 3.12.0."
assert_log_excludes 'CALL dart|pub get'
pass "a PATH SDK below the runtime floor performs no project mutation"

reset_case
track_lockfile
mkdir -p "${DART_CACHE}/bin"
cp "${TOOL_SHIM_TEMPLATE}" "${DART_CACHE}/bin/melos"
run_bootstrap "${DART_BIN}" --sdk dart --bootstrap melos
assert_status 0
assert_log_contains 'CALL melos|bootstrap --enforce-lockfile'
assert_log_excludes 'CALL dart|pub get'
pass "melos bootstrap uses the cached tool without a redundant pub get"

reset_case
run_bootstrap "${DART_BIN}" --sdk dart --bootstrap melos
assert_nonzero
assert_stderr_contains "melos is unavailable"
pass "a missing melos executable fails instead of activating it"

reset_case
track_lockfile
mkdir -p "${DART_CACHE}/bin"
cp "${TOOL_SHIM_TEMPLATE}" "${DART_CACHE}/bin/very_good"
run_bootstrap "${DART_BIN}" --sdk dart --bootstrap very-good
assert_status 0
assert_log_contains 'CALL very_good|packages get --recursive'
assert_log_excludes '--enforce-lockfile'
pass "very-good bootstrap runs the recursive package get without a lockfile flag"

reset_case
track_lockfile
mkdir -p "${DART_CACHE}/bin"
cp "${TOOL_SHIM_TEMPLATE}" "${DART_CACHE}/bin/very_good"
# shellcheck disable=SC2016 # The generated stub expands its runtime environment.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "fatal: detected dubious ownership in repository at %s\n" "${PWD}" >&2' \
  'exit 128' >"${TEST_ROOT}/commands/git"
chmod +x "${TEST_ROOT}/commands/git"
run_bootstrap "${DART_BIN}" --sdk dart --bootstrap very-good
assert_status 0
assert_log_contains 'CALL very_good|packages get --recursive'
rm -f "${TEST_ROOT}/commands/git"
pass "very-good bootstrap ignores an unreadable git checkout because it never reads the lockfile"

reset_case
run_bootstrap "${DART_BIN}" --sdk dart --bootstrap flutter
assert_nonzero
assert_stderr_contains "Option '--bootstrap flutter' requires '--sdk flutter'."
assert_log_excludes 'CALL'
pass "flutter bootstrap with the dart family fails at validation"

reset_case
export PUB_GET_STATUS=5
run_bootstrap "${DART_BIN}" --sdk dart --bootstrap dart
assert_nonzero
assert_stderr_contains "Project bootstrap failed"
assert_stdout_excludes 'bootstrap completed'
pass "a failing pub get propagates its status and suppresses success"

reset_case
run_bootstrap "${DART_BIN}" --sdk dart --bootstrap none
assert_status 0
assert_log_excludes 'CALL dart|pub get'
assert_stdout_contains 'Merry bootstrap completed'
pass "bootstrap none skips project commands"
