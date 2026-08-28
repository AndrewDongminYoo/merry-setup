# Merry Setup v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the smallest portable Linux x64 Bash implementation and thin GitHub Composite Action that satisfy all 91 requirements in Spec 0001.

**Architecture:** Keep `bin/merry-setup` as one self-contained downloadable Bash program. Keep GitHub-specific behavior in `action/preflight.sh`, `action/run.sh`, and `action.yml`. Exercise public behavior through black-box shell tests with isolated homes, fixture metadata, and a controlled stub `PATH`; no unit test downloads a real SDK.

**Tech Stack:** Bash 5 on Linux x64, GitHub Composite Actions YAML, Trunk, ShellCheck, actionlint, markdownlint, yamllint, and local fixture-driven shell tests.

**Spec:** `docs/specs/0001-merry-setup/spec.md`

## Global Constraints

- Preserve the current index and author-unknown work. Do not stage, commit, push, publish, or create remote state without a separate request.
- Keep private local workflow metadata and its vocabulary out of public files and Git history.
- Treat the existing unborn `main` checkout as the implementation workspace because no `HEAD` exists from which to create a worktree.
- Use test-first behavior changes: add one failing black-box assertion, confirm the expected failure, implement the smallest passing behavior, and rerun the focused test.
- Use `apply_patch` for hand-authored file changes. Run formatters or rewriters only against explicit paths.
- Never download a real Dart or Flutter SDK during local unit tests. Real installation coverage belongs only in isolated Linux x64 integration workflows.
- Keep Action inputs in `env` and pass them to the CLI through Bash arrays. Never use `eval` or interpolate Action expressions into shell command text.
- Require callers of the canonical CLI to select `--sdk`, `--bootstrap`, and `--persist-path` explicitly. `--sdk-version` defaults to `stable`, and `--project-dir` defaults to the caller's current working directory.
- Keep exact external release data out of fixtures unless the test needs it. Minimal synthetic fixtures own parser behavior; the selected upstream SDK owns transitive artifact behavior.

## File Ownership Map

| Path | Responsibility |
| --- | --- |
| `bin/merry-setup` | Complete portable CLI, validation, SDK store, tool plan, persistence, Trunk selection, and bootstrap orchestration. |
| `action.yml` | Exact public Action inputs and ordered Composite Action steps. |
| `action/preflight.sh` | Non-mutating bootstrap enum and manifest guard before delegated Trunk setup. |
| `action/run.sh` | Safe environment-to-argv adapter for the canonical CLI. |
| `test/test_helper.sh` | Isolated fixture roots, assertions, command stubs, logs, and cleanup. |
| `test/run.sh` | Explicit test entry point. |
| `test/*_test.sh` | Black-box contract groups with focused command-flow assertions. |
| `test/fixtures/**` | Synthetic official-metadata-shaped release and checksum inputs. |
| `.trunk/trunk.yaml` | Shared pinned linter gate and non-mutating pre-push check. |
| `.markdownlint.yaml`, `.yamllint.yaml` | Narrow repository documentation and YAML policy. |
| `.github/workflows/ci.yml` | Fast Linux x64 syntax, lint, and fixture-test gate. |
| `.github/workflows/integration.yml` | Manual and release-gated real Dart and Flutter smoke matrix. |
| `LICENSE`, `README.md` | MIT distribution boundary and pinned consumer usage. |

## Requirement Coverage

| Requirements | Owning tasks |
| --- | --- |
| 1–8 | Tasks 3 and 9 |
| 9–14 | Tasks 2, 3, and 8 |
| 15–31 | Tasks 2 and 4 |
| 32–42 | Tasks 2 and 5 |
| 43–45 | Tasks 5 and 7 |
| 46–51 | Task 5 |
| 52–55 | Task 6 |
| 56–62 | Tasks 1 and 7 |
| 63–68 | Tasks 3 and 7 |
| 69–77 | Task 8 |
| 78–85 | Task 3 |
| 86–91 | Tasks 4–9 |

---

## Task 1: Establish the Public Trunk Quality Gate

**Files:**

- Create: `.trunk/trunk.yaml`
- Create: `.markdownlint.yaml`
- Create: `.yamllint.yaml`
- Modify only if Trunk requires it: `.gitignore`

