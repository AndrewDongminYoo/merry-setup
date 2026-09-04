#!/usr/bin/env bash
set -euo pipefail

ACTION_PREFLIGHT_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ACTION_PREFLIGHT_TEST_DIR
# shellcheck source=test/test_helper.sh
source "${ACTION_PREFLIGHT_TEST_DIR}/test_helper.sh"

readonly PREFLIGHT_PATH="${REPO_ROOT}/action/preflight.sh"

setup_test_env
trap cleanup_test_env EXIT

workspace="${TEST_ROOT}/workspace"
mkdir -p "${workspace}"

run_preflight() {
  set +e
  "${PREFLIGHT_PATH}" >"${TEST_STDOUT}" 2>"${TEST_STDERR}"
  ACTUAL_STATUS=$?
  set -e
}

unset GITHUB_WORKSPACE || true
MERRY_SETUP_CACHE=yes MERRY_SETUP_BOOTSTRAP=none MERRY_SETUP_PROJECT_DIR=. run_preflight
assert_nonzero
assert_stderr_contains "Input 'cache' must be 'true' or 'false'."
pass "invalid cache enum fails before delegated setup"

MERRY_SETUP_BOOTSTRAP=none MERRY_SETUP_PROJECT_DIR=. run_preflight
assert_status 0
pass "none skips workspace and manifest validation"

GITHUB_WORKSPACE="${workspace}" MERRY_SETUP_BOOTSTRAP=very_good MERRY_SETUP_PROJECT_DIR=. run_preflight
assert_nonzero
assert_stderr_contains "Input 'bootstrap' must be one of: none, dart, flutter, melos, very-good; received 'very_good'."
pass "invalid bootstrap enum"

GITHUB_WORKSPACE="${workspace}" MERRY_SETUP_BOOTSTRAP=flutter MERRY_SETUP_PROJECT_DIR=missing run_preflight
assert_nonzero
assert_stderr_contains "Project directory does not exist: missing"
pass "missing project directory"

mkdir -p "${workspace}/app"
GITHUB_WORKSPACE="${workspace}" MERRY_SETUP_BOOTSTRAP=dart MERRY_SETUP_PROJECT_DIR=app run_preflight
assert_nonzero
assert_stderr_contains "Project directory does not contain pubspec.yaml: app"
pass "missing project manifest"

printf 'name: fixture\n' >"${workspace}/app/pubspec.yaml"
for bootstrap_strategy in dart flutter melos very-good; do
  GITHUB_WORKSPACE="${workspace}" MERRY_SETUP_BOOTSTRAP="${bootstrap_strategy}" MERRY_SETUP_PROJECT_DIR=app run_preflight
  assert_status 0
done
pass "supported non-none strategies"

absolute_project="${workspace}/project with spaces"
mkdir -p "${absolute_project}"
printf 'name: spaced_fixture\n' >"${absolute_project}/pubspec.yaml"
GITHUB_WORKSPACE="${workspace}" MERRY_SETUP_BOOTSTRAP=flutter MERRY_SETUP_PROJECT_DIR="${absolute_project}" run_preflight
assert_status 0
pass "absolute project path with spaces"

GITHUB_WORKSPACE="${workspace}" MERRY_SETUP_BOOTSTRAP=dart MERRY_SETUP_PROJECT_DIR=app MERRY_SETUP_SDK=invalid run_preflight
assert_status 0
pass "preflight ignores unrelated SDK input"

sentinel_path="${TEST_ROOT}/delegated-trunk-ran"
if GITHUB_WORKSPACE="${workspace}" MERRY_SETUP_BOOTSTRAP=melos MERRY_SETUP_PROJECT_DIR=missing "${PREFLIGHT_PATH}" >"${TEST_STDOUT}" 2>"${TEST_STDERR}"; then
  : >"${sentinel_path}"
fi
assert_path_absent "${sentinel_path}"
pass "preflight failure blocks delegated mutation"
