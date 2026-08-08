#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 7 ]; then
  echo "usage: $0 <binary> <products-dir> <app-bundle> <version> <build> <bundle-id> <minimum-macos>" >&2
  exit 2
fi

BIN="$1"
PRODUCTS_DIR="$2"
APP_BUNDLE="$3"
PRODUCT_VERSION="$4"
PRODUCT_BUILD="$5"
BUNDLE_IDENTIFIER="$6"
MINIMUM_MACOS="$7"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
EXECUTABLE_NAME="negaflow"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
PLUTIL="/usr/bin/plutil"
SHASUM="/usr/bin/shasum"

if [ ! -x "$BIN" ]; then
  echo "[package-app] ERROR: 실행파일이 없거나 실행 가능하지 않습니다: $BIN" >&2
  exit 1
fi
if [[ ! "$PRODUCT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "[package-app] ERROR: 잘못된 제품 버전: $PRODUCT_VERSION" >&2
  exit 1
fi
if [[ ! "$PRODUCT_BUILD" =~ ^[1-9][0-9]*$ ]]; then
  echo "[package-app] ERROR: build 번호는 양의 정수여야 합니다: $PRODUCT_BUILD" >&2
  exit 1
fi
if [[ ! "$BUNDLE_IDENTIFIER" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]; then
  echo "[package-app] ERROR: 잘못된 bundle identifier: $BUNDLE_IDENTIFIER" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$RESOURCES_DIR"
cp "$BIN" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
cp "$ROOT/Sources/negaflowApp/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

cp "$ROOT/Config/negaflowApp-Info.plist" "$INFO_PLIST"
"$PLIST_BUDDY" -c "Set :CFBundleDevelopmentRegion en" "$INFO_PLIST"
"$PLIST_BUDDY" -c "Set :CFBundleExecutable $EXECUTABLE_NAME" "$INFO_PLIST"
"$PLIST_BUDDY" -c "Set :CFBundleIdentifier $BUNDLE_IDENTIFIER" "$INFO_PLIST"
"$PLIST_BUDDY" -c "Set :CFBundleShortVersionString $PRODUCT_VERSION" "$INFO_PLIST"
"$PLIST_BUDDY" -c "Set :CFBundleVersion $PRODUCT_BUILD" "$INFO_PLIST"
"$PLIST_BUDDY" -c "Set :LSMinimumSystemVersion $MINIMUM_MACOS" "$INFO_PLIST"

for locale in en ko ja zh-Hans fr de; do
  source_strings="$ROOT/Sources/negaflowApp/Resources/$locale.lproj/InfoPlist.strings"
  locale_dir="$RESOURCES_DIR/$locale.lproj"
  mkdir -p "$locale_dir"
  cp "$source_strings" "$locale_dir/InfoPlist.strings"
done

while IFS= read -r -d '' resource_bundle; do
  cp -R "$resource_bundle" "$RESOURCES_DIR/"
done < <(find "$PRODUCTS_DIR" -maxdepth 2 -type d -name 'negaflow_*.bundle' -print0)

CHROMABASE_RESOURCE_BUNDLE="$RESOURCES_DIR/negaflow_Chromabase.bundle"
if [ -d "$CHROMABASE_RESOURCE_BUNDLE/Contents/Resources" ]; then
  CHROMABASE_RESOURCE_ROOT="$CHROMABASE_RESOURCE_BUNDLE/Contents/Resources"
else
  CHROMABASE_RESOURCE_ROOT="$CHROMABASE_RESOURCE_BUNDLE"
fi
SCANNER_PROFILES_DIR="$CHROMABASE_RESOURCE_ROOT/ScannerProfiles"
SCANNER_PROFILE_MANIFEST="$SCANNER_PROFILES_DIR/manifest.json"
if [ ! -s "$SCANNER_PROFILE_MANIFEST" ]; then
  echo "[package-app] ERROR: ScannerProfiles manifest가 패키지에 없습니다: $SCANNER_PROFILE_MANIFEST" >&2
  exit 1
fi

SCANNER_PROFILE_SCHEMA="$($PLUTIL -extract schemaVersion raw -o - "$SCANNER_PROFILE_MANIFEST" 2>/dev/null)" || {
  echo "[package-app] ERROR: ScannerProfiles manifest를 읽을 수 없습니다: $SCANNER_PROFILE_MANIFEST" >&2
  exit 1
}
SCANNER_PROFILE_COUNT="$($PLUTIL -extract profileCount raw -o - "$SCANNER_PROFILE_MANIFEST" 2>/dev/null)" || {
  echo "[package-app] ERROR: ScannerProfiles manifest에 profileCount가 없습니다: $SCANNER_PROFILE_MANIFEST" >&2
  exit 1
}
if [ "$SCANNER_PROFILE_SCHEMA" != "2" ] || [[ ! "$SCANNER_PROFILE_COUNT" =~ ^[1-9][0-9]*$ ]]; then
  echo "[package-app] ERROR: ScannerProfiles manifest 스키마 또는 profileCount가 잘못되었습니다: $SCANNER_PROFILE_MANIFEST" >&2
  exit 1
fi

for ((profile_index = 0; profile_index < SCANNER_PROFILE_COUNT; profile_index++)); do
  profile_id="$($PLUTIL -extract "profiles.$profile_index.id" raw -o - "$SCANNER_PROFILE_MANIFEST" 2>/dev/null)" || {
    echo "[package-app] ERROR: ScannerProfiles manifest의 profile 항목을 읽을 수 없습니다: index=$profile_index" >&2
    exit 1
  }
  manifest_profile_hash="$($PLUTIL -extract "profiles.$profile_index.profileHash" raw -o - "$SCANNER_PROFILE_MANIFEST" 2>/dev/null)" || {
    echo "[package-app] ERROR: ScannerProfiles manifest의 profileHash를 읽을 수 없습니다: index=$profile_index" >&2
    exit 1
  }
  manifest_file_sha256="$($PLUTIL -extract "profiles.$profile_index.fileSHA256" raw -o - "$SCANNER_PROFILE_MANIFEST" 2>/dev/null)" || {
    echo "[package-app] ERROR: ScannerProfiles manifest의 fileSHA256을 읽을 수 없습니다: index=$profile_index" >&2
    exit 1
  }
  if [[ ! "$profile_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "[package-app] ERROR: ScannerProfiles manifest의 profile id가 잘못되었습니다: $profile_id" >&2
    exit 1
  fi
  if [[ ! "$manifest_profile_hash" =~ ^sha256:[0-9a-f]{64}$ ]] \
      || [[ ! "$manifest_file_sha256" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "[package-app] ERROR: ScannerProfiles manifest의 hash가 잘못되었습니다: $profile_id" >&2
    exit 1
  fi

  profile_path="$SCANNER_PROFILES_DIR/$profile_id.json"
  if [ ! -s "$profile_path" ]; then
    echo "[package-app] ERROR: ScannerProfiles profile이 패키지에 없습니다: $profile_id.json" >&2
    exit 1
  fi
  profile_schema="$($PLUTIL -extract schemaVersion raw -o - "$profile_path" 2>/dev/null)" || {
    echo "[package-app] ERROR: ScannerProfiles profile JSON을 읽을 수 없습니다: $profile_id.json" >&2
    exit 1
  }
  embedded_profile_id="$($PLUTIL -extract id raw -o - "$profile_path" 2>/dev/null)" || {
    echo "[package-app] ERROR: ScannerProfiles profile id를 읽을 수 없습니다: $profile_id.json" >&2
    exit 1
  }
  embedded_profile_hash="$($PLUTIL -extract profileHash raw -o - "$profile_path" 2>/dev/null)" || {
    echo "[package-app] ERROR: ScannerProfiles profileHash를 읽을 수 없습니다: $profile_id.json" >&2
    exit 1
  }
  if [ "$profile_schema" != "2" ] \
      || [ "$embedded_profile_id" != "$profile_id" ] \
      || [ "$embedded_profile_hash" != "$manifest_profile_hash" ]; then
    echo "[package-app] ERROR: ScannerProfiles profile identity가 manifest와 일치하지 않습니다: $profile_id.json" >&2
    exit 1
  fi

  actual_file_sha256="$($SHASUM -a 256 "$profile_path")" || {
    echo "[package-app] ERROR: ScannerProfiles profile hash를 계산할 수 없습니다: $profile_id.json" >&2
    exit 1
  }
  actual_file_sha256="sha256:${actual_file_sha256%% *}"
  if [ "$actual_file_sha256" != "$manifest_file_sha256" ]; then
    echo "[package-app] ERROR: ScannerProfiles profile fileSHA256이 manifest와 일치하지 않습니다: $profile_id.json" >&2
    exit 1
  fi
done

if $PLUTIL -extract "profiles.$SCANNER_PROFILE_COUNT.id" raw -o - "$SCANNER_PROFILE_MANIFEST" >/dev/null 2>&1; then
  echo "[package-app] ERROR: ScannerProfiles manifest의 profileCount와 profiles 배열이 일치하지 않습니다" >&2
  exit 1
fi

$PLUTIL -lint "$INFO_PLIST" >/dev/null
test -x "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
test -s "$RESOURCES_DIR/AppIcon.icns"
for locale in en ko ja zh-Hans fr de; do
  test -s "$RESOURCES_DIR/$locale.lproj/InfoPlist.strings"
done

echo "[package-app] bundle: $APP_BUNDLE"