- [x] Run Trunk initialization after listing existing manifests and quality configuration.

```bash
git status --short
trunk init --yes-to-all --only-detected-linters --only-detected-formatters --no-progress
```

Expected in a repository with `HEAD`: Trunk creates shared `.trunk/` configuration. The current unborn repository instead reports that it cannot analyze committed files; do not create a product commit only to bypass that guard.

- [x] When initialization is blocked by the missing `HEAD`, add the supported minimal shared configuration and let `trunk check enable` resolve exact plugin versions.

```bash
trunk check enable actionlint markdownlint shellcheck yamllint --no-progress
```

- [x] Keep only the evidence-backed linters for Markdown, YAML, GitHub Actions, and Bash: markdownlint, yamllint, actionlint, and shellcheck.
- [x] Configure Markdown linting to allow paragraph-length lines because the repository explicitly uses no hard wraps.
- [x] Configure a non-mutating `trunk-check-pre-push` hook and no pre-commit formatter.
- [x] Prove the gate can fail before trusting it.

```bash
scratch_root="$(mktemp -d /tmp/merry-setup-trunk.XXXXXX)"
# Copy the exact shared Trunk configuration and target files into scratch_root.
# Create one validation-only commit inside scratch_root, then change a fenced code block to omit its language.
trunk check --no-fix --filter=markdownlint docs/notes/trunk-canary.md --no-progress
```

Expected: nonzero status with a fenced-code-language finding.

- [x] Remove the canary and run explicit repository checks. Until the product repository has its first authorized commit, run these commands against the identical files in the disposable validation repository so Trunk has a baseline reference.

```bash
trunk check --no-fix --filter=markdownlint docs/plans/2026-08-27-merry-setup-v1-implementation.md README.md AGENTS.md docs/specs/0001-merry-setup/spec.md docs/specs/0001-merry-setup/interview-ledger.md
trunk check --no-fix --filter=yamllint .trunk/trunk.yaml .markdownlint.yaml .yamllint.yaml
```

Expected: all configured checks pass.

## Task 2: Build the Black-Box Test Harness and Canonical Parser

**Files:**

- Create: `test/test_helper.sh`
- Create: `test/run.sh`
- Create: `test/cli_validation_test.sh`
- Create: `bin/merry-setup`

- [x] Add a test helper that creates an isolated temporary root, sets `HOME`, `MERRY_SETUP_HOME`, and a fixture command directory, records exact argv one item per line, and removes only its own root in an exit trap.
- [x] Add assertions for exit status, exact stderr substring, file existence, file absence, and recorded command count.
- [x] Write the first failing CLI cases: unknown command, missing `--sdk`, missing `--bootstrap`, missing `--persist-path`, unknown option, missing option value, invalid SDK, invalid bootstrap, invalid persistence adapter, relative `MERRY_SETUP_HOME`, and non-`none` bootstrap without `pubspec.yaml`.

```bash
/opt/homebrew/bin/bash test/cli_validation_test.sh
```

Expected: the test fails because `bin/merry-setup` does not yet implement the contract.

- [x] Create `bin/merry-setup` with `#!/usr/bin/env bash`, `set -euo pipefail`, optional `DEBUG=1` tracing, `die`, usage, command selection, array-safe option parsing, enum validators, absolute-path/control-character validators, and the canonical manifest preflight.
- [x] Make this task's canonical validation set complete before host probing or any external command lookup.
- [x] Make the file executable and rerun the focused tests.

```bash
chmod +x bin/merry-setup test/run.sh test/test_helper.sh test/cli_validation_test.sh
/opt/homebrew/bin/bash -n bin/merry-setup test/test_helper.sh test/run.sh test/cli_validation_test.sh
/opt/homebrew/bin/bash test/cli_validation_test.sh
/opt/homebrew/bin/shellcheck bin/merry-setup test/test_helper.sh test/run.sh test/cli_validation_test.sh
```

Expected: syntax, focused validation tests, and ShellCheck pass.

## Task 3: Implement the Thin Composite Action Boundary

**Files:**

- Create: `action.yml`
- Create: `action/preflight.sh`
- Create: `action/run.sh`
- Create: `test/action_preflight_test.sh`
- Create: `test/action_adapter_test.sh`
- Create: `test/action_metadata_test.sh`

