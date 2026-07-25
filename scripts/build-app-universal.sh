#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${NEGAFLOW_DERIVED_DATA_PATH:-$ROOT/build/DerivedData.universal.$(id -un)}"

NEGAFLOW_BUILD_ARCHITECTURES=universal \
NEGAFLOW_DERIVED_DATA_PATH="$DERIVED_DATA" \
  bash "$ROOT/scripts/run-app.sh" build
