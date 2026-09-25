#!/usr/bin/env bash
set -euo pipefail

command -v dirname >/dev/null 2>&1 || {
  printf 'ERROR: dirname is required to locate this setup script.\n' >&2
  exit 1
}

SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SETUP_DIR

command -v "${SETUP_DIR}/bin/merry-setup" >/dev/null 2>&1 || {
  printf 'ERROR: bin/merry-setup is required to run setup.\n' >&2
  exit 1
}

exec "${SETUP_DIR}/bin/merry-setup" setup \
  --sdk dart \
  --bootstrap none \
  --persist-path bashrc \
  --no-merry