- [x] Write failing preflight tests for `none`, each supported non-`none` bootstrap, invalid enum, missing manifest, relative path, absolute path, and a project path containing spaces.
- [x] Use a mutation sentinel after preflight to prove a failure cannot reach delegated Trunk setup.

```bash
/opt/homebrew/bin/bash test/action_preflight_test.sh
```

Expected: failure because `action/preflight.sh` does not exist.

- [x] Implement `action/preflight.sh` with only bootstrap enum validation and regular `pubspec.yaml` validation. Resolve relative Action project directories against `GITHUB_WORKSPACE`, skip all manifest work for `none`, and perform no write.
- [x] Write failing adapter tests for required values, `merry=true|false`, Merry conflicts, LF/CRLF multiline values, blank lines, one input line per argv element, `TRUNK_PATH`, and exact canonical CLI order.
- [x] Implement `action/run.sh` as one Bash argument-array constructor. It must consume environment values, pass `setup`, select `--persist-path github`, pass upstream `TRUNK_PATH` through `--trunk-path`, and execute only `bin/merry-setup`.
- [x] Add `action.yml` with exactly the approved input names and step order: preflight, pinned `trunk-io/trunk-action/setup`, canonical setup. Map all dynamic expressions through `env`.

```bash
/opt/homebrew/bin/bash -n action/preflight.sh action/run.sh test/action_preflight_test.sh test/action_adapter_test.sh
/opt/homebrew/bin/bash test/action_preflight_test.sh
/opt/homebrew/bin/bash test/action_adapter_test.sh
/opt/homebrew/bin/shellcheck action/preflight.sh action/run.sh test/action_preflight_test.sh test/action_adapter_test.sh test/action_metadata_test.sh
/opt/homebrew/bin/bash test/action_metadata_test.sh
trunk check --no-fix --filter=yamllint action.yml
```

Expected: the scripts pass syntax, tests, and ShellCheck; the exact Action metadata contract passes its canary-proven structural test and yamllint. Trunk actionlint reports no applicable linter for root `action.yml`, so reserve it for workflow files rather than treating a skip as a pass.

## Task 4: Implement SDK Resolution and Atomic Publication

**Files:**

- Modify: `bin/merry-setup`
- Modify: `test/run.sh`
- Create: `test/sdk_installation_test.sh`
- Create: `test/fixtures/dart-version-3.11.4.json`
- Create: `test/fixtures/dart-version-3.12.0.json`
- Create: `test/fixtures/flutter-releases.json`

- [x] Write failing tests for Linux x64 host validation, stable-to-exact resolution, exact versions, missing metadata, missing checksum, missing architecture, semantic-version ordering, the 3.12.0 runtime floor, Flutter bundled Dart, and no download below the floor.
- [x] Add a narrow fail-closed parser for the official metadata fields used by v1. Do not introduce `jq`, Python, or another runtime dependency before an SDK exists.
- [x] Write failing tests for checksum mismatch, extraction failure, staged version mismatch, unique sibling staging, cleanup, valid reuse, invalid final paths, symlink final paths, and a publication race winner.
- [x] Implement download-to-staging, official checksum verification, archive extraction, executable and version validation, same-filesystem no-clobber rename, losing-race validation, and exit-trap cleanup.
- [x] Never delete or replace an invalid existing final SDK path. Never name a final directory `stable` or create a `current` alias.

```bash
/opt/homebrew/bin/bash test/sdk_installation_test.sh
/opt/homebrew/bin/bash -n bin/merry-setup test/sdk_installation_test.sh
/opt/homebrew/bin/shellcheck bin/merry-setup test/sdk_installation_test.sh
```

Expected: every SDK path uses an exact resolved version, all error paths leave no partial final tree, and the fixture-controlled download stub is never bypassed.

## Task 5: Implement Pub Cache, Global Package Planning, and FlutterFire

**Files:**

- Modify: `bin/merry-setup`
- Create: `test/tools_and_bundles_test.sh`

