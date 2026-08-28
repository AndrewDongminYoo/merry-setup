---
type: Spec
title: Merry Setup Initial Release
---

## Problem

The operator maintains multiple Dart and Flutter repositories whose Codex Cloud setup scripts repeat SDK resolution, archive verification, installation, PATH persistence, global tool activation, Trunk setup, and project dependency bootstrap.
The scripts differ primarily in SDK type, global Dart packages, coupled tools such as FlutterFire and Firebase CLI, precache targets, and bootstrap strategy.
Keeping complete copies in every repository makes fixes and security improvements expensive to distribute, while a GitHub-only workflow cannot serve Codex Cloud setup scripts or other compatible Linux shells.

## Proposed Outcome

Create a public repository and executable named `merry-setup` whose portable Bash CLI is the canonical setup implementation.
Each consumer repository keeps a small setup wrapper that downloads or invokes a pinned `merry-setup` revision with project-specific typed arguments.
The same repository provides a thin root composite Action for GitHub Actions and delegates GitHub-native Trunk setup to the official Trunk Action.
The initial release supports Linux x64 and deliberately excludes full CI workflow policy, Marketplace publication, and organization migration. [L1] [L2] [L4] [L5] [L6]

## User Stories

1. As a Dart project maintainer, I can prepare a Codex Cloud container with the selected Dart SDK, `merry`, additional global tools, Trunk, and locked project dependencies from a small repository-local wrapper.
2. As a Flutter project maintainer, I can prepare a Codex Cloud container with the selected Flutter SDK, bundled Dart, required precache artifacts, global tools, Trunk, and the appropriate project bootstrap strategy.
3. As a GitHub Actions author, I can add one composite Action step that exposes installed tools to later steps without adopting a complete reusable workflow.
4. As a project with an exceptional tool policy, I can disable the default `merry` installation explicitly.
5. As a maintainer, I can pin SDK and tool versions where reproducibility matters or deliberately select the current stable SDK where freshness is preferred.
6. As a maintainer of a cached Codex environment, I can rerun project dependency bootstrap without reinstalling the SDK and global tools.
7. As a security-conscious consumer, I receive a deterministic failure for unsupported hosts, invalid inputs, incomplete release metadata, failed downloads, checksum mismatches, missing project manifests, and failed bootstrap commands.

## Requirements

### Repository and Distribution

1. The repository name must be `merry-setup`, and the portable executable path must be `bin/merry-setup`. [L5]
2. The root `action.yml` must define one composite Action named `Merry Setup`; `action.yaml` is not an alternative public entry point. [L1] [L5] [L9]
3. The Bash CLI must remain usable without GitHub Actions environment variables. [L1]
4. Consumer Codex setup scripts must pin the downloaded Bash implementation to an immutable revision and must download it to a file before execution.
5. Documentation must not recommend `curl | bash`, a default branch reference, or a movable major tag as the secure reproducible installation example.
6. The initial release must not publish a reusable workflow or require Marketplace registration. [L2]
7. Before public publication, the repository root must contain a `LICENSE` file that uses the standard MIT License text with the actual copyright year and `Dongmin Yu` as the copyright holder. [L17]
8. Before public publication, the README must identify the repository's original Bash code, Composite Action metadata and adapters, tests, and documentation as MIT-licensed. It must state that downloaded or invoked third-party SDKs, Actions, launchers, packages, and other artifacts remain governed by their respective licenses. It must not imply that `merry-setup` relicenses those components. [L17]

### Commands and Project Context

9. `merry-setup setup` must require explicit SDK and bootstrap selections, install or reuse the selected SDK, install requested global tools, prepare Trunk, persist paths, and run the selected project bootstrap strategy. [L9]
10. `merry-setup bootstrap` must run only project dependency bootstrap and must not download or replace an SDK or global tool.
11. `--project-dir <path>` must select the project root and default to the caller's current working directory.
12. When `setup` or `bootstrap` selects a bootstrap strategy other than `none`, the selected project directory must contain a regular `pubspec.yaml` before any `merry-setup`-controlled setup mutation, including delegated tool setup. [L11]
13. The implementation must not derive the project directory from the downloaded script location.
14. Unknown commands, unknown options, missing option values, and conflicting inputs must fail with a concise error and nonzero status.

