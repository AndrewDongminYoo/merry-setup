#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
# shellcheck source=test/test_helper.sh
source "${TEST_DIR}/test_helper.sh"

setup_test_env
trap cleanup_test_env EXIT

run_cli
assert_nonzero
assert_stderr_contains "Command is required."
pass "missing command"

run_cli frobnicate
assert_nonzero
assert_stderr_contains "Unknown command: frobnicate"
pass "unknown command"

run_cli setup --bootstrap none --persist-path none --no-merry
assert_nonzero
assert_stderr_contains "Option '--sdk' is required."
pass "missing SDK"

run_cli setup --sdk dart --persist-path none --no-merry
assert_nonzero
assert_stderr_contains "Option '--bootstrap' is required."
pass "missing bootstrap strategy"

run_cli setup --sdk dart --bootstrap none --no-merry
assert_nonzero
assert_stderr_contains "Option '--persist-path' is required."
pass "missing persistence adapter"

run_cli setup --unknown value --sdk dart --bootstrap none --persist-path none
assert_nonzero
assert_stderr_contains "Unknown option: --unknown"
pass "unknown option"

run_cli setup --sdk
assert_nonzero
assert_stderr_contains "Option '--sdk' requires a value."
pass "missing option value"

run_cli setup --sdk java --bootstrap none --persist-path none
assert_nonzero
assert_stderr_contains "Option '--sdk' must be one of: dart, flutter; received 'java'."
pass "invalid SDK"

run_cli setup --sdk dart --bootstrap very_good --persist-path none
assert_nonzero
assert_stderr_contains "Option '--bootstrap' must be one of: none, dart, flutter, melos, very-good; received 'very_good'."
pass "invalid bootstrap strategy"

run_cli setup --sdk dart --bootstrap none --persist-path profile
assert_nonzero
assert_stderr_contains "Option '--persist-path' must be one of: bashrc, github, none; received 'profile'."
pass "invalid persistence adapter"

MERRY_SETUP_HOME=relative run_cli setup --sdk dart --bootstrap none --persist-path none
assert_nonzero
assert_stderr_contains "MERRY_SETUP_HOME must be a nonempty absolute path."
pass "relative managed home"

MERRY_SETUP_HOME="${TEST_ROOT}/managed:segment" run_cli setup --sdk dart --bootstrap none --persist-path none
assert_nonzero
assert_stderr_contains "MERRY_SETUP_HOME must be a nonempty absolute path."
pass "PATH-delimiter managed home"

run_cli setup --sdk dart --bootstrap none --persist-path none --no-merry --merry-version '^2.0.0'
assert_nonzero
assert_stderr_contains "Option '--merry-version' conflicts with '--no-merry'."
pass "Merry opt-out conflict"

run_cli setup --sdk dart --bootstrap none --persist-path none --precache web
assert_nonzero
assert_stderr_contains "Option '--precache' is invalid when '--sdk dart' is selected."
pass "Dart precache conflict"

missing_project="${TEST_ROOT}/missing project"
run_cli setup --sdk dart --bootstrap dart --persist-path none --project-dir "${missing_project}"
assert_nonzero
assert_stderr_contains "Project directory does not exist: ${missing_project}"
pass "canonical project-directory preflight"

run_cli_in "${TEST_ROOT}/project" setup --sdk dart --bootstrap dart --persist-path none
assert_nonzero
assert_stderr_contains "Project directory does not contain pubspec.yaml: ${TEST_ROOT}/project"
pass "current working directory project default"

# Host validation runs after the manifest check, so an unsupported host proves the manifest step was skipped
# while keeping the run away from the network. The curl stub records any download attempt.
printf '%s\n' '#!/usr/bin/env bash' 'printf '\''Darwin\n'\''' >"${TEST_ROOT}/commands/uname"
chmod +x "${TEST_ROOT}/commands/uname"
create_recording_stub curl
run_cli setup --sdk dart --bootstrap none --persist-path none --no-merry
assert_nonzero
assert_stderr_excludes "pubspec.yaml"
assert_stderr_contains "Unsupported operating system: Darwin."
assert_command_count 0 curl
pass "bootstrap none skips manifest validation"
