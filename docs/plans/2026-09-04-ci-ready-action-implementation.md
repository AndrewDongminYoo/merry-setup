# CI-Ready Composite Action Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the merged CI-ready Action Spec so later workflow steps can use npm-installed bundle tools and opt in to a checksum-bound upstream SDK archive cache.

**Architecture:** Keep release resolution, archive validation, extraction, and local archive transport in `bin/merry-setup`. Keep GitHub remote restore, cache-key construction, and explicit save in the composite Action. Add one narrow resolve adapter that converts the CLI plan into trusted internal step outputs, and keep the normal `cache: false` setup argv unchanged.

**Tech Stack:** Bash 5 on Linux x64, GitHub Composite Actions YAML, `actions/cache` restore and save entry points pinned to `55cc8345863c7cc4c66a329aec7e433d2d1c52a9` (`v6.1.0`, verified through the official repository on 2026-09-04), fixture-driven shell tests, ShellCheck, actionlint, markdownlint, yamllint, and Trunk.

**Spec:** `docs/specs/0002-ci-ready-action/spec.md`

## Global Constraints

- Preserve the public CLI and Action defaults for consumers that omit `cache`.
- Keep remote cache operations out of `bin/merry-setup`.
- Cache only the official upstream SDK release archive under `${RUNNER_TEMP}`.
- Never cache an extracted SDK, Flutter precache artifacts, `PUB_CACHE`, or a shared `MERRY_SETUP_HOME`.
- Verify every supplied or restored archive against the checksum from current official release metadata before extraction or execution.
- Keep all Action expressions in `env` or `with` values and all CLI arguments in Bash arrays.
- Never use `eval` or interpolate Action inputs into shell command text.
- Use fixture metadata and command stubs for local tests. Do not download a real SDK or mutate the operator's actual home directory.
- Demonstrate every new validator and behavior assertion with an expected failing fixture before trusting its passing result.
- Do not stage, commit, push, merge, tag, publish, dispatch a workflow, or change repository cache state without a separate request.

## File Ownership Map

| Path | Responsibility |
| --- | --- |
| `bin/merry-setup` | Canonical validation, read-only plan resolution, local archive handoff, checksum verification, installation, and persistence. |
| `action/preflight.sh` | Non-mutating validation of `cache`, `bootstrap`, and the selected project manifest before delegated setup. |
| `action/run.sh` | Shared Action input-to-CLI argv conversion for `resolve` and `setup`. |
| `action/resolve.sh` | Parse the resolved CLI plan, compute the exact Action-owned archive path and cache key, inspect the final SDK path, and write internal step outputs. |
| `action.yml` | Public `cache` input and ordered resolve, restore, setup, and explicit save steps. |
| `test/resolve_test.sh` | Read-only CLI resolution, normalized plan output, validation parity, and changing-metadata regressions. |
| `test/sdk_installation_test.sh` | Existing SDK installation coverage plus local archive transport validation, restored archive verification, cold archive publication, and corrupt archive rejection. |
| `test/action_cache_test.sh` | Resolve adapter outputs, cache-key identity, final-path branching, and safe Action argv construction. |
| Existing `test/*_test.sh` files | Focused persistence, preflight, Action metadata, and regression assertions. |
| `test/run.sh` | Explicit registration of the three new black-box test groups. |
| `docs/specs/0001-merry-setup/spec.md` | Amend the superseded v1 input, persistence, preflight, and cache boundaries without copying Spec 0002. |
| `README.md` | Document `resolve`, archive transport, npm bin persistence, `cache`, the private-store precondition, and corrupt-entry recovery. |
| `.github/workflows/integration.yml` | Add exact-version save and dependent fresh-runner restore coverage. |

## Requirement Coverage

| Spec 0002 requirements | Owning tasks |
| --- | --- |
| 1–5 | Task 1 |
| 6–9 | Tasks 2 and 4 |
| 10–11 | Task 3 |
| 12–14 | Task 4 |
| Documentation and integration strategy | Task 5 |

