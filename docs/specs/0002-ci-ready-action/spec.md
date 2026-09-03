---
type: Spec
title: CI-Ready Composite Action
---

## Problem

Fifteen consumer repositories now delegate their Codex Cloud setup to `merry-setup` through a pinned wrapper, but none of them uses the composite Action in CI.
Every one of those repositories still installs its own toolchain inside its workflows, so the duplication the v1 release removed from container setup remains in CI.

Two gaps stand between the current Action and that use, and both were observed rather than predicted.

The first is the npm global bin directory.
`apply_path_persistence` writes exactly three directories, because requirements 64 and 65 of the initial release enumerate them exhaustively and requirement 27 forbids relocating the npm global prefix.
The `flutterfire` bundle installs `firebase-tools` through npm, and that executable is reachable inside the CLI process but is never written to `$GITHUB_PATH`.
A later workflow step therefore finds `firebase` only when the runner already carries npm's global bin on `PATH`.
The integration workflow's Flutter job does find it on `ubuntu-24.04`, so the gap is currently invisible, which is precisely what makes it worth closing deliberately rather than discovering on a runner that differs.

The second is caching.
The initial release placed caching out of scope and relies on whatever the host environment provides.
A Codex Cloud container is created once and reused, so a full SDK download per creation is acceptable there.
A CI job starts from a clean runner every time, so the same behaviour means downloading a complete Dart or Flutter SDK on every push.
The integration workflow measured that cost: its Flutter job takes minutes dominated by the SDK download, against seconds for the rest of the flow.

## Proposed Outcome

Extend the composite Action so a consumer repository can replace its per-workflow toolchain setup with one step.

Persist the npm global bin directory when, and only when, a bundle has put an executable there.
Add opt-in caching of the version-addressed SDK store and the managed pub cache, keyed on the values that already determine their contents.
Both changes stay inside the existing contract shape: no new mutable state, no relocation of tooling the initial release declared out of bounds, and no behaviour that differs between a cache hit and a cold run.

## User Stories

1. As a repository owner, I replace a workflow's Flutter installation, tool activation and dependency bootstrap with one `merry-setup` step, and a later step can run every tool the step installed.
2. As a repository owner, I enable caching with one input and see repeat runs skip the SDK download while producing the same installed tree as a cold run.
3. As a reviewer, I can tell from the workflow file alone which SDK version and which tools a job will use.

## Requirements

### npm Global Bin Persistence

1. When a bundle installs an executable through npm, the resolved npm global bin directory must be persisted by the `github` and `bashrc` adapters alongside the three directories the initial release already persists.
2. When no bundle is enabled, no npm directory may be resolved, queried or persisted, and the persisted set must be byte-identical to the initial release's.
3. The npm global bin directory must be persisted with lower precedence than the exact SDK bin directory and `${PUB_CACHE}/bin`, matching the process-level ordering requirement 44 already fixes.
4. `merry-setup` must still not relocate the npm global prefix; it reads the prefix npm reports and persists that path unchanged. This narrows requirement 27 rather than reversing it: the prefix stays npm's to choose, and only its visibility to later steps becomes `merry-setup`'s concern.
5. Requirements 64 and 65 must be amended to describe a persisted set that is conditional on the bundle, so the enumeration remains exhaustive rather than being contradicted by behaviour.

### SDK and Pub Cache Caching

6. The composite Action must expose one optional `cache` input accepting `true` or `false`, defaulting to `false`, so existing consumers see no change until they opt in.
7. When `cache` is `true`, the Action must restore and save the SDK store at `${MERRY_SETUP_HOME}/sdks/<family>/<version>` and the managed pub cache at `${MERRY_SETUP_HOME}/pub-cache/<family>/<version>`.
8. The cache key must contain the SDK family, the exact resolved SDK version, the runner operating system and architecture, a digest of the activation plan as given, package names with their constraints, and the normalized Flutter precache plan, sorted and deduplicated, because those are the inputs that determine the stored contents. The precache plan belongs in the key because `flutter precache` writes its platform artifacts under the installed SDK's `bin/cache`, inside the path requirement 7 saves, so two jobs that request different targets would otherwise share an entry and restore whichever set the first writer saved. The key is a lookup key, not a determinism guarantee: a package with an open constraint already resolves differently on two cold runs on different days, and the cache neither removes nor adds that variance, because requirement 10 makes activation run on every hit.
9. A `sdk-version` of `stable` resolves to an exact version only after release metadata is read, so the key must be computed after resolution rather than from the requested value. `action.yml` invokes the CLI once, and `resolve_and_install_sdk` installs in the same call that resolves, so the exact version is not available to the Action before the download today. The CLI must therefore gain a `resolve` command that reads release metadata, prints the exact version for the requested family and version, and performs no download, no extraction, no mutation of `MERRY_SETUP_HOME` and no persistence. The Action must compute the key from that command's output before any restore step and must not carry a resolver of its own. The Action must then invoke `setup` with that exact version rather than with the requested `stable`, through the exact-version form `--sdk-version` already accepts, so one run resolves the channel once: if the channel advanced between the two calls, a setup that resolved again would install a newer SDK under paths the key never named, and that run would receive no usable cache. An implementation that keys on `stable` must be rejected, because it would serve a stale SDK indefinitely.
10. A cache hit must produce the same reported state as a cold run at the same moment: the same resolved SDK log line, the same activated package versions, and the same persisted paths. The CLI is cache-unaware, so `dart pub global activate` must still run for every package on a hit, and a package with an open constraint therefore resolves fresh on every run; the restored pub cache saves the download, and never decides which version is active. A restored `global_packages` record must not be trusted as an activation.
11. A restored tree must pass through the same acceptance path as any pre-existing installation. The Action restores into the final SDK path, so a valid restored tree is reused through the initial release's same-version reuse rule, and a corrupt or partial one must cause the deterministic failure that requirement 30 of the initial release already fixes, without automatic deletion, repair or reinstallation. Requirement 30 is not amended. The guard against a poisoned entry sits at save time instead: the Action must save an entry only after the setup step has succeeded, so a tree the CLI rejected is never written under its key, and the documented remedy for an entry corrupted after a successful save is deleting it from the repository's cache rather than a self-healing run.
12. Caching must remain absent from the portable CLI: no save, no restore, no key computation and no cache-aware branch may exist in `bin/merry-setup`. The `resolve` command of requirement 9 is a read-only query that reports what `setup` would select and is usable outside CI, so it is not a cache feature. The Action owns every cache step, so a Codex Cloud wrapper gains nothing to configure and nothing to break.
13. Third-party cache actions must be pinned to a full commit SHA, as `AGENTS.md` already requires for every Action in a committed workflow.

