# merry-setup

`merry-setup` is a bootstrap tool for consistent Dart and Flutter development environments across Codex Cloud, GitHub Actions, and compatible Linux x64 shells.

One Bash implementation, `bin/merry-setup`, installs a versioned Dart or Flutter SDK, activates global Dart tools, prepares the Trunk launcher, persists `PATH` and `PUB_CACHE`, and runs the selected project bootstrap.
The root `action.yml` is a thin GitHub composite action over that same implementation.

## What a setup run does

1. Validates every option and the project manifest before any download or file mutation.
2. Resolves `stable` to an exact release version from the official Dart or Flutter release metadata.
3. Installs the SDK into `${MERRY_SETUP_HOME}/sdks/<family>/<version>` through a checksum-verified staging directory, or reuses a valid existing installation.
    A caller can supply a local release archive that the CLI copies into private staging, binds to current official checksum metadata, and extracts only from that verified snapshot.
4. Derives a managed `PUB_CACHE` for that exact SDK version and activates `merry` plus every requested global tool with `dart pub global activate`.
5. Installs the `flutterfire` bundle (`flutterfire_cli` and `firebase-tools`) when requested.
6. Runs `flutter precache` once with the selected platform targets.
7. Selects a Trunk launcher and confirms it with `trunk version`.
8. Persists `PATH` and `PUB_CACHE` through the selected adapter.
9. Runs the selected project bootstrap strategy.
10. Prints `Merry setup completed` only after every step succeeded.

## Requirements

- Linux x64. Other operating systems and architectures fail before any download.
- Bash 4 or newer, `curl`, `tar`, `unzip`, `sha256sum`, and GNU `mv`.
- `git` on `PATH` whenever the project root holds a `pubspec.lock` and the bootstrap strategy is `dart`, `flutter`, or `melos`. Those strategies decide `--enforce-lockfile` from the lockfile's tracked state, which is unknowable without git, so setup fails rather than guessing. `none` and `very-good` never inspect it.
- `npm` on `PATH` only when the `flutterfire` bundle is requested.
- The effective Dart runtime must be at least 3.12.0, whether it is a standalone Dart SDK or the Dart bundled with Flutter.

## CLI

```plaintext
merry-setup setup     --sdk dart|flutter --bootstrap STRATEGY --persist-path ADAPTER [options]
merry-setup resolve   --sdk dart|flutter --bootstrap STRATEGY --persist-path ADAPTER [options]
merry-setup bootstrap --sdk dart|flutter --bootstrap STRATEGY --persist-path ADAPTER [options]

STRATEGY: none | dart | flutter | melos | very-good
ADAPTER:  none | bashrc | github
```

`setup` performs the full flow above.
`resolve` validates the same Action-exposed setup options and prints a normalized line-oriented plan without downloading an SDK archive, extracting files, changing `MERRY_SETUP_HOME`, or persisting environment state.
It reads only official release metadata.
`bootstrap` locates the SDK family already on `PATH`, verifies its exact version and the runtime floor, derives the same managed `PUB_CACHE`, and runs only the bootstrap strategy; it never downloads an SDK, activates a tool, or reads remote release metadata.

| Option | Meaning |
| --- | --- |
| `--sdk-version stable\|<exact>` | SDK version to install or, for `bootstrap`, to require on `PATH`. Defaults to `stable`. |
| `--project-dir <path>` | Project root containing `pubspec.yaml`. Defaults to the current working directory. |
| `--no-merry` | Skip the default `merry` activation. |
| `--merry-version <constraint>` | Pub version constraint for `merry`. Conflicts with `--no-merry`. |
| `--dart-package <name>[=<constraint>]` | Additional global package. Repeatable. Explicit constraints also apply to implied `melos`, `very_good_cli`, and `flutterfire_cli`. |
| `--bundle flutterfire` | Activate `flutterfire_cli` and install `firebase-tools` through npm. Repeatable for future bundles. |
| `--firebase-tools-version <exact>` | Exact `firebase-tools` version. Valid only with the `flutterfire` bundle. |
| `--precache <targets>` | Comma-separated `android`, `web`, `linux`. Repeatable. Flutter only. |
| `--trunk-path <path>` | Explicit Trunk launcher. When absent, `.trunk/bin/trunk`, `tools/trunk`, and `trunk` under the project are reused, then `${MERRY_SETUP_HOME}/bin/trunk`, then the official launcher is downloaded. |
| `--sdk-archive <path>` | Absolute local SDK archive transport path. Valid only for `setup` and only with `--sdk-archive-sha256`. |
| `--sdk-archive-sha256 <digest>` | Exact lowercase SHA-256 from a prior `resolve` plan. Valid only for `setup` and only with `--sdk-archive`. |

