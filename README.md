<div align="center">
  <h1>negaflow</h1>
  <p>macOS Native Film Import, Scan & Developing Application</p>

  [![macOS](https://img.shields.io/badge/macOS-14.0+-black.svg?logo=apple)](#)
  [![Swift](https://img.shields.io/badge/Swift-5.9-F05138.svg?logo=swift)](#)
  [![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](#)
  <br/>
  <a href="README_en.md">Read in English</a>
</div>

<br/>

> **상태 알림:** negaflow 본체는 이미지 가져오기와 현상 파이프라인을 기본으로 제공합니다. 실제 SANE 하드웨어 스캔은 별도 GPL 플러그인인 [negaflow-scanner-sane](https://github.com/habinsong/negaflow-scanner-sane.git)을 설치했을 때만 활성화됩니다.

## 프로젝트 소개 (About The Project)

**negaflow**는 필름 스캔본을 가져와 현상하고 출력하는 macOS 네이티브 애플리케이션입니다.

RAW/DNG/TIFF/JPEG/PNG 같은 이미지 원본을 먼저 가져오고, 필요한 경우 외부 스캐너 플러그인으로 실제 필름 스캔을 추가합니다. 내장된 **Chromabase 색감 엔진**은 네거티브 반전, 필름 베이스 보정, `main`/`print` 타겟, 톤 매핑, 소프트 프루프, 로컬 보정, 출력까지 한 흐름으로 처리합니다.

## 주요 기능 (Key Features)

* **이미지 가져오기 우선:** RAW/DNG/TIFF/JPEG/PNG/HEIF 및 macOS가 인식하는 카메라 RAW를 가져와 바로 현상합니다.
* **선택적 스캐너 플러그인:** SANE 스캔 코드는 본 저장소에서 제거되었고, 외부 프로세스 플러그인 `negaflow-scanner-sane`을 통해 JSON/CLI 계약으로만 연결됩니다.
* **Chromabase 색감 파이프라인:** 필름 베이스 색상 추정, 오렌지 마스크 제거, 하이라이트 롤오프, `main` 플랫 마스터와 `print` 완성본 타겟을 처리합니다.
* **암실식 로컬 보정:** 브러시, 원형, 선형, 다각형 마스크로 dodge/burn 보정을 비파괴적으로 적용합니다.
* **출력 신뢰도:** 내장 ICC 기반 소프트 프루프와 paper/black ink 시뮬레이션으로 sRGB, Display P3, 프린트 계열 출력을 미리 확인합니다.
* **B&W 톤 조절:** 흑백 네거티브/포지티브에 Selenium, Sepia, Shadow Hue, Highlight Hue, Strength를 적용합니다.
* **페어드 내보내기:** 보정본과 함께 후보정용 `main` 플랫 마스터를 같은 폴더의 `-main-flat` 파일로 내보낼 수 있습니다.
* **내장 룩:** 사진의 분위기에 맞춰 적용 가능한 6가지 룩(Neutral, Rich Neutral, Soft Print, Clear Chrome, Warm Lab, Deep Slide)을 제공합니다.
* **프레임 기반 롤 워크플로:** `Scan Next`로 같은 세션에 다음 프레임을 추가하고, 좌측 목록에서 각 프레임의 원본·현상·출력 상태를 독립적으로 관리합니다.
* **사진 우선 편집 화면:** 확대·축소·이동·드래그 크롭, 원본/현상 비교, 조작 가능한 히스토그램, 회전·좌우/상하 반전 도구를 제공합니다.
* **세션 방향 유지:** 회전과 반전은 현재 프레임에 적용하는 동시에 이후 스캔에 유지됩니다. 크롭은 다음 프레임에 복사하지 않으며, 앱을 다시 열면 방향 기본값으로 돌아갑니다.
* **단계적 현상 조절:** Basic Tone, Tone Curve, Color, Calibration, Detail & Effects는 각각 열고 닫을 수 있으며, 섹션별 초기화가 가능합니다.

## 시스템 요구 사항 (Prerequisites)

* **OS:** macOS 14.0 (Sonoma) 이상
* **Build:** Xcode 15 이상 (또는 Command Line Tools)
* **Dependencies:** 본체 빌드에는 별도 스캐너 의존성이 없습니다. 실제 SANE 하드웨어 스캔은 `negaflow-scanner-sane` 플러그인과 `scanimage`가 필요합니다.

## 설치 및 빌드 (Installation)

저장소를 복제한 뒤 제공되는 셸 스크립트를 통해 앱을 빌드하고 실행할 수 있습니다.
(*참고: Xcode 26 SDK의 `SwiftUICore` 프레임워크 링크 제약으로 인해, GUI 실행은 반드시 `xcodebuild`를 거쳐야 합니다.*)

```bash
# 1. 저장소 클론
git clone https://github.com/habinsong/negaflow.git negaflow
cd negaflow

# 2. 앱 빌드 및 실행
bash scripts/run-app.sh
```

실제 SANE 스캐너를 연결하려면 플러그인을 별도 저장소에서 설치합니다.

```bash
git clone https://github.com/habinsong/negaflow-scanner-sane.git
cd negaflow-scanner-sane
brew install sane-backends
./install.sh
```

## 사용 방법 (Usage)

### GUI 인터페이스
```bash
bash scripts/run-app.sh run
```
단일 윈도우는 프레임 목록, 중앙 캔버스, 우측 인스펙터로 구성됩니다. 우측 인스펙터는 `Scan → Base → 도구 → Tone → Color → Detail → Export` 순서이며, 활성 섹션만 펼쳐 작업할 수 있습니다.

1. 이미지 파일을 가져오거나, SANE 플러그인이 설치된 경우 실제 스캐너를 선택하고 `Scan` 또는 `Scan Next`를 누릅니다.
2. 중앙 캔버스에서 확대·축소, 이동, 크롭과 원본/현상 비교를 수행합니다.
3. 우측 도구 스트립에서 방향을 맞춥니다. 표시되는 `다음 스캔` 값이 이후 프레임에 적용될 방향입니다.
4. 현상 섹션을 열어 조절하고, 필요한 섹션의 초기화 아이콘으로 수동 조절만 되돌립니다.
5. JPEG 또는 16-bit TIFF와 선택적 sidecar JSON을 출력합니다.

### 커맨드라인 도구 (CLI)
자동화된 스크립트 작성이나 헤드리스(Headless) 환경에서의 빠른 현상을 위해 CLI 도구를 제공합니다.

```bash
# 타겟 빌드
swift build

# 스캐너 제어(외부 플러그인 설치 시)
.build/debug/negaflow detect
.build/debug/negaflow capabilities <scannerID>
.build/debug/negaflow scan --dpi 3600

# 필름 현상
.build/debug/negaflow develop in.tiff out.jpg --look rich-neutral --target print
.build/debug/negaflow develop photo.dng out.jpg --look clear-chrome
```

## 하드웨어 호환성 (Supported Hardware)

negaflow 본체는 장치의 특정 모델명을 코드에 고정하지 않습니다. 설치된 스캐너 플러그인이 보고하는 **기능(Capability)**을 기반으로 UI와 스캔 옵션을 구성합니다.

* **플러그인 저장소:** [habinsong/negaflow-scanner-sane](https://github.com/habinsong/negaflow-scanner-sane.git)
* **검증된 경로:** Plustek OpticFilm 8100의 SANE `genesys` 감지와 3600 dpi / 16-bit RGB 스캔 흐름
* **호환 대상:** 플러그인이 `scanimage -L`/`scanimage -A`에서 감지한 Plustek OpticFilm 및 기타 SANE 지원 스캐너

스캐너 하드웨어나 플러그인이 없어도 Mock 백엔드와 이미지 가져오기 흐름으로 현상 엔진을 검증할 수 있습니다.

## 검증

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
bash scripts/run-app.sh build
```

자동 테스트는 색감 엔진, 이미지 변형, 가져오기 로더, 외부 스캐너 플러그인 호스트, 내보내기를 검증합니다. GUI 변경은 실제 앱에서 이미지 가져오기 또는 설치된 스캐너 플러그인 상태로 `Import/Scan → Develop → Export` 흐름까지 확인합니다.

## 아키텍처 구조 (Architecture)

프로젝트 코드는 책임의 분리를 위해 세 가지 주요 계층으로 나뉘어 있습니다.

1. **ScannerKit:** 스캐너 추상화 계층입니다. 본체에는 Mock과 외부 프로세스 플러그인 호스트만 포함되며, SANE 구현은 별도 저장소에 있습니다.
2. **Chromabase:** 필름 데이터의 색상 변환과 네거티브 반전 수학을 처리하는 핵심 엔진입니다.
3. **negaflowApp / negaflow:** 사용자 상호작용을 담당하는 SwiftUI 데스크톱 앱 및 CLI입니다.

## 라이선스 (License)

본 프로젝트의 소스 코드는 **Apache License 2.0** 조건하에 배포됩니다.
SANE 스캐너 지원은 별도 GPL-2.0-or-later 프로젝트인 `negaflow-scanner-sane`이 담당합니다. negaflow 본체는 해당 플러그인을 별도 OS 프로세스와 JSON/CLI 프로토콜로만 호출하며, GPL 코드를 링크하거나 포함하지 않습니다.