### Host and SDK Selection

15. The initial release must support Linux x64 hosts only.
16. Unsupported operating systems and architectures must fail explicitly before downloading an SDK.
17. `--sdk dart|flutter` must select the SDK family and must be required unless an unambiguous future configuration source is specified by a separate approved Spec. [L7]
18. `--sdk-version stable|<exact-version>` must select the requested SDK version and must default to `stable`.
19. Stable Dart resolution must use the official Dart archive metadata, and stable Flutter resolution must use the official Flutter Linux release manifest.
20. Flutter installation must use the bundled Dart executable rather than downloading a second Dart SDK.
21. The minimum effective Dart runtime for the initial release must be 3.12.0. This floor applies uniformly to a standalone Dart SDK, the Dart SDK bundled with Flutter, and an existing SDK reused by `bootstrap`, including configurations that disable Merry or select `bootstrap=none`. [L15]
22. A resolved standalone Dart version below 3.12.0 and a Flutter release whose manifest declares a bundled Dart version below 3.12.0 must fail before the SDK archive is downloaded. Version checks must extract the first semantic version token and compare semantic components rather than strings. The staged or reused Dart executable must be checked again, and a version below the floor or inconsistent with selected release metadata must fail before SDK publication, package activation, PATH persistence, or project bootstrap as applicable. [L15]
23. The implementation must verify SDK archive checksums from official release metadata before publishing an installed SDK.
24. A failed download, incomplete manifest, missing checksum, checksum mismatch, failed extraction, or missing extracted executable must not modify an existing final SDK directory or expose a partially installed final SDK path.
25. Before reuse, an SDK at the requested exact-version final path must pass family, version, executable, and structural validation.
26. The implementation must log the resolved SDK family, version, host architecture, and final executable path.
27. `MERRY_SETUP_HOME` must select the root for `merry-setup`-managed state, including SDKs and the managed default pub cache, must default to `$HOME/.merry-setup`, and must be a nonempty absolute path without control characters or the PATH delimiter `:`. It must remain a supported CLI environment contract rather than a v1 Composite Action input, and it must not relocate the npm global prefix, upstream `TRUNK_PATH`, or project dependency directories. [L13] [L14]
28. After resolving `stable` to an exact release version, the selected SDK root must be `${MERRY_SETUP_HOME}/sdks/<family>/<resolved-version>`; Flutter installations must be keyed by the resolved Flutter version and must continue to use their bundled Dart SDK. [L13]
29. A new SDK must be downloaded, checksum-verified, extracted, and structurally validated in a unique sibling staging directory under the same family directory as its final path. The completed SDK archive tree must become visible through a same-filesystem rename, and no partially extracted final SDK directory may be exposed. [L13]
30. An existing invalid, mismatched, or symbolic-link final path must cause a deterministic failure without automatic deletion or replacement. A concurrent installer that loses publication may reuse the winning installation only after validating it. [L13]
31. PATH persistence must reference the exact resolved-version SDK directory. The initial release must not maintain a mutable `current` SDK alias or automatically remove older SDK versions. [L13]

### Merry and Additional Tools

32. `merry` must be activated globally by default after a compatible Dart executable is available. [L3]
33. `--no-merry` must skip only the default `merry` activation and must not change additional package or bootstrap behavior. [L3]
34. `--merry-version <constraint>` must pass an explicit version constraint to Dart package activation and must conflict with `--no-merry`.
35. Repeated `--dart-package <name>` and `--dart-package <name>=<constraint>` options must contribute additional packages to one validated activation plan. [L7] [L10]
36. Package names and constraints must be split at the first `=`, stored as argument-array elements, and passed without `eval` or shell re-evaluation. [L10]
37. Invalid package names, empty package entries, empty constraints, control characters, repeated package names, and `--dart-package merry` must fail before package activation, including repetitions with identical constraints. [L10]
38. `--bootstrap melos` must ensure a compatible global `melos` executable is available; an explicit `--dart-package melos=<constraint>` supplies the constraint, and an omitted package input adds one unconstrained implicit plan entry. [L10]
39. `--bootstrap very-good` must apply the equivalent rule to `very_good_cli`. [L10]
40. The implementation must log the version of `merry` and every activated global tool when the tool exposes a non-mutating version command.
41. All planned global Dart packages must be installed through `dart pub global activate`; package names and optional constraints must be passed as separate argument-array elements. The initial release must not invoke `dart install`, `dart uninstall`, or `dart installed`, and must not manage `DART_DATA_HOME`. [L15]
42. An omitted tool constraint must let Pub select the latest package version compatible with the effective Dart runtime at execution time. The implementation must log the actual activated version and must not describe an unconstrained result as the latest published package version. [L15]

