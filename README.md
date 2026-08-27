# merry-setup

`merry-setup` is a bootstrap tool for consistent Dart and Flutter development environments across Codex Cloud, GitHub Actions, and compatible Linux shells.

The repository currently contains the approved product specification, implementation plan, validation-only Bash CLI, and initial GitHub Composite Action adapter.
SDK resolution, installation, tool activation, persistence, and project bootstrap are not implemented yet, so the CLI and Action are not ready for consumer use.

## Planned Capabilities

- Install a selected Dart or Flutter SDK.
- Install `merry` by default with an explicit opt-out.
- Activate additional global Dart tools through validated inputs.
- Install coupled tool bundles such as FlutterFire and Firebase CLI.
- Bootstrap Dart, Flutter, Melos, and Very Good workspaces.
- Persist tool paths for Codex Bash sessions and GitHub Actions steps.
- Delegate GitHub-native Trunk setup to the official Trunk Action.

## Documentation

The initial product contract is defined in [the merry-setup specification](docs/specs/0001-merry-setup/spec.md).

Implementation plans belong in `docs/plans/`, and working notes belong in `docs/notes/`.

## Status

The project is in the initial implementation phase.
No release or compatibility guarantee exists yet.
