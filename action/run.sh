#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

readonly CLI_PATH="${GITHUB_ACTION_PATH}/bin/merry-setup"

[[ -x ${CLI_PATH} ]] || die "Merry Setup CLI is missing or not executable: ${CLI_PATH}"
[[ -n ${TRUNK_PATH:-} ]] || die "TRUNK_PATH was not set by the Trunk setup action."

args=(
  setup
  --sdk "${MERRY_SETUP_SDK:-}"
  --sdk-version "${MERRY_SETUP_SDK_VERSION:-}"
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

exec "${CLI_PATH}" "${args[@]}"
