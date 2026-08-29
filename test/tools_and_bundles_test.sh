#!/usr/bin/env bash
set -euo pipefail

TOOLS_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TOOLS_TEST_DIR

if [[ -z ${MERRY_SETUP_TEST_CASE:-} ]]; then
  readonly cases=(
    managed_dart_cache_and_merry
    stable_managed_cache
    managed_flutter_cache
    explicit_pub_cache
    exact_version_cache_separation
    empty_pub_cache
    relative_pub_cache
    control_character_pub_cache
    path_delimiter_pub_cache
    merry_opt_out
    empty_merry_opt_out_conflict
    merry_version
    empty_merry_version
    option_like_merry_version
    explicit_and_implicit_packages
    implicit_melos
    implicit_very_good
    duplicate_package
    forbidden_merry_package
    empty_package_entry
    empty_package_constraint
    control_character_package
    invalid_package_constraint
    invalid_package_name
    reserved_package_name
    flutterfire_exact_version
    flutterfire_version_mismatch
    flutterfire_default_version
    standalone_flutterfire_cli
    duplicate_bundle
    empty_bundle
    unknown_bundle
    firebase_version_without_bundle
    invalid_firebase_version
    flutterfire_uses_npm_prefix_executable
    flutterfire_uses_validated_npm
    invalid_npm_prefix
    flutterfire_precedes_activated_node
    missing_npm
    failed_npm_install
    failed_activation_preserves_cache
  )
  failed_cases=0

  for case_name in "${cases[@]}"; do
    if MERRY_SETUP_TEST_CASE="${case_name}" "${BASH}" "${BASH_SOURCE[0]}"; then
      :
    else
      printf 'FAIL: tools and bundles case %s\n' "${case_name}" >&2
      ((failed_cases += 1))
    fi
  done

  ((failed_cases == 0)) || exit 1
  exit 0
fi

# shellcheck source=test/test_helper.sh
# shellcheck disable=SC1091 # The test suite supplies this repository-local helper.
source "${TOOLS_TEST_DIR}/test_helper.sh"

setup_test_env
trap cleanup_test_env EXIT

readonly FIXTURE_DIR="${TOOLS_TEST_DIR}/fixtures"

printf 'name: fixture\n' >"${TEST_ROOT}/project/pubspec.yaml"

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

write_dart_executable() {
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
    'printf '\''CALL dart|PUB_CACHE=%s'\'' "${PUB_CACHE:-<unset>}" >>"${TEST_COMMAND_LOG}"' \
    'printf '\''|%s'\'' "$@" >>"${TEST_COMMAND_LOG}"' \
    'printf '\''\n'\'' >>"${TEST_COMMAND_LOG}"' \
    'if [[ ${1:-} == pub && ${2:-} == global && ${3:-} == activate ]]; then' \
    '  package_name="${4:-}"' \
    '  if [[ ${DART_ACTIVATE_FAIL_PACKAGE:-} == "${package_name}" ]]; then exit 17; fi' \
    '  mkdir -p "${PUB_CACHE}/bin"' \
    '  printf '\''%s 9.9.9\n'\'' "${package_name}" >>"${PUB_CACHE}/.global-list"' \
    '  tool_name=""' \
    '  case "${package_name}" in' \
    '  merry | melos) tool_name="${package_name}" ;;' \
    '  very_good_cli) tool_name=very_good ;;' \
    '  flutterfire_cli) tool_name=flutterfire ;;' \
    '  node_tool) tool_name=node ;;' \
    '  esac' \
    '  if [[ -n ${tool_name} ]]; then' \
    '    printf '\''#!/usr/bin/env bash\nprintf "CALL %s|%%s\\n" "$@" >>"%s"\nprintf "9.9.9\\n"\n'\'' "${tool_name}" "${TEST_COMMAND_LOG}" >"${PUB_CACHE}/bin/${tool_name}"' \
    '    chmod +x "${PUB_CACHE}/bin/${tool_name}"' \
    '  fi' \
    '  exit 0' \
    'fi' \
    'if [[ ${1:-} == pub && ${2:-} == global && ${3:-} == list ]]; then' \
    '  [[ ! -f ${PUB_CACHE}/.global-list ]] || cat "${PUB_CACHE}/.global-list"' \
    '  exit 0' \
    'fi' \
    'exit 2' >"${dart_path}"
  chmod +x "${dart_path}"
}

