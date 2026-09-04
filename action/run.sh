#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

readonly CLI_PATH="${GITHUB_ACTION_PATH}/bin/merry-setup"
readonly command_name="${1:-setup}"
readonly cache_enabled="${MERRY_SETUP_CACHE:-false}"
sdk_version="${MERRY_SETUP_SDK_VERSION:-}"

[[ -x ${CLI_PATH} ]] || die "Merry Setup CLI is missing or not executable: ${CLI_PATH}"
[[ -n ${TRUNK_PATH:-} ]] || die "TRUNK_PATH was not set by the Trunk setup action."
[[ $# -le 1 ]] || die "The Action adapter accepts at most one internal command."
case "${command_name}" in
setup | resolve)
  ;;
*)
  die "Unsupported internal Action command: ${command_name}"
  ;;
esac
case "${cache_enabled}" in
true | false)
  ;;
*)
  die "Input 'cache' must be 'true' or 'false'."
  ;;
esac

if [[ ${command_name} == setup && ${cache_enabled} == true ]]; then
  [[ -n ${MERRY_SETUP_RESOLVED_SDK_VERSION:-} ]] || die "Resolved SDK version is unavailable for cache-enabled setup."
  [[ -n ${MERRY_SETUP_RESOLVED_SDK_ARCHIVE_SHA256:-} ]] || die "Resolved SDK archive checksum is unavailable for cache-enabled setup."
  [[ -n ${MERRY_SETUP_ARCHIVE_PATH:-} ]] || die "SDK archive path is unavailable for cache-enabled setup."
  case "${MERRY_SETUP_SDK_PRESENT:-}" in
  true | false)
    ;;
  *)
    die "Resolved SDK path state is unavailable for cache-enabled setup."
    ;;
  esac
  sdk_version="${MERRY_SETUP_RESOLVED_SDK_VERSION}"
fi

args=(
  "${command_name}"
  --sdk "${MERRY_SETUP_SDK:-}"
  --sdk-version "${sdk_version}"
  --project-dir "${MERRY_SETUP_PROJECT_DIR:-}"
  --persist-path github
  --bootstrap "${MERRY_SETUP_BOOTSTRAP:-}"
  --trunk-path "${TRUNK_PATH}"
)

case "${MERRY_SETUP_MERRY:-}" in
true)
  ;;
false)
  args+=(--no-merry)
  ;;
*)
  die "Input 'merry' must be 'true' or 'false'."
  ;;
esac

if [[ -n ${MERRY_SETUP_MERRY_VERSION:-} ]]; then
  args+=(--merry-version "${MERRY_SETUP_MERRY_VERSION}")
fi

if [[ -n ${MERRY_SETUP_FIREBASE_TOOLS_VERSION:-} ]]; then
  args+=(--firebase-tools-version "${MERRY_SETUP_FIREBASE_TOOLS_VERSION}")
fi

append_multiline_input() {
  local option_name="$1"
  local input_value="$2"
  local line_value=""

  while IFS= read -r line_value || [[ -n ${line_value} ]]; do
    line_value="${line_value%$'\r'}"
    [[ -z ${line_value} ]] && continue
    args+=("${option_name}" "${line_value}")
  done <<<"${input_value}"
}

append_multiline_input --dart-package "${MERRY_SETUP_DART_PACKAGES:-}"
append_multiline_input --bundle "${MERRY_SETUP_BUNDLES:-}"
append_multiline_input --precache "${MERRY_SETUP_PRECACHE:-}"

if [[ ${command_name} == setup && ${cache_enabled} == true && ${MERRY_SETUP_SDK_PRESENT} == false ]]; then
  args+=(--sdk-archive "${MERRY_SETUP_ARCHIVE_PATH}" --sdk-archive-sha256 "${MERRY_SETUP_RESOLVED_SDK_ARCHIVE_SHA256}")
fi

exec "${CLI_PATH}" "${args[@]}"
