---
type: Interview Ledger
parent: spec.md
---

## Records

### L1

Status: current

Question: How should repeated Dart and Flutter cloud setup logic be shared across repositories?

Recommended Answer:
- Publish one portable Bash setup implementation in a dedicated public repository.
- Keep a small project-local `setup.sh` wrapper in each consumer repository.
- Add a thin GitHub composite action over the same setup contract.

Answer: 좋습니다.

Decision: `merry-setup` must use a portable Bash CLI as the source of truth, preserve small project-local wrappers for Codex Cloud, and expose a thin GitHub composite action.

Reason: Bash is the common bootstrap layer available before Dart or Flutter is installed, while project-local wrappers make configuration and Codex cache invalidation explicit.

### L2

Status: current

Question: Should the shared automation be a reusable workflow or a Marketplace-first Action?

Recommended Answer:
- Use a composite action for setup inside an existing job.
- Keep complete CI jobs and policy in separate reusable workflows if they become necessary.
- Defer Marketplace publication until the input contract has been exercised and stabilized.

Answer: 좋습니다.

Decision: The initial release must provide a composite action and must not include a reusable workflow or Marketplace publication work.

Negative Requirements:
- Do not bundle analyze, test, coverage, or release policy into the setup Action.

### L3

Status: current

Question: Should consumers have to request the `merry` global package explicitly?

Answer: No. Every current consumer project uses `merry`, so install it unless the consumer explicitly opts out.

Decision: `merry` must be installed by default and the CLI must provide an explicit `--no-merry` opt-out.

### L4

Status: current

Question: How should Trunk installation be handled?

Answer: Trunk has a different responsibility and already provides `trunk-action`, so use the upstream Trunk setup path instead of owning a separate GitHub installation implementation.

Decision: The composite action must delegate GitHub-native Trunk setup to `trunk-io/trunk-action/setup` pinned to a full commit SHA. The portable Bash path must use the same official Trunk launcher contract without copying GitHub-specific `GITHUB_ENV` implementation details.

Reason: The repository should not become an independent Trunk distributor or duplicate upstream Action behavior.

### L5

Status: current

Question: What should the repository and tool be named?

Answer: Use `merry-setup`.

Decision: The repository, executable, and Action display name must use `merry-setup` or `Merry Setup` consistently.

### L6

Status: current

Question: Should a separate organization be created for the initial project?

Answer: No. Start with the personal `merry-setup` repository and move Merry ecosystem tools to a dedicated organization later if the ecosystem grows.

Decision: Organization creation and repository transfer are deferred until multiple independent Merry ecosystem tools justify the additional ownership structure.

### L7

Status: current

Question: Which project-specific differences must the shared setup contract represent?

Recommended Answer:
- Select Dart or Flutter and allow stable or exact SDK versions.
- Accept validated additional global Dart packages.
- Represent FlutterFire and Firebase CLI as an explicit coupled bundle.
- Select Dart, Flutter, Melos, or Very Good bootstrap behavior.
- Select Codex Bash, GitHub Actions, or no PATH persistence.
- Keep Linux x64 as the initial supported host.

Answer: 좋습니다.

Decision: The initial contract must represent SDK selection, SDK version, additional global Dart packages, coupled bundles, project bootstrap, Flutter precache targets, project directory, and PATH persistence through typed inputs.

Negative Requirements:
- Do not accept arbitrary shell fragments.
- Do not infer hidden npm side effects from a generic Dart package input.

### L8

Status: superseded in part by L12

Question: What should be created before product implementation begins?

Answer: Create the minimal `merry-setup` scaffold and specification.

Decision: The initial repository change must contain project guidance, standard documentation directories, workflow storage configuration, an Interview Ledger, and a Spec, but no placeholder installer or Action that appears usable before implementation.

### L9

Status: current

Question: What should the public GitHub composite Action expose in the initial release?

Recommended Answer:
- Require explicit `sdk` and `bootstrap` inputs.
- Keep Merry as the only first-class default tool input.
- Represent Melos and Very Good through bootstrap implications, FlutterFire through a named bundle, and remaining Dart tools through newline-delimited package inputs.
- Fix the public entry point at `action.yml`, use small Bash adapters, and omit caching, architecture selection, automatic detection, command selection, generic npm packages, and outputs.

Answer: Approved this minimal Action surface, added `--trunk-path <path>`, and selected optional exact Firebase Tools versioning rather than an always-latest-only contract.

Decision: The initial `action.yml` must expose required `sdk` and `bootstrap` strings plus the approved minimal optional inputs, delegate input conversion to `action/run.sh`, pass the upstream `TRUNK_PATH` to the canonical CLI, and support `--firebase-tools-version <exact-version>` only for the FlutterFire bundle.

