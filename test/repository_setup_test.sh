#!/usr/bin/env bash
set -euo pipefail

SETUP_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SETUP_TEST_DIR
# shellcheck source=test/test_helper.sh
# shellcheck disable=SC1091 # The test suite supplies this repository-local helper.
source "${SETUP_TEST_DIR}/test_helper.sh"

setup_test_env
trap cleanup_test_env EXIT

readonly SOURCE_SETUP="${REPO_ROOT}/setup.sh"
readonly FIXTURE_REPOSITORY="${TEST_ROOT}/repository"
readonly FIXTURE_PROJECT="${TEST_ROOT}/project"
readonly EXPECTED_LOG="${TEST_ROOT}/expected.log"

[[ -f ${SOURCE_SETUP} ]] || fail "repository setup wrapper is missing: ${SOURCE_SETUP}"

mkdir -p "${FIXTURE_REPOSITORY}/bin"
cp "${SOURCE_SETUP}" "${FIXTURE_REPOSITORY}/setup.sh"

# shellcheck disable=SC2016 # The generated stub expands its runtime values.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  '{' \
  '  printf '\''PWD %s\n'\'' "${PWD}"' \
  '  printf '\''ARG %s\n'\'' "$@"' \
  '} >"${TEST_COMMAND_LOG}"' >"${FIXTURE_REPOSITORY}/bin/merry-setup"
chmod +x "${FIXTURE_REPOSITORY}/bin/merry-setup"

(
  cd "${FIXTURE_PROJECT}"
  /usr/bin/env bash "${FIXTURE_REPOSITORY}/setup.sh"
)

printf '%s\n' \
  "PWD ${FIXTURE_PROJECT}" \
  'ARG setup' \
  'ARG --sdk' \
  'ARG dart' \
  'ARG --bootstrap' \
  'ARG none' \
  'ARG --persist-path' \
  'ARG bashrc' \
  'ARG --no-merry' >"${EXPECTED_LOG}"

assert_file_equals "${EXPECTED_LOG}" "${TEST_COMMAND_LOG}"
pass "repository setup delegates the minimal Linux environment to the local CLI"