---

### Task 1: Persist the npm Global Bin Only for the FlutterFire Bundle

**Files:**

- Modify: `test/trunk_and_persistence_test.sh`
- Modify: `bin/merry-setup`
- Modify: `docs/specs/0001-merry-setup/spec.md`

**Interfaces:**

- Consumes: `NPM_GLOBAL_BIN`, which `install_flutterfire_bundle` sets from `<npm prefix --global>/bin` only after the named bundle resolves npm.
- Produces: `write_bashrc_block <sdk-bin> <pub-bin> [npm-bin]` and a GitHub path list whose later-step precedence is SDK, `PUB_CACHE`, local tools, npm tools, then the existing path.

- [x] **Step 1: Add failing bundle and bundle-free persistence cases.**

```bash
# Bundle-free GitHub setup must keep the v1 file byte-for-byte.
run_setup flutter 3.44.0 github --trunk-path "${EXPLICIT_LAUNCHER}"
assert_file_equals "${TEST_ROOT}/v1-github-path" "${GITHUB_PATH}"
assert_log_excludes 'CALL npm|'

# FlutterFire setup must append the derived npm bin before the SDK entry so GitHub's reverse insertion keeps SDK and PUB_CACHE ahead of it.
run_setup flutter 3.44.0 github --bundle flutterfire --trunk-path "${EXPLICIT_LAUNCHER}"
assert_file_equals "${TEST_ROOT}/flutterfire-github-path" "${GITHUB_PATH}"
```

- [x] **Step 2: Run the focused test and confirm that the FlutterFire expected path fails while the bundle-free baseline passes.**

```bash
bash test/trunk_and_persistence_test.sh
```

Expected: nonzero status because the bundle-enabled output omits the npm global bin. The command log must also prove that the bundle-free case made no npm call.

- [x] **Step 3: Add the optional npm bin to both persistence adapters without resolving npm in `apply_path_persistence`.**

```bash
persisted_bins=()
[[ -z ${NPM_GLOBAL_BIN} ]] || persisted_bins+=("${NPM_GLOBAL_BIN}")
persisted_bins+=("${LOCAL_TOOL_BIN}" "${pub_bin}" "${sdk_bin}")
printf '%s\n' "${persisted_bins[@]}" >>"${GITHUB_PATH}"
```

For `bashrc`, construct the managed `PATH` value as SDK, pub, local, optional npm, then the prior `PATH`.

- [x] **Step 4: Run the focused persistence test and the FlutterFire bundle tests.**

```bash
bash test/trunk_and_persistence_test.sh
bash test/tools_and_bundles_test.sh flutterfire_exact_version flutterfire_default_version
```

Expected: both commands pass, the bundle-free persisted set remains unchanged, and only the bundle-enabled run persists npm's bin directory.

- [x] **Step 5: Amend requirements 64, 65, 78, 82, 83 and the superseded caching exclusions in Spec 0001.**

State only that Spec 0002 adds conditional npm persistence, the `cache` input, the read-only internal resolve phase, and Action-owned archive caching. Keep the complete new contract in Spec 0002.

### Task 2: Add a Read-Only Normalized `resolve` Command

**Files:**

- Create: `test/resolve_test.sh`
- Modify: `test/run.sh`
- Modify: `bin/merry-setup`

**Interfaces:**

- Produces one scalar per line: `sdk_family`, `sdk_version`, `sdk_archive_sha256`, `sdk_path`, `precache`, repeated sorted `activation` entries, `bundle`, `bundle_flutterfire_cli_version`, `bundle_firebase_tools_version`, and `bootstrap`.
- Uses `latest` only as an input-plan marker for unconstrained package selection. It does not claim an actual published version.
- Leaves `MERRY_SETUP_HOME`, persistence files, SDK archive paths, project files, and the Trunk launcher unchanged.

- [x] **Step 1: Add a failing `resolve` test for exact identity and no mutation.**