- [ ] Write failing `PUB_CACHE` tests for managed family/version separation, explicit override priority, set-but-empty values, relative values, control characters, and Flutter cache keys based on the Flutter version.
- [ ] Write failing package-plan tests for Merry default, `--no-merry`, Merry version conflict, name/constraint splitting, duplicate names, forbidden additional Merry, implicit Melos, implicit Very Good CLI, implicit FlutterFire CLI, and explicit constraints overriding only their implicit entry.
- [ ] Write failing FlutterFire tests for duplicate bundles, missing npm, exact `firebase-tools` versions, npm default selection, invalid exact versions, and a standalone `flutterfire_cli` package causing no npm side effect.
- [ ] Implement one name-keyed activation plan in Bash arrays and install each entry once through `dart pub global activate` with separate argv elements.
- [ ] Resolve and export `PUB_CACHE` before activation, keep `${PUB_CACHE}/bin` ahead of unrelated global bins, log non-mutating tool versions when supported, and never invoke `dart install` or clear the cache after failure.

```bash
/opt/homebrew/bin/bash test/tools_and_bundles_test.sh
/opt/homebrew/bin/shellcheck bin/merry-setup test/tools_and_bundles_test.sh
```

Expected: exact recorded argv proves one activation per package, safe constraint separation, and only the named FlutterFire bundle invokes npm.

## Task 6: Implement Deterministic Flutter Precache

**Files:**

- Modify: `bin/merry-setup`
- Create: `test/precache_test.sh`

- [ ] Write the complete failing matrix for no target, `android`, `web,android`, repeated mixed targets, Dart conflicts, empty comma tokens, `none`, `ios`, `all`, and `android_maven`.
- [ ] Implement target parsing, rejection, deduplication, and canonical order without exposing upstream granular flags.
- [ ] Invoke `flutter precache` exactly once only when the canonical set is nonempty.
- [ ] Propagate a failing precache status and suppress final success.

```bash
/opt/homebrew/bin/bash test/precache_test.sh
/opt/homebrew/bin/shellcheck bin/merry-setup test/precache_test.sh
```

Expected: the stub log contains either zero precache calls or one exact `flutter precache` argv in `--android --web --linux` order.

## Task 7: Implement Trunk Selection and Persistence Adapters

**Files:**

- Modify: `bin/merry-setup`
- Create: `test/trunk_and_persistence_test.sh`

- [ ] Write failing Trunk tests for an explicit executable, invalid explicit path, documented repository-local launcher reuse, official launcher fallback, logged path/version, and no independent version index.
- [ ] Implement explicit-path-first selection, repository-local reuse, and the narrow official portable-launcher fallback. Keep Action setup delegated through `TRUNK_PATH`.
- [ ] Write failing persistence tests for `none`, missing GitHub environment files, `$GITHUB_ENV` content, `$GITHUB_PATH` order, shell-safe `.bashrc` values, one managed block after reruns, and replacement of stale exact-version paths.
- [ ] Implement current-process exports before tools, `github` file writes, and one idempotently replaced `bashrc` block. Use safe single-quote encoding for persisted literal paths.

```bash
/opt/homebrew/bin/bash test/trunk_and_persistence_test.sh
/opt/homebrew/bin/shellcheck bin/merry-setup test/trunk_and_persistence_test.sh
```

Expected: every child command observes one resolved `PUB_CACHE`; persistence files contain only the selected exact paths; Trunk version succeeds before final success.

## Task 8: Implement Bootstrap-Only and End-to-End Orchestration

**Files:**

- Modify: `bin/merry-setup`
- Create: `test/bootstrap_test.sh`
- Create: `test/setup_flow_test.sh`
- Modify: `test/run.sh`

- [ ] Write failing bootstrap command tests for PATH-selected Dart and Flutter families, exact version mismatch, missing SDK, runtime below 3.12.0, no remote metadata lookup, managed cache derivation, and deleted manifest after a successful Action preflight.
- [ ] Write failing strategy tests for `none`, Dart, Flutter, Melos, and Very Good, plus tracked, untracked, and absent root lockfiles.
- [ ] Implement strategy argv exactly: `dart pub get`, `flutter pub get`, `melos bootstrap`, and the documented recursive Very Good package-get command. Add `--enforce-lockfile` only where the approved strategy supports it and the root lockfile is tracked.
- [ ] Assemble setup ordering: full validation, host and release resolution, SDK reuse/install, runtime recheck, pub cache, package activation, precache, Trunk, persistence, bootstrap, and final success.
- [ ] Assemble bootstrap-only ordering without SDK/global-tool installation or remote metadata.
- [ ] Run setup twice against one fixture and prove SDK reuse, one package activation per invocation, one current profile block, usable tool shims, cleanup, failure propagation, and no premature success.

