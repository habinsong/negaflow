#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "[ci-gui] ERROR: xcodegen이 필요합니다." >&2
  exit 1
fi

PROJECT_DIR="$(mktemp -d /tmp/negaflow-ci-gui.XXXXXX)"
trap 'rm -rf "$PROJECT_DIR"' EXIT
NEGAFLOW_PACKAGE_ROOT="$ROOT" xcodegen generate --spec project.yml --project "$PROJECT_DIR"
PROJECT_PATH="$(find "$PROJECT_DIR" -maxdepth 1 -name '*.xcodeproj' -print -quit)"
RESULT_BUNDLE="$ROOT/build/NegaflowE2E.xcresult"
rm -rf "$RESULT_BUNDLE"

ACTION="build-for-testing"
if [ "${NEGAFLOW_CI_GUI_RUN:-0}" = "1" ]; then
  ACTION="test"
fi

xcodebuild -quiet \
  -project "$PROJECT_PATH" \
  -scheme negaflowAppE2E \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData.ci \
  -resultBundlePath "$RESULT_BUNDLE" \
  CODE_SIGNING_ALLOWED=NO \
  "$ACTION"

APP="build/DerivedData.ci/Build/Products/Debug/negaflowApp.app"
[ "$(plutil -extract CFBundleDisplayName raw "$APP/Contents/Info.plist")" = "negaflow" ]
[ "$(plutil -extract CFBundleIconFile raw "$APP/Contents/Info.plist")" = "AppIcon" ]
test -s "$APP/Contents/Resources/AppIcon.icns"

echo "[ci-gui] $ACTION complete"