Negative Requirements:
- Do not add separate Melos, Very Good, FlutterFire, Trunk installation, architecture, cache, automatic detection, generic npm package, or command inputs.
- Do not add Composite Action outputs until a real consumer requires them.

### L10

Status: current

Question: How should explicit Dart package inputs interact with tools implied by Merry, bootstrap strategies, and bundles?

Answer: Build one package-name-keyed activation plan before mutation, reject repeated package names, and let one explicit constraint configure an otherwise implicit Melos, Very Good, or FlutterFire CLI entry.

Decision: Merry is managed only through its first-class inputs; an explicit Melos, Very Good, or FlutterFire CLI package constraint overrides the corresponding implicit unconstrained plan entry without causing a second activation; duplicate explicit package names fail even when their constraints match.

Negative Requirements:
- Do not silently merge repeated explicit package inputs.
- Do not treat repeated activation as idempotence.
- Do not infer the Firebase Tools npm side effect from `flutterfire_cli` without the named FlutterFire bundle.

### L11

Status: current

Question: How should the composite Action preserve the manifest-before-mutation requirement when Trunk setup is delegated?

Answer: Run a narrow non-mutating Action preflight before Trunk setup, skip the manifest check for `bootstrap=none`, validate only the bootstrap enum and manifest context, and require the canonical CLI to repeat the manifest check before its own mutations.

Decision: `action/preflight.sh` must guard the delegated Trunk mutation without becoming a second canonical validator, and `bin/merry-setup` must repeat the manifest check to preserve standalone behavior and protect the interval between preflight and CLI execution.

Negative Requirements:
- Do not validate SDKs, package syntax, bundles, precache targets, Merry conflicts, npm availability, or host support in the Action preflight.
- Do not let a passing Action preflight suppress the canonical CLI manifest check.

### L12

Status: current

Question: Which local workflow and empty-directory artifacts belong in the public repository scaffold?

Answer: Private local workflow metadata must remain ignored, and empty standard directories do not need placeholder files before an authorized artifact exists.

Decision: Public tracked files must not expose private local workflow metadata, and unnecessary `.gitkeep` files must remain absent until implementation creates a real file in the corresponding directory.

### L13

Status: current

Question: Where should Dart and Flutter SDK installations be stored and how should a completed installation become visible?

Recommended Answer:
- Use `MERRY_SETUP_HOME` as a supported low-level environment override, defaulting to `$HOME/.merry-setup`, without adding a public Action input.
- Store SDKs under family- and resolved-version-specific directories.
- Resolve `stable` to an exact version before deriving the installation path.
- Extract and validate each archive in a unique sibling staging directory, then publish the completed SDK tree through a same-filesystem rename.
- Add the exact resolved SDK bin directory to PATH instead of maintaining a mutable `current` symlink.

Answer: Approved.

Decision: `merry-setup` must use a version-addressed SDK store rooted at `MERRY_SETUP_HOME`, defaulting to `$HOME/.merry-setup`. Completed SDK trees must become visible only through same-filesystem atomic publication from a validated sibling staging directory.

Negative Requirements:
- Do not expose the SDK installation root as a v1 Action input.
- Do not use `RUNNER_TOOL_CACHE` as the canonical portable CLI location.
- Do not name an installed SDK directory `stable`.
- Do not maintain a mutable `current` SDK symlink.
- Do not delete or replace an invalid pre-existing version directory automatically.
- Do not implement automatic SDK garbage collection in v1.

### L14

Status: current

Question: Where should the Dart system package cache and globally activated tool state be stored?

Recommended Answer:
- Default `PUB_CACHE` to an SDK-family- and resolved-version-specific directory under `MERRY_SETUP_HOME`.
- Honor an explicitly supplied standard `PUB_CACHE` value as an advanced override without adding a public Action input.
- Export and persist both `PUB_CACHE` and its `bin` directory.
- Share one mutable activation namespace among projects using the same SDK family and exact version, without adding project or activation-plan hashing or failed-plan rollback in v1.

Answer: Approved.

Decision: Unless the caller explicitly supplies `PUB_CACHE`, `merry-setup` must use `${MERRY_SETUP_HOME}/pub-cache/<family>/<resolved-version>`. An explicit managed-state or pub-cache path must be a nonempty absolute path without control characters or the PATH delimiter `:` because each resolved `bin` directory becomes one PATH entry. The resolved cache must be used consistently for global package activation, tool execution, and project dependency bootstrap, and must be persisted alongside PATH when the selected adapter supports persistence.