## Technical Decisions

1. The npm directory is persisted conditionally rather than always, because an unconditional entry would put a directory on `PATH` for every consumer to serve the one bundle that needs it. [observed]
2. Caching is an Action input rather than a CLI option, because the two environments differ in exactly this respect: a container is created once and a runner is created per job. Putting it in the CLI would ask every Codex Cloud wrapper to carry a setting that is meaningless there. [operator, 2026-09-03]
3. The cache key is computed after `stable` resolution rather than from the requested version, for the same reason the initial release resolves before deriving the store path: a movable input must never name a fixed artifact. [derived from requirement 28]
4. The default is `false` rather than `true`, so adopting this release cannot change the behaviour of the fifteen repositories that merged the v1 wrapper today.
5. Resolution is exposed as a CLI command rather than duplicated in the Action, because `AGENTS.md` keeps the Action a thin composite over the Bash behaviour, and a second resolver in YAML would be a second copy of the metadata parser to drift. [review finding, PR #6]
6. A corrupt restore fails rather than reinstalls, because requirement 30 exists to keep `merry-setup` from deleting a final path it did not create in this run, and a hit that quietly deleted and reinstalled would give a hit and a cold run different behaviour, against requirement 10. Saving only on success is the cheaper guard: restoring into a staging area would need the validator outside the CLI, which requirement 12 forbids. [review finding, PR #6]

## Testing Strategy

1. Persistence tests must cover a bundle-enabled run whose `$GITHUB_PATH` gains the npm bin directory in the required order, and a bundle-free run whose persisted set is unchanged from the initial release.
2. A bundle-free run must be asserted to make no npm call at all, so requirement 2 is verified by absence rather than by inspection of the output.
3. Cache-key tests must show that two runs differing only in resolved SDK version, activation plan, precache plan, or runner architecture produce different keys, that two precache plans naming the same targets in a different order or with repeats produce the same key, and that `stable` and the version it resolves to produce the same key.
4. A restored tree that fails `sdk_installation_is_valid` must be shown to fail deterministically with the initial release's message, not to be repaired or reinstalled, using a fixture whose restored tree is deliberately incomplete, and the workflow must be shown not to save an entry after a failed setup step.
5. Every cache assertion must be demonstrated to fail before it is trusted, matching the initial release's testing strategy.
6. The integration workflow must gain two jobs on the same key: a save job that runs the Action cold, and a restore job that depends on it and starts on a fresh runner, because the cache is saved in the cache action's post step and a second invocation inside the save job would find the first invocation's tree still on disk. The restore job must assert the same resolved SDK and activated versions as the save job while skipping the archive download.
7. The `resolve` command must be shown to leave `MERRY_SETUP_HOME` untouched and to make no request beyond release metadata, using the recording stubs the SDK test already builds, and its output for `stable` must equal the version `setup` logs in the same stubbed environment. The Action's own tests must show that `setup` receives the exact version `resolve` printed, using a metadata stub whose `stable` answer changes between the two calls, so a second resolution would be visible as a mismatch.

## Out of Scope

- Caching in the portable Bash CLI.
- Modelling the invalidation of Flutter's precache artifacts beyond the key. They live under the SDK's `bin/cache` and are therefore saved with the SDK tree, and requirement 8 keys them by target set; whether Flutter later considers a saved artifact stale is Flutter's own concern, not this release's.
- A generic npm package interface. The npm path remains the named `flutterfire` bundle.
- Cache eviction, size limits, or cleanup beyond what the cache action itself provides.
- Marketplace publication and reusable workflows, still deferred from the initial release.

## Open Questions

1. Should a cache hit still verify the archive checksum? The stored tree is already extracted, so there is no archive to check, and requirement 11 substitutes structural validation. Confirm that substitution is acceptable before implementation. `[UNCERTAIN]`

## Follow-Ups

- Decompose into two independently mergeable Work Items, because the npm persistence change amends the initial release's requirements while the cache change only adds to the Action.
- Amend requirements 64 and 65 of `docs/specs/0001-merry-setup/spec.md` in the same change that implements requirement 1, so the two specs cannot disagree.
- Re-measure the Flutter integration job's duration after caching lands, and record the before and after rather than describing the improvement qualitatively.