```bash
run_cli resolve --sdk dart --sdk-version stable --bootstrap none --persist-path none --no-merry
assert_status 0
assert_stdout_contains 'sdk_family=dart'
assert_stdout_contains 'sdk_version=3.12.0'
assert_stdout_contains "sdk_path=${MERRY_SETUP_HOME}/sdks/dart/3.12.0"
assert_path_absent "${MERRY_SETUP_HOME}"
assert_log_excludes '/sdk/dartsdk-linux-x64-release.zip'
```

- [x] **Step 2: Run the new test and confirm `resolve` fails as an unknown command.**

```bash
bash test/resolve_test.sh
```

Expected: nonzero status with `Unknown command: resolve` before any production edit.

- [x] **Step 3: Split release resolution from installation and move metadata temporary files outside `MERRY_SETUP_HOME`.**

```bash
resolve_sdk_release "${sdk_family}" "${sdk_version}"
CURRENT_SDK_ROOT="${MERRY_SETUP_HOME}/sdks/${sdk_family}/${RESOLVED_SDK_VERSION}"
print_resolved_plan "${sdk_family}" "${bootstrap_strategy}" "${firebase_tools_version}"
```

For Dart, resolution must read the official checksum metadata for the exact version. For Flutter, retain the existing manifest checksum. Cleanup must cover each external metadata temporary file.

- [x] **Step 4: Add normalized-plan, no-side-effect, and validation-parity cases.**

```bash
run_cli resolve --sdk flutter --sdk-version stable --bootstrap melos --persist-path none --dart-package beta=^2.0.0 --dart-package alpha=^1.0.0 --precache web,android --precache android
assert_stdout_contains 'precache=android,web'
assert_stdout_order 'activation=alpha@^1.0.0' 'activation=beta@^2.0.0'
```

Run equivalent activation orders and equivalent precache groupings and compare their complete stdout.
For every Action-exposed setup option, reuse the existing invalid fixtures through both `resolve` and `setup` and compare the exact pre-mutation error.
Use a changing stable metadata stub to prove that a caller can carry the first exact version forward without resolving the channel a second time.

- [x] **Step 5: Run the resolve tests and existing CLI validation and SDK installation tests.**

```bash
bash test/resolve_test.sh
bash test/cli_validation_test.sh
bash test/sdk_installation_test.sh
```

Expected: all commands pass and the recording log contains only release metadata requests for every `resolve` case.

### Task 3: Bind Local Archive Transport to Official Metadata

**Files:**

- Modify: `test/sdk_installation_test.sh`
- Modify: `bin/merry-setup`

**Interfaces:**

- Adds paired setup-only options `--sdk-archive <absolute-path>` and `--sdk-archive-sha256 <64-lowercase-hex>`.
- Consumes the exact official checksum resolved in Task 2.
- Produces a verified archive at the requested path only after a cold download succeeds, and never identifies its remote source.

- [x] **Step 1: Add failing transport validation cases before valid fixtures.**

```bash
run_cli setup --sdk dart --sdk-version 3.12.0 --bootstrap none --persist-path none --no-merry --sdk-archive relative/archive --sdk-archive-sha256 "${VALID_SHA256}"
assert_nonzero
assert_command_count 0 curl

run_cli setup --sdk dart --sdk-version 3.12.0 --bootstrap none --persist-path none --no-merry --sdk-archive "${TEST_ROOT}/archive"
assert_nonzero
assert_command_count 0 curl
```

Cover the missing pair, uppercase or wrong-length digest, control character, regular directory, symbolic link, and dangling symbolic link.

- [x] **Step 2: Run the validator cases and confirm the expected pre-metadata failures.**

```bash
bash test/sdk_installation_test.sh
```

Expected: nonzero status from the test file because transport options do not exist yet. After the parser exists, temporarily use one invalid fixture first and confirm that no curl or SDK path mutation occurs before running valid cases.

