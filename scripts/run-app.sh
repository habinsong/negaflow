#!/usr/bin/env bash
# scripts/run-app.sh — Negaflow GUI 앱을 빌드하고 실행한다.
#
# 왜 이 스크립트가 필요한가?
#   Xcode 26 SDK에서 SPM CLI 링커(swift run / swift build)가 SwiftUI가 의존하는
#   비공개 SwiftUICore 프레임워크를 링크하지 못한다. 반면 xcodebuild(= Xcode 빌드
#   시스템)는 그 제약을 우회할 수 있다. 따라서 GUI 앱은 xcodebuild로 빌드한다.
#
# 사용법:
#   bash scripts/run-app.sh            # 디버그 빌드 후 실행
#   bash scripts/run-app.sh build      # 빌드만 (실행 안 함)
#   bash scripts/run-app.sh release    # 릴리스 빌드 후 실행
#
# 요구사항: Xcode 26 (swift 6.3), 선택적으로 8200i USB 연결 + SANE 설치.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="Debug"
DO_RUN=1
case "${1:-run}" in
  build)   DO_RUN=0 ;;
  release) CONFIG="Release" ;;
  run|"")  ;;
  *) echo "usage: $0 [run|build|release]"; exit 2 ;;
esac

BUILD_DIR="$ROOT/build"
APP_BUNDLE="$BUILD_DIR/Negaflow.app"
DERIVED="$BUILD_DIR/DerivedData"

echo "[run-app] building NegaflowApp ($CONFIG) via xcodebuild..."
mkdir -p "$BUILD_DIR"

# 1) xcodebuild 로 패키지 빌드. 스킴은 product 이름(Negaflow)을 따른다.
xcodebuild \
  -scheme Negaflow \
  -configuration "$CONFIG" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  -skipMacroValidation \
  build 2>&1 | tail -40

# 2) 산출 실행파일을 찾는다.
BIN=$(find "$DERIVED/Build/Products/$CONFIG" -maxdepth 2 -type f -name "NegaflowApp" 2>/dev/null | head -1 || true)
if [ -z "$BIN" ]; then
  # NegaflowApp 실행파일이 번들로 안 나올 수도 있다 → 직접 실행파일을 .app로 포장.
  BIN=$(find "$DERIVED/Build/Products/$CONFIG" -maxdepth 3 -type f -perm +111 -name "Negaflow*" 2>/dev/null | grep -v "\.app/" | head -1 || true)
fi
if [ -z "$BIN" ]; then
  echo "[run-app] ERROR: 빌드 산출물을 찾을 수 없습니다. 위 xcodebuild 로그를 확인하세요." >&2
  exit 1
fi
echo "[run-app] binary: $BIN"

if [ -e "$APP_BUNDLE" ] && [ ! -w "$APP_BUNDLE" ]; then
  ARCHIVED_BUNDLE="$BUILD_DIR/Negaflow.app.unwritable.$(date +%Y%m%d%H%M%S)"
  mv "$APP_BUNDLE" "$ARCHIVED_BUNDLE" || {
    echo "[run-app] ERROR: 기존 $APP_BUNDLE 를 옮길 수 없습니다. 소유권을 확인하세요." >&2
    exit 1
  }
  echo "[run-app] moved unwritable existing bundle: $ARCHIVED_BUNDLE"
fi

# 3) 간단한 .app 번들로 포장 (open 으로 띄우기 위해).
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BIN" "$APP_BUNDLE/Contents/MacOS/Negaflow"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Negaflow</string>
  <key>CFBundleIdentifier</key><string>com.negaflow.app</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleExecutable</key><string>Negaflow</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Chromabase 프리셋 리소스 번들이 산출물 옆에 있으면 같이 복사 (런타임에 Presets 로드용).
PRESET_BUNDLE=$(find "$DERIVED/Build/Products/$CONFIG" -name "Negaflow_Chromabase.bundle" 2>/dev/null | head -1 || true)
if [ -n "$PRESET_BUNDLE" ]; then
  cp -R "$PRESET_BUNDLE" "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || \
    mkdir -p "$APP_BUNDLE/Contents/Resources" && cp -R "$PRESET_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
fi

echo "[run-app] bundle: $APP_BUNDLE"

if [ "$DO_RUN" -eq 1 ]; then
  echo "[run-app] launching…"
  open "$APP_BUNDLE"
fi
