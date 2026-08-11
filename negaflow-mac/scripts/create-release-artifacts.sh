#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "usage: $0 <signed-app> <dsym-bundle> <output-directory> <arm64|universal>" >&2
  exit 2
fi

APP_BUNDLE="$1"
DSYM_BUNDLE="$2"
OUTPUT_DIR="$3"
ARCHITECTURE_LABEL="$4"

case "$ARCHITECTURE_LABEL" in
  arm64|universal) ;;
  *)
    echo "[release-artifacts] ERROR: 아키텍처 표시는 arm64 또는 universal이어야 합니다." >&2
    exit 2
    ;;
esac

if [ ! -d "$APP_BUNDLE/Contents" ]; then
  echo "[release-artifacts] ERROR: 앱 번들이 아닙니다: $APP_BUNDLE" >&2
  exit 1
fi
if [ ! -d "$DSYM_BUNDLE/Contents" ]; then
  echo "[release-artifacts] ERROR: dSYM 번들이 아닙니다: $DSYM_BUNDLE" >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw "$INFO_PLIST")"
EXECUTABLE_PATH="$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
if [ ! -x "$EXECUTABLE_PATH" ]; then
  echo "[release-artifacts] ERROR: 앱 실행파일이 없습니다: $EXECUTABLE_PATH" >&2
  exit 1
fi
EXECUTABLE_ARCHITECTURES="$(lipo -archs "$EXECUTABLE_PATH")"
case "$ARCHITECTURE_LABEL" in
  arm64)
    if [ "$EXECUTABLE_ARCHITECTURES" != "arm64" ]; then
      echo "[release-artifacts] ERROR: arm64 앱이 필요하지만 다음 아키텍처가 들어 있습니다: $EXECUTABLE_ARCHITECTURES" >&2
      exit 1
    fi
    ;;
  universal)
    if [[ " $EXECUTABLE_ARCHITECTURES " != *" arm64 "* ]] \
        || [[ " $EXECUTABLE_ARCHITECTURES " != *" x86_64 "* ]]; then
      echo "[release-artifacts] ERROR: universal 앱에 arm64와 x86_64가 모두 필요합니다: $EXECUTABLE_ARCHITECTURES" >&2
      exit 1
    fi
    ;;
esac
APP_ICON="$APP_BUNDLE/Contents/Resources/AppIcon.icns"
if [ ! -s "$APP_ICON" ]; then
  echo "[release-artifacts] ERROR: 앱 아이콘이 없습니다: $APP_ICON" >&2
  exit 1
fi
if [ "$(sips -g hasAlpha "$APP_ICON" | tail -n 1 | awk '{print $2}')" != "no" ]; then
  echo "[release-artifacts] ERROR: 앱 아이콘에 투명 여백이 남아 있습니다: $APP_ICON" >&2
  exit 1
fi
APP_UUIDS="$(dwarfdump --uuid "$EXECUTABLE_PATH" | awk '{print $2}' | sort)"
DSYM_UUIDS="$(dwarfdump --uuid "$DSYM_BUNDLE" | awk '{print $2}' | sort)"
if [ -z "$APP_UUIDS" ] || [ "$APP_UUIDS" != "$DSYM_UUIDS" ]; then
  echo "[release-artifacts] ERROR: 앱과 dSYM UUID가 일치하지 않습니다." >&2
  exit 1
fi

VERSION="$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")"
BUILD="$(plutil -extract CFBundleVersion raw "$INFO_PLIST")"
BUNDLE_IDENTIFIER="$(plutil -extract CFBundleIdentifier raw "$INFO_PLIST")"
BASE_NAME="negaflow-$VERSION-$BUILD-macOS-$ARCHITECTURE_LABEL"
ZIP_NAME="$BASE_NAME.zip"
DMG_NAME="$BASE_NAME.dmg"
PKG_NAME="$BASE_NAME.pkg"
# 릴리스 페이지는 파일 이름 순으로 늘어놓는다. 설치본(.dmg/.pkg)이 맨 위에 오도록
# 나머지는 그 뒤로 정렬되는 이름을 쓴다 — 예전 이름은 "-SHA256SUMS.txt" 라서 하이픈이
# 점보다 앞서 체크섬 파일이 목록 맨 위에 올라왔다.
DSYM_NAME="$BASE_NAME.symbols-dSYM.zip"
CHECKSUM_NAME="$BASE_NAME.sha256.txt"