### Pub Cache and Global Tool State

43. When `PUB_CACHE` is unset, the implementation must set it to `${MERRY_SETUP_HOME}/pub-cache/<family>/<resolved-version>`. When `PUB_CACHE` is set explicitly, including when it is set to an empty value, the override must be validated and must fail unless it is a nonempty absolute path without control characters or the PATH delimiter `:`. The standard environment override must remain an advanced environment contract rather than a v1 Composite Action input. [L14]
44. The resolved `PUB_CACHE` must be exported before Dart package activation, Flutter precache, global tool execution, and project bootstrap, and `${PUB_CACHE}/bin` must precede unrelated global-tool directories on PATH. [L14]
45. The managed default cache must be keyed by the selected SDK family and resolved exact SDK version. Flutter must use the resolved Flutter version rather than its bundled Dart version. After a successful setup, its activation plan determines the current tool versions. v1 does not guarantee plan-level activation rollback after a failed activation. A failure must not clear the cache. Project-specific or activation-plan-specific cache hashing, automatic cache cleanup, and concurrent activation guarantees are out of scope for v1. [L14]

### Coupled Tool Bundles

46. Repeated `--bundle <name>` inputs must enable only documented bundles and must reject duplicate bundle names before mutation.
47. The initial documented bundle must be `flutterfire`. [L7]
48. The `flutterfire` bundle must activate `flutterfire_cli` through Dart exactly once and install `firebase-tools` through npm; an explicit `--dart-package flutterfire_cli=<constraint>` supplies the Dart package constraint instead of creating a second activation. [L10]
49. `--firebase-tools-version <exact-version>` must be valid only when the `flutterfire` bundle is enabled; it must select `firebase-tools@<exact-version>`, while omission deliberately selects npm's current default version, and either mode must fail with an actionable error when npm is unavailable. [L9]
50. Passing `--dart-package flutterfire_cli` without `--bundle flutterfire` must not install `firebase-tools`; the coupled npm side effect requires the named bundle. [L7] [L10]
51. A future generic npm package interface is out of scope for the initial release.

### Flutter Precache

52. The initial documented Flutter precache targets must be exactly `android`, `web`, and `linux`. Repeated `--precache <targets>` options may contain comma-separated targets, but unknown targets, the token `none`, and empty comma-separated entries must fail before precache mutation. [L16]
53. Precache inputs must be invalid when `--sdk dart` is selected and must fail before SDK or precache mutation. [L16]
54. When at least one target is selected, the implementation must deduplicate all targets and invoke Flutter exactly once with explicit flags in the canonical order `--android --web --linux`, while omitting unselected flags. When no target is selected, the implementation must skip precaching and must not invoke bare `flutter precache`. [L16]
55. Precache targets request Flutter platform artifacts and do not promise a complete platform toolchain or offline build readiness. Selecting `android` must not require or install an Android SDK, and the implementation must not install browsers or Linux desktop system packages. The selected Flutter SDK version governs the exact transitive and universal artifact set. [L16]

### Trunk Integration

56. The initial GitHub composite Action must delegate Trunk setup to `trunk-io/trunk-action/setup@e1234e67a86010d61ddac8d8ebf4b783e2ffd2fa`, the verified full commit SHA for `v2.0.0`. [L4] [L9]
57. The composite Action must consume the upstream `TRUNK_PATH` contract instead of copying `locate_trunk.sh`. [L4]
58. `--trunk-path <path>` must select an explicit executable Trunk launcher; when the option is absent, the portable Bash setup must first reuse a launcher found at a documented repository-local location. [L9]
59. When no launcher is available outside GitHub Actions, the portable setup may download the official Trunk launcher from the upstream endpoint used by Trunk.
60. `merry-setup` must not maintain an independent Trunk release index or checksum table when upstream does not publish that contract. [L4]
61. The implementation must log the selected launcher path and invoke its non-mutating version command before reporting success.
62. The actual Trunk CLI and linter versions remain governed by the consumer repository's `.trunk/trunk.yaml`.