- [x] **Step 3: Add minimal paired-option validation and compare the supplied digest with the current official checksum before archive access.**

```bash
[[ ${sdk_archive_sha256} == "${RESOLVED_ARCHIVE_SHA256}" ]] || die "The supplied SDK archive checksum does not match current official release metadata."
```

- [x] **Step 4: Add restored and missing archive behavior.**

If the archive exists, copy it into the unique private sibling staging directory, then verify and extract only that snapshot. If the archive is absent, download to a temporary sibling file, verify it, copy and verify the private staging snapshot, atomically publish the downloaded file at the requested path, and extract only the private snapshot. Never fall back to an upstream archive download after a corrupt restored archive.

- [x] **Step 5: Add corrupt bytes, valid restored archive, absent archive, metadata drift, and existing SDK cases.**

The corrupt fixture must fail before any extractor or restored SDK executable runs. The metadata-drift fixture must change the checksum between `resolve` and `setup` and fail before archive access. The existing valid SDK case must reuse the installation without requiring or creating the Action-owned archive.

- [x] **Step 6: Run transport and SDK regression tests.**

```bash
bash test/sdk_installation_test.sh
```

Expected: all cases pass, failed cases leave the final SDK absent, and no `.staging.*`, `.metadata.*`, or archive-download temporary files remain.

### Task 4: Orchestrate Opt-In Remote Cache Restore and Explicit Save

**Files:**

- Create: `action/resolve.sh`
- Create: `test/action_cache_test.sh`
- Modify: `action/preflight.sh`
- Modify: `action/run.sh`
- Modify: `action.yml`
- Modify: `test/action_preflight_test.sh`
- Modify: `test/action_adapter_test.sh`
- Modify: `test/action_metadata_test.sh`
- Modify: `test/run.sh`

**Interfaces:**

- `action/resolve.sh` emits internal outputs `sdk-family`, `sdk-version`, `sdk-archive-sha256`, `sdk-path`, `archive-path`, `cache-key`, and `sdk-present` through `$GITHUB_OUTPUT`.
- The cache key is `merry-setup-sdk-archive-<family>-<version>-<runner-os>-<runner-arch>-<sha256>` with no restore prefix.
- `action/run.sh resolve` uses the public Action inputs. `action/run.sh setup` uses the exact resolved version and paired archive transport values only when caching is enabled and the final SDK path was absent.

- [x] **Step 1: Add a fail-first invalid `cache: yes` preflight fixture and the unchanged default argv fixture.**

```bash
MERRY_SETUP_CACHE=yes run_preflight
assert_nonzero
assert_stderr_contains "Input 'cache' must be 'true' or 'false'."

MERRY_SETUP_CACHE=false run_adapter
assert_file_equals "${expected_v1_argv}" "${argv_log}"
```

- [x] **Step 2: Add failing resolve-adapter cache-key and final-path cases.**

Use a stub CLI plan with fixed literals. Change only version, runner architecture, and checksum and assert that each changes the key. Change only plan fields that are not key inputs and assert that the key stays equal. Make `stable` and the exact request return the same resolved plan and assert equal keys. Create a dangling final-path symlink and assert `sdk-present=true`.

- [x] **Step 3: Run Action-focused tests and confirm they fail for the missing input, adapter, and cache steps.**

```bash
bash test/action_preflight_test.sh
bash test/action_adapter_test.sh
bash test/action_cache_test.sh
bash test/action_metadata_test.sh
```

- [x] **Step 4: Validate `cache` in the first preflight step and implement strict plan parsing.**

Reject duplicate or missing required scalar plan keys, control characters, unsafe runner identity values, non-absolute paths, and invalid checksums. Check `[[ -e ${sdk_path} || -L ${sdk_path} ]]` without creating a directory. Compute the archive path under `${RUNNER_TEMP}` without creating it.

- [x] **Step 5: Add the ordered composite steps.**

