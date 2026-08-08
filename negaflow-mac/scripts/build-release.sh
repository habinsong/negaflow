#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 빌드 산출물은 저장소 루트의 build/ 에 둔다. macOS 트리를 negaflow-mac/ 으로 옮긴 뒤에도
# 앱 번들 경로는 그대로 <repo>/build/negaflow.app 이라, 설치·실행 습관과 문서가 어긋나지 않는다.
BUILD_DIR="${NEGAFLOW_BUILD_DIR:-$(cd "$ROOT/.." && pwd)/build}"
APP_BUNDLE="$BUILD_DIR/negaflow.app"
OUTPUT_DIR="${NEGAFLOW_RELEASE_OUTPUT_DIR:-$BUILD_DIR/release-artifacts}"
RELEASE_MODE="${NEGAFLOW_RELEASE_MODE:-local}"

case "$RELEASE_MODE" in
  local) ;;
  distribution)
    if [ -z "${NEGAFLOW_CODESIGN_IDENTITY:-}" ] \
        || [ "$NEGAFLOW_CODESIGN_IDENTITY" = "-" ]; then
      echo "[build-release] ERROR: distribution 모드에는 NEGAFLOW_CODESIGN_IDENTITY가 필요합니다." >&2
      exit 2
    fi
    if [ -z "${NEGAFLOW_NOTARY_KEYCHAIN_PROFILE:-}" ]; then
      echo "[build-release] ERROR: distribution 모드에는 NEGAFLOW_NOTARY_KEYCHAIN_PROFILE이 필요합니다." >&2
      exit 2
    fi
    if [ -z "${NEGAFLOW_INSTALLER_SIGN_IDENTITY:-}" ]; then
      echo "[build-release] ERROR: distribution 모드에는 NEGAFLOW_INSTALLER_SIGN_IDENTITY가 필요합니다." >&2
      exit 2
    fi
    ;;
  *)
    echo "[build-release] ERROR: NEGAFLOW_RELEASE_MODE는 local 또는 distribution이어야 합니다." >&2
    exit 2
    ;;
esac

build_universal_products() {
  local architecture="universal"
  local derived_data="$BUILD_DIR/DerivedData.release.$architecture"
  local variant_root="$BUILD_DIR/release-apps/$architecture"
  local saved_app="$variant_root/negaflow.app"
  local saved_dsym="$variant_root/negaflow.app.dSYM"
  local built_dsym

  NEGAFLOW_BUILD_ARCHITECTURES="$architecture" \
  NEGAFLOW_DERIVED_DATA_PATH="$derived_data" \
    bash "$ROOT/scripts/run-app.sh" build

  built_dsym="$(find "$derived_data/Build/Products/Release" \
    -maxdepth 3 -type d -name 'negaflowApp.dSYM' -print -quit)"
  if [ -z "$built_dsym" ]; then
    echo "[build-release] ERROR: $architecture Release dSYM을 찾을 수 없습니다." >&2
    exit 1
  fi

  rm -rf "$variant_root"
  mkdir -p "$variant_root"
  ditto "$APP_BUNDLE" "$saved_app"
  ditto "$built_dsym" "$saved_dsym"
}

