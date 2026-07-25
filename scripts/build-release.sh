#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP_BUNDLE="$BUILD_DIR/Negaflow.app"
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

build_variant() {
  local architecture="$1"
  local derived_data="$BUILD_DIR/DerivedData.release.$architecture"
  local variant_root="$BUILD_DIR/release-apps/$architecture"
  local saved_app="$variant_root/Negaflow.app"
  local saved_dsym="$variant_root/Negaflow.app.dSYM"
  local built_dsym
  local version
  local build
  local base_name
  local notary_zip
  local final_zip
  local final_dmg
  local final_pkg
  local final_dsym
  local final_checksums

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

  version="$(plutil -extract CFBundleShortVersionString raw "$saved_app/Contents/Info.plist")"
  build="$(plutil -extract CFBundleVersion raw "$saved_app/Contents/Info.plist")"
  base_name="Negaflow-$version-$build-macOS-$architecture"

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

build_variant arm64
build_variant universal

echo "[build-release] complete: mode=$RELEASE_MODE output=$OUTPUT_DIR"