### PATH Persistence

63. `--persist-path bashrc|github|none` must select the persistence adapter. [L7]
64. `bashrc` mode must idempotently replace one `merry-setup`-managed block in `~/.bashrc`, or append the block when absent. The block must safely quote and export the resolved `PUB_CACHE` and must set PATH with the exact SDK bin directory, `${PUB_CACHE}/bin`, the local tool bin directory, and the pre-existing PATH without accumulating stale exact-version entries. [L14]
65. `github` mode must write the resolved `PUB_CACHE` to `$GITHUB_ENV` and append the exact SDK bin directory, `${PUB_CACHE}/bin`, and the local tool bin directory to `$GITHUB_PATH`; it must fail clearly before those writes when either environment file is unavailable. [L14]
66. `none` mode must export the resolved `PUB_CACHE` and update PATH only for the CLI process and its child commands without modifying a persistence file. [L14]
67. Every mode must make the resolved `PUB_CACHE` and PATH effective before invoking installed tools.
68. The composite Action must select `github` persistence and must not edit runner shell profile files.

### Project Bootstrap

69. `--bootstrap none|dart|flutter|melos|very-good` must explicitly select one bootstrap strategy. [L7] [L9]
70. `dart` must run `dart pub get`, and `flutter` must run `flutter pub get`.
71. `melos` must run `melos bootstrap` without a redundant preceding root `flutter pub get`.
72. `very-good` must run the documented recursive Very Good package-get command.
73. When `pubspec.lock` is tracked at the selected project root, direct Dart or Flutter pub get and Melos bootstrap must use their documented `--enforce-lockfile` option.
74. An untracked or absent root lockfile must not enable `--enforce-lockfile` automatically.
75. `none` must skip project dependency commands without skipping SDK or tool setup.
76. A failed bootstrap command must propagate its nonzero status and prevent the final success message.
77. The `bootstrap` command must locate the requested SDK family through PATH and verify its exact installed version without querying remote release metadata or resolving `stable` again. When no explicit `PUB_CACHE` override is supplied, it must derive the managed cache from that exact installed version. An explicitly requested exact SDK version must match the located executable, and a missing or mismatched executable must fail before bootstrap mutation. [L14]

### GitHub Composite Action

78. The v1 Action must expose exactly these string-valued public inputs: required `sdk`, required `bootstrap`, and optional `sdk-version`, `merry`, `merry-version`, `dart-packages`, `bundles`, `firebase-tools-version`, `precache`, `project-dir`, and `trunk-path`; `merry` must accept only `true` or `false` and default to `true`. [L1] [L7] [L9] [L14]
79. `dart-packages`, `bundles`, and `precache` must use a documented newline-delimited representation; `action/run.sh` must ignore blank lines, remove one trailing carriage return from CRLF-authored lines, and convert every remaining line to exactly one Bash argument without shell re-evaluation. [L9]
80. Action expressions must be assigned through `env` entries rather than interpolated directly into a `run` command, and `action/run.sh` must construct the canonical CLI invocation as an argument array. [L9]
81. The Action must expect the consumer to check out its repository before invocation and must not perform checkout itself.
82. The Action must always execute full `setup`, must select `github` PATH persistence, must use `$GITHUB_PATH` or `$GITHUB_ENV` for values needed by later workflow steps, and must not expose a command selector or v1 outputs. [L9]
83. Before invoking `trunk-io/trunk-action/setup`, `action/preflight.sh` must validate only the bootstrap enum and, unless the value is `none`, the existence of a regular `pubspec.yaml` under the resolved project directory; it must not write files, install tools, or validate unrelated inputs. [L11]
84. The Action preflight must not replace canonical validation; after delegated Trunk setup, `bin/merry-setup` must independently repeat the project-manifest check before its own mutations. [L11]
85. The Action must not request a GitHub token or write permission for setup behavior.

### Idempotence, Cleanup, and Output