Bootstrap strategies run `dart pub get`, `flutter pub get`, `melos bootstrap`, or `very_good packages get --recursive` inside the project directory.
`--enforce-lockfile` is added to the Dart, Flutter, and Melos commands when the root `pubspec.lock` is tracked by git.
`--bootstrap flutter` requires `--sdk flutter`; `--bootstrap melos` and `--bootstrap very-good` imply the matching global tool during `setup` and require it to be present during `bootstrap`.

### Environment contracts

| Variable | Behavior |
| --- | --- |
| `MERRY_SETUP_HOME` | Root for managed SDKs, the managed pub cache, and the downloaded Trunk launcher. Defaults to `$HOME/.merry-setup`. Must be an absolute path without `:` or control characters. |
| `PUB_CACHE` | Overrides the managed cache. When set it must be a nonempty absolute path; the default is `${MERRY_SETUP_HOME}/pub-cache/<family>/<version>`. |
| `GITHUB_ENV`, `GITHUB_PATH` | Required writable files for `--persist-path github`. The Action supplies them. |
| `HOME` | Required for `--persist-path bashrc`, which rewrites one `merry-setup` managed block in `~/.bashrc`. |
| `DEBUG=1` | Enables `set -x` tracing. Do not enable it once secret-bearing commands or environments are introduced, because the trace prints every argument. |

The `bashrc` adapter keeps exactly one block between `# >>> merry-setup managed block >>>` and `# <<< merry-setup managed block <<<`, replaces stale exact-version paths on rerun, and refuses to rewrite a file whose block is incomplete.
The `github` adapter appends `PUB_CACHE` to `GITHUB_ENV` and the SDK, pub-cache, and launcher `bin` directories to `GITHUB_PATH` so that later steps see the SDK first.
When the `flutterfire` bundle installs Firebase Tools, the `bashrc` and `github` adapters also persist the npm global bin directory after the SDK and pub-cache bins in effective `PATH` precedence.
Bundle-free runs do not query or persist an npm directory.

## Codex Cloud setup script

Consumers keep a small project-local wrapper that downloads a pinned revision of the CLI to a file and then executes it.
Never pipe the download into a shell, never reference a branch, and never reference a movable tag.

```bash
#!/usr/bin/env bash
set -euo pipefail

# Set this to a verified full commit SHA from AndrewDongminYoo/merry-setup.
readonly MERRY_SETUP_REVISION="${MERRY_SETUP_REVISION:?set MERRY_SETUP_REVISION to a full commit SHA}"
readonly MERRY_SETUP_URL="https://raw.githubusercontent.com/AndrewDongminYoo/merry-setup/${MERRY_SETUP_REVISION}/bin/merry-setup"
readonly MERRY_SETUP_BIN="${HOME}/.merry-setup/bin/merry-setup"

[[ ${MERRY_SETUP_REVISION} =~ ^[0-9a-f]{40}$ ]] || { echo "MERRY_SETUP_REVISION must be a full commit SHA." >&2; exit 1; }
mkdir -p "$(dirname "${MERRY_SETUP_BIN}")"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --output "${MERRY_SETUP_BIN}" "${MERRY_SETUP_URL}"
chmod 0755 "${MERRY_SETUP_BIN}"

"${MERRY_SETUP_BIN}" setup \
  --sdk flutter \
  --bootstrap flutter \
  --persist-path bashrc \
  --bundle flutterfire \
  --precache linux,web
```

The wrapper runs from the project root, so `--project-dir` defaults correctly.
Repeated runs reuse the installed SDK, re-activate each planned package once, and keep one managed `~/.bashrc` block.

## GitHub composite action

The Action expects the consumer to check out its repository first.
It validates the bootstrap input and `pubspec.yaml`, delegates Trunk setup to `trunk-io/trunk-action/setup`, and then runs the CLI with `--persist-path github` and the upstream `TRUNK_PATH`.
Pin it to a full commit SHA.

