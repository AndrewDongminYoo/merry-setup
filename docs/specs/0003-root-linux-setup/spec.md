---
type: Spec
title: Root Linux Setup Validation
---

## Problem

Flutter release archives can preserve an upstream owner when a root Linux process extracts them.
The Flutter launchers call Git before the SDK is published, so Git can reject the staged SDK when its owner differs from the current user.
The SDK validator currently replaces launcher failures with a generic metadata mismatch, which removes the diagnostic that identifies the failure.

The repository also needs a portable `setup.sh` entry point for Linux initialization.
Local command stubs cover its argument contract, but they do not prove that a real SDK installs in a root container with the base tools that the target environment already provides.

## Outcome

Flutter extraction must discard archived ownership before staged SDK validation.
SDK validation must preserve output from failed Dart and Flutter version commands.
The Integration workflow must install a real stable Flutter SDK in a root Ubuntu container with only the required base packages.
The repository `setup.sh` must delegate its minimal Dart environment to the local CLI from any current working directory.

## Requirements

1. Flutter archive extraction must use GNU tar ownership suppression.
2. A failed staged `dart --version` command must write its captured output to stderr before the caller reports the installation failure.
3. A failed staged `flutter --version --machine` command must write its captured output to stderr before the caller reports the installation failure.
4. The root-container Integration job must assert UID `0`, install stable Flutter through `bin/merry-setup`, assert that one installed Flutter SDK root has UID `0`, and execute its machine-readable version command.
5. The root-container image must be pinned by digest.
6. The repository `setup.sh` must resolve `bin/merry-setup` relative to its own location and preserve the caller's current working directory as the project root.

## Non-Goals

- Reproduce every package or language runtime from a general development container.
- Change SDK version selection or release metadata parsing.
- Add Flutter to the repository's own minimal `setup.sh` environment.
- Run a full SDK download in the local unit suite.

## Acceptance Criteria

1. The archive ownership regression test fails when tar ownership suppression is removed and passes when it is present.
2. Dart and Flutter launcher failure tests fail when captured stderr is discarded and pass when it is preserved.
3. The full shell test suite, Bash syntax checks, ShellCheck, workflow YAML parsing, Trunk checks, and `git diff --check` pass.
4. The hosted root-container job completes before the PR is ready to merge.
