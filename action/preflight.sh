#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

readonly bootstrap_strategy="${MERRY_SETUP_BOOTSTRAP:-}"
readonly requested_project_dir="${MERRY_SETUP_PROJECT_DIR:-.}"

case "${bootstrap_strategy}" in
none)
  exit 0
  ;;
dart | flutter | melos | very-good)
  ;;
*)
  die "Input 'bootstrap' must be one of: none, dart, flutter, melos, very-good; received '${bootstrap_strategy}'."
  ;;
esac

[[ -n ${GITHUB_WORKSPACE:-} ]] || die "GITHUB_WORKSPACE is unavailable."

if [[ ${requested_project_dir} == /* ]]; then
  project_dir="${requested_project_dir}"
else
  project_dir="${GITHUB_WORKSPACE}/${requested_project_dir}"
fi
readonly project_dir

[[ -d ${project_dir} ]] || die "Project directory does not exist: ${requested_project_dir}"
[[ -f ${project_dir}/pubspec.yaml ]] || die "Project directory does not contain pubspec.yaml: ${requested_project_dir}"
