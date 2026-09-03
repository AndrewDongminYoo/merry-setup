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

create_host_stub() {
  local stub_path="${TEST_ROOT}/commands/uname"

  # shellcheck disable=SC2016 # The generated stub expands its runtime arguments.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'case "${1:-}" in' \
    '-s) printf '\''Linux\n'\'' ;;' \
    '-m) printf '\''x86_64\n'\'' ;;' \
    '*) exit 2 ;;' \
    'esac' >"${stub_path}"
  chmod +x "${stub_path}"
}

create_metadata_stub() {
  local stub_path="${TEST_ROOT}/commands/curl"

  # shellcheck disable=SC2016 # The generated stub expands its runtime environment.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf '\''COMMAND curl\n'\'' >>"${TEST_COMMAND_LOG}"' \
    'output_file=""' \
    'request_url=""' \
    'while (($# > 0)); do' \
    '  case "$1" in' \
    '  --output) output_file="$2"; shift 2 ;;' \
    '  --fail | --silent | --show-error | --location) shift ;;' \
    '  *) request_url="$1"; shift ;;' \
    '  esac' \
    'done' \
    'case "${request_url}" in' \
    '*/VERSION) source_file="${DART_VERSION_FIXTURE}" ;;' \
    '*releases_linux.json) source_file="${FLUTTER_RELEASES_FIXTURE}" ;;' \
    '*) exit 22 ;;' \
    'esac' \
    '/bin/cp "${source_file}" "${output_file}"' >"${stub_path}"
  chmod +x "${stub_path}"
}

write_dart_stub() {
  local dart_path="$1"
  local runtime_version="$2"

  mkdir -p "$(dirname "${dart_path}")"
  # shellcheck disable=SC2016 # The generated stub expands its runtime environment.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    "readonly runtime_version='${runtime_version}'" \
    'if [[ ${1:-} == --version ]]; then' \
    '  printf '\''Dart SDK version: %s (stable) on linux_x64\n'\'' "${runtime_version}" >&2' \
    '  exit 0' \
    'fi' \
    'printf '\''CALL dart|%s\n'\'' "$*" >>"${TEST_COMMAND_LOG}"' \
    'exit 2' >"${dart_path}"
  chmod +x "${dart_path}"
}

create_dart_sdk() {
  local sdk_version="$1"
  local sdk_root="${MERRY_SETUP_HOME}/sdks/dart/${sdk_version}"

  mkdir -p "${sdk_root}/include"
  printf 'synthetic Dart embedding API header\n' >"${sdk_root}/include/dart_api.h"
  write_dart_stub "${sdk_root}/bin/dart" "${sdk_version}"
}

create_flutter_sdk() {
  local flutter_version="$1"
  local dart_version="$2"
  local sdk_root="${MERRY_SETUP_HOME}/sdks/flutter/${flutter_version}"

  write_dart_stub "${sdk_root}/bin/dart" "${dart_version}"
  # shellcheck disable=SC2016 # The generated stub expands its runtime environment.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ ${1:-} == --version && ${2:-} == --machine ]]; then' \
    "  printf '%s\\n' '{\"frameworkVersion\":\"${flutter_version}\",\"dartSdkVersion\":\"${dart_version}\"}'" \
    '  exit 0' \
    'fi' \
    'printf '\''CALL flutter|%s\n'\'' "$*" >>"${TEST_COMMAND_LOG}"' \
    'if [[ ${1:-} == precache ]]; then exit "${FLUTTER_PRECACHE_STATUS:-0}"; fi' \
    'exit 2' >"${sdk_root}/bin/flutter"
  chmod +x "${sdk_root}/bin/flutter"
}

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

assert_log_contains() {
  local expected_line="$1"

  grep -Fqx -- "${expected_line}" "${TEST_COMMAND_LOG}" || fail "command log did not contain: ${expected_line}; log: $(<"${TEST_COMMAND_LOG}")"
}

run_flutter_setup() {
  run_cli setup --sdk flutter --sdk-version 3.44.0 --bootstrap none --persist-path none --no-merry "$@"
}

create_host_stub
create_metadata_stub
create_dart_sdk 3.12.0
create_flutter_sdk 3.44.0 3.12.0

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
grep -Fq 'setup completed' "${TEST_STDOUT}" && fail "success message printed after a failed precache"
pass "failing precache propagates status and suppresses success"
