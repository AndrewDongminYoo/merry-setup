# Root Linux Setup Implementation Plan

**Goal:** Prevent root-container Flutter installation failures and verify the repository setup entry point.

**Spec:** `docs/specs/0003-root-linux-setup/spec.md`

## Owned Paths

- `setup.sh`
- `bin/merry-setup`
- `test/repository_setup_test.sh`
- `test/sdk_installation_test.sh`
- `test/run.sh`
- `.github/workflows/integration.yml`

## Steps

- [x] Add a repository setup wrapper test and `setup.sh` as a thin local CLI adapter.
- [x] Add a Flutter ownership regression test and confirm that extraction without ownership suppression fails.
- [x] Add GNU tar ownership suppression and confirm that the focused test passes.
- [x] Add fail-first Dart and Flutter launcher diagnostic tests, preserve their captured output, and confirm that the focused tests pass.
- [x] Add a digest-pinned root Ubuntu Integration job that performs a real stable Flutter installation.
- [x] Run the local syntax, lint, test, workflow parsing, and diff checks.
- [ ] Push the branch and require the hosted Integration and review gates before merge readiness.

## Verification

```bash
bash -n bin/merry-setup setup.sh test/run.sh test/repository_setup_test.sh test/sdk_installation_test.sh
shellcheck bin/merry-setup setup.sh test/run.sh test/repository_setup_test.sh test/sdk_installation_test.sh
bash test/run.sh
ruby -e 'require "yaml"; YAML.load_file(ARGV.fetch(0), aliases: true)' .github/workflows/integration.yml
trunk check .github/workflows/integration.yml bin/merry-setup test/sdk_installation_test.sh setup.sh test/repository_setup_test.sh test/run.sh
git diff --check
```