Negative Requirements:
- Do not silently fall back to `$HOME/.pub-cache`.
- Do not expose a v1 Action input for the pub cache location.
- Do not share the managed default cache across SDK families or exact SDK versions.
- Do not add project-specific or activation-plan-specific cache hashing in v1.
- Do not claim plan-level activation atomicity or rollback after a failed activation.
- Do not claim concurrent activation safety for two setup processes sharing one resolved cache.
- Do not automatically clean or delete old pub caches in v1.

### L15

Status: current

Question: Which global Dart tool installation mechanism and minimum Dart runtime should the initial release support?

Recommended Answer:
- Use `dart pub global activate` as the v1 global Dart tool installation mechanism even though Dart now classifies it as legacy.
- Require an effective Dart runtime of at least 3.12.0 for every setup and bootstrap configuration.
- Apply the minimum to standalone Dart, Flutter's bundled Dart, and an existing SDK selected by the bootstrap-only command.
- Treat an unconstrained tool activation as the latest version compatible with the selected SDK, not as a promise to install the latest published package version.

Answer: Approved.

Decision: The initial release must use `dart pub global activate` for Merry and all additional or implied global Dart packages. The minimum effective Dart runtime is 3.12.0 and applies uniformly even when Merry is disabled or project bootstrap is `none`.

Reason: Dart 3.12.0 was the smallest shared runtime baseline for the current v1 implicit tool releases on 2026-08-27, while one uniform floor avoids a tool-plan-dependent compatibility matrix. Retaining Pub global activation also preserves the approved SDK-scoped `PUB_CACHE` activation and executable contract for v1. The dated package calculation is decision evidence rather than a floating compatibility rule.

Negative Requirements:
- Do not invoke `dart install`, `dart uninstall`, or `dart installed` in v1.
- Do not introduce a v1 `DART_DATA_HOME` installation-state contract.
- Do not describe `dart pub global activate` as Dart's currently recommended installation mechanism.
- Do not claim that an unconstrained activation installs the latest published package version.
- Do not vary the minimum runtime according to Merry opt-out, bootstrap strategy, bundle selection, or package plan.
- Do not compare semantic versions lexicographically.

### L16

Status: current

Question: Which Flutter precache targets should the initial public contract support?

Recommended Answer:
- Expose only `android`, `web`, and `linux`.
- Treat the values as requested Flutter platform artifact targets rather than complete platform-toolchain installation promises.
- Invoke `flutter precache` only when at least one target is selected and always pass explicit upstream platform flags.
- Keep Android SDK, browsers, Linux desktop system packages, upstream force behavior, all-platform selection, and granular artifact flags out of scope.

Answer: Approved.

Decision: The initial release must accept only `android`, `web`, and `linux` as Flutter precache targets. The implementation must validate each repeated or comma-separated input token. It must deduplicate the selected targets and normalize them into the fixed order `android`, `web`, `linux`. It must pass the selected targets through one explicit `flutter precache` invocation.

Reason: The upstream precache surface is broader than the Linux x64 v1 scope and includes controls that would expose internal artifact details as a public compatibility contract. Explicit platform flags prevent Flutter's host- and configuration-dependent default selection when the caller supplied no target.

Negative Requirements:
- Do not invoke bare `flutter precache` when no target was supplied.
- Do not expose `all`, `all-platforms`, `force`, `universal`, `host-arch`, or granular Android artifact flags.
- Do not install or require an Android SDK merely because `android` was selected.
- Do not install browsers or Linux desktop system packages.
- Do not describe successful precaching as complete offline platform build readiness.
- Do not promise an exact downloaded-file set independently of the selected Flutter SDK version.

### L17

Status: current

Question: Which public license should govern the initial repository?

Recommended Answer:
- License the repository's original Bash code, Composite Action metadata and adapters, tests, and documentation under the MIT License.
- Preserve the standard MIT copyright and permission notice.
- Clarify that downloaded or invoked third-party SDKs, Actions, launchers, packages, and other artifacts remain governed by their respective licenses.

Answer: Approved. Use `Dongmin Yu` as the copyright holder.

Decision: The initial public `merry-setup` repository must use the MIT License. Before public publication, the repository root must contain a `LICENSE` file with the standard MIT text, the actual copyright year, and `Dongmin Yu` as the copyright holder.

Reason: The project intends broad reuse across personal and external Dart and Flutter repositories. MIT permits broad reuse while minimizing consumer obligations. The current project risk model does not require the patent and notice-management surface of Apache-2.0.

Negative Requirements:
- Do not claim that MIT covers or relicenses third-party SDKs, Actions, launchers, packages, or downloaded artifacts.
- Do not publish a `LICENSE` file with unresolved year or copyright-holder placeholders.
- Do not add Apache-2.0 `NOTICE` handling or modified-file notice requirements to the v1 repository.
- Do not require per-file license headers in the initial release.
- Do not add a CLA or DCO process without a demonstrated contribution-policy need.
