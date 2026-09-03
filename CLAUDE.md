# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`merry-setup` bootstraps Dart and Flutter environments for Codex Cloud, GitHub Actions, and Linux x64 shells.
Read `AGENTS.md` first: it owns project scope, shell and Action conventions, documentation style, and git safety, and this file does not restate them.
The product contract is `docs/specs/0001-merry-setup/spec.md`; the task breakdown is `docs/plans/2026-08-27-merry-setup-v1-implementation.md`.
Bracketed IDs such as `[L13]` in both files are Interview Ledger references (`docs/specs/0001-merry-setup/interview-ledger.md`) that trace a decision to the conversation that fixed it.

## Commands

```bash
# Full local gate (mirrors .github/workflows/ci.yml)
bash -n bin/merry-setup action/preflight.sh action/run.sh test/*.sh
shellcheck bin/merry-setup action/preflight.sh action/run.sh test/*.sh
bash test/run.sh

# One test group (each file is self-contained)
bash test/sdk_installation_test.sh

# Trunk gate: actionlint, markdownlint, shellcheck, yamllint; pre-push hook is enabled
trunk fmt <paths> && trunk check <paths>

# Trace the CLI
DEBUG=1 bin/merry-setup setup --sdk dart --bootstrap none --persist-path none
```

`bin/merry-setup` uses `declare -A`, so it needs Bash 4 or newer.
macOS `/bin/bash` is 3.2 and fails at the top of the file; run everything through Homebrew bash on PATH (`test/run.sh` already invokes `/usr/bin/env bash`).
The CLI calls GNU `mv --no-clobber --no-target-directory` and `sha256sum`; the tests stub both, so the suite passes on macOS, but a real run only works on Linux x64 because `validate_host` rejects everything else.

## Architecture

One implementation, two thin adapters:

- `bin/merry-setup` is the canonical, complete implementation in a single file. Every rule about validation, SDK installation, tool activation, and persistence lives here.
- `action/preflight.sh` and `action/run.sh` are the composite Action adapter. `preflight.sh` is a non-mutating guard (bootstrap enum plus `pubspec.yaml`) that runs before the delegated `trunk-io/trunk-action/setup` step. `run.sh` converts `MERRY_SETUP_*` env vars into a Bash argv array and `exec`s the CLI with `--persist-path github` and the upstream `TRUNK_PATH`. Multi-line inputs (`dart-packages`, `bundles`, `precache`) become repeated flags.
- `action.yml` is the public Action API. Inputs reach the scripts via `env`, never by interpolation into `run:`.

### CLI flow (`main`)

Parse argv, validate enums, conflicts, the Trunk path, and the persistence environment, resolve `MERRY_SETUP_HOME` (default `$HOME/.merry-setup`), check the project manifest when bootstrap is not `none`, then `validate_bundles`, `build_activation_plan`, `validate_host`, `resolve_and_install_sdk`, `install_flutterfire_bundle`, `resolve_pub_cache`, `activate_global_packages`, `run_flutter_precache`, `resolve_trunk_launcher`, `apply_path_persistence`, `run_project_bootstrap`, and the final `Merry setup completed` line.
Validation runs entirely before the first network or filesystem mutation, and tests depend on that ordering.

The `bootstrap` command skips installation: `locate_path_sdk` finds the family on `PATH`, checks the exact version and the runtime floor, then the same pub-cache, persistence, and bootstrap steps run.
Trunk lookup order is explicit path, `.trunk/bin/trunk`, `tools/trunk`, `trunk` under the project, `MERRY_SETUP_HOME/bin/trunk`, then a download of the official launcher.
The `github` adapter writes `GITHUB_PATH` lines in reverse precedence because the runner prepends them in reverse; the `bashrc` adapter owns one marker-delimited block.

### SDK store

- Version-addressed store at `MERRY_SETUP_HOME/sdks/<family>/<exact-version>`, no `current` alias. `stable` resolves to an exact version before any path is derived.
- Release metadata comes from the official Google Storage endpoints (`DART_RELEASE_BASE_URL`, `FLUTTER_RELEASES_URL`) and is parsed with a deliberately narrow Bash-only JSON reader (`narrow_json_document_is_valid`, `json_single_string_value`). There is no `jq`; the parser fails closed on anything it does not recognize.
- Installation stages into a sibling `.<version>.staging.XXXXXX` directory, verifies the checksum, validates the tree with `sdk_installation_is_valid`, then publishes with `mv --no-clobber`. A same-version race is resolved by re-validating whichever install won. `cleanup_sdk_transients` runs on EXIT.
- `MINIMUM_DART_RUNTIME=3.12.0` is a fixed v1 policy, applied to standalone Dart and to Flutter's bundled Dart, and enforced before the archive download.

### Global tools

- One name-keyed activation plan (`ACTIVATION_PACKAGE_NAMES`, `_CONSTRAINTS`, `_INDEX`). `merry` is added by default and `--no-merry` opts out; `melos` and `very_good_cli` are implied by the bootstrap strategy; `flutterfire_cli` by the `flutterfire` bundle. Explicit `--dart-package name=constraint` entries are added first, so an implied package keeps the explicit constraint. Naming `merry` as a `--dart-package` is an error.
- Activation is `dart pub global activate` per package; `dart install` is out of scope for v1.
- `PUB_CACHE` defaults to `MERRY_SETUP_HOME/pub-cache/<family>/<version>` unless the caller sets it; a set-but-invalid override is an error, not a fallback.
- The FlutterFire bundle is the only npm path: `firebase-tools` via `npm install --global`, with `npm prefix --global` locating the bin directory.

## Tests

Black-box only: every test drives `bin/merry-setup` through `run_cli` or `run_cli_in` from `test/test_helper.sh` and asserts on exit status, stderr, files, and the recorded command log.

- `setup_test_env` isolates `HOME`, `MERRY_SETUP_HOME`, and `PATH`, and unsets `PUB_CACHE`. `create_recording_stub NAME` places a logging stub on PATH; `assert_command_count` reads the log.
- `test_helper.sh` also ships the shared flow stubs (`create_host_stub`, `create_metadata_stub`, `create_dart_sdk`, `create_flutter_sdk`, `write_trunk_launcher_stub`): a pre-created SDK under `MERRY_SETUP_HOME` makes setup reuse it, and the dart stub fakes activation, `pub global list`, and `pub get`. The SDK test builds its own richer `curl`, `sha256sum`, `mv`, `tar`, and `unzip` stubs to exercise download and publication. Nothing may reach the network or the real home directory, and `bootstrap_test.sh` closes `PATH` so a real SDK on the host cannot leak in.
- Work test-first: add the failing assertion, confirm the failure, implement the smallest passing change. A new validator needs a broken fixture that fails before its passing fixture counts as evidence.
- `test/run.sh` lists test files explicitly; register new groups there.

## Docs and workflow

- `.act/` configures the ACT spec workflow (backend `local`, artifacts in `docs/specs/`). Specs are the requirements source of truth; do not widen scope without one.
- `.markdownlint.yaml` disables MD013, so prose uses no hard wraps and sentence-level line breaks.