86. Repeated setup with matching inputs must reuse matching SDK installations, maintain one current profile block, activate each planned Dart package at most once per invocation, restore the requested activation plan when rerun against a mutable shared cache, and leave each requested known tool executable usable. [L14]
87. Temporary files and directories created by the Bash CLI must be removed on normal exit and handled through an exit trap on failure; a failed package activation must not delete the resolved pub cache. [L14]
88. The implementation must use `set -euo pipefail` and must not use `eval`.
89. Error messages must identify the failing requirement, requested value, or missing prerequisite without printing secrets or unrelated environment variables.
90. A success message must be emitted only after SDK setup, requested tools, Trunk setup, PATH persistence, and selected project bootstrap have completed.
91. `DEBUG=1` may enable shell tracing, and documentation must warn consumers not to use debug tracing when secret-bearing commands or environments are introduced in the future.

## Technical Decisions

1. Bash is the canonical bootstrap implementation because it must run before Dart or Flutter is available. [L1]
2. Project-local setup wrappers remain part of the supported design because they capture project configuration and make pinned implementation upgrades visible to Codex environment caching. [L1]
3. The GitHub integration is a composite Action rather than a reusable workflow because setup is one step within consumer-owned jobs. [L2]
4. `merry` is a product default with a negative opt-out because it is shared by the current consumer set. [L3]
5. FlutterFire is a named bundle because installing `firebase-tools` is a material cross-ecosystem side effect that should not be hidden behind a generic Dart package request. [L7]
6. Trunk remains an upstream-owned integration, with GitHub Actions delegating to `trunk-io/trunk-action/setup` and portable Bash using only the official launcher contract. [L4]
7. Full CI workflow policy, Marketplace distribution, and organization ownership are lifecycle concerns outside the initial setup implementation. [L2] [L6]
8. The initial platform remains Linux x64 so the first release can preserve the behavior already exercised by the source setup scripts instead of claiming unverified portability. [L7]
9. No executable or Action placeholder is part of the specification scaffold because a nonfunctional setup surface would be misleading. [L8]
10. The v1 Action public API remains intentionally smaller than general-purpose setup Actions: SDK and bootstrap intent are explicit, Merry is the only first-class default tool toggle, and all other supported tools use bootstrap implications, named bundles, or validated Dart package inputs. [L9] [L10]
11. Package activation uses one validated name-keyed installation plan so implicit Melos, Very Good, and FlutterFire requirements can consume explicit constraints without duplicate work. [L10]
12. The Action preflight is a narrow non-mutating guard before delegated Trunk setup, while the portable Bash CLI remains the canonical full validator and repeats the manifest check to preserve its standalone contract. [L11]
13. Private local workflow metadata is not part of the public repository scaffold, and empty standard directories do not need tracked placeholders before they contain an authorized artifact. [L12]
14. SDK installations use a version-addressed portable store rooted at the supported `MERRY_SETUP_HOME` environment contract. Stable selections resolve before path derivation, validated SDK trees are atomically published from sibling staging directories, and each run uses the exact resolved-version path without a mutable `current` alias. [L13]
15. Unless the caller explicitly overrides the standard `PUB_CACHE` environment contract, pub state uses an SDK-family- and exact-version-addressed managed default under `MERRY_SETUP_HOME`. Persistence adapters keep `PUB_CACHE` and PATH aligned, while projects sharing one resolved cache deliberately share a mutable activation namespace without v1 concurrency guarantees. [L14]
16. The initial release deliberately retains `dart pub global activate` and one minimum effective Dart runtime of 3.12.0 as the smallest implementation and validation surface for its approved SDK-scoped pub activation model. The floor is a fixed v1 compatibility policy rather than a floating calculation from future package releases. [L15]
17. The v1 precache API exposes only the `android`, `web`, and `linux` platform targets and maps their canonical set to one explicit upstream invocation. Flutter continues to own transitive artifact selection, while platform toolchain installation remains outside the setup contract. [L16]
18. The MIT License is selected for the initial public repository to minimize adoption and redistribution friction. The current project risk model does not require explicit patent licensing or Apache-style notice management. [L17]

## Testing Strategy

