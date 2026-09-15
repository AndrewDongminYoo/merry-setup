#!/usr/bin/env bash
set -euo pipefail

SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SETUP_DIR

exec "${SETUP_DIR}/bin/merry-setup" setup \
  --sdk dart \
  --bootstrap none \
  --persist-path bashrc \
  --no-merry