```bash
/opt/homebrew/bin/bash test/bootstrap_test.sh
/opt/homebrew/bin/bash test/setup_flow_test.sh
/opt/homebrew/bin/bash test/run.sh
/opt/homebrew/bin/shellcheck bin/merry-setup action/preflight.sh action/run.sh test/*.sh
```

Expected: all black-box tests pass and no test reaches the network or the operator's real home.

## Task 9: Complete Distribution Documentation and CI

**Files:**

- Create: `LICENSE`
- Modify: `README.md`
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/integration.yml`

- [x] Add the standard MIT text with `Copyright (c) 2026 Dongmin Yu` and no placeholder.
- [ ] Update README with CLI and Action contracts, immutable-revision download-to-file examples, no `curl | bash`, environment contracts, target/tool boundaries, debug warning, and third-party license boundary.
- [ ] Resolve every third-party workflow Action tag to a current verified full commit SHA before inserting it. Reject any value that is not exactly 40 hexadecimal characters.

```bash
git ls-remote https://github.com/actions/checkout.git 'refs/tags/v4^{}' refs/tags/v4
```

Expected: select the peeled tag commit when present and record the verification date in a YAML comment without promising that it remains upstream-latest.

- [ ] Add a fast Linux x64 CI workflow for explicit Bash syntax, ShellCheck, Trunk checks, and `test/run.sh`.
- [ ] Add isolated real integration jobs for Dart/default Merry/bootstrap Dart, Flutter/Melos/FlutterFire/all three precache targets, and exact Dart 3.12.0/Merry/Very Good CLI. Keep the real integration workflow manual or release-gated until its installation cost and runtime are observed.

```bash
trunk check --no-fix --filter=actionlint .github/workflows/ci.yml .github/workflows/integration.yml
trunk check --no-fix --filter=yamllint action.yml .github/workflows/ci.yml .github/workflows/integration.yml .trunk/trunk.yaml .markdownlint.yaml .yamllint.yaml
trunk check --no-fix --filter=markdownlint README.md LICENSE docs/plans/2026-08-27-merry-setup-v1-implementation.md docs/specs/0001-merry-setup/spec.md docs/specs/0001-merry-setup/interview-ledger.md
```

Expected: public metadata and documentation pass their explicit linters. Local evidence does not claim the Linux integration jobs passed until GitHub executes them.

## Task 10: Run the Release-Readiness Gate

**Files:**

- Verify only; modify the smallest owning file if a check exposes a real defect.

- [ ] Prove the full custom test entry point can fail by temporarily making one isolated fixture invalid, record the expected assertion, restore it, and rerun.
- [ ] Run the deployment-interpreter syntax and static checks.

```bash
/opt/homebrew/bin/bash -n bin/merry-setup action/preflight.sh action/run.sh test/*.sh
/opt/homebrew/bin/shellcheck bin/merry-setup action/preflight.sh action/run.sh test/*.sh
/opt/homebrew/bin/bash test/run.sh
trunk check --no-fix --all
git diff --check
```

Expected: all local checks pass with no real SDK download and no unscoped file mutation.

- [ ] Audit the public file set for private workflow names, unresolved placeholders, unpinned third-party Actions, unsafe Action expression interpolation, missing fence languages, and executable bits.

```bash
rg -n --hidden --glob '!.git/**' '[T]ODO|[T]BD|[P]LACEHOLDER|curl[^\n]*\|[^\n]*(bash|sh)|uses: [^@]+@(main|master|v[0-9]+)$' .
git status --short
```

Expected: the audit prints no public boundary violation or unresolved placeholder; status lists only intended local implementation files and preserved pre-existing changes.

- [ ] Report the minimum repeatable verification command and explicitly mark real Linux integration as pending until remote execution is authorized and observed.