1. Shell syntax checks must run `bash -n` against explicit executable and test paths.
2. ShellCheck must inspect explicit Bash paths, and any repository formatter or rewriting tool must receive explicit paths.
3. Unit tests must prepend a fixture-controlled command directory to PATH and stub `uname`, `curl`, `tar`, `git`, `dart`, `flutter`, `npm`, and the Trunk launcher as required by each scenario.
4. Tests must set isolated `HOME`, `MERRY_SETUP_HOME`, `PUB_CACHE`, temporary, and project directories and must never mutate the operator's real home directory.
5. SDK manifest and archive checksum behavior must be tested with local fixtures for a valid release, incomplete metadata, missing requested architecture, and checksum mismatch.
6. A checksum or manifest validator must first be demonstrated to fail on an intentionally broken fixture before its passing fixture is accepted as evidence.
7. SDK-store tests must verify `stable` resolution to an exact version before final-path derivation, exact resolved-version PATH entries, unique sibling staging directories, same-filesystem atomic publication, cleanup after a failed pre-publication step, reuse of a valid installation, deterministic rejection of an invalid or symbolic-link final path, and validation of a winning installation after a same-version publication race. [L13]
8. Runtime-floor tests must verify that standalone Dart 3.11.4 metadata and a Flutter manifest declaring bundled Dart 3.11.x fail before the SDK archive download stub, while 3.12.0 reaches installation; a build-description manifest value yields its first semantic version token; semantic comparison is not lexicographic; a staged metadata mismatch fails before publication; an installed SDK below the floor is not reused; bootstrap with PATH Dart below the floor performs no project mutation; and `--no-merry` with `bootstrap=none` does not bypass the floor. [L15]
9. Pub-cache selection tests must verify family separation even when standalone Dart and Flutter bundle the same Dart version, exact-version separation, `stable` resolution before managed-path derivation, explicit override precedence, failure for set-but-empty, relative, or control-character overrides, and preservation of a failed activation's cache contents. [L14]
10. Persistence and command-flow tests must verify that every Dart, Flutter, global-tool, and bootstrap stub receives the same resolved `PUB_CACHE`; `bashrc` reruns maintain one managed block and replace stale exact-version paths; GitHub mode writes both `$GITHUB_ENV` and `$GITHUB_PATH`; and `none` mode changes no persistence file. [L14]
11. Command-flow tests must record exact stub invocations and verify ordering for Dart setup, Flutter setup, Merry default activation, `--no-merry`, additional Dart packages, implicit and explicitly constrained Melos, Very Good, and FlutterFire packages, each bootstrap strategy, bootstrap-only maintenance, and restoration of a newly requested tool constraint in a shared mutable cache. Package constraints must remain separate argument-array elements, and no flow may invoke `dart install`. [L3] [L7] [L10] [L14] [L15]
12. Precache tests must verify that omitting all targets produces zero Flutter invocations, `android` maps to `--android`, `web,android` maps to `--android --web`, and separate inputs containing `linux`, `android,web`, and repeated `android` normalize to one `--android --web --linux` invocation. They must verify that `--sdk dart` with a target fails before SDK or precache mutation. They must also verify that `android,`, `,web`, `android,,web`, `none`, `ios`, `all`, and `android_maven` fail validation. A failing Flutter precache stub must propagate its status and suppress the final success message. [L16]
13. Lockfile tests must distinguish a tracked root lockfile, an untracked root lockfile, and an absent lockfile.
14. Failure tests must cover unsupported operating systems and architectures, an effective Dart runtime below 3.12.0, invalid packages, repeated package names, invalid bundles, invalid precache targets, invalid `PUB_CACHE` overrides, missing npm, invalid Firebase Tools versions, missing `pubspec.yaml`, download failure, extraction failure, version mismatch, invalid SDK final paths, a missing or wrong-family bootstrap SDK, failed package activation, and downstream command failure.
15. Idempotence tests must run setup twice against the same isolated fixture and verify exact-version SDK reuse, one activation per planned Dart package per invocation, one current profile block, and stable installed paths.
16. Action adapter tests must verify that `bootstrap=none` skips the manifest check, supported non-`none` values require `pubspec.yaml`, invalid bootstrap values fail before Trunk setup, relative and absolute project directories including spaces resolve correctly, and no preflight failure reaches the delegated Trunk step. [L11]
17. Action adapter tests must verify safe LF and CRLF multiline-input conversion, blank-line handling, GitHub `PUB_CACHE` and PATH persistence, upstream `TRUNK_PATH` consumption, and failure when required GitHub environment files are missing. [L9] [L14]
18. Canonical CLI tests must verify that a direct non-`none` setup with no manifest calls no mutation stub, deleting the manifest after a passing Action preflight still causes the CLI to fail before its own mutation stubs, and bootstrap derives its managed cache from the existing PATH-selected exact SDK without querying stable release metadata. [L11] [L14]
19. Unit and command-flow tests must not download a real Dart or Flutter SDK.
20. Before the initial release, isolated Linux x64 integration workflows must exercise `sdk=dart`, `bootstrap=dart`, and Merry by default; `sdk=flutter`, `bootstrap=melos`, the FlutterFire bundle, and the `android`, `web`, and `linux` precache targets; and exact Dart 3.12.0 with Merry and Very Good CLI activation. [L15] [L16]
21. The integration workflows must pin every third-party Action to a verified full commit SHA.