derive_arm64_products() {
  local source_root="$BUILD_DIR/release-apps/universal"
  local variant_root="$BUILD_DIR/release-apps/arm64"
  local source_app="$source_root/negaflow.app"
  local source_dsym="$source_root/negaflow.app.dSYM"
  local saved_app="$variant_root/negaflow.app"
  local saved_dsym="$variant_root/negaflow.app.dSYM"
  local executable_name
  local source_executable
  local saved_executable
  local source_dwarf
  local saved_dwarf
  local sign_identity="${NEGAFLOW_CODESIGN_IDENTITY:--}"

  executable_name="$(plutil -extract CFBundleExecutable raw "$source_app/Contents/Info.plist")"
  source_executable="$source_app/Contents/MacOS/$executable_name"
  source_dwarf="$(find "$source_dsym/Contents/Resources/DWARF" -maxdepth 1 -type f -print -quit)"
  if [ ! -x "$source_executable" ] || [ -z "$source_dwarf" ]; then
    echo "[build-release] ERROR: universal 앱 또는 dSYM 산출물이 올바르지 않습니다." >&2
    exit 1
  fi

  rm -rf "$variant_root"
  mkdir -p "$variant_root"
  ditto "$source_app" "$saved_app"
  ditto "$source_dsym" "$saved_dsym"

  saved_executable="$saved_app/Contents/MacOS/$executable_name"
  saved_dwarf="$saved_dsym/Contents/Resources/DWARF/$(basename "$source_dwarf")"
  lipo "$source_executable" -thin arm64 -output "$saved_executable.thin"
  mv "$saved_executable.thin" "$saved_executable"
  chmod +x "$saved_executable"
  lipo "$source_dwarf" -thin arm64 -output "$saved_dwarf.thin"
  mv "$saved_dwarf.thin" "$saved_dwarf"
  rm -rf "$saved_dsym/Contents/Resources/Relocations/x86_64"

  bash "$ROOT/scripts/sign-app.sh" "$saved_app" "$sign_identity"
  if [ "$(lipo -archs "$saved_executable")" != "arm64" ]; then
    echo "[build-release] ERROR: arm64 실행파일 슬라이스 생성에 실패했습니다." >&2
    exit 1
  fi
  if [ "$(dwarfdump --uuid "$saved_executable" | awk '{print $2}')" \
      != "$(dwarfdump --uuid "$saved_dsym" | awk '{print $2}')" ]; then
    echo "[build-release] ERROR: arm64 앱과 dSYM UUID가 일치하지 않습니다." >&2
    exit 1
  fi
}

publish_variant() {
  local architecture="$1"
  local variant_root="$BUILD_DIR/release-apps/$architecture"
  local saved_app="$variant_root/negaflow.app"
  local saved_dsym="$variant_root/negaflow.app.dSYM"
  local version
  local build
  local base_name
  local notary_zip
  local final_zip
  local final_dmg
  local final_pkg
  local final_dsym
  local final_checksums

  version="$(plutil -extract CFBundleShortVersionString raw "$saved_app/Contents/Info.plist")"
  build="$(plutil -extract CFBundleVersion raw "$saved_app/Contents/Info.plist")"
  base_name="negaflow-$version-$build-macOS-$architecture"

  if [ "$RELEASE_MODE" = "distribution" ]; then
    notary_zip="$variant_root/$base_name-notary.zip"
    ditto -c -k --sequesterRsrc --keepParent "$saved_app" "$notary_zip"
    bash "$ROOT/scripts/notarize-app.sh" "$notary_zip" "$saved_app"
  fi

  NEGAFLOW_OVERWRITE_RELEASE="${NEGAFLOW_OVERWRITE_RELEASE:-0}" \
    bash "$ROOT/scripts/create-release-artifacts.sh" \
      "$saved_app" \
      "$saved_dsym" \
      "$OUTPUT_DIR" \
      "$architecture"

  if [ "$RELEASE_MODE" = "distribution" ]; then
    final_zip="$OUTPUT_DIR/$base_name.zip"
    final_dmg="$OUTPUT_DIR/$base_name.dmg"
    final_pkg="$OUTPUT_DIR/$base_name.pkg"
    final_dsym="$OUTPUT_DIR/$base_name.dSYM.zip"
    final_checksums="$OUTPUT_DIR/$base_name-SHA256SUMS.txt"

    bash "$ROOT/scripts/notarize-app.sh" "$final_dmg" "$saved_app"
    bash "$ROOT/scripts/notarize-app.sh" "$final_pkg" "$saved_app"
    (
      cd "$OUTPUT_DIR"
      shasum -a 256 \
        "$(basename "$final_zip")" \
        "$(basename "$final_dmg")" \
        "$(basename "$final_pkg")" \
        "$(basename "$final_dsym")" > "$(basename "$final_checksums")"
    )
    shasum -a 256 -c "$final_checksums"
  fi
}

build_universal_products
derive_arm64_products
publish_variant arm64
publish_variant universal

echo "[build-release] complete: mode=$RELEASE_MODE output=$OUTPUT_DIR"
