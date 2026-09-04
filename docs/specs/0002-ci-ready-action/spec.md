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
Add opt-in caching of the upstream SDK release archive.
On every cache hit, the CLI must verify that archive against the checksum from official release metadata before it extracts or executes SDK content.
The Action must not cache an extracted SDK tree or the managed pub cache in this release.
Both changes stay inside the existing contract shape: no relocation of tooling the initial release declared out of bounds, and no installed state that differs between a cache hit and a cold run.

## User Stories

1. As a repository owner, I replace a workflow's Flutter installation, tool activation and dependency bootstrap with one `merry-setup` step, and a later step can run every tool the step installed.
2. As a repository owner, I enable caching with one input and see repeat runs skip the SDK release archive download while producing the same installed tree as a cold run.
3. As a reviewer, I can tell from the workflow file alone which SDK version and which tools a job will use.

## Requirements

### npm Global Bin Persistence

1. When a bundle installs an executable through npm, the resolved npm global bin directory must be persisted by the `github` and `bashrc` adapters alongside the three directories the initial release already persists.
2. When no bundle is enabled, no npm directory may be resolved, queried or persisted, and the persisted set must be byte-identical to the initial release's.
3. The npm global bin directory must be persisted with lower precedence than the exact SDK bin directory and `${PUB_CACHE}/bin`, matching the process-level ordering requirement 44 already fixes.
4. `merry-setup` must still not relocate the npm global prefix; it reads the prefix `npm prefix --global` reports and persists the bin directory derived from it, `<prefix>/bin`, which is the directory the bundle installation already uses to locate the executable, never the prefix itself, because a prefix such as `/usr/local` on `PATH` exposes nothing. This narrows requirement 27 rather than reversing it: the prefix stays npm's to choose, and only the visibility of its bin directory to later steps becomes `merry-setup`'s concern.
5. Requirements 64 and 65 must be amended to describe a persisted set that is conditional on the bundle, so the enumeration remains exhaustive rather than being contradicted by behaviour.

### SDK Release Archive Caching

6. The composite Action must expose one optional `cache` input.
    The input must accept `true` or `false` and must default to `false`.
    Existing consumers must see no change until they opt in.
    When `cache` is `false`, the Action must:

    - Use the initial release's setup flow unchanged.
    - Make no `resolve` call.
    - Make no archive restore.
    - Make no archive save.
7. When `cache` is `true`, the Action must maintain one cache entry for the upstream SDK release archive.
    The Action must restore the archive to `${RUNNER_TEMP}/merry-setup/sdk-archives/<family>/<version>/sdk-archive`, outside `MERRY_SETUP_HOME`.
    The entry must not contain an extracted SDK tree, Flutter precache artifacts, or any part of `PUB_CACHE`.
8. The archive cache key must contain the SDK family, the exact resolved SDK version, the runner operating system and architecture, and the SHA-256 checksum from official release metadata.
    The key must not contain the Flutter precache plan because precache artifacts are not in the entry.
    The key must have no fallback because an archive for another release is not usable.
    The requested value `stable` and the exact version it resolves to must produce the same key.
9. A `sdk-version` of `stable` resolves to an exact version only after the CLI reads release metadata.
    The CLI must gain a `resolve` command that accepts every `setup` option exposed by the Action and runs the same pre-mutation validation as `setup`.
    The command must print the resolved plan in a line-oriented `key=value` form.
    The plan must include the SDK family, the exact SDK version, the official archive SHA-256 checksum, the normalized precache plan, the normalized activation plan, each bundle and its selected tool version, and the bootstrap strategy.
    The command must make no SDK archive or artifact download.
    The command must perform no extraction, no mutation of `MERRY_SETUP_HOME`, and no persistence.
    Release metadata is the only network resource that `resolve` may read.
    `action.yml` must compute the key from this output instead of parsing setup inputs independently.
    If `resolve` fails, the Action must not run a cache restore.
    The Action must invoke `setup` with the exact version from this output instead of resolving `stable` again.