## Out of Scope

- macOS, Windows, Linux ARM64, Android host setup, and iOS host setup.
- Installing operating-system packages through apt, Homebrew, Chocolatey, or another system package manager.
- FVM, mise, asdf, or another version-manager integration.
- A generic npm global package interface beyond the named FlutterFire bundle.
- Action inputs for architecture selection, caching, automatic SDK or bootstrap detection, per-tool booleans, generic npm packages, or command selection. [L9]
- Composite Action outputs for the initial release. [L9]
- GitHub reusable workflows for analyze, test, coverage, release, or deployment policy. [L2]
- Marketplace publication for the initial release. [L2]
- Creating or migrating to a Merry organization. [L6]
- Creating GitHub repositories, remotes, releases, tags, or published artifacts as part of the local specification scaffold. [L8]
- Consumer repository migrations.
- Action or SDK caching beyond the behavior supplied by Codex environments and upstream setup tools.
- Automatic SDK garbage collection or a mutable `current` SDK alias. [L13]
- Project-specific or activation-plan-specific pub-cache hashing. [L14]
- Concurrent global activation guarantees or locking for setup processes that share one resolved pub cache. [L14]
- Automatic cleanup of old managed pub caches. [L14]
- `dart install`, `dart uninstall`, `dart installed`, or a `DART_DATA_HOME`-based global tool state model in v1. [L15]
- Contributor license agreements, developer certificate of origin enforcement, and third-party source or binary vendoring policy. [L17]

## Open Questions

No product-contract or publication-input questions remain for the initial release. Publication preparation must verify the actual copyright year before creating `LICENSE`. [L17]

## Follow-Ups

- Review this Spec for contradictions and unnecessary scope before decomposing implementation work.
- Create independently executable Work Items for the portable CLI, GitHub Action adapter, tests, documentation, and release hardening; the SDK installation Work Item must cover `stable` resolution to an exact version, the minimum effective Dart runtime, exact-version final-path derivation, sibling staging publication, Pub global activation, managed pub-cache selection and override validation, persistence adapters, and bootstrap cache derivation. [L13] [L14] [L15]
- Ensure that the Flutter setup Work Item covers precache target validation, deterministic normalization, one explicit upstream invocation, and failure propagation without platform toolchain installation. [L16]
- Before public publication, create the root `LICENSE` from the standard MIT text with the verified copyright year and `Dongmin Yu` as the copyright holder. [L17]
- Before public publication, add the README License section and its third-party licensing boundary. [L17]
- Publication validation must fail if the copyright year remains unresolved or the holder is not exactly `Dongmin Yu`. [L17]
- If future work vendors third-party source or binary artifacts, add a license and notice review as a publication blocker before accepting that vendoring scope. [L17]
- Configure the repository's Trunk quality gate before product implementation begins.
- Create the GitHub repository and remote only after explicit authorization for that external change.
- Create a separate Spec for `dart install` only if Dart publishes a removal schedule for Pub global activation, a required tool depends on `dart install` or native build hooks, AOT startup becomes more important than setup simplicity, or consumers require an SDK-independent binary store. [L15]