```yaml
steps:
  - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803 # v6
    with:
      persist-credentials: false
  - uses: AndrewDongminYoo/merry-setup@<full-commit-sha>
    with:
      sdk: flutter
      cache: true
      bootstrap: melos
      bundles: |
        flutterfire
      precache: |
        android
        web
  - run: flutter analyze
```

| Input | Required | Default | Meaning |
| --- | --- | --- | --- |
| `sdk` | yes | | `dart` or `flutter`. |
| `bootstrap` | yes | | `none`, `dart`, `flutter`, `melos`, or `very-good`. |
| `sdk-version` | no | `stable` | `stable` or an exact version. |
| `cache` | no | `false` | `true` caches only the verified SDK release archive. Use it only when `MERRY_SETUP_HOME` is private to the current job. |
| `merry` | no | `true` | `true` or `false`; `false` skips the default `merry` activation. |
| `merry-version` | no | | Pub constraint for `merry`. |
| `dart-packages` | no | | Additional global packages, one `<name>` or `<name>=<constraint>` per line. |
| `bundles` | no | | Bundles, one per line. Currently `flutterfire`. |
| `firebase-tools-version` | no | | Exact `firebase-tools` version, valid only with the `flutterfire` bundle. |
| `precache` | no | | Flutter precache targets, one per line. Invalid when `sdk` is `dart`. |
| `project-dir` | no | `.` | Project directory containing `pubspec.yaml`. |
| `trunk-path` | no | | Existing Trunk launcher; otherwise the official setup action locates or downloads one. |

Multi-line inputs ignore blank lines and a trailing carriage return, and every remaining line becomes exactly one CLI argument without shell re-evaluation.
When `cache` is `false`, the Action follows the initial setup path and makes no resolve, cache restore, or cache save call.
When `cache` is `true`, the Action resolves `stable` to an exact version, builds one key from the SDK family, exact version, runner operating system and architecture, and official SHA-256 checksum, and restores only the upstream release archive under `${RUNNER_TEMP}`.
The key has no fallback and does not include precache, activation, bundle, bootstrap, project, or persistence state.
The CLI compares the resolved checksum with current official metadata, copies restored bytes into private staging, and verifies that snapshot before extraction.
Flutter precache, package activation, bundle installation, persistence, and project bootstrap still run normally.
The Action never caches an extracted SDK, Flutter precache artifacts, or `PUB_CACHE`.
Do not enable this cache when concurrent jobs share one `MERRY_SETUP_HOME` because the Action's read-only final-path check is not a concurrency lock.
If an immutable cache entry is corrupt, delete that exact entry from the repository cache before rerunning the workflow.
The Action exposes neither archive transport inputs nor public outputs and requests no token.

## Boundaries

- Only Linux x64; no macOS, Windows, or ARM64 hosts, and no Android or iOS host toolchains.
- No operating-system package managers, no FVM, mise, or asdf integration, and no generic npm package interface beyond the `flutterfire` bundle.
- No mutable `current` SDK alias, no automatic SDK or pub-cache cleanup, and no locking for concurrent runs that share one pub cache.
- `precache` requests Flutter platform artifacts only; it does not install an Android SDK, browsers, or Linux desktop packages.
- Trunk CLI and linter versions are governed by the consumer repository's `.trunk/trunk.yaml`.

## Status

The CLI, the composite action, and the black-box test suite implement the complete v1 contract in [the merry-setup specification](docs/specs/0001-merry-setup/spec.md).
An earlier manual integration run installed real SDKs on Linux x64, but the current workflow head and the archive-cache path have not completed a hosted run.
Local tests therefore cover the new behavior, while hosted cache readiness remains unverified until the updated integration workflow passes.

## Development

```bash
bash -n bin/merry-setup action/preflight.sh action/resolve.sh action/run.sh test/*.sh
shellcheck bin/merry-setup action/preflight.sh action/resolve.sh action/run.sh test/*.sh
bash test/run.sh
```

Tests stub every external command and never download a real SDK or touch the operator's home directory.
Implementation plans belong in `docs/plans/`, and working notes belong in `docs/notes/`.

## License

The original Bash code, Composite Action metadata and adapters, tests, and documentation in this repository are licensed under the [MIT License](LICENSE).
Downloaded or invoked third-party SDKs, Actions, launchers, packages, and other artifacts remain governed by their respective licenses; `merry-setup` does not relicense them.