10. The `setup` command must accept an optional `--sdk-archive <path>` transport option.
    The composite Action must use this option for its Action-owned archive path, but it must not expose the path as an Action input.
    The CLI must validate the path before mutation.
    The path must be absolute and must not contain control characters.
    The path must not be a symbolic link, including a dangling symbolic link.
    If the path exists, it must be a regular file.
    If the path contains an archive restored by the Action, the CLI must obtain the expected checksum from official release metadata and verify the archive before extraction.
    If the path does not exist, the CLI must download the official archive through its existing download path and must verify the official checksum.
    After successful verification, the CLI must place the archive at the requested path so the Action can save it.
    For both sources, the CLI must extract the archive in the initial release's unique sibling staging directory.
    The CLI must structurally validate the staged SDK and must publish it through the initial release's atomic rename path.
    The CLI must not execute any file from a restored archive before checksum verification succeeds.
    A checksum mismatch must fail without extraction, execution, SDK publication, or a fallback release-archive download.
11. A cache hit must produce the same reported state as a cold run at the same moment.
    The resolved SDK log line, activated package versions, and persisted paths must be the same.
    Flutter precache, global package activation, bundle installation, and project bootstrap must run normally after the SDK installation.
    A hit skips only the SDK release archive download from the upstream distribution.
12. When `cache` is `true`, the Action must perform these steps:

    - Run `resolve` and compute the exact archive key.
    - Restore the archive to the Action-owned path.
    - Run `setup` with the resolved exact version and `--sdk-archive`.
    - Save the archive in an explicit step immediately after a successful `setup` when no entry matched the exact key.

    The Action must not use the cache action's job-level post step for the save.
    If checksum verification or setup fails, the Action must not save an entry.
    The documented remedy for a corrupt immutable entry is to delete that entry from the repository cache.
13. Remote caching must remain absent from the portable CLI.
    `bin/merry-setup` must contain no remote save, remote restore, cache-key computation, or cache-hit branch.
    The `resolve` command is a read-only query.
    The `--sdk-archive` option selects local archive bytes and does not identify whether they came from a GitHub cache or another caller.
    The Action owns every remote cache operation.
14. Third-party cache actions must be pinned to a full commit SHA, as `AGENTS.md` already requires for every Action in a committed workflow.

## Technical Decisions

1. The npm directory is persisted conditionally rather than always, because an unconditional entry would put a directory on `PATH` for every consumer to serve the one bundle that needs it. [observed]
2. Caching is an Action input rather than a CLI option, because the two environments differ in exactly this respect: a container is created once and a runner is created per job. Putting it in the CLI would ask every Codex Cloud wrapper to carry a setting that is meaningless there. [operator, 2026-09-03]
3. The archive cache key is computed after `stable` resolution rather than from the requested version.
    The key includes the official checksum because a movable input must never name fixed bytes, and official metadata is the authority for those bytes. [derived from requirements 23 and 28]
