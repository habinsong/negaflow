#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_ICON="$ROOT/Sources/negaflowApp/Resources/AppIcon-1024.png"
OPAQUE_ICON="$ROOT/Sources/negaflowApp/Resources/AppIcon-App-1024.png"
ICNS_ICON="$ROOT/Sources/negaflowApp/Resources/AppIcon.icns"
ICONSET_DIR="$(mktemp -d "${TMPDIR:-/tmp}/negaflow-app-icon.XXXXXX.iconset")"

cleanup() {
  rm -rf "$ICONSET_DIR"
}
trap cleanup EXIT

/usr/bin/swift "$ROOT/scripts/generate-app-icon.swift" "$SOURCE_ICON" "$OPAQUE_ICON"

make_icon() {
  local pixels="$1"
  local name="$2"
  /usr/bin/sips \
    --resampleHeightWidth "$pixels" "$pixels" \
    "$OPAQUE_ICON" \
    --out "$ICONSET_DIR/$name" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png

/usr/bin/iconutil --convert icns --output "$ICNS_ICON" "$ICONSET_DIR"

if [ "$(/usr/bin/sips -g hasAlpha "$OPAQUE_ICON" | /usr/bin/tail -n 1 | /usr/bin/awk '{print $2}')" != "no" ]; then
  echo "[app-icon] ERROR: 앱 아이콘 PNG에 투명 채널이 남아 있습니다." >&2
  exit 1
fi

echo "[app-icon] source: $SOURCE_ICON"
echo "[app-icon] opaque: $OPAQUE_ICON"
echo "[app-icon] icns: $ICNS_ICON"
