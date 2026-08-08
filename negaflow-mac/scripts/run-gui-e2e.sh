#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="${NEGAFLOW_E2E_PROJECT_DIR:-$ROOT/build/NegaflowE2EProject}"
DERIVED_DATA="${NEGAFLOW_E2E_DERIVED_DATA:-$ROOT/build/DerivedData.ui-tests}"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "[gui-e2e] ERROR: xcodegen 2.42.0+ is required." >&2
  exit 1
fi

if command -v automationmodetool >/dev/null 2>&1; then
  AUTOMATION_STATUS="$(automationmodetool 2>&1 || true)"
  if [[ "$AUTOMATION_STATUS" == *"Automation Mode is disabled"* ]]; then
    echo "[gui-e2e] ERROR: macOS Automation Mode is disabled." >&2
    echo "[gui-e2e] Enable Automation Mode with administrator authentication, then retry." >&2
    exit 1
  fi
fi

rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
NEGAFLOW_PACKAGE_ROOT="$ROOT" \
  xcodegen generate --spec "$ROOT/project.yml" --project "$PROJECT_DIR"

xcodebuild \
  -project "$PROJECT_DIR/NegaflowE2E.xcodeproj" \
  -scheme negaflowAppE2E \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -skipMacroValidation \
  test