4. The default is `false` rather than `true`, so adopting this release cannot change the behaviour of the fifteen repositories that merged the v1 wrapper today.
5. Resolution is exposed as a CLI command rather than duplicated in the Action, because `AGENTS.md` keeps the Action a thin composite over the Bash behaviour, and a second resolver in YAML would be a second copy of the metadata parser to drift. [review finding, PR #6]
6. The Action caches the official distribution archive rather than an extracted SDK tree.
    GitHub states that cache contents are not signed or verified and that a workflow must treat restored files as untrusted input.
    The CLI can authenticate the archive against official release metadata before it extracts or executes SDK content.
    An extracted tree has no equivalent upstream manifest in the current contract. [review finding, PR #6] [GitHub cache security](https://docs.github.com/en/actions/concepts/workflows-and-actions/dependency-caching#cache-security)
7. The CLI owns the local archive handoff because it already owns release metadata parsing, checksum verification, extraction, structural validation, and atomic publication.
    The Action supplies only the local path.
    This boundary keeps security behavior in the portable Bash implementation without adding remote cache operations to it. [review finding, PR #6]
8. The managed pub cache is not cached in this release.
    It contains extracted hosted packages, activation records, and executable shims.
    Pub compares the expected hosted-package checksum with a checksum record stored inside the same cache before it reuses the extracted package directory.
    This Spec has no independent provenance check for those restored directories.
    A later Spec must solve that boundary before the Action may cache `PUB_CACHE`. [local adversarial review, PR #6] [Pub hosted-cache verification](https://github.com/dart-lang/pub/blob/51d9e82d3931536ad629a7430314ac34413c30c4/lib/src/source/hosted.dart#L1247-L1372) [Pub global-package state](https://github.com/dart-lang/pub/blob/51d9e82d3931536ad629a7430314ac34413c30c4/lib/src/global_packages.dart#L38-L72)

## Testing Strategy

1. Persistence tests must cover a bundle-enabled run whose `$GITHUB_PATH` gains the npm bin directory in the required order, and a bundle-free run whose persisted set is unchanged from the initial release.
2. A bundle-free run must be asserted to make no npm call at all, so requirement 2 is verified by absence rather than by inspection of the output.
3. Cache-key tests must verify these properties:

    - The default `cache: false` flow produces the initial release's setup command log.
    - The default `cache: false` flow runs no cache action.
    - A change to the resolved SDK version, runner architecture, or official archive checksum produces a different key.
    - A change only to the precache plan, activation plan, bundle plan, bootstrap strategy, project dependency files, persistence adapter, or project directory produces the same key.
    - The requested value `stable` and the exact version it resolves to produce the same key.

4. Archive tests must use a restored archive fixture with deliberately modified bytes.
    The fixture must fail checksum verification before extraction.
    The command log must show that no restored SDK executable ran.
    The final SDK path must remain absent.
    The Action must not reach its save step after this failure.
5. Every cache assertion must be demonstrated to fail before it is trusted, matching the initial release's testing strategy.
6. The integration workflow must use a save job and a dependent restore job.
    The restore job must start on a fresh runner because a second invocation in the save job would not test the remote entry.
    Both jobs must pin the same exact SDK version rather than `stable`.
    Both jobs must pin every activated package to an exact version, including `merry` through `--merry-version`.
    These pins prevent an unrelated channel or package release from changing the comparison.
    The restore job must assert the same resolved SDK and activated versions as the save job.
    It must make no request for the upstream SDK release archive.
    It may read release metadata, and the cache action must download its own archive on a hit.
7. The `resolve` command tests must use the recording stubs that the SDK tests already provide.
    The tests must show that `resolve` leaves `MERRY_SETUP_HOME` untouched and reads no network resource beyond release metadata.
    The printed plan for `stable` must contain the checksum and exact version that `setup` uses in the same stubbed environment.
    Equivalent precache order, repetition, and comma grouping must produce the same plan.
    Equivalent activation order must produce the same plan.
    A repeated activation input must remain the error that requirement 37 of the initial release defines.
    Every argument combination that `setup` rejects before mutation must fail in `resolve` with the same message.
    An invalid plan must not reach the restore step.
    The Action must pass the exact version from `resolve` to `setup`.
    A metadata stub whose `stable` answer changes between calls must expose any second channel resolution.
8. The `--sdk-archive` tests must cover a valid restored archive, a corrupt restored archive, and an absent archive path.
    A valid restored archive must be checksum-verified before extraction and must not cause an upstream release-archive request.
    An absent archive path must receive the downloaded and verified archive for the explicit save step.
    A relative path, a symbolic link, a directory, and a path with control characters must fail before SDK mutation.

## Out of Scope

- Remote caching in the portable Bash CLI.
- Caching an extracted SDK tree or Flutter precache artifacts.
- Caching the managed or caller-supplied pub cache.
- A `cache-key-extra` input for project dependency state.
- A generic npm package interface. The npm path remains the named `flutterfire` bundle.
- Cache eviction, size limits, or cleanup beyond what the cache action itself provides.
- Marketplace publication and reusable workflows, still deferred from the initial release.

## Follow-Ups

- Decompose into two independently mergeable Work Items, because the npm persistence change amends the initial release's requirements while the cache change only adds to the Action.
- Amend requirements 64 and 65 of `docs/specs/0001-merry-setup/spec.md` in the same change that implements requirement 1, so the two specs cannot disagree.
- Amend requirement 78 of `docs/specs/0001-merry-setup/spec.md`, which enumerates the Action's inputs exhaustively, in the same change that adds the `cache` input of requirement 6.
- Write a separate Spec before caching any part of `PUB_CACHE`.
  That Spec must define an independent provenance or integrity check for each restored package tree before an executable can use it.
- Re-measure the Flutter integration job's duration after caching lands, and record the before and after rather than describing the improvement qualitatively.