```yaml
- name: Resolve SDK archive cache plan
  id: sdk-cache-plan
  if: inputs.cache == 'true'
  shell: bash
  run: '"$GITHUB_ACTION_PATH/action/resolve.sh"'
- name: Restore SDK release archive
  id: sdk-cache-restore
  if: inputs.cache == 'true' && steps.sdk-cache-plan.outputs.sdk-present == 'false'
  uses: actions/cache/restore@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1.0
- name: Set up Dart or Flutter environment
  shell: bash
  run: '"$GITHUB_ACTION_PATH/action/run.sh" setup'
- name: Save SDK release archive
  if: inputs.cache == 'true' && steps.sdk-cache-plan.outputs.sdk-present == 'false' && steps.sdk-cache-restore.outputs.cache-hit != 'true'
  uses: actions/cache/save@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1.0
```

Use the exact `archive-path` and `cache-key` outputs for both cache steps. Do not configure `restore-keys`. Keep the setup step immediately before the save step so implicit `success()` prevents a save after setup failure.

- [x] **Step 6: Implement cached and existing-SDK argv selection in `action/run.sh`.**

`cache=false` must emit the original v1 argv. `cache=true` must require the resolve outputs. It must use the exact resolved version. It must omit both transport options when `sdk-present=true`, and include both when `sdk-present=false`.

- [x] **Step 7: Run Action tests and syntax validation.**

```bash
bash test/action_preflight_test.sh
bash test/action_adapter_test.sh
bash test/action_cache_test.sh
bash test/action_metadata_test.sh
bash -n action/preflight.sh action/resolve.sh action/run.sh
```

Expected: all tests pass, cache actions are pinned to the verified full SHA, the default branch has no resolve or remote cache execution path, and every setup failure suppresses explicit save through the Action step order and condition.

### Task 5: Document and Exercise the Complete CI Flow

**Files:**

- Modify: `README.md`
- Modify: `.github/workflows/integration.yml`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**

- Documents `cache: true` as valid only with a job-private `MERRY_SETUP_HOME`.
- Documents deletion of the exact repository cache entry as the remedy for a corrupt immutable archive entry.
- Adds one exact Dart 3.12.0 save job and one dependent fresh-runner restore job with an exact `merry-version`.

- [x] **Step 1: Update the CLI and Action documentation.**

Add `resolve` and both setup-only transport options to the CLI reference. State that transport options are local byte selection, not remote cache controls. Add `cache` to the Action input table and example. Explain the cache contents, key identity, private-store precondition, checksum revalidation, no fallback, and corrupt-entry deletion.

- [x] **Step 2: Add the new shell paths to CI syntax and ShellCheck commands.**

```yaml
run: bash -n bin/merry-setup action/preflight.sh action/resolve.sh action/run.sh test/*.sh
```

- [x] **Step 3: Add exact-version save and dependent restore integration jobs.**

Use `sdk-version: 3.12.0`, an exact current `merry-version` verified from the official package source at implementation time, `cache: true`, and `needs: cache-save`. The restore job must use a new GitHub-hosted runner and must verify the same resolved SDK and activated Merry versions. Keep real workflow dispatch external and deferred.

- [x] **Step 4: Run the full local gate.**

```bash
bash -n bin/merry-setup action/preflight.sh action/resolve.sh action/run.sh test/*.sh
shellcheck bin/merry-setup action/preflight.sh action/resolve.sh action/run.sh test/*.sh
bash test/run.sh
trunk check --no-fix --all --no-progress
```

Expected: all commands pass with no real SDK download. The Trunk result must report each warning and failure separately.

- [x] **Step 5: Inspect the complete diff and working tree without staging it.**

```bash
git status --short
git diff --check
git diff --stat
git diff -- action.yml action bin test docs/specs docs/plans README.md .github/workflows
```

Expected: only the files in this plan change. Leave commits, pushes, workflow dispatch, cache mutation, tags, releases, and Marketplace publication for explicit follow-up authorization.