create_dart_sdk() {
  local sdk_version="$1"
  local sdk_root="${MERRY_SETUP_HOME}/sdks/dart/${sdk_version}"

  mkdir -p "${sdk_root}/include"
  printf 'synthetic Dart embedding API header\n' >"${sdk_root}/include/dart_api.h"
  write_dart_executable "${sdk_root}/bin/dart" "${sdk_version}"
}

create_flutter_sdk() {
  local flutter_version="$1"
  local dart_version="$2"
  local sdk_root="${MERRY_SETUP_HOME}/sdks/flutter/${flutter_version}"

  write_dart_executable "${sdk_root}/bin/dart" "${dart_version}"
  # shellcheck disable=SC2016 # The generated stub expands no user-controlled values.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    "printf '%s\\n' '{\"frameworkVersion\":\"${flutter_version}\",\"dartSdkVersion\":\"${dart_version}\"}'" >"${sdk_root}/bin/flutter"
  chmod +x "${sdk_root}/bin/flutter"
}

create_metadata_stub() {
  local stub_path="${TEST_ROOT}/commands/curl"

  # shellcheck disable=SC2016 # The generated stub expands its runtime environment.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
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

create_npm_stub() {
  local stub_path="${TEST_ROOT}/commands/npm"

  export NPM_GLOBAL_PREFIX="${TEST_ROOT}/npm-prefix"

  # shellcheck disable=SC2016 # The generated stub expands its runtime environment.
  printf '%s\n' \
    '#!/usr/bin/env node' \
    'set -euo pipefail' \
    'printf '\''CALL npm'\'' >>"${TEST_COMMAND_LOG}"' \
    'printf '\''|%s'\'' "$@" >>"${TEST_COMMAND_LOG}"' \
    'printf '\''\n'\'' >>"${TEST_COMMAND_LOG}"' \
    'if [[ ${1:-} == prefix && ${2:-} == --global && $# -eq 2 ]]; then printf '\''%s\n'\'' "${NPM_GLOBAL_PREFIX}"; exit 0; fi' \
    '[[ ${NPM_INSTALL_FAIL:-0} != 1 ]] || exit 19' \
    'firebase_version=15.0.0' \
    'if [[ ${*: -1} == firebase-tools@* ]]; then firebase_version="${*: -1}"; firebase_version="${firebase_version#firebase-tools@}"; fi' \
    'if [[ -n ${FIREBASE_REPORTED_VERSION:-} ]]; then firebase_version="${FIREBASE_REPORTED_VERSION}"; fi' \
    'mkdir -p "${NPM_GLOBAL_PREFIX}/bin"' \
    'printf '\''#!/usr/bin/env bash\nprintf "CALL npm-prefix-firebase|%%s\\n" "$@" >>"%s"\nprintf "%%s\\n" "%s"\n'\'' "${TEST_COMMAND_LOG}" "${firebase_version}" >"${NPM_GLOBAL_PREFIX}/bin/firebase"' \
    'chmod +x "${NPM_GLOBAL_PREFIX}/bin/firebase"' >"${stub_path}"
  chmod +x "${stub_path}"
}

create_node_stub() {
  local stub_path="${TEST_ROOT}/commands/node"

  printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'exec /bin/bash "$@"' >"${stub_path}"
  chmod +x "${stub_path}"
}

assert_log_contains() {
  local expected_line="$1"

  grep -Fqx -- "${expected_line}" "${TEST_COMMAND_LOG}" || fail "command log did not contain: ${expected_line}"
}

assert_log_excludes() {
  local unexpected_text="$1"

  if grep -Fq -- "${unexpected_text}" "${TEST_COMMAND_LOG}"; then
    fail "command log unexpectedly contained: ${unexpected_text}"
  fi
}

assert_stdout_contains() {
  local expected_text="$1"

  grep -Fq -- "${expected_text}" "${TEST_STDOUT}" || fail "stdout did not contain: ${expected_text}"
}

run_setup() {
  local sdk_family="$1"
  local sdk_version="$2"
  local bootstrap_strategy="$3"
  shift 3

  run_cli setup \
    --sdk "${sdk_family}" \
    --sdk-version "${sdk_version}" \
    --bootstrap "${bootstrap_strategy}" \
    --persist-path none \
    --project-dir "${TEST_ROOT}/project" \
    "$@"
}

prepare_dart_case() {
  local sdk_version="${1:-3.12.0}"

  create_host_stub
  create_metadata_stub
  create_npm_stub
  create_node_stub
  create_dart_sdk "${sdk_version}"
  export DART_VERSION_FIXTURE="${FIXTURE_DIR}/dart-version-3.12.0.json"
  export FLUTTER_RELEASES_FIXTURE="${FIXTURE_DIR}/flutter-releases.json"
}

prepare_flutter_case() {
  create_host_stub
  create_metadata_stub
  create_npm_stub
  create_node_stub
  create_flutter_sdk 3.44.0 3.12.0
  export DART_VERSION_FIXTURE="${FIXTURE_DIR}/dart-version-3.12.0.json"
  export FLUTTER_RELEASES_FIXTURE="${FIXTURE_DIR}/flutter-releases.json"
}

case_managed_dart_cache_and_merry() {
  prepare_dart_case
  run_setup dart 3.12.0 none
  assert_nonzero
  assert_log_contains "CALL dart|PUB_CACHE=${MERRY_SETUP_HOME}/pub-cache/dart/3.12.0|pub|global|activate|merry"
  assert_log_contains "CALL dart|PUB_CACHE=${MERRY_SETUP_HOME}/pub-cache/dart/3.12.0|pub|global|list"
  assert_stdout_contains 'Activated Dart package: name=merry version=9.9.9'
  assert_log_contains 'CALL merry|--version'
  assert_stdout_contains 'Tool version: package=merry executable=merry version=9.9.9'
  assert_log_excludes '|install|'
  pass "managed Dart cache activates Merry by default"
}

case_stable_managed_cache() {
  prepare_dart_case
  run_setup dart stable none
  assert_nonzero
  assert_log_contains "CALL dart|PUB_CACHE=${MERRY_SETUP_HOME}/pub-cache/dart/3.12.0|pub|global|activate|merry"
  assert_log_excludes '/pub-cache/dart/stable'
  pass "stable resolves before managed cache derivation"
}

case_managed_flutter_cache() {
  prepare_flutter_case
  run_setup flutter 3.44.0 none
  assert_nonzero
  assert_log_contains "CALL dart|PUB_CACHE=${MERRY_SETUP_HOME}/pub-cache/flutter/3.44.0|pub|global|activate|merry"
  assert_log_excludes '/pub-cache/flutter/3.12.0'
  pass "managed Flutter cache is keyed by Flutter version"
}

case_explicit_pub_cache() {
  prepare_dart_case
  export PUB_CACHE="${TEST_ROOT}/explicit pub cache"
  run_setup dart 3.12.0 none
  assert_nonzero
  assert_log_contains "CALL dart|PUB_CACHE=${PUB_CACHE}|pub|global|activate|merry"
  assert_log_excludes "${MERRY_SETUP_HOME}/pub-cache"
  pass "explicit PUB_CACHE overrides managed cache"
}

case_exact_version_cache_separation() {
  prepare_dart_case 3.12.0
  create_dart_sdk 3.13.0
  run_setup dart 3.12.0 none
  assert_nonzero
  run_setup dart 3.13.0 none
  assert_nonzero
  assert_log_contains "CALL dart|PUB_CACHE=${MERRY_SETUP_HOME}/pub-cache/dart/3.12.0|pub|global|activate|merry"
  assert_log_contains "CALL dart|PUB_CACHE=${MERRY_SETUP_HOME}/pub-cache/dart/3.13.0|pub|global|activate|merry"
  pass "managed caches separate exact SDK versions"
}

case_empty_pub_cache() {
  prepare_dart_case
  export PUB_CACHE=''
  run_setup dart 3.12.0 none
  assert_nonzero
  assert_stderr_contains 'PUB_CACHE must be a nonempty absolute path.'
  assert_log_excludes 'CALL dart'
  pass "empty PUB_CACHE fails before activation"
}

case_relative_pub_cache() {
  prepare_dart_case
  export PUB_CACHE='relative/cache'
  run_setup dart 3.12.0 none
  assert_nonzero
  assert_stderr_contains 'PUB_CACHE must be a nonempty absolute path.'
  assert_log_excludes 'CALL dart'
  pass "relative PUB_CACHE fails before activation"
}

case_control_character_pub_cache() {
  prepare_dart_case
  export PUB_CACHE="${TEST_ROOT}/cache"$'\ninvalid'
  run_setup dart 3.12.0 none
  assert_nonzero
  assert_stderr_contains 'PUB_CACHE must be a nonempty absolute path.'
  assert_log_excludes 'CALL dart'
  pass "control-character PUB_CACHE fails before activation"
}

case_path_delimiter_pub_cache() {
  prepare_dart_case
  export PUB_CACHE="${TEST_ROOT}/cache:segment"
  run_setup dart 3.12.0 none
  assert_nonzero
  assert_stderr_contains 'PUB_CACHE must be a nonempty absolute path.'
  assert_log_excludes 'CALL dart'
  pass "PATH-delimiter PUB_CACHE fails before activation"
}

case_merry_opt_out() {
  prepare_dart_case
  run_setup dart 3.12.0 none --no-merry
  assert_nonzero
  assert_log_excludes '|pub|global|activate|merry'
  assert_log_excludes '|pub|global|list'
  pass "Merry opt-out produces no activation"
}

case_empty_merry_opt_out_conflict() {
  prepare_dart_case
  run_setup dart 3.12.0 none --no-merry --merry-version ''
  assert_nonzero
  assert_stderr_contains "Option '--merry-version' conflicts with '--no-merry'."
  assert_log_excludes 'CALL dart'
  pass "explicit empty Merry version still conflicts with opt-out"
}

case_merry_version() {
  prepare_dart_case
  run_setup dart 3.12.0 none --merry-version '^2.3.0'
  assert_nonzero
  assert_log_contains "CALL dart|PUB_CACHE=${MERRY_SETUP_HOME}/pub-cache/dart/3.12.0|pub|global|activate|merry|^2.3.0"
  pass "Merry version is passed as a separate constraint"
}

case_empty_merry_version() {
  prepare_dart_case
  run_setup dart 3.12.0 none --merry-version ''
  assert_nonzero
  assert_stderr_contains "Option '--merry-version' has an invalid constraint."
  assert_log_excludes 'CALL dart'
  pass "empty Merry constraints fail before activation"
}

case_option_like_merry_version() {
  prepare_dart_case
  run_setup dart 3.12.0 none --merry-version '-h'
  assert_nonzero
  assert_stderr_contains "Option '--merry-version' has an invalid constraint."
  assert_log_excludes 'CALL dart'
  pass "option-like Merry constraints fail before activation"
}

case_explicit_and_implicit_packages() {
  prepare_dart_case
  run_setup dart 3.12.0 melos --dart-package 'melos=^8.0.0' --dart-package 'custom_tool=>=1.0.0 <2.0.0'
  assert_nonzero
  assert_log_contains "CALL dart|PUB_CACHE=${MERRY_SETUP_HOME}/pub-cache/dart/3.12.0|pub|global|activate|melos|^8.0.0"
  assert_log_contains "CALL dart|PUB_CACHE=${MERRY_SETUP_HOME}/pub-cache/dart/3.12.0|pub|global|activate|custom_tool|>=1.0.0 <2.0.0"
  [[ $(grep -c -F '|pub|global|activate|melos' "${TEST_COMMAND_LOG}") -eq 1 ]] || fail 'Melos activated more than once'
  assert_log_contains 'CALL melos|--version'
  assert_stdout_contains 'Tool version: package=melos executable=melos version=9.9.9'
  pass "explicit constraints configure one package-plan entry"
}

case_implicit_melos() {
  prepare_dart_case
  run_setup dart 3.12.0 melos --no-merry
  assert_nonzero
  assert_log_contains "CALL dart|PUB_CACHE=${MERRY_SETUP_HOME}/pub-cache/dart/3.12.0|pub|global|activate|melos"
  pass "Melos bootstrap implies one global package"
}

case_implicit_very_good() {
  prepare_dart_case
  run_setup dart 3.12.0 very-good --no-merry
  assert_nonzero
  assert_log_contains "CALL dart|PUB_CACHE=${MERRY_SETUP_HOME}/pub-cache/dart/3.12.0|pub|global|activate|very_good_cli"
  assert_log_contains 'CALL very_good|--version'
  assert_stdout_contains 'Tool version: package=very_good_cli executable=very_good version=9.9.9'
  pass "Very Good bootstrap implies one global package"
}

case_duplicate_package() {
  prepare_dart_case
  run_setup dart 3.12.0 none --dart-package 'melos=^8.0.0' --dart-package 'melos=^8.0.0'
  assert_nonzero
  assert_stderr_contains "Dart package 'melos' was provided more than once."
  assert_log_excludes 'CALL dart'
  pass "duplicate package names fail before activation"
}

case_forbidden_merry_package() {
  prepare_dart_case
  run_setup dart 3.12.0 none --dart-package 'merry=2.3.0'
  assert_nonzero
  assert_stderr_contains "Dart package 'merry' must be configured through Merry options."
  assert_log_excludes 'CALL dart'
  pass "additional Merry package input is forbidden"
}

case_empty_package_entry() {
  prepare_dart_case
  run_setup dart 3.12.0 none --dart-package ''
  assert_nonzero
  assert_stderr_contains 'Invalid Dart package entry.'
  assert_log_excludes 'CALL dart'
  pass "empty package entries fail before activation"
}

case_empty_package_constraint() {
  prepare_dart_case
  run_setup dart 3.12.0 none --dart-package 'melos='
  assert_nonzero
  assert_stderr_contains "Dart package 'melos' has an empty constraint."
  assert_log_excludes 'CALL dart'
  pass "empty package constraints fail before activation"
}

case_control_character_package() {
  prepare_dart_case
  run_setup dart 3.12.0 none --dart-package $'melos\nother'
  assert_nonzero
  assert_stderr_contains 'Invalid Dart package entry.'
  assert_log_excludes 'CALL dart'
  pass "control-character package entries fail before activation"
}

case_invalid_package_constraint() {
  prepare_dart_case
  run_setup dart 3.12.0 none --dart-package 'melos=-h'
  assert_nonzero
  assert_stderr_contains "Dart package 'melos' has an invalid constraint."
  assert_log_excludes 'CALL dart'
  pass "option-like package constraints fail before activation"
}

case_invalid_package_name() {
  prepare_dart_case
  run_setup dart 3.12.0 none --dart-package 'Bad-Package=1.0.0'
  assert_nonzero
  assert_stderr_contains "Invalid Dart package name: 'Bad-Package'."
  assert_log_excludes 'CALL dart'
  pass "invalid package names fail before activation"
}

case_reserved_package_name() {
  prepare_dart_case
  run_setup dart 3.12.0 none --dart-package class
  assert_nonzero
  assert_stderr_contains "Invalid Dart package name: 'class'."
  assert_log_excludes 'CALL dart'
  pass "Dart reserved words are invalid package names"
}

case_flutterfire_exact_version() {
  prepare_flutter_case
  run_setup flutter 3.44.0 none --bundle flutterfire --dart-package 'flutterfire_cli=^1.4.0' --firebase-tools-version 14.2.1
  assert_nonzero
  assert_log_contains "CALL dart|PUB_CACHE=${MERRY_SETUP_HOME}/pub-cache/flutter/3.44.0|pub|global|activate|flutterfire_cli|^1.4.0"
  [[ $(grep -c -F '|pub|global|activate|flutterfire_cli' "${TEST_COMMAND_LOG}") -eq 1 ]] || fail 'FlutterFire CLI activated more than once'
  assert_log_contains 'CALL npm|install|--global|firebase-tools@14.2.1'
  assert_log_contains 'CALL flutterfire|--version'
  assert_stdout_contains 'Firebase Tools version: 14.2.1'
  pass "FlutterFire exact versions install one coupled bundle"
}

case_flutterfire_version_mismatch() {
  prepare_flutter_case
  export FIREBASE_REPORTED_VERSION=14.2.0
  run_setup flutter 3.44.0 none --bundle flutterfire --firebase-tools-version 14.2.1 --no-merry
  assert_nonzero
  assert_stderr_contains 'Installed Firebase Tools version 14.2.0 does not match requested version 14.2.1.'
  assert_stderr_excludes 'Remaining setup steps are not implemented'
  pass "Firebase Tools exact-version mismatch fails after installation"
}

case_flutterfire_default_version() {
  prepare_flutter_case
  run_setup flutter 3.44.0 none --bundle flutterfire --no-merry
  assert_nonzero
  assert_log_contains "CALL dart|PUB_CACHE=${MERRY_SETUP_HOME}/pub-cache/flutter/3.44.0|pub|global|activate|flutterfire_cli"
  assert_log_contains 'CALL npm|install|--global|firebase-tools'
  assert_stdout_contains 'Firebase Tools version: 15.0.0'
  pass "FlutterFire omission uses npm default selection"
}

case_standalone_flutterfire_cli() {
  prepare_dart_case
  run_setup dart 3.12.0 none --dart-package flutterfire_cli --no-merry
  assert_nonzero
  assert_log_contains "CALL dart|PUB_CACHE=${MERRY_SETUP_HOME}/pub-cache/dart/3.12.0|pub|global|activate|flutterfire_cli"
  assert_log_excludes 'CALL npm'
  pass "standalone FlutterFire CLI has no npm side effect"
}

case_duplicate_bundle() {
  prepare_flutter_case
  run_setup flutter 3.44.0 none --bundle flutterfire --bundle flutterfire
  assert_nonzero
  assert_stderr_contains "Bundle 'flutterfire' was provided more than once."
  assert_log_excludes 'CALL dart'
  assert_log_excludes 'CALL npm'
  pass "duplicate bundles fail before mutation"
}

case_empty_bundle() {
  prepare_flutter_case
  run_setup flutter 3.44.0 none --bundle ''
  assert_nonzero
  assert_stderr_contains 'Invalid bundle name.'
  assert_log_excludes 'CALL dart'
  assert_log_excludes 'CALL npm'
  pass "empty bundle names fail before mutation"
}

case_unknown_bundle() {
  prepare_flutter_case
  run_setup flutter 3.44.0 none --bundle unknown
  assert_nonzero
  assert_stderr_contains "Unsupported bundle: 'unknown'."
  assert_log_excludes 'CALL dart'
  pass "unknown bundles fail before mutation"
}

case_firebase_version_without_bundle() {
  prepare_dart_case
  run_setup dart 3.12.0 none --firebase-tools-version 14.2.1
  assert_nonzero
  assert_stderr_contains "Option '--firebase-tools-version' requires the 'flutterfire' bundle."
  assert_log_excludes 'CALL dart'
  pass "Firebase Tools version requires FlutterFire bundle"
}

case_invalid_firebase_version() {
  prepare_flutter_case
  run_setup flutter 3.44.0 none --bundle flutterfire --firebase-tools-version latest
  assert_nonzero
  assert_stderr_contains "Option '--firebase-tools-version' must be an exact semantic version."
  assert_log_excludes 'CALL dart'
  pass "invalid Firebase Tools version fails before mutation"
}

case_flutterfire_uses_npm_prefix_executable() {
  prepare_flutter_case
  # shellcheck disable=SC2016 # The generated stub expands its runtime environment.
  printf '%s\n' '#!/usr/bin/env bash' 'printf "CALL stale-firebase|%s\\n" "$@" >>"${TEST_COMMAND_LOG}"' 'printf "14.2.1\\n"' >"${TEST_ROOT}/commands/firebase"
  chmod +x "${TEST_ROOT}/commands/firebase"
  run_setup flutter 3.44.0 none --bundle flutterfire --firebase-tools-version 14.2.1 --no-merry
  assert_nonzero
  assert_log_contains 'CALL npm|prefix|--global'
  assert_log_contains 'CALL npm-prefix-firebase|--version'
  assert_log_excludes 'CALL stale-firebase|--version'
  assert_stdout_contains 'Firebase Tools version: 14.2.1'
  pass "FlutterFire validates npm-prefix Firebase Tools over stale PATH entry"
}

case_flutterfire_uses_validated_npm() {
  prepare_flutter_case
  export PUB_CACHE="${TEST_ROOT}/explicit-cache"
  mkdir -p "${PUB_CACHE}/bin"
  # shellcheck disable=SC2016 # The generated stub expands its runtime environment.
  printf '%s\n' '#!/usr/bin/env bash' 'printf "CALL fake-pub-cache-npm|%s\\n" "$@" >>"${TEST_COMMAND_LOG}"' 'exit 27' >"${PUB_CACHE}/bin/npm"
  chmod +x "${PUB_CACHE}/bin/npm"
  run_setup flutter 3.44.0 none --bundle flutterfire --no-merry
  assert_nonzero
  assert_log_contains 'CALL npm|install|--global|firebase-tools'
  assert_log_contains 'CALL npm|prefix|--global'
  assert_log_excludes 'CALL fake-pub-cache-npm'
  assert_stdout_contains 'Firebase Tools version: 15.0.0'
  pass "FlutterFire uses npm resolved before PUB_CACHE changes PATH"
}

case_invalid_npm_prefix() {
  prepare_flutter_case
  export NPM_GLOBAL_PREFIX="${TEST_ROOT}/bad:prefix"
  run_setup flutter 3.44.0 none --bundle flutterfire --no-merry
  assert_nonzero
  assert_stderr_contains 'npm global prefix must be a nonempty absolute path.'
  assert_log_contains 'CALL npm|prefix|--global'
  assert_log_excludes 'CALL npm|install|--global|firebase-tools'
  assert_path_absent "${NPM_GLOBAL_PREFIX}"
  pass "invalid npm prefix fails before global installation"
}

case_flutterfire_precedes_activated_node() {
  prepare_flutter_case
  run_setup flutter 3.44.0 none --bundle flutterfire --dart-package node_tool --no-merry
  assert_nonzero
  assert_log_contains 'CALL npm|prefix|--global'
  assert_log_contains 'CALL npm|install|--global|firebase-tools'
  assert_log_excludes 'CALL node|'
  assert_stdout_contains 'Firebase Tools version: 15.0.0'
  pass "FlutterFire npm runs before activated tools change PATH"
}

case_missing_npm() {
  local original_path="${PATH}"

  prepare_flutter_case
  rm -f "${TEST_ROOT}/commands/npm"
  ln -s "${BASH}" "${TEST_ROOT}/commands/bash"
  ln -s "$(command -v mkdir)" "${TEST_ROOT}/commands/mkdir"
  ln -s "$(command -v mktemp)" "${TEST_ROOT}/commands/mktemp"
  ln -s "$(command -v rm)" "${TEST_ROOT}/commands/rm"
  export PATH="${TEST_ROOT}/commands"
  run_setup flutter 3.44.0 none --bundle flutterfire
  PATH="${original_path}"
  export PATH
  assert_nonzero
  assert_stderr_contains "npm is required for the 'flutterfire' bundle."
  assert_log_excludes 'CALL dart'
  pass "missing npm fails before SDK or package mutation"
}

case_failed_npm_install() {
  prepare_flutter_case
  export NPM_INSTALL_FAIL=1
  run_setup flutter 3.44.0 none --bundle flutterfire --no-merry
  assert_nonzero
  assert_stderr_contains 'Failed to install Firebase Tools through npm.'
  assert_log_contains 'CALL npm|install|--global|firebase-tools'
  assert_stderr_excludes 'Remaining setup steps are not implemented'
  pass "failed npm install suppresses remaining setup success"
}

case_failed_activation_preserves_cache() {
  prepare_dart_case
  readonly expected_cache="${MERRY_SETUP_HOME}/pub-cache/dart/3.12.0"
  mkdir -p "${expected_cache}"
  printf 'preserve\n' >"${expected_cache}/sentinel"
  export DART_ACTIVATE_FAIL_PACKAGE=broken
  run_setup dart 3.12.0 none --dart-package broken --no-merry
  assert_nonzero
  assert_stderr_contains "Failed to activate Dart package 'broken'."
  assert_path_exists "${expected_cache}/sentinel"
  assert_stdout_contains 'Resolved SDK:'
  assert_stderr_excludes 'Remaining setup steps are not implemented'
  pass "failed activation preserves the resolved pub cache"
}

"case_${MERRY_SETUP_TEST_CASE}"
