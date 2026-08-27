#!/usr/bin/env bash
set -euo pipefail

HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HELPER_DIR
REPO_ROOT="$(cd "${HELPER_DIR}/.." && pwd)"
readonly REPO_ROOT
readonly ORIGINAL_TEST_PATH="${PATH}"
readonly CLI_PATH="${REPO_ROOT}/bin/merry-setup"

TEST_ROOT=""
TEST_STDOUT=""
TEST_STDERR=""
TEST_COMMAND_LOG=""
ACTUAL_STATUS=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  return 1
}

setup_test_env() {
  TEST_ROOT="$(mktemp -d /tmp/merry-setup-test.XXXXXX)"
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
  if [[ -n ${TEST_ROOT} && -d ${TEST_ROOT} && ${TEST_ROOT} == /tmp/merry-setup-test.* ]]; then
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

pass() {
  printf 'PASS: %s\n' "$1"
}
