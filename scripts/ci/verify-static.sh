#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

git diff --check
bash -n scripts/*.sh scripts/ci/*.sh
plutil -lint Config/NegaflowApp-Info.plist Config/Negaflow.entitlements >/dev/null
for resource in Sources/negaflowApp/Resources/*.lproj/*.stringsdict \
                Sources/negaflowApp/Resources/*.lproj/InfoPlist.strings; do
  plutil -lint "$resource" >/dev/null
done
file Sources/negaflowApp/Resources/AppIcon.icns | grep -q 'Mac OS X icon'
python3 -m unittest discover -s scripts/tests -p 'test_*.py'
bash scripts/ci/verify-boundaries.sh
python3 scripts/ci/verify-provenance.py

echo "[ci-static] complete"
