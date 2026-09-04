#!/usr/bin/env bash
set -euo pipefail

RESOLVE_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly RESOLVE_TEST_DIR
# shellcheck source=test/test_helper.sh
# shellcheck disable=SC1091 # The test suite supplies this repository-local helper.
source "${RESOLVE_TEST_DIR}/test_helper.sh"

setup_test_env
trap cleanup_test_env EXIT

readonly DART_ARCHIVE_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
readonly FIXTURE_DIR="${RESOLVE_TEST_DIR}/fixtures"
readonly DART_CHECKSUM_FIXTURE="${TEST_ROOT}/dart.sha256sum"
readonly EXPECTED_PLAN="${TEST_ROOT}/expected-plan"

mkdir -p "${TEST_ROOT}/tmp"
export TMPDIR="${TEST_ROOT}/tmp"
export DART_VERSION_FIXTURE="${FIXTURE_DIR}/dart-version-3.12.0.json"
export DART_CHECKSUM_FIXTURE
export FLUTTER_RELEASES_FIXTURE="${FIXTURE_DIR}/flutter-releases.json"
printf '%s *dartsdk-linux-x64-release.zip\n' "${DART_ARCHIVE_SHA256}" >"${DART_CHECKSUM_FIXTURE}"

create_host_stub

# shellcheck disable=SC2016 # The generated stub expands its runtime environment.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf '\''COMMAND curl\n'\'' >>"${TEST_COMMAND_LOG}"' \
  'printf '\''ARG %s\n'\'' "$@" >>"${TEST_COMMAND_LOG}"' \
  'output_file=""' \
  'request_url=""' \
  'while (($# > 0)); do' \
  '  case "$1" in' \
  '  --output | --proto | --proto-redir) [[ $1 != --output ]] || output_file="$2"; shift 2 ;;' \
  '  --fail | --silent | --show-error | --location) shift ;;' \
  '  *) request_url="$1"; shift ;;' \
  '  esac' \
  'done' \
  'case "${request_url}" in' \
  '*/VERSION) source_file="${DART_VERSION_FIXTURE}" ;;' \
  '*.sha256sum) source_file="${DART_CHECKSUM_FIXTURE}" ;;' \
  '*releases_linux.json) source_file="${FLUTTER_RELEASES_FIXTURE}" ;;' \
  '*) exit 22 ;;' \
  'esac' \
  '/bin/cp "${source_file}" "${output_file}"' >"${TEST_ROOT}/commands/curl"
chmod +x "${TEST_ROOT}/commands/curl"

assert_validation_parity() {
  local case_name="$1"
  shift

  : >"${TEST_COMMAND_LOG}"
  rm -rf -- "${MERRY_SETUP_HOME}"
  run_cli resolve "$@"
  assert_nonzero
  cp "${TEST_STDERR}" "${TEST_ROOT}/resolve-error"
  run_cli setup "$@"
  assert_nonzero
  assert_file_equals "${TEST_ROOT}/resolve-error" "${TEST_STDERR}"
  assert_command_count 0 curl
  assert_path_absent "${MERRY_SETUP_HOME}"
  pass "resolve validation parity: ${case_name}"
}

run_cli resolve --sdk dart --sdk-version stable --bootstrap none --persist-path none --no-merry
assert_status 0
printf '%s\n' \
  'sdk_family=dart' \
  'sdk_version=3.12.0' \
  "sdk_archive_sha256=${DART_ARCHIVE_SHA256}" \
  "sdk_path=${MERRY_SETUP_HOME}/sdks/dart/3.12.0" \
  'precache=none' \
  'activation=none' \
  'bundle=none' \
  'bootstrap=none' >"${EXPECTED_PLAN}"
assert_file_equals "${EXPECTED_PLAN}" "${TEST_STDOUT}"
assert_path_absent "${MERRY_SETUP_HOME}"
assert_command_count 2 curl
if grep -Eq 'ARG https://.*/dartsdk-linux-x64-release\.zip$' "${TEST_COMMAND_LOG}"; then
  fail "resolve downloaded the Dart SDK archive"
fi
[[ -z $(find "${TMPDIR}" -type f -print) ]] || fail "resolve left metadata temporary files behind"
pass "resolve prints an SDK plan without mutating the managed home"

: >"${TEST_COMMAND_LOG}"
create_recording_stub npm
printf 'name: fixture\n' >"${TEST_ROOT}/project/pubspec.yaml"
run_cli resolve \
  --sdk flutter \
  --sdk-version stable \
  --bootstrap melos \
  --persist-path none \
  --project-dir "${TEST_ROOT}/project" \
  --no-merry \
  --dart-package 'beta=^2.0.0' \
  --dart-package 'alpha=^1.0.0' \
  --bundle flutterfire \
  --firebase-tools-version 14.2.1 \
  --precache web,android \
  --precache android
assert_status 0
printf '%s\n' \
  'sdk_family=flutter' \
  'sdk_version=3.44.0' \
  'sdk_archive_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
  "sdk_path=${MERRY_SETUP_HOME}/sdks/flutter/3.44.0" \
  'precache=android,web' \
  'activation=alpha@^1.0.0' \
  'activation=beta@^2.0.0' \
  'activation=flutterfire_cli@latest' \
  'activation=melos@latest' \
  'bundle=flutterfire' \
  'bundle_flutterfire_cli_version=latest' \
  'bundle_firebase_tools_version=14.2.1' \
  'bootstrap=melos' >"${EXPECTED_PLAN}"
assert_file_equals "${EXPECTED_PLAN}" "${TEST_STDOUT}"
assert_path_absent "${MERRY_SETUP_HOME}"
assert_log_excludes 'COMMAND npm'
pass "resolve normalizes precache, activation, and bundle plans"

cp "${TEST_STDOUT}" "${TEST_ROOT}/stable-plan"
: >"${TEST_COMMAND_LOG}"
run_cli resolve \
  --sdk flutter \
  --sdk-version 3.44.0 \
  --bootstrap melos \
  --persist-path none \
  --project-dir "${TEST_ROOT}/project" \
  --no-merry \
  --dart-package 'alpha=^1.0.0' \
  --dart-package 'beta=^2.0.0' \
  --bundle flutterfire \
  --firebase-tools-version 14.2.1 \
  --precache android \
  --precache web
assert_status 0
assert_file_equals "${TEST_ROOT}/stable-plan" "${TEST_STDOUT}"
assert_path_absent "${MERRY_SETUP_HOME}"
pass "stable and exact requests with equivalent input orders print the same plan"

: >"${TEST_COMMAND_LOG}"
run_cli resolve --sdk dart --sdk-version 3.12.0 --bootstrap none --persist-path none --dart-package alpha --dart-package alpha --no-merry
assert_nonzero
cp "${TEST_STDERR}" "${TEST_ROOT}/resolve-error"
assert_command_count 0 curl
run_cli setup --sdk dart --sdk-version 3.12.0 --bootstrap none --persist-path none --dart-package alpha --dart-package alpha --no-merry
assert_nonzero
assert_file_equals "${TEST_ROOT}/resolve-error" "${TEST_STDERR}"
assert_command_count 0 curl
assert_path_absent "${MERRY_SETUP_HOME}"
pass "resolve and setup reject repeated activation input with the same pre-mutation error"

export GITHUB_ENV="${TEST_ROOT}/github-env"
export GITHUB_PATH="${TEST_ROOT}/github-path"
printf 'KEEP_ENV=1\n' >"${GITHUB_ENV}"
printf '/keep/path\n' >"${GITHUB_PATH}"
cp "${GITHUB_ENV}" "${TEST_ROOT}/expected-github-env"
cp "${GITHUB_PATH}" "${TEST_ROOT}/expected-github-path"
run_cli resolve --sdk dart --sdk-version 3.12.0 --bootstrap none --persist-path github --no-merry
assert_status 0
assert_file_equals "${TEST_ROOT}/expected-github-env" "${GITHUB_ENV}"
assert_file_equals "${TEST_ROOT}/expected-github-path" "${GITHUB_PATH}"
assert_path_absent "${MERRY_SETUP_HOME}"
pass "resolve validates GitHub persistence without writing it"

assert_validation_parity "missing SDK" --bootstrap none --persist-path none --no-merry
assert_validation_parity "invalid SDK" --sdk invalid --sdk-version 3.12.0 --bootstrap none --persist-path none --no-merry
assert_validation_parity "invalid exact SDK version" --sdk dart --sdk-version next --bootstrap none --persist-path none --no-merry
assert_validation_parity "invalid bootstrap" --sdk dart --sdk-version 3.12.0 --bootstrap invalid --persist-path none --no-merry
assert_validation_parity "invalid persistence adapter" --sdk dart --sdk-version 3.12.0 --bootstrap none --persist-path invalid --no-merry
assert_validation_parity "missing project manifest" --sdk dart --sdk-version 3.12.0 --bootstrap dart --persist-path none --project-dir "${TEST_ROOT}/missing" --no-merry
assert_validation_parity "Merry conflict" --sdk dart --sdk-version 3.12.0 --bootstrap none --persist-path none --no-merry --merry-version 2.0.0
assert_validation_parity "invalid package" --sdk dart --sdk-version 3.12.0 --bootstrap none --persist-path none --dart-package 'bad package' --no-merry
assert_validation_parity "invalid bundle" --sdk dart --sdk-version 3.12.0 --bootstrap none --persist-path none --bundle invalid --no-merry
assert_validation_parity "Firebase version without bundle" --sdk dart --sdk-version 3.12.0 --bootstrap none --persist-path none --firebase-tools-version 14.2.1 --no-merry
assert_validation_parity "Dart precache" --sdk dart --sdk-version 3.12.0 --bootstrap none --persist-path none --precache web --no-merry
assert_validation_parity "invalid Trunk path" --sdk dart --sdk-version 3.12.0 --bootstrap none --persist-path none --trunk-path "${TEST_ROOT}/missing-trunk" --no-merry
PUB_CACHE=relative assert_validation_parity "invalid PUB_CACHE" --sdk dart --sdk-version 3.12.0 --bootstrap none --persist-path none --no-merry
