#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

readonly RUN_ADAPTER="${GITHUB_ACTION_PATH}/action/run.sh"
readonly runner_temp="${RUNNER_TEMP:-}"
readonly runner_os="${RUNNER_OS:-}"
readonly runner_arch="${RUNNER_ARCH:-}"
readonly output_file="${GITHUB_OUTPUT:-}"
readonly runner_identity_pattern='^[A-Za-z0-9._-]+$'
readonly version_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
readonly checksum_pattern='^[0-9a-f]{64}$'

[[ -x ${RUN_ADAPTER} ]] || die "Merry Setup Action adapter is missing or not executable: ${RUN_ADAPTER}"
[[ -n ${output_file} && -f ${output_file} && -w ${output_file} ]] || die "GITHUB_OUTPUT must point to a writable file."
[[ -n ${runner_temp} && ${runner_temp} == /* && ! ${runner_temp} =~ [[:cntrl:]] ]] || die "RUNNER_TEMP must be an absolute path without control characters."
[[ ${runner_os} =~ ${runner_identity_pattern} ]] || die "RUNNER_OS contains an unsupported cache-key value."
[[ ${runner_arch} =~ ${runner_identity_pattern} ]] || die "RUNNER_ARCH contains an unsupported cache-key value."

resolved_plan="$("${RUN_ADAPTER}" resolve)"
sdk_family=""
sdk_version=""
sdk_archive_sha256=""
sdk_path=""
declare -A seen_scalar=()
declare -A seen_category=()

while IFS= read -r plan_line || [[ -n ${plan_line} ]]; do
  [[ -n ${plan_line} && ${plan_line} == *=* && ! ${plan_line} =~ [[:cntrl:]] ]] || die "The CLI returned a malformed resolved-plan line."
  plan_key="${plan_line%%=*}"
  plan_value="${plan_line#*=}"
  [[ -n ${plan_value} ]] || die "The CLI returned an empty resolved-plan value for '${plan_key}'."

  case "${plan_key}" in
  sdk_family | sdk_version | sdk_archive_sha256 | sdk_path | precache | bundle | bundle_flutterfire_cli_version | bundle_firebase_tools_version | bootstrap)
    [[ ${seen_scalar[${plan_key}]+present} != present ]] || die "The CLI returned duplicate resolved-plan key '${plan_key}'."
    seen_scalar["${plan_key}"]=true
    ;;
  activation)
    ;;
  *)
    die "The CLI returned unsupported resolved-plan key '${plan_key}'."
    ;;
  esac

  case "${plan_key}" in
  sdk_family) sdk_family="${plan_value}" ;;
  sdk_version) sdk_version="${plan_value}" ;;
  sdk_archive_sha256) sdk_archive_sha256="${plan_value}" ;;
  sdk_path) sdk_path="${plan_value}" ;;
  precache | activation | bundle | bootstrap) seen_category["${plan_key}"]=true ;;
  esac
done <<<"${resolved_plan}"

for required_key in sdk_family sdk_version sdk_archive_sha256 sdk_path; do
  [[ ${seen_scalar[${required_key}]+present} == present ]] || die "The CLI resolved plan is missing '${required_key}'."
done
for required_category in precache activation bundle bootstrap; do
  [[ ${seen_category[${required_category}]+present} == present ]] || die "The CLI resolved plan is missing '${required_category}'."
done

case "${sdk_family}" in
dart | flutter)
  ;;
*)
  die "The CLI returned an unsupported SDK family in its resolved plan."
  ;;
esac
[[ ${sdk_version} =~ ${version_pattern} ]] || die "The CLI returned an invalid exact SDK version in its resolved plan."
[[ ${sdk_archive_sha256} =~ ${checksum_pattern} ]] || die "The CLI returned an invalid SDK archive checksum in its resolved plan."
[[ ${sdk_path} == /* && ! ${sdk_path} =~ [[:cntrl:]] ]] || die "The CLI returned an invalid final SDK path in its resolved plan."

archive_path="${runner_temp}/merry-setup/sdk-archives/${sdk_family}/${sdk_version}/sdk-archive"
cache_key="merry-setup-sdk-archive-${sdk_family}-${sdk_version}-${runner_os}-${runner_arch}-${sdk_archive_sha256}"
sdk_present=false
if [[ -e ${sdk_path} || -L ${sdk_path} ]]; then
  sdk_present=true
fi

printf '%s\n' \
  "sdk-family=${sdk_family}" \
  "sdk-version=${sdk_version}" \
  "sdk-archive-sha256=${sdk_archive_sha256}" \
  "sdk-path=${sdk_path}" \
  "archive-path=${archive_path}" \
  "cache-key=${cache_key}" \
  "sdk-present=${sdk_present}" >>"${output_file}"
