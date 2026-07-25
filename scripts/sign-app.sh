#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: $0 <app-bundle> [codesign-identity|-]" >&2
  exit 2
fi

APP_BUNDLE="$1"
SIGN_IDENTITY="${2:--}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTITLEMENTS="$ROOT/Config/Negaflow.entitlements"

if [ ! -d "$APP_BUNDLE/Contents" ]; then
  echo "[sign-app] ERROR: 앱 번들이 아닙니다: $APP_BUNDLE" >&2
  exit 1
fi
if [ ! -f "$ENTITLEMENTS" ]; then
  echo "[sign-app] ERROR: entitlement 파일이 없습니다: $ENTITLEMENTS" >&2
  exit 1
fi

sign_args=(--force --options runtime --sign "$SIGN_IDENTITY")
if [ "$SIGN_IDENTITY" = "-" ]; then
  sign_args+=(--timestamp=none)
  signing_label="ad-hoc"
else
  if [[ "$SIGN_IDENTITY" != Developer\ ID\ Application:* ]]; then
    echo "[sign-app] ERROR: 배포 서명은 Developer ID Application 인증서여야 합니다." >&2
    exit 1
  fi
  if ! security find-identity -v -p codesigning | grep -Fq "\"$SIGN_IDENTITY\""; then
    echo "[sign-app] ERROR: Keychain에서 서명 인증서를 찾을 수 없습니다: $SIGN_IDENTITY" >&2
    exit 1
  fi
  sign_args+=(--timestamp)
  signing_label="$SIGN_IDENTITY"
fi

for container in Frameworks PlugIns XPCServices Helpers; do
  nested_root="$APP_BUNDLE/Contents/$container"
  [ -d "$nested_root" ] || continue
  while IFS= read -r -d '' executable; do
    codesign "${sign_args[@]}" "$executable"
  done < <(find "$nested_root" -type f -perm +111 -print0)
done

codesign "${sign_args[@]}" --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
signature_details="$(codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1)"
if ! grep -q 'runtime' <<< "$signature_details"; then
  echo "[sign-app] ERROR: hardened runtime 서명 플래그가 없습니다." >&2
  exit 1
fi
entitlement_details="$(codesign -d --entitlements :- "$APP_BUNDLE" 2>/dev/null || true)"
if grep -q 'com.apple.security.get-task-allow' <<< "$entitlement_details"; then
  echo "[sign-app] ERROR: 배포 금지 entitlement get-task-allow가 포함되었습니다." >&2
  exit 1
fi

echo "[sign-app] signing: $signing_label"
