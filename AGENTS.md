# Repository Guidelines

## Project Scope

`merry-setup` bootstraps Dart and Flutter development environments for Codex Cloud, GitHub Actions, and compatible Linux shells.
Keep the repository focused on SDK installation, global Dart tools, project dependency bootstrap, PATH persistence, and the thin GitHub composite action adapter.
Do not add general CI policy, project generation, release automation for consumer repositories, or unrelated Merry ecosystem tools without an approved Spec.

## Project Structure

The portable Bash entry point belongs in `bin/merry-setup`.
The root `action.yml` must remain a thin composite action over the Bash behavior and upstream GitHub-native setup actions.
Shell tests belong in `test/`.
Write Specs to `docs/specs/`, plans to `docs/plans/`, and working notes to `docs/notes/`.

## Shell Conventions

Use Bash with `set -euo pipefail` and support Linux x64 in the initial release.
Pass user-controlled values through validated variables and arrays.
Do not use `eval`, interpolate Action inputs directly into commands, or accept arbitrary shell fragments as configuration.
Keep downloads explicit, fail closed on incomplete metadata, and verify checksums whenever the upstream distribution publishes them.
Preserve the current working directory as the default project root and accept an explicit project-directory override.

## GitHub Actions Conventions

Pin third-party Actions to full commit SHAs in committed workflows and examples.
Use `$GITHUB_PATH` and `$GITHUB_ENV` for values that must survive later workflow steps.
Delegate GitHub-native Trunk setup to `trunk-io/trunk-action/setup` rather than copying its implementation.

## Testing and Verification

Run `bash -n bin/merry-setup` and ShellCheck on explicit paths when the executable exists.
Use command stubs and a controlled `PATH` for SDK download, package activation, bootstrap, and error-path tests.
Every custom validator must have a demonstrated failing fixture before its passing result is trusted.
Do not make unit tests download a real SDK or mutate the operator's actual home directory.

## Documentation

Write technical documentation and code identifiers in English.
Use no hard wraps unless a configured linter requires them.
Use sentence-level line breaks, increment heading levels by one, and add a language identifier to every fenced code block.

## Git Safety

Preserve unrelated work and stage explicit paths only.
Use Conventional Commit messages without co-author trailers.
Do not bypass hooks with `--no-verify`.
