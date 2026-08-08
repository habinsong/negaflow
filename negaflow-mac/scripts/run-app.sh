#!/usr/bin/env bash
# scripts/run-app.sh — negaflow GUI 앱을 빌드하고 실행한다.
#
# 왜 이 스크립트가 필요한가?
#   Xcode 26 SDK에서 SPM CLI 링커(swift run / swift build)가 SwiftUI가 의존하는
#   비공개 SwiftUICore 프레임워크를 링크하지 못한다. 반면 xcodebuild(= Xcode 빌드
#   시스템)는 그 제약을 우회할 수 있다. 따라서 GUI 앱은 xcodebuild로 빌드한다.
#
# 사용법:
#   bash scripts/run-app.sh            # arm64 릴리스 빌드 후 실행
#   bash scripts/run-app.sh build      # arm64 릴리스 빌드만 (실행 안 함)
#   bash scripts/run-app.sh release    # arm64 릴리스 빌드 후 실행
#
# 선택 환경 변수:
#   NEGAFLOW_CODESIGN_IDENTITY          # Developer ID Application 인증서 이름
#   미지정 시 로컬 검증용 ad-hoc 서명. notarization은 배포 파이프라인에서 별도로 수행한다.
#
# 요구사항: Xcode 26 (swift 6.3).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PRODUCT_VERSION_FILE="$ROOT/Sources/Chromabase/ProductVersion.txt"
if [ ! -f "$PRODUCT_VERSION_FILE" ]; then
  echo "[run-app] ERROR: 제품 버전 파일이 없습니다: $PRODUCT_VERSION_FILE" >&2
  exit 1
fi
PRODUCT_VERSION="$(tr -d '[:space:]' < "$PRODUCT_VERSION_FILE")"
if [[ ! "$PRODUCT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "[run-app] ERROR: 잘못된 제품 버전: $PRODUCT_VERSION" >&2
  exit 1
fi
PRODUCT_BUILD_FILE="$ROOT/Sources/Chromabase/ProductBuild.txt"
if [ ! -f "$PRODUCT_BUILD_FILE" ]; then
  echo "[run-app] ERROR: 제품 build 파일이 없습니다: $PRODUCT_BUILD_FILE" >&2
  exit 1
fi
PRODUCT_BUILD="${NEGAFLOW_BUILD_NUMBER:-$(tr -d '[:space:]' < "$PRODUCT_BUILD_FILE")}"
BUNDLE_IDENTIFIER="${NEGAFLOW_BUNDLE_IDENTIFIER:-com.songhabin.negaflow}"
BUILD_ARCHITECTURES="${NEGAFLOW_BUILD_ARCHITECTURES:-arm64}"

case "$BUILD_ARCHITECTURES" in
  arm64)
    XCODE_ARCH_ARGS=("ARCHS=arm64" "ONLY_ACTIVE_ARCH=YES")
    ;;
  universal)
    XCODE_ARCH_ARGS=("ARCHS=arm64 x86_64" "ONLY_ACTIVE_ARCH=NO")
    ;;
  *)
    echo "[run-app] ERROR: NEGAFLOW_BUILD_ARCHITECTURES는 arm64 또는 universal이어야 합니다." >&2
    exit 2
    ;;
esac

# 기본은 Release: 컴파일러 최적화(-O / whole-module)로 CPU 코드(AutoLevels 픽셀 샘플링,
# 퍼센타일 정렬, transform 등)가 Debug(-Onone) 대비 수배 빨라진다 — 이미지 처리 앱이라 체감이 크다.
CONFIG="Release"
DO_RUN=1
case "${1:-run}" in
  build)   DO_RUN=0 ;;
  release) CONFIG="Release" ;;
  debug)   CONFIG="Debug" ;;
  run|"")  ;;
  *) echo "usage: $0 [run|build|release|debug]"; exit 2 ;;
esac

BUILD_DIR="$ROOT/build"
APP_BUNDLE="$BUILD_DIR/negaflow.app"
DERIVED="${NEGAFLOW_DERIVED_DATA_PATH:-$BUILD_DIR/DerivedData.$(id -un)}"

