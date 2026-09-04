#!/usr/bin/env bash
set -euo pipefail

SDK_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SDK_TEST_DIR
# shellcheck source=test/test_helper.sh
# shellcheck disable=SC1091 # The test suite supplies this repository-local helper.
source "${SDK_TEST_DIR}/test_helper.sh"

readonly FIXTURE_DIR="${SDK_TEST_DIR}/fixtures"
readonly DART_ARCHIVE_SHA256="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
readonly FLUTTER_ARCHIVE_SHA256="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

setup_test_env
trap cleanup_test_env EXIT

readonly archive_fixture="${TEST_ROOT}/sdk-archive"
readonly dart_checksum_fixture="${TEST_ROOT}/dart.sha256sum"
readonly invalid_metadata_fixture="${TEST_ROOT}/invalid-metadata.json"
readonly incomplete_flutter_fixture="${TEST_ROOT}/incomplete-flutter.json"

printf 'synthetic archive\n' >"${archive_fixture}"
printf '%s *dartsdk-linux-x64-release.zip\n' "${DART_ARCHIVE_SHA256}" >"${dart_checksum_fixture}"

export DART_VERSION_FIXTURE="${FIXTURE_DIR}/dart-version-3.12.0.json"
export DART_CHECKSUM_FIXTURE="${dart_checksum_fixture}"
export FLUTTER_RELEASES_FIXTURE="${FIXTURE_DIR}/flutter-releases.json"
export SDK_ARCHIVE_FIXTURE="${archive_fixture}"
export ARCHIVE_ACTUAL_SHA256="${DART_ARCHIVE_SHA256}"
export STAGED_DART_VERSION=3.12.0
export STAGED_FLUTTER_VERSION=3.44.0
export TEST_UNAME_S=Linux
export TEST_UNAME_M=x86_64

