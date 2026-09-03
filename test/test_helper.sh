#!/usr/bin/env bash
set -euo pipefail

HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HELPER_DIR
REPO_ROOT="$(cd "${HELPER_DIR}/.." && pwd)"
readonly REPO_ROOT
readonly ORIGINAL_TEST_PATH="${PATH}"
readonly CLI_PATH="${REPO_ROOT}/bin/merry-setup"

TEST_ROOT=""
TEST_TEMP_BASE=""
TEST_STDOUT=""
TEST_STDERR=""
TEST_COMMAND_LOG=""
ACTUAL_STATUS=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  return 1
}

setup_test_env() {
  TEST_TEMP_BASE="${TMPDIR:-/tmp}"
  [[ -d ${TEST_TEMP_BASE} ]] || fail "test temporary directory does not exist: ${TEST_TEMP_BASE}"
  TEST_TEMP_BASE="$(cd "${TEST_TEMP_BASE}" && pwd -P)"
  TEST_ROOT="$(mktemp -d "${TEST_TEMP_BASE}/merry-setup-test.XXXXXX")"
  TEST_STDOUT="${TEST_ROOT}/stdout"
  TEST_STDERR="${TEST_ROOT}/stderr"
  TEST_COMMAND_LOG="${TEST_ROOT}/commands.log"

  mkdir -p "${TEST_ROOT}/home" "${TEST_ROOT}/commands" "${TEST_ROOT}/project"
  : >"${TEST_COMMAND_LOG}"
  export HOME="${TEST_ROOT}/home"
  export MERRY_SETUP_HOME="${TEST_ROOT}/managed"
  export TEST_COMMAND_LOG
  export PATH="${TEST_ROOT}/commands:${ORIGINAL_TEST_PATH}"
  unset PUB_CACHE || true
}

cleanup_test_env() {
  if [[ -n ${TEST_ROOT} && -n ${TEST_TEMP_BASE} && -d ${TEST_ROOT} && ${TEST_ROOT} == "${TEST_TEMP_BASE}/merry-setup-test."* ]]; then
    rm -rf -- "${TEST_ROOT}"
  fi
}

create_recording_stub() {
  local command_name="$1"
  local stub_path="${TEST_ROOT}/commands/${command_name}"

  # shellcheck disable=SC2016 # The generated stub expands its runtime values.
  printf '%s\n' '#!/usr/bin/env bash' 'printf '\''COMMAND %s\n'\'' "$(basename "$0")" >>"${TEST_COMMAND_LOG}"' 'printf '\''ARG %s\n'\'' "$@" >>"${TEST_COMMAND_LOG}"' >"${stub_path}"
  chmod +x "${stub_path}"
}

run_cli() {
  set +e
  "${CLI_PATH}" "$@" >"${TEST_STDOUT}" 2>"${TEST_STDERR}"
  ACTUAL_STATUS=$?
  set -e
}

run_cli_in() {
  local working_directory="$1"
  shift

  set +e
  (
    cd "${working_directory}"
    "${CLI_PATH}" "$@"
  ) >"${TEST_STDOUT}" 2>"${TEST_STDERR}"
  ACTUAL_STATUS=$?
  set -e
}

assert_status() {
  local expected_status="$1"

  if [[ ${ACTUAL_STATUS} -ne ${expected_status} ]]; then
    fail "expected status ${expected_status}, received ${ACTUAL_STATUS}; stderr: $(<"${TEST_STDERR}")"
  fi
}

assert_nonzero() {
  if [[ ${ACTUAL_STATUS} -eq 0 ]]; then
    fail "expected a nonzero status; stdout: $(<"${TEST_STDOUT}")"
  fi
}

assert_stderr_contains() {
  local expected_text="$1"

  if ! grep -Fq -- "${expected_text}" "${TEST_STDERR}"; then
    fail "stderr did not contain '${expected_text}'; actual: $(<"${TEST_STDERR}")"
  fi
}

