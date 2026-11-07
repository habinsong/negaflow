<p align="center">
  <img src="../Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for macOS</h1>

<p align="center">macOS 네이티브로 만든 negaflow입니다.</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.2.6-EF8B26" alt="버전 1.2.6"></a>
  <a href="#"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 이상"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-6E7781" alt="Apache 2.0"></a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <strong>한국어</strong> ·
  <a href="README_ja.md">日本語</a> ·
  <a href="README_zh-Hans.md">简体中文</a> ·
  <a href="README_fr.md">Français</a> ·
  <a href="README_de.md">Deutsch</a>
</p>

<p align="center">
  <a href="../../README_ko.md">공통 문서</a> ·
  <a href="../../negaflow-windows/docs/README_ko.md">Windows</a>
</p>

---

## 필요한 환경

실행:

- macOS 14.0 이상 (macOS 14, 26, 27 지원)
- Apple Silicon 또는 Intel
- 메모리 8GB, 중형 필름은 16GB 권장

빌드:

- 앱: Xcode 26 이상
- 엔진과 CLI: Swift 5.9 이상

## 설치

[Releases](https://github.com/habinsong/negaflow/releases)에서 받습니다.

| 파일 | 지원하는 Mac |
|---|---|
| `negaflow-1.2.6-mac-universal.pkg` | Apple Silicon, Intel |
| `negaflow-1.2.6-mac-arm64.pkg` | Apple Silicon 전용 |

대부분의 Mac에는 Universal PKG를 쓰면 되고 `/Applications`에 설치됩니다. 앱을 직접 옮기려면 같은 페이지의 DMG나 ZIP을 받으세요.

앱은 ad hoc 서명이고 공증을 받지 않아서 첫 실행을 macOS가 막습니다. 시스템 설정의 개인정보 보호 및 보안에서 '그래도 열기'를 누르세요.

라이브러리와 설정은 `~/Library/Application Support/negaflow`에 있습니다.

앱은 실행할 때 한 번 GitHub에 최신 릴리스를 묻습니다. 새 버전이 있으면 오른쪽 위 ⋯ 메뉴 맨 아래에 "X.Y.Z 버전 업데이트"가 나옵니다. 누르면 릴리스 페이지가 열리고, 이 Mac에 맞는 PKG를 릴리스의 `SHA256SUMS.txt`로 확인한 뒤 다운로드 폴더에 받습니다. 설치는 직접 합니다. 최신이면 항목이 "현재 최신 버전입니다."로 바뀌고 누르면 프로젝트 페이지로 갑니다. 오프라인처럼 확인에 실패하면 항목이 보이지 않습니다.

## 빌드

```bash
git clone https://github.com/habinsong/negaflow.git
cd negaflow/negaflow-mac

# Release 앱을 빌드하고 실행
bash scripts/run-app.sh

# 실행 없이 빌드만
bash scripts/run-app.sh build
```

`run-app.sh`는 `xcodebuild`를 부르고 앱 번들을 조립해 로컬 서명합니다. 엔진이나 CLI만 다룰 때는 `swift build`로 충분합니다.

배포 파일:

```bash
bash negaflow-mac/scripts/build-release.sh
bash negaflow-mac/scripts/create-release-artifacts.sh
```

## 점검

```bash
# Swift 테스트
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# 앱 Release 빌드
bash scripts/run-app.sh build

# 저장소의 전체 검사
bash scripts/ci-gate.sh
```

## Custom 색 타깃

타깃 캡슐은 MAIN, HS, SP, F135, HR 다음에 CS가 옵니다. CS를 고르면 왼쪽 아래 선택기가 Custom 타깃 18개를 2열 목록으로 보여 주고, 룩 선택기는 오른쪽에 그대로 있습니다. CS에 들어가면 Emulsion이 선택되며, 이미 Custom 타깃을 쓰는 사진은 그 타깃을 유지합니다.

목록은 세 묶음입니다. Emulsion부터 Dichroic까지 11개, Wetzlar부터 Rochester까지 4개, Slide Show부터 Point & Shoot까지 3개입니다. Custom 타깃은 custom-3 톤·농도·채도 응답을 적용합니다. 저장, 미리보기, 썸네일, 내보내기는 선택한 타깃 ID를 씁니다. 다른 타깃은 그대로입니다.

CLI도 같은 ID를 받습니다: `--target classic`, `--target dye-transfer`, `--target point-and-shoot`.

## 명령줄

macOS 빌드에는 CLI가 들어 있습니다.

```bash
swift build

# 스캐너 찾기
.build/debug/negaflow detect
.build/debug/negaflow capabilities <scannerID>

# 현상
.build/debug/negaflow develop in.tiff out.jpg --look rich-neutral --target main

# GrainMend
.build/debug/negaflow develop scan.tif out.jpg --defects 1
.build/debug/negaflow defect-bench ./scans --out ./report

# 프로파일과 엔진 자체 점검
.build/debug/negaflow list-scanner-profiles
.build/debug/negaflow selftest
```

전체 옵션은 인수 없이 `negaflow`를 실행하면 나옵니다.

## 스캐너

플러그인을 설치하기 전에는 스캐너 컨트롤이 보이지 않습니다. SANE 장치는 따로 설치하는 [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane)이 맡습니다.

## 모듈

| 모듈 | 역할 |
|---|---|
| `Chromabase` | Chroma Engine, GrainMend, 프로파일, 내보내기 |
| `ScannerKit` | 스캐너 기능 확인과 플러그인 연결 |
| `negaflowApp` | 라이브러리, 현상, 스캔, 내보내기 화면 |
| `negaflowCLI` | 현상, 스캔, 벤치마크, 자체 점검 명령 |

## 기준 이미지

`docs/verification/macos-golden`에는 이 빌드가 만든 이미지가 있습니다. 이 폴더는 Git이 무시하므로 이미지를 만든 컴퓨터에만 있습니다. Windows 엔진 테스트가 복사본과 픽셀 단위로 비교합니다. macOS 출력을 일부러 바꿀 때만 다시 만드세요.

## 관련 문서

- [두 버전의 차이](../../docs/ko/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/ko/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/ko/product/GRAINMEND.md)
- [제품 구조](../../docs/ko/architecture/PRODUCT_ARCHITECTURE.md)
