<p align="center">
  <img src="../Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for macOS</h1>

<p align="center">macOS 네이티브로 만든 negaflow입니다.</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.4-EF8B26" alt="버전 1.1.4"></a>
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

## 필요한 것

실행할 때:

- macOS 14.0 이상
- Apple Silicon 또는 Intel
- 35mm 작업은 메모리 8GB, 중형 필름을 다루면 16GB가 편합니다

빌드할 때:

- 앱은 Xcode 26
- 엔진과 CLI는 Swift 5.9 이상

## 설치

[Releases](https://github.com/habinsong/negaflow/releases)에서 내려받습니다.

| 설치 파일 | 지원하는 Mac |
|---|---|
| `negaflow-1.1.4-mac-universal.pkg` | Apple Silicon, Intel |
| `negaflow-1.1.4-mac-arm64.pkg` | Apple Silicon 전용 |

대부분은 Universal PKG를 쓰면 됩니다. `/Applications`에 설치됩니다. 직접 옮기려면 같은 페이지의 DMG나 ZIP을 쓰십시오.

애플 공증을 받지 않아서 처음 실행할 때 macOS가 막습니다. 시스템 설정의 개인정보 보호 및 보안에서 '그래도 열기'를 누르면 됩니다.

라이브러리와 설정은 `~/Library/Application Support/negaflow`에 저장됩니다.

## 빌드

```bash
git clone https://github.com/habinsong/negaflow.git
cd negaflow/negaflow-mac

# Release 빌드 후 실행
bash scripts/run-app.sh

# 실행하지 않고 빌드만
bash scripts/run-app.sh build
```

`run-app.sh`가 `xcodebuild`를 부르고 앱 번들을 조립한 뒤 로컬 서명까지 합니다. 엔진이나 CLI만 손볼 때는 `swift build`로 충분합니다.

배포 파일을 만들 때:

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

# 저장소 전체 점검
bash scripts/ci-gate.sh
```

## 명령줄

macOS 버전에는 CLI가 들어 있습니다.

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

# 프로파일 목록과 엔진 자체 점검
.build/debug/negaflow list-scanner-profiles
.build/debug/negaflow selftest
```

`negaflow`를 인자 없이 실행하면 전체 옵션이 나옵니다.

## 스캐너

플러그인을 설치하기 전까지 스캐너 조작은 나타나지 않습니다. SANE 장치는 [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane)이 담당하며 따로 설치해야 합니다.

## 모듈 구성

| 모듈 | 역할 |
|---|---|
| `Chromabase` | 크로마 엔진, GrainMend, 프로파일과 내보내기 |
| `ScannerKit` | 스캐너 기능 확인과 외부 플러그인 연결 |
| `negaflowApp` | 라이브러리, 현상, 스캔과 내보내기 화면 |
| `negaflowCLI` | 현상, 스캔, 벤치마크와 자체 점검 명령 |

## 기준 이미지

저장소 최상위의 `docs/verification/macos-golden`에는 이 빌드가 만든 이미지가 들어 있습니다. Windows 엔진 테스트가 이 파일들을 읽어 화소 단위로 비교합니다. macOS 출력이 바뀌어야 할 때만 다시 만들면 됩니다.

## 관련 문서

- [macOS와 Windows의 차이](../../docs/ko/platform/PLATFORM_DIFFERENCES.md)
- [크로마 엔진](../../docs/ko/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/ko/product/GRAINMEND.md)
- [제품 구조](../../docs/ko/architecture/PRODUCT_ARCHITECTURE.md)