create_sdk_stubs() {
  local stub_path=""

  stub_path="${TEST_ROOT}/commands/uname"
  # shellcheck disable=SC2016 # The generated stub expands its runtime environment.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'case "${1:-}" in' \
    '-s) printf '\''%s\n'\'' "${TEST_UNAME_S}" ;;' \
    '-m) printf '\''%s\n'\'' "${TEST_UNAME_M}" ;;' \
    '*) exit 2 ;;' \
    'esac' >"${stub_path}"
  chmod +x "${stub_path}"

  stub_path="${TEST_ROOT}/commands/curl"
  # shellcheck disable=SC2016 # The generated stub expands its runtime environment.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'output_file=""' \
    'request_url=""' \
    'printf '\''COMMAND curl\n'\'' >>"${TEST_COMMAND_LOG}"' \
    'printf '\''ARG %s\n'\'' "$@" >>"${TEST_COMMAND_LOG}"' \
    'while (($# > 0)); do' \
    '  case "$1" in' \
    '  --output | --proto | --proto-redir) [[ $1 != --output ]] || output_file="$2"; shift 2 ;;' \
    '  --fail | --silent | --show-error | --location) shift ;;' \
    '  *) request_url="$1"; shift ;;' \
    '  esac' \
    'done' \
    '[[ -n ${output_file} && ${request_url} == https://* ]] || exit 2' \
    'if [[ -n ${CURL_FAIL_PATTERN:-} && ${request_url} == *"${CURL_FAIL_PATTERN}"* ]]; then exit 22; fi' \
    'if [[ -n ${CURL_FAIL_EXACT:-} && ${request_url} == "${CURL_FAIL_EXACT}" ]]; then exit 22; fi' \
    'case "${request_url}" in' \
    '*/VERSION) source_file="${DART_VERSION_FIXTURE}" ;;' \
    '*.sha256sum) source_file="${DART_CHECKSUM_FIXTURE}" ;;' \
    '*dartsdk-linux-x64-release.zip) source_file="${SDK_ARCHIVE_FIXTURE}" ;;' \
    '*releases_linux.json) source_file="${FLUTTER_RELEASES_FIXTURE}" ;;' \
    '*flutter_linux_*-stable.tar.xz) source_file="${SDK_ARCHIVE_FIXTURE}" ;;' \
    '*) exit 22 ;;' \
    'esac' \
    '[[ -f ${source_file} ]] || exit 22' \
    '/bin/cp "${source_file}" "${output_file}"' >"${stub_path}"
  chmod +x "${stub_path}"

  stub_path="${TEST_ROOT}/commands/sha256sum"
  # shellcheck disable=SC2016 # The generated stub expands its runtime environment.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf '\''COMMAND sha256sum\n'\'' >>"${TEST_COMMAND_LOG}"' \
    'printf '\''ARG %s\n'\'' "$@" >>"${TEST_COMMAND_LOG}"' \
    'if [[ -n ${ARCHIVE_SWAP_SOURCE:-} && -n ${ARCHIVE_SWAP_TARGET:-} ]]; then /bin/cp "${ARCHIVE_SWAP_SOURCE}" "${ARCHIVE_SWAP_TARGET}"; fi' \
    'printf '\''%s  %s\n'\'' "${ARCHIVE_ACTUAL_SHA256}" "$1"' >"${stub_path}"
  chmod +x "${stub_path}"

  stub_path="${TEST_ROOT}/commands/unzip"
  # shellcheck disable=SC2016 # The generated stub expands its runtime environment.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf '\''COMMAND unzip\n'\'' >>"${TEST_COMMAND_LOG}"' \
    'printf '\''ARG %s\n'\'' "$@" >>"${TEST_COMMAND_LOG}"' \
    '[[ ${EXTRACT_FAIL:-0} != 1 ]] || exit 9' \
    'if [[ -n ${FORBIDDEN_ARCHIVE_CONTENT:-} ]] && grep -Fqx -- "${FORBIDDEN_ARCHIVE_CONTENT}" "$2"; then exit 10; fi' \
    'extract_root=""' \
    'while (($# > 0)); do' \
    '  case "$1" in' \
    '  -d) extract_root="$2"; shift 2 ;;' \
    '  *) shift ;;' \
    '  esac' \
    'done' \
    'mkdir -p "${extract_root}/dart-sdk/bin" "${extract_root}/dart-sdk/include"' \
    'printf '\''%s\n'\'' '\''#!/usr/bin/env bash'\'' '\''printf "Dart SDK version: %s (stable) on linux_x64\\n" "${STAGED_DART_VERSION}" >&2'\'' >"${extract_root}/dart-sdk/bin/dart"' \
    'printf '\''synthetic Dart embedding API header\n'\'' >"${extract_root}/dart-sdk/include/dart_api.h"' \
    'if [[ ${STAGED_DART_AS_FLUTTER:-0} == 1 ]]; then printf '\''#!/usr/bin/env bash\n'\'' >"${extract_root}/dart-sdk/bin/flutter"; chmod +x "${extract_root}/dart-sdk/bin/flutter"; fi' \
    'chmod +x "${extract_root}/dart-sdk/bin/dart"' >"${stub_path}"
  chmod +x "${stub_path}"

  stub_path="${TEST_ROOT}/commands/tar"
  # shellcheck disable=SC2016 # The generated stub expands its runtime environment.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf '\''COMMAND tar\n'\'' >>"${TEST_COMMAND_LOG}"' \
    'printf '\''ARG %s\n'\'' "$@" >>"${TEST_COMMAND_LOG}"' \
    '[[ ${EXTRACT_FAIL:-0} != 1 ]] || exit 9' \
    'extract_root=""' \
    'while (($# > 0)); do' \
    '  case "$1" in' \
    '  -C) extract_root="$2"; shift 2 ;;' \
    '  *) shift ;;' \
    '  esac' \
    'done' \
    'mkdir -p "${extract_root}/flutter/bin"' \
    'printf '\''%s\n'\'' '\''#!/usr/bin/env bash'\'' '\''echo "{\"frameworkVersion\":\"${STAGED_FLUTTER_VERSION}\",\"dartSdkVersion\":\"${STAGED_DART_VERSION}\"}"'\'' >"${extract_root}/flutter/bin/flutter"' \
    'printf '\''%s\n'\'' '\''#!/usr/bin/env bash'\'' '\''printf "Dart SDK version: %s (stable) on linux_x64\\n" "${STAGED_DART_VERSION}" >&2'\'' >"${extract_root}/flutter/bin/dart"' \
    'chmod +x "${extract_root}/flutter/bin/flutter" "${extract_root}/flutter/bin/dart"' >"${stub_path}"
  chmod +x "${stub_path}"

  stub_path="${TEST_ROOT}/commands/mv"
  # shellcheck disable=SC2016 # The generated stub expands its runtime environment.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf '\''COMMAND mv\n'\'' >>"${TEST_COMMAND_LOG}"' \
    'printf '\''ARG %s\n'\'' "$@" >>"${TEST_COMMAND_LOG}"' \
    'source_dir="${@: -2:1}"' \
    'final_dir="${@: -1}"' \
    'if [[ ${PUBLISH_RACE:-0} == 1 ]]; then' \
    '  if [[ ${PUBLISH_RACE_TARGET:-sdk} == symlink ]]; then' \
    '    mkdir -p "${RACE_SYMLINK_TARGET}"' \
    '    ln -s "${RACE_SYMLINK_TARGET}" "${final_dir}"' \
    '  elif [[ ${PUBLISH_RACE_TARGET:-sdk} == invalid ]]; then' \
    '    mkdir -p "${final_dir}"' \
    '    printf '\''preserve\n'\'' >"${final_dir}/race-invalid"' \
    '  elif [[ ${RACE_FAMILY} == dart ]]; then' \
    '    mkdir -p "${final_dir}/bin" "${final_dir}/include"' \
    '    printf '\''%s\n'\'' '\''#!/usr/bin/env bash'\'' '\''printf "Dart SDK version: %s (stable) on linux_x64\\n" "${RACE_DART_VERSION}" >&2'\'' >"${final_dir}/bin/dart"' \
    '    printf '\''synthetic Dart embedding API header\n'\'' >"${final_dir}/include/dart_api.h"' \
    '    chmod +x "${final_dir}/bin/dart"' \
    '  else' \
    '    mkdir -p "${final_dir}/bin"' \
    '    printf '\''%s\n'\'' '\''#!/usr/bin/env bash'\'' '\''echo "{\"frameworkVersion\":\"${RACE_VERSION}\",\"dartSdkVersion\":\"${RACE_DART_VERSION}\"}"'\'' >"${final_dir}/bin/flutter"' \
    '    printf '\''%s\n'\'' '\''#!/usr/bin/env bash'\'' '\''printf "Dart SDK version: %s (stable) on linux_x64\\n" "${RACE_DART_VERSION}" >&2'\'' >"${final_dir}/bin/dart"' \
    '    chmod +x "${final_dir}/bin/flutter" "${final_dir}/bin/dart"' \
    '  fi' \
    '  exit "${RACE_MV_STATUS:-1}"' \
    'fi' \
    '[[ ! -e ${final_dir} && ! -L ${final_dir} ]] || exit 1' \
    '/bin/mv "${source_dir}" "${final_dir}"' >"${stub_path}"
  chmod +x "${stub_path}"
}

reset_case() {
  if [[ -d ${MERRY_SETUP_HOME} && ${MERRY_SETUP_HOME} == "${TEST_ROOT}/managed" ]]; then
    rm -rf -- "${MERRY_SETUP_HOME}"
  fi
  : >"${TEST_COMMAND_LOG}"
  : >"${TEST_STDOUT}"
  : >"${TEST_STDERR}"
  export DART_VERSION_FIXTURE="${FIXTURE_DIR}/dart-version-3.12.0.json"
  export DART_CHECKSUM_FIXTURE="${dart_checksum_fixture}"
  export FLUTTER_RELEASES_FIXTURE="${FIXTURE_DIR}/flutter-releases.json"
  export ARCHIVE_ACTUAL_SHA256="${DART_ARCHIVE_SHA256}"
  export STAGED_DART_VERSION=3.12.0
  export STAGED_FLUTTER_VERSION=3.44.0
  export TEST_UNAME_S=Linux
  export TEST_UNAME_M=x86_64
  unset ARCHIVE_SWAP_SOURCE ARCHIVE_SWAP_TARGET CURL_FAIL_PATTERN CURL_FAIL_EXACT EXTRACT_FAIL FORBIDDEN_ARCHIVE_CONTENT PUBLISH_RACE PUBLISH_RACE_TARGET RACE_FAMILY RACE_VERSION RACE_DART_VERSION RACE_MV_STATUS RACE_SYMLINK_TARGET STAGED_DART_AS_FLUTTER || true
}

run_setup() {
  local sdk_family="$1"
  local sdk_version="$2"

  run_cli setup --sdk "${sdk_family}" --sdk-version "${sdk_version}" --bootstrap none --persist-path none --no-merry --trunk-path "${TEST_ROOT}/launchers/trunk"
}

run_transport_setup() {
  local archive_path="$1"
  local archive_sha256="$2"

  run_cli setup --sdk dart --sdk-version 3.12.0 --bootstrap none --persist-path none --no-merry --trunk-path "${TEST_ROOT}/launchers/trunk" --sdk-archive "${archive_path}" --sdk-archive-sha256 "${archive_sha256}"
}

assert_archive_download_count() {
  local expected_count="$1"
  local actual_count=0

  actual_count="$(grep -E -c 'ARG https://.*/(dartsdk-linux-x64-release\.zip|flutter_linux_.*-stable\.tar\.xz)$' "${TEST_COMMAND_LOG}" || true)"
  [[ ${actual_count} -eq ${expected_count} ]] || fail "expected ${expected_count} SDK archive downloads, received ${actual_count}"
}

assert_no_staging_paths() {
  local family_root="$1"
  local staging_count=0

  if [[ -d ${family_root} ]]; then
    staging_count="$(find "${family_root}" -maxdepth 1 -name '.*.staging.*' -print | wc -l | tr -d ' ')"
  fi
  [[ ${staging_count} -eq 0 ]] || fail "staging paths remain under ${family_root}"
}

assert_stdout_contains() {
  local expected_text="$1"

  if ! grep -Fq -- "${expected_text}" "${TEST_STDOUT}"; then
    fail "stdout did not contain '${expected_text}'; actual: $(<"${TEST_STDOUT}")"
  fi
}

create_sdk_stubs
write_trunk_launcher_stub "${TEST_ROOT}/launchers/trunk"

reset_case
export TEST_UNAME_S=Darwin
run_setup dart 3.12.0
assert_nonzero
assert_stderr_contains "Unsupported operating system: Darwin."
assert_command_count 0 curl
pass "unsupported operating system fails before metadata lookup"

reset_case
export TEST_UNAME_M=arm64
run_setup dart 3.12.0
assert_nonzero
assert_stderr_contains "Unsupported architecture: arm64."
assert_command_count 0 curl
pass "unsupported architecture fails before metadata lookup"

reset_case
run_cli setup --sdk dart --sdk-version 3.12.0 --bootstrap none --persist-path none --no-merry --sdk-archive "${TEST_ROOT}/action-cache/sdk-archive"
assert_nonzero
assert_stderr_contains "Options '--sdk-archive' and '--sdk-archive-sha256' must be provided together."
assert_command_count 0 curl
assert_path_absent "${MERRY_SETUP_HOME}"
pass "archive transport options must be provided together"

reset_case
run_cli setup --sdk dart --sdk-version 3.12.0 --bootstrap none --persist-path none --no-merry --sdk-archive-sha256 "${DART_ARCHIVE_SHA256}"
assert_nonzero
assert_stderr_contains "Options '--sdk-archive' and '--sdk-archive-sha256' must be provided together."
assert_command_count 0 curl
assert_path_absent "${MERRY_SETUP_HOME}"
pass "archive checksum cannot be provided without its transport path"

reset_case
run_cli resolve --sdk dart --sdk-version 3.12.0 --bootstrap none --persist-path none --no-merry --sdk-archive "${TEST_ROOT}/action-cache/sdk-archive" --sdk-archive-sha256 "${DART_ARCHIVE_SHA256}"
assert_nonzero
assert_stderr_contains "Options '--sdk-archive' and '--sdk-archive-sha256' are valid only with 'setup'."
assert_command_count 0 curl
assert_path_absent "${MERRY_SETUP_HOME}"
pass "archive transport options are setup-only"

reset_case
run_transport_setup "${TEST_ROOT}/action-cache/sdk-archive" AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
assert_nonzero
assert_stderr_contains "Option '--sdk-archive-sha256' must be exactly 64 lowercase hexadecimal characters."
assert_command_count 0 curl
assert_path_absent "${MERRY_SETUP_HOME}"
pass "archive transport rejects a non-lowercase digest before metadata lookup"

reset_case
run_transport_setup relative/sdk-archive "${DART_ARCHIVE_SHA256}"
assert_nonzero
assert_stderr_contains "Option '--sdk-archive' must be an absolute path without control characters."
assert_command_count 0 curl
assert_path_absent "${MERRY_SETUP_HOME}"
pass "archive transport rejects a relative path before metadata lookup"

reset_case
run_transport_setup "${TEST_ROOT}/action-cache/sdk-archive"$'\ninvalid' "${DART_ARCHIVE_SHA256}"
assert_nonzero
assert_stderr_contains "Option '--sdk-archive' must be an absolute path without control characters."
assert_command_count 0 curl
assert_path_absent "${MERRY_SETUP_HOME}"
pass "archive transport rejects control characters before metadata lookup"

reset_case
mkdir -p "${TEST_ROOT}/archive-directory"
run_transport_setup "${TEST_ROOT}/archive-directory" "${DART_ARCHIVE_SHA256}"
assert_nonzero
assert_stderr_contains "Option '--sdk-archive' must be absent or point to a regular file."
assert_command_count 0 curl
assert_path_absent "${MERRY_SETUP_HOME}"
pass "archive transport rejects a directory before metadata lookup"

reset_case
printf 'target\n' >"${TEST_ROOT}/archive-target"
ln -s "${TEST_ROOT}/archive-target" "${TEST_ROOT}/archive-link"
run_transport_setup "${TEST_ROOT}/archive-link" "${DART_ARCHIVE_SHA256}"
assert_nonzero
assert_stderr_contains "Option '--sdk-archive' must not be a symbolic link."
assert_command_count 0 curl
assert_path_absent "${MERRY_SETUP_HOME}"
pass "archive transport rejects a symbolic link before metadata lookup"

reset_case
ln -s "${TEST_ROOT}/missing-archive-target" "${TEST_ROOT}/dangling-archive-link"
run_transport_setup "${TEST_ROOT}/dangling-archive-link" "${DART_ARCHIVE_SHA256}"
assert_nonzero
assert_stderr_contains "Option '--sdk-archive' must not be a symbolic link."
assert_command_count 0 curl
assert_path_absent "${MERRY_SETUP_HOME}"
pass "archive transport rejects a dangling symbolic link before metadata lookup"

reset_case
mkdir -p "${TEST_ROOT}/action-cache"
printf 'trusted restored archive\n' >"${TEST_ROOT}/action-cache/sdk-archive"
printf 'swapped untrusted archive\n' >"${TEST_ROOT}/swapped-sdk-archive"
export ARCHIVE_SWAP_SOURCE="${TEST_ROOT}/swapped-sdk-archive"
export ARCHIVE_SWAP_TARGET="${TEST_ROOT}/action-cache/sdk-archive"
export FORBIDDEN_ARCHIVE_CONTENT='swapped untrusted archive'
run_transport_setup "${TEST_ROOT}/action-cache/sdk-archive" "${DART_ARCHIVE_SHA256}"
assert_status 0
assert_archive_download_count 0
assert_path_exists "${MERRY_SETUP_HOME}/sdks/dart/3.12.0/bin/dart"
grep -Fqx 'swapped untrusted archive' "${TEST_ROOT}/action-cache/sdk-archive" || fail "archive swap canary did not replace the caller-owned path"
if grep -Fqx "ARG ${TEST_ROOT}/action-cache/sdk-archive" "${TEST_COMMAND_LOG}"; then fail "checksum or extraction reopened the caller-owned archive path"; fi
pass "restored archive bytes are snapshotted before verification and extraction"

reset_case
mkdir -p "${TEST_ROOT}/action-cache"
printf 'restored archive\n' >"${TEST_ROOT}/action-cache/sdk-archive"
run_transport_setup "${TEST_ROOT}/action-cache/sdk-archive" "${DART_ARCHIVE_SHA256}"
assert_status 0
assert_archive_download_count 0
assert_command_count 1 sha256sum
grep -Eq '^ARG .*/sdks/dart/\.3\.12\.0\.staging\.[^/]+/sdk-archive$' "${TEST_COMMAND_LOG}" || fail "restored Dart archive was not verified and extracted from private staging"
assert_path_exists "${MERRY_SETUP_HOME}/sdks/dart/3.12.0/bin/dart"
pass "a valid restored archive is verified from private staging without an upstream archive request"

reset_case
printf 'corrupt restored archive\n' >"${TEST_ROOT}/action-cache/corrupt-sdk-archive"
export ARCHIVE_ACTUAL_SHA256=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
run_transport_setup "${TEST_ROOT}/action-cache/corrupt-sdk-archive" "${DART_ARCHIVE_SHA256}"
assert_nonzero
assert_stderr_contains "SDK archive checksum mismatch."
assert_archive_download_count 0
assert_command_count 0 unzip
assert_path_absent "${MERRY_SETUP_HOME}/sdks/dart/3.12.0"
grep -Fqx 'corrupt restored archive' "${TEST_ROOT}/action-cache/corrupt-sdk-archive" || fail "corrupt restored archive was modified"
pass "a corrupt restored archive fails before extraction without an upstream fallback"

reset_case
printf '%s *dartsdk-linux-x64-release.zip\n' bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb >"${TEST_ROOT}/changed-dart.sha256sum"
export DART_CHECKSUM_FIXTURE="${TEST_ROOT}/changed-dart.sha256sum"
printf 'restored archive\n' >"${TEST_ROOT}/action-cache/drifted-sdk-archive"
run_transport_setup "${TEST_ROOT}/action-cache/drifted-sdk-archive" "${DART_ARCHIVE_SHA256}"
assert_nonzero
assert_stderr_contains "The supplied SDK archive checksum does not match current official release metadata."
assert_archive_download_count 0
assert_command_count 0 sha256sum
assert_command_count 0 unzip
assert_path_absent "${MERRY_SETUP_HOME}/sdks/dart/3.12.0"
pass "changed official metadata rejects the earlier checksum before archive access"

reset_case
run_transport_setup "${TEST_ROOT}/action-cache/cold/sdk-archive" "${DART_ARCHIVE_SHA256}"
assert_status 0
assert_archive_download_count 1
assert_path_exists "${TEST_ROOT}/action-cache/cold/sdk-archive"
assert_path_exists "${MERRY_SETUP_HOME}/sdks/dart/3.12.0/bin/dart"
[[ -z $(find "${TEST_ROOT}/action-cache/cold" -name '*.download.*' -print) ]] || fail "archive download temporary files remain"
pass "a cold transport download publishes a verified archive for an explicit save step"

reset_case
export CURL_FAIL_EXACT=https://storage.googleapis.com/dart-archive/channels/stable/release/3.12.0/sdk/dartsdk-linux-x64-release.zip
run_transport_setup "${TEST_ROOT}/action-cache/failed/sdk-archive" "${DART_ARCHIVE_SHA256}"
assert_nonzero
assert_stderr_contains "Failed to download Dart SDK archive"
assert_path_absent "${TEST_ROOT}/action-cache/failed/sdk-archive"
assert_path_absent "${MERRY_SETUP_HOME}/sdks/dart/3.12.0"
[[ -z $(find "${TEST_ROOT}/action-cache/failed" -name '*.download.*' -print) ]] || fail "failed archive download left temporary files"
pass "a failed cold transport download leaves no archive or SDK"

reset_case
create_dart_sdk 3.12.0
run_transport_setup "${TEST_ROOT}/action-cache/reused/sdk-archive" "${DART_ARCHIVE_SHA256}"
assert_status 0
assert_command_count 0 curl
assert_path_absent "${TEST_ROOT}/action-cache/reused/sdk-archive"
assert_stdout_contains "Reusing Dart SDK 3.12.0"
pass "a reused SDK does not require or create an archive transport path"

reset_case
printf '%s\n' \
  '{' \
  '  "date": "2026-05-18",' \
  '  "revision": "missing-version"' \
  '}' >"${invalid_metadata_fixture}"
export DART_VERSION_FIXTURE="${invalid_metadata_fixture}"
run_setup dart stable
assert_nonzero
assert_stderr_contains "Dart release metadata does not contain exactly one valid version."
assert_archive_download_count 0
pass "Dart metadata validator canary"

reset_case
sed '$d' "${FIXTURE_DIR}/dart-version-3.12.0.json" >"${invalid_metadata_fixture}"
export DART_VERSION_FIXTURE="${invalid_metadata_fixture}"
run_setup dart stable
assert_nonzero
assert_stderr_contains "Dart release metadata is incomplete or malformed."
assert_archive_download_count 0
pass "truncated Dart metadata fails closed"

reset_case
run_setup dart stable
assert_status 0
assert_stdout_contains "Merry setup completed"
assert_path_exists "${MERRY_SETUP_HOME}/sdks/dart/3.12.0/bin/dart"
assert_path_absent "${MERRY_SETUP_HOME}/sdks/dart/stable"
[[ ! -L ${MERRY_SETUP_HOME}/sdks/dart/stable ]] || fail "Dart stable alias is a dangling symlink"
assert_path_absent "${MERRY_SETUP_HOME}/sdks/dart/current"
[[ ! -L ${MERRY_SETUP_HOME}/sdks/dart/current ]] || fail "Dart current alias is a dangling symlink"
assert_archive_download_count 1
grep -Fqx 'ARG --no-clobber' "${TEST_COMMAND_LOG}" || fail "SDK publication did not request no-clobber semantics"
grep -Fqx 'ARG --no-target-directory' "${TEST_COMMAND_LOG}" || fail "SDK publication did not disable target-directory semantics"
assert_stdout_contains "Resolved SDK: family=dart version=3.12.0 host_architecture=x86_64 executable=${MERRY_SETUP_HOME}/sdks/dart/3.12.0/bin/dart"
pass "Dart stable resolves before exact final path derivation"

reset_case
run_setup dart 3.12.0
assert_status 0
assert_stdout_contains "Merry setup completed"
assert_path_exists "${MERRY_SETUP_HOME}/sdks/dart/3.12.0/bin/dart"
if grep -Fq '/release/latest/VERSION' "${TEST_COMMAND_LOG}"; then fail "exact Dart version fetched stable metadata"; fi
pass "exact Dart version skips stable metadata"

reset_case
run_setup dart 3.9.0
assert_nonzero
assert_stderr_contains "Effective Dart runtime 3.9.0 is below the minimum 3.12.0."
assert_archive_download_count 0
pass "semantic version comparison is not lexicographic"

reset_case
export DART_VERSION_FIXTURE="${FIXTURE_DIR}/dart-version-3.11.4.json"
run_setup dart stable
assert_nonzero
assert_stderr_contains "Effective Dart runtime 3.11.4 is below the minimum 3.12.0."
assert_archive_download_count 0
pass "Dart runtime floor blocks archive download"

reset_case
printf 'invalid checksum metadata\n' >"${dart_checksum_fixture}"
run_setup dart 3.12.0
assert_nonzero
assert_stderr_contains "Dart checksum metadata is missing or invalid."
assert_archive_download_count 0
pass "Dart checksum validator canary"
printf '%s *dartsdk-linux-x64-release.zip\n' "${DART_ARCHIVE_SHA256}" >"${dart_checksum_fixture}"

reset_case
export ARCHIVE_ACTUAL_SHA256=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
run_setup dart 3.12.0
assert_nonzero
assert_stderr_contains "SDK archive checksum mismatch."
assert_path_absent "${MERRY_SETUP_HOME}/sdks/dart/3.12.0"
assert_no_staging_paths "${MERRY_SETUP_HOME}/sdks/dart"
pass "checksum mismatch leaves no final or staging tree"

reset_case
export EXTRACT_FAIL=1
run_setup dart 3.12.0
assert_nonzero
assert_stderr_contains "Failed to extract Dart SDK archive."
assert_path_absent "${MERRY_SETUP_HOME}/sdks/dart/3.12.0"
assert_no_staging_paths "${MERRY_SETUP_HOME}/sdks/dart"
pass "extraction failure cleans sibling staging"

reset_case
export STAGED_DART_VERSION=3.12.1
run_setup dart 3.12.0
assert_nonzero
assert_stderr_contains "Staged Dart SDK does not match release metadata."
assert_path_absent "${MERRY_SETUP_HOME}/sdks/dart/3.12.0"
assert_no_staging_paths "${MERRY_SETUP_HOME}/sdks/dart"
pass "staged Dart version mismatch blocks publication"

reset_case
export STAGED_DART_AS_FLUTTER=1
run_setup dart 3.12.0
assert_nonzero
assert_stderr_contains "Staged Dart SDK does not match release metadata."
assert_path_absent "${MERRY_SETUP_HOME}/sdks/dart/3.12.0"
assert_no_staging_paths "${MERRY_SETUP_HOME}/sdks/dart"
pass "staged Dart archive with a Flutter launcher is rejected"

reset_case
export EXTRACT_FAIL=1
run_setup dart 3.12.0
first_staging="$(grep -E '^ARG .*/sdks/dart/\.3\.12\.0\.staging\.[^/]+/extract$' "${TEST_COMMAND_LOG}" | head -n 1)"
: >"${TEST_COMMAND_LOG}"
run_setup dart 3.12.0
second_staging="$(grep -E '^ARG .*/sdks/dart/\.3\.12\.0\.staging\.[^/]+/extract$' "${TEST_COMMAND_LOG}" | head -n 1)"
[[ -n ${first_staging} && -n ${second_staging} && ${first_staging} != "${second_staging}" ]] || fail "sibling staging directories were not unique"
assert_no_staging_paths "${MERRY_SETUP_HOME}/sdks/dart"
pass "staging directories are unique siblings"

reset_case
run_setup dart 3.12.0
: >"${TEST_COMMAND_LOG}"
run_setup dart 3.12.0
assert_status 0
assert_stdout_contains "Merry setup completed"
assert_command_count 0 curl
assert_command_count 0 unzip
pass "valid exact-version Dart SDK is reused"

reset_case
invalid_final="${MERRY_SETUP_HOME}/sdks/dart/3.12.0"
mkdir -p "${invalid_final}"
printf 'preserve\n' >"${invalid_final}/operator-file"
run_setup dart 3.12.0
assert_nonzero
assert_stderr_contains "Existing Dart SDK installation is invalid"
assert_path_exists "${invalid_final}/operator-file"
assert_command_count 0 curl
pass "invalid final directory is preserved and rejected"

reset_case
wrong_version_final="${MERRY_SETUP_HOME}/sdks/dart/3.12.0"
mkdir -p "${wrong_version_final}/bin" "${wrong_version_final}/include"
printf '%s\n' '#!/usr/bin/env bash' 'printf "Dart SDK version: 3.12.1 (stable) on linux_x64\\n" >&2' >"${wrong_version_final}/bin/dart"
printf 'synthetic Dart embedding API header\n' >"${wrong_version_final}/include/dart_api.h"
chmod +x "${wrong_version_final}/bin/dart"
run_setup dart 3.12.0
assert_nonzero
assert_stderr_contains "Existing Dart SDK installation is invalid"
assert_command_count 0 curl
pass "wrong-version existing Dart SDK is rejected"

reset_case
wrong_family_final="${MERRY_SETUP_HOME}/sdks/dart/3.12.0"
mkdir -p "${wrong_family_final}/bin"
printf '%s\n' '#!/usr/bin/env bash' 'printf "Dart SDK version: 3.12.0 (stable) on linux_x64\\n" >&2' >"${wrong_family_final}/bin/dart"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"${wrong_family_final}/bin/flutter"
chmod +x "${wrong_family_final}/bin/dart" "${wrong_family_final}/bin/flutter"
run_setup dart 3.12.0
assert_nonzero
assert_stderr_contains "Existing Dart SDK installation is invalid"
assert_command_count 0 curl
pass "wrong-family existing SDK is rejected as Dart"

reset_case
mkdir -p "${TEST_ROOT}/symlink-target" "${MERRY_SETUP_HOME}/sdks/dart"
ln -s "${TEST_ROOT}/symlink-target" "${MERRY_SETUP_HOME}/sdks/dart/3.12.0"
run_setup dart 3.12.0
assert_nonzero
assert_stderr_contains "Existing Dart SDK installation is invalid"
[[ -L ${MERRY_SETUP_HOME}/sdks/dart/3.12.0 ]] || fail "SDK symlink final was replaced"
assert_command_count 0 curl
pass "symbolic-link final path is preserved and rejected"

reset_case
export PUBLISH_RACE=1
export RACE_FAMILY=dart
export RACE_VERSION=3.12.0
export RACE_DART_VERSION=3.12.0
run_setup dart 3.12.0
assert_status 0
assert_stdout_contains "Merry setup completed"
assert_path_exists "${MERRY_SETUP_HOME}/sdks/dart/3.12.0/bin/dart"
assert_no_staging_paths "${MERRY_SETUP_HOME}/sdks/dart"
pass "publication loser validates and reuses race winner"

reset_case
export PUBLISH_RACE=1
export PUBLISH_RACE_TARGET=symlink
export RACE_MV_STATUS=0
export RACE_SYMLINK_TARGET="${TEST_ROOT}/race-symlink-target"
run_setup dart 3.12.0
assert_nonzero
assert_stderr_contains "Failed to publish Dart SDK 3.12.0 atomically."
[[ -L ${MERRY_SETUP_HOME}/sdks/dart/3.12.0 ]] || fail "race symlink final was replaced"
assert_no_staging_paths "${MERRY_SETUP_HOME}/sdks/dart"
pass "publication never replaces a race-created symbolic link"

reset_case
export PUBLISH_RACE=1
export PUBLISH_RACE_TARGET=invalid
export RACE_MV_STATUS=0
run_setup dart 3.12.0
assert_nonzero
assert_stderr_contains "Failed to publish Dart SDK 3.12.0 atomically."
assert_path_exists "${MERRY_SETUP_HOME}/sdks/dart/3.12.0/race-invalid"
assert_no_staging_paths "${MERRY_SETUP_HOME}/sdks/dart"
pass "publication rejects and preserves an invalid race-created final directory"

reset_case
sed '/"dart_sdk_arch"/d' "${FIXTURE_DIR}/flutter-releases.json" >"${incomplete_flutter_fixture}"
export FLUTTER_RELEASES_FIXTURE="${incomplete_flutter_fixture}"
run_setup flutter stable
assert_nonzero
assert_stderr_contains "Flutter release metadata does not provide Linux x64."
assert_archive_download_count 0
pass "Flutter architecture validator canary"

reset_case
sed -e '/"sha256"/d' -e 's/^\(      "archive": .*\),$/\1/' "${FIXTURE_DIR}/flutter-releases.json" >"${incomplete_flutter_fixture}"
export FLUTTER_RELEASES_FIXTURE="${incomplete_flutter_fixture}"
run_setup flutter stable
assert_nonzero
assert_stderr_contains "Flutter release metadata does not contain a valid checksum."
assert_archive_download_count 0
pass "Flutter checksum validator canary"

reset_case
sed '$d' "${FIXTURE_DIR}/flutter-releases.json" >"${incomplete_flutter_fixture}"
export FLUTTER_RELEASES_FIXTURE="${incomplete_flutter_fixture}"
run_setup flutter stable
assert_nonzero
assert_stderr_contains "Flutter release metadata is incomplete or malformed."
assert_archive_download_count 0
pass "truncated Flutter metadata fails closed"

reset_case
sed '/^  },$/d' "${FIXTURE_DIR}/flutter-releases.json" >"${incomplete_flutter_fixture}"
export FLUTTER_RELEASES_FIXTURE="${incomplete_flutter_fixture}"
run_setup flutter stable
assert_nonzero
assert_stderr_contains "Flutter release metadata is incomplete or malformed."
assert_archive_download_count 0
pass "unbalanced Flutter metadata fails closed"

reset_case
sed 's/^\(  "base_url": .*\),$/\1/' "${FIXTURE_DIR}/flutter-releases.json" >"${incomplete_flutter_fixture}"
export FLUTTER_RELEASES_FIXTURE="${incomplete_flutter_fixture}"
run_setup flutter stable
assert_nonzero
assert_stderr_contains "Flutter release metadata is incomplete or malformed."
assert_archive_download_count 0
pass "missing Flutter metadata member separator fails closed"

reset_case
run_setup flutter 3.41.6
assert_nonzero
assert_stderr_contains "Effective Dart runtime 3.11.4 is below the minimum 3.12.0."
assert_archive_download_count 0
pass "Flutter bundled Dart floor blocks archive download"

reset_case
export ARCHIVE_ACTUAL_SHA256="${FLUTTER_ARCHIVE_SHA256}"
run_setup flutter stable
assert_status 0
assert_stdout_contains "Merry setup completed"
assert_path_exists "${MERRY_SETUP_HOME}/sdks/flutter/3.44.0/bin/flutter"
assert_path_exists "${MERRY_SETUP_HOME}/sdks/flutter/3.44.0/bin/dart"
assert_path_absent "${MERRY_SETUP_HOME}/sdks/flutter/stable"
[[ ! -L ${MERRY_SETUP_HOME}/sdks/flutter/stable ]] || fail "Flutter stable alias is a dangling symlink"
assert_path_absent "${MERRY_SETUP_HOME}/sdks/flutter/current"
[[ ! -L ${MERRY_SETUP_HOME}/sdks/flutter/current ]] || fail "Flutter current alias is a dangling symlink"
assert_archive_download_count 1
assert_stdout_contains "Resolved SDK: family=flutter version=3.44.0 host_architecture=x86_64 executable=${MERRY_SETUP_HOME}/sdks/flutter/3.44.0/bin/flutter"
pass "Flutter stable resolves and accepts build-description Dart version"

reset_case
export ARCHIVE_ACTUAL_SHA256="${FLUTTER_ARCHIVE_SHA256}"
run_setup flutter 3.44.0
assert_status 0
assert_stdout_contains "Merry setup completed"
assert_path_exists "${MERRY_SETUP_HOME}/sdks/flutter/3.44.0/bin/flutter"
pass "exact Flutter release selects one stable manifest record"

reset_case
export ARCHIVE_ACTUAL_SHA256="${FLUTTER_ARCHIVE_SHA256}"
export STAGED_FLUTTER_VERSION=3.44.1
run_setup flutter 3.44.0
assert_nonzero
assert_stderr_contains "Staged Flutter SDK does not match release metadata."
assert_path_absent "${MERRY_SETUP_HOME}/sdks/flutter/3.44.0"
assert_no_staging_paths "${MERRY_SETUP_HOME}/sdks/flutter"
pass "staged Flutter version mismatch blocks publication"

reset_case
mkdir -p "${TEST_ROOT}/action-cache/flutter"
printf 'restored Flutter archive\n' >"${TEST_ROOT}/action-cache/flutter/sdk-archive"
export ARCHIVE_ACTUAL_SHA256="${FLUTTER_ARCHIVE_SHA256}"
run_cli setup --sdk flutter --sdk-version 3.44.0 --bootstrap none --persist-path none --no-merry --trunk-path "${TEST_ROOT}/launchers/trunk" --sdk-archive "${TEST_ROOT}/action-cache/flutter/sdk-archive" --sdk-archive-sha256 "${FLUTTER_ARCHIVE_SHA256}"
assert_status 0
assert_archive_download_count 0
assert_command_count 1 sha256sum
grep -Eq '^ARG .*/sdks/flutter/\.3\.44\.0\.staging\.[^/]+/sdk-archive$' "${TEST_COMMAND_LOG}" || fail "restored Flutter archive was not verified and extracted from private staging"
assert_path_exists "${MERRY_SETUP_HOME}/sdks/flutter/3.44.0/bin/flutter"
pass "Flutter setup verifies and installs a restored archive without an upstream archive request"