assert_stderr_excludes() {
  local unexpected_text="$1"

  if grep -Fq -- "${unexpected_text}" "${TEST_STDERR}"; then
    fail "stderr unexpectedly contained '${unexpected_text}'; actual: $(<"${TEST_STDERR}")"
  fi
}

assert_file_equals() {
  local expected_file="$1"
  local actual_file="$2"

  if ! cmp -s "${expected_file}" "${actual_file}"; then
    printf '%s\n' '--- expected' >&2
    sed -n '1,200p' "${expected_file}" >&2
    printf '%s\n' '--- actual' >&2
    sed -n '1,200p' "${actual_file}" >&2
    fail "files differ: ${expected_file} ${actual_file}"
  fi
}

assert_path_absent() {
  local target_path="$1"

  [[ ! -e ${target_path} ]] || fail "path should not exist: ${target_path}"
}

assert_path_exists() {
  local target_path="$1"

  [[ -e ${target_path} ]] || fail "path should exist: ${target_path}"
}

assert_command_count() {
  local expected_count="$1"
  local command_name="$2"
  local actual_count=0

  actual_count="$(grep -c -F "COMMAND ${command_name}" "${TEST_COMMAND_LOG}" || true)"
  [[ ${actual_count} -eq ${expected_count} ]] || fail "expected ${expected_count} ${command_name} calls, received ${actual_count}"
}

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
    'printf '\''ARG %s\n'\'' "$@" >>"${TEST_COMMAND_LOG}"' \
    'output_file=""' \
    'request_url=""' \
    'while (($# > 0)); do' \
    '  case "$1" in' \
    '  --output) output_file="$2"; shift 2 ;;' \
    '  --fail | --silent | --show-error | --location) shift ;;' \
    '  *) request_url="$1"; shift ;;' \
    '  esac' \
    'done' \
    'if [[ -n ${CURL_FAIL_PATTERN:-} && ${request_url} == *"${CURL_FAIL_PATTERN}"* ]]; then exit 22; fi' \
    'case "${request_url}" in' \
    '*/VERSION) source_file="${DART_VERSION_FIXTURE}" ;;' \
    '*releases_linux.json) source_file="${FLUTTER_RELEASES_FIXTURE}" ;;' \
    'https://trunk.io/releases/trunk) source_file="${TRUNK_LAUNCHER_FIXTURE:-}" ;;' \
    '*) exit 22 ;;' \
    'esac' \
    '[[ -f ${source_file} ]] || exit 22' \
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

write_trunk_launcher_stub() {
  local launcher_path="$1"

  mkdir -p "$(dirname "${launcher_path}")"
  # shellcheck disable=SC2016 # The generated stub expands its runtime environment.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf '\''CALL trunk|%s\n'\'' "$*" >>"${TEST_COMMAND_LOG}"' \
    'if [[ ${1:-} == version ]]; then printf '\''1.25.0\n'\''; exit "${TRUNK_VERSION_STATUS:-0}"; fi' \
    'exit 2' >"${launcher_path}"
  chmod +x "${launcher_path}"
}

assert_log_contains() {
  local expected_line="$1"

  grep -Fqx -- "${expected_line}" "${TEST_COMMAND_LOG}" || fail "command log did not contain: ${expected_line}; log: $(<"${TEST_COMMAND_LOG}")"
}

assert_log_excludes() {
  local unexpected_text="$1"

  if grep -Fq -- "${unexpected_text}" "${TEST_COMMAND_LOG}"; then
    fail "command log unexpectedly contained: ${unexpected_text}"
  fi
}

assert_stdout_contains() {
  local expected_text="$1"

  grep -Fq -- "${expected_text}" "${TEST_STDOUT}" || fail "stdout did not contain: ${expected_text}; actual: $(<"${TEST_STDOUT}")"
}

assert_stdout_excludes() {
  local unexpected_text="$1"

  if grep -Fq -- "${unexpected_text}" "${TEST_STDOUT}"; then
    fail "stdout unexpectedly contained: ${unexpected_text}"
  fi
}

pass() {
  printf 'PASS: %s\n' "$1"
}