mkdir -p "$OUTPUT_DIR"
for name in "$ZIP_NAME" "$DMG_NAME" "$PKG_NAME" "$DSYM_NAME" "$CHECKSUM_NAME"; do
  if [ -e "$OUTPUT_DIR/$name" ] && [ "${NEGAFLOW_OVERWRITE_RELEASE:-0}" != "1" ]; then
    echo "[release-artifacts] ERROR: 기존 artifact가 있습니다: $OUTPUT_DIR/$name" >&2
    exit 1
  fi
done

STAGING_ROOT="$(mktemp -d /tmp/negaflow-release-artifacts.XXXXXX)"
trap 'rm -rf "$STAGING_ROOT"' EXIT
APP_COPY="$STAGING_ROOT/negaflow.app"
DMG_ROOT="$STAGING_ROOT/dmg-root"
mkdir -p "$DMG_ROOT"
ditto "$APP_BUNDLE" "$APP_COPY"
ditto -c -k --sequesterRsrc --keepParent "$APP_COPY" "$STAGING_ROOT/$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$DSYM_BUNDLE" "$STAGING_ROOT/$DSYM_NAME"
PKG_ARGS=(
  --component "$APP_COPY"
  --install-location /Applications
  --identifier "$BUNDLE_IDENTIFIER.pkg"
  --version "$VERSION"
)
if [ -n "${NEGAFLOW_INSTALLER_SIGN_IDENTITY:-}" ]; then
  PKG_ARGS+=(
    --sign "$NEGAFLOW_INSTALLER_SIGN_IDENTITY"
    --timestamp
  )
fi
pkgbuild "${PKG_ARGS[@]}" "$STAGING_ROOT/$PKG_NAME" >/dev/null
if [ -n "${NEGAFLOW_INSTALLER_SIGN_IDENTITY:-}" ]; then
  pkgutil --check-signature "$STAGING_ROOT/$PKG_NAME" >/dev/null
fi
ditto "$APP_COPY" "$DMG_ROOT/negaflow.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create \
  -volname "negaflow $VERSION" \
  -srcfolder "$DMG_ROOT" \
  -format UDZO \
  -ov \
  "$STAGING_ROOT/$DMG_NAME" >/dev/null

if [ -n "${NEGAFLOW_CODESIGN_IDENTITY:-}" ] \
    && [ "${NEGAFLOW_CODESIGN_IDENTITY}" != "-" ]; then
  codesign --force --timestamp --sign "$NEGAFLOW_CODESIGN_IDENTITY" "$STAGING_ROOT/$DMG_NAME"
  codesign --verify --verbose=2 "$STAGING_ROOT/$DMG_NAME"
fi

(
  cd "$STAGING_ROOT"
  shasum -a 256 "$ZIP_NAME" "$DMG_NAME" "$PKG_NAME" "$DSYM_NAME" \
    | sed 's#  .*/#  #' > "$CHECKSUM_NAME"
)

for name in "$ZIP_NAME" "$DMG_NAME" "$PKG_NAME" "$DSYM_NAME" "$CHECKSUM_NAME"; do
  mv -f "$STAGING_ROOT/$name" "$OUTPUT_DIR/$name"
done

echo "[release-artifacts] zip: $OUTPUT_DIR/$ZIP_NAME"
echo "[release-artifacts] dmg: $OUTPUT_DIR/$DMG_NAME"
echo "[release-artifacts] pkg: $OUTPUT_DIR/$PKG_NAME"
echo "[release-artifacts] dSYM: $OUTPUT_DIR/$DSYM_NAME"
echo "[release-artifacts] checksums: $OUTPUT_DIR/$CHECKSUM_NAME"