echo "[run-app] building negaflowApp ($CONFIG, $BUILD_ARCHITECTURES) via xcodebuild..."
mkdir -p "$BUILD_DIR"

# 1) xcodebuild 로 패키지 빌드. 스킴은 product 이름(negaflowApp)을 따른다.
xcodebuild \
  -scheme negaflowApp \
  -configuration "$CONFIG" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  -skipMacroValidation \
  "${XCODE_ARCH_ARGS[@]}" \
  build 2>&1 | tail -40

# 2) 산출 실행파일을 찾는다.
BIN=$(find "$DERIVED/Build/Products/$CONFIG" -maxdepth 2 -type f -name "negaflowApp" 2>/dev/null | head -1 || true)
if [ -z "$BIN" ]; then
  # negaflowApp 실행파일이 번들로 안 나올 수도 있다 → 직접 실행파일을 .app로 포장.
  BIN=$(find "$DERIVED/Build/Products/$CONFIG" -maxdepth 3 -type f -perm +111 -name "negaflowApp*" 2>/dev/null | grep -v "\.app/" | head -1 || true)
fi
if [ -z "$BIN" ]; then
  echo "[run-app] ERROR: 빌드 산출물을 찾을 수 없습니다. 위 xcodebuild 로그를 확인하세요." >&2
  exit 1
fi
BIN_ARCHITECTURES="$(lipo -archs "$BIN")"
case "$BUILD_ARCHITECTURES" in
  arm64)
    if [ "$BIN_ARCHITECTURES" != "arm64" ]; then
      echo "[run-app] ERROR: arm64 실행파일이 필요하지만 다음 아키텍처가 생성됐습니다: $BIN_ARCHITECTURES" >&2
      exit 1
    fi
    ;;
  universal)
    if [[ " $BIN_ARCHITECTURES " != *" arm64 "* ]] \
        || [[ " $BIN_ARCHITECTURES " != *" x86_64 "* ]]; then
      echo "[run-app] ERROR: universal 실행파일에 arm64와 x86_64가 모두 필요합니다: $BIN_ARCHITECTURES" >&2
      exit 1
    fi
    ;;
esac
echo "[run-app] binary: $BIN"
echo "[run-app] architectures: $BIN_ARCHITECTURES"

if [ -e "$APP_BUNDLE" ] && [ ! -w "$APP_BUNDLE" ]; then
  ARCHIVED_BUNDLE="$BUILD_DIR/negaflow.app.unwritable.$(date +%Y%m%d%H%M%S)"
  mv "$APP_BUNDLE" "$ARCHIVED_BUNDLE" || {
    echo "[run-app] ERROR: 기존 $APP_BUNDLE 를 옮길 수 없습니다. 소유권을 확인하세요." >&2
    exit 1
  }
  echo "[run-app] moved unwritable existing bundle: $ARCHIVED_BUNDLE"
fi

# 3) 실행파일, 앱/엔진 리소스, 현지화, 아이콘과 표준 메타데이터를 .app으로 조립한다.
bash "$ROOT/scripts/package-app.sh" \
  "$BIN" \
  "$DERIVED/Build/Products/$CONFIG" \
  "$APP_BUNDLE" \
  "$PRODUCT_VERSION" \
  "$PRODUCT_BUILD" \
  "$BUNDLE_IDENTIFIER" \
  "14.0"

# 로컬 빌드는 ad-hoc, 배포 빌드는 Developer ID + hardened runtime + timestamp로 서명한다.
SIGN_IDENTITY="${NEGAFLOW_CODESIGN_IDENTITY:--}"
bash "$ROOT/scripts/sign-app.sh" "$APP_BUNDLE" "$SIGN_IDENTITY"

plutil -lint "$APP_BUNDLE/Contents/Info.plist" >/dev/null
test -x "$APP_BUNDLE/Contents/MacOS/negaflow"

echo "[run-app] bundle: $APP_BUNDLE"

if [ "$DO_RUN" -eq 1 ]; then
  echo "[run-app] launching…"
  open "$APP_BUNDLE"
fi
