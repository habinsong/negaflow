#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <signed-zip|dmg|pkg> <app-bundle>" >&2
  exit 2
fi

ARCHIVE="$1"
APP_BUNDLE="$2"
KEYCHAIN_PROFILE="${NEGAFLOW_NOTARY_KEYCHAIN_PROFILE:-}"
LOG_PATH="${NEGAFLOW_NOTARY_LOG_PATH:-build/notarization-log.json}"

if [ ! -f "$ARCHIVE" ]; then
  echo "[notarize-app] ERROR: 제출 파일이 없습니다: $ARCHIVE" >&2
  exit 1
fi
case "${ARCHIVE##*.}" in
  zip|dmg|pkg) ;;
  *)
    echo "[notarize-app] ERROR: notarytool 제출 형식은 zip, dmg, pkg만 허용합니다." >&2
    exit 1
    ;;
esac
if [ ! -d "$APP_BUNDLE/Contents" ]; then
  echo "[notarize-app] ERROR: 앱 번들이 아닙니다: $APP_BUNDLE" >&2
  exit 1
fi
if [ -z "$KEYCHAIN_PROFILE" ]; then
  echo "[notarize-app] ERROR: NEGAFLOW_NOTARY_KEYCHAIN_PROFILE이 필요합니다." >&2
  echo "xcrun notarytool store-credentials '<profile>' 명령으로 Keychain에 먼저 저장하세요." >&2
  exit 2
fi
signature_details="$(codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1)"
if ! grep -q '^Authority=Developer ID Application:' <<< "$signature_details"; then
  echo "[notarize-app] ERROR: 앱이 Developer ID Application으로 서명되지 않았습니다." >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

result_file="$(mktemp /tmp/negaflow-notary-result.XXXXXX.json)"
trap 'rm -f "$result_file"' EXIT
xcrun notarytool submit "$ARCHIVE" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait \
  --output-format json > "$result_file"

status="$(plutil -extract status raw -o - "$result_file")"
submission_id="$(plutil -extract id raw -o - "$result_file")"
if [ "$status" != "Accepted" ]; then
  mkdir -p "$(dirname "$LOG_PATH")"
  xcrun notarytool log "$submission_id" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    "$LOG_PATH"
  echo "[notarize-app] ERROR: notarization status=$status log=$LOG_PATH" >&2
  exit 1
fi

xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
case "${ARCHIVE##*.}" in
  dmg)
    xcrun stapler staple "$ARCHIVE"
    xcrun stapler validate "$ARCHIVE"
    ;;
  pkg)
    xcrun stapler staple "$ARCHIVE"
    xcrun stapler validate "$ARCHIVE"
    spctl --assess --type install --verbose=4 "$ARCHIVE"
    ;;
esac
spctl --assess --type execute --verbose=4 "$APP_BUNDLE"
echo "[notarize-app] accepted: $submission_id"
