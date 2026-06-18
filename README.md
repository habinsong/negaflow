<div align="center">
  <h1>Negaflow</h1>
  <p>macOS Native Film Scanning & Developing Application for Plustek OpticFilm</p>

  [![macOS](https://img.shields.io/badge/macOS-13.0+-black.svg?logo=apple)](#)
  [![Swift](https://img.shields.io/badge/Swift-5.9-F05138.svg?logo=swift)](#)
  [![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](#)
  <br/>
  <a href="README_en.md">Read in English</a>
</div>

<br/>

> **상태 알림:** 본 프로젝트는 현재 **초기 개발 단계(Under Active Development)**입니다. 하드웨어 지원 범위 및 API 구조 등은 향후 변경될 수 있습니다.

## 프로젝트 소개 (About The Project)

**Negaflow**는 Plustek OpticFilm 스캐너 사용자를 위한 macOS 네이티브 필름 스캔 및 현상 애플리케이션입니다.

기존의 복잡한 스캔 소프트웨어 워크플로에서 벗어나, 원본 스캔부터 최종 색감 보정 및 출력(JPEG/TIFF)까지 단일 앱에서 직관적으로 처리할 수 있도록 설계되었습니다. 내장된 **Chromabase 색감 엔진**을 통해 고품질의 네거티브 반전과 현대적인 톤 매핑을 제공합니다.

## 주요 기능 (Key Features)

* **스캐너 다이렉트 제어:** SANE `genesys` 백엔드를 활용해 네이티브 수준의 스캐너 통합을 구현했습니다. (최대 7200dpi, 16-bit RGB 지원)
* **강력한 색감 파이프라인:** Chromabase 엔진이 필름 베이스 색상 추정, 오렌지 마스크 제거, 하이라이트 롤오프를 자동화합니다.
* **통합 포맷 지원:** 스캐너를 통한 필름(컬러 네거티브/슬라이드/흑백) 현상은 물론, 디지털 카메라를 이용한 스캔본(RAW/DNG)의 현상도 지원합니다.
* **프로덕션 레벨 프리셋:** 사진의 분위기에 맞춰 즉시 적용 가능한 6가지 룩(Neutral, Rich Neutral, Soft Print, Clear Chrome, Warm Lab, Deep Slide)을 내장하고 있습니다.

## 시스템 요구 사항 (Prerequisites)

* **OS:** macOS 13.0 (Ventura) 이상
* **Build:** Xcode 15 이상 (또는 Command Line Tools)
* **Dependencies:** SANE 백엔드 (`scanimage`) - *실제 하드웨어 스캔 시 필수*

## 설치 및 빌드 (Installation)

저장소를 복제한 뒤 제공되는 셸 스크립트를 통해 앱을 빌드하고 실행할 수 있습니다.
(*참고: Xcode 26 SDK의 `SwiftUICore` 프레임워크 링크 제약으로 인해, GUI 실행은 반드시 `xcodebuild`를 거쳐야 합니다.*)

```bash
# 1. 저장소 클론
git clone <repo> Negaflow
cd Negaflow

# 2. SANE 백엔드 설치 (Homebrew)
brew install sane-backends

# 3. 앱 빌드 및 실행
bash scripts/run-app.sh
```

## 사용 방법 (Usage)

### GUI 인터페이스
```bash
bash scripts/run-app.sh run
```
단일 윈도우 인터페이스 내에서 프리뷰 캔버스 시청, 현상 컨트롤 조작, 실시간 히스토그램 확인이 가능합니다.

### 커맨드라인 도구 (CLI)
자동화된 스크립트 작성이나 헤드리스(Headless) 환경에서의 빠른 현상을 위해 CLI 도구를 제공합니다.

```bash
# 타겟 빌드
swift build

# 스캐너 제어
.build/debug/negaflow detect
.build/debug/negaflow capabilities <scannerID>
.build/debug/negaflow scan --dpi 3600

# 필름 현상
.build/debug/negaflow develop in.tiff out.jpg --look rich-neutral
.build/debug/negaflow develop photo.dng out.jpg --look clear-chrome
```

## 하드웨어 호환성 (Supported Hardware)

Negaflow는 장치의 특정 모델명을 코드에 고정(Hardcoding)하지 않고, 스캐너가 시스템에 보고하는 **기능(Capability)**을 기반으로 작동합니다.

* **완전 검증됨 (Verified):** Plustek OpticFilm 8200i
* **호환 예정 (Compatible):** Plustek OpticFilm 8100, 8300i
* **실험적 지원 (Experimental):** OpticFilm 7200i, 7400, 7600i 등 구형 라인업

*(스캐너 하드웨어가 없는 경우에도, 앱 내부의 **Demo** 기능을 켜서 Mock 백엔드와 샘플 스캔본으로 전체 색감 엔진 로직을 시연해 볼 수 있습니다.)*

## 아키텍처 구조 (Architecture)

프로젝트 코드는 책임의 분리를 위해 세 가지 주요 계층으로 나뉘어 있습니다.

1. **ScannerKit:** 스캐너 통신을 담당하는 하드웨어 추상화 계층입니다. (현재 기본 백엔드로 SANE 사용)
2. **Chromabase:** 필름 데이터의 색상 변환과 네거티브 반전 수학을 처리하는 핵심 엔진입니다.
3. **NegaflowApp / negaflow:** 사용자 상호작용을 담당하는 SwiftUI 데스크톱 앱 및 CLI입니다.

## 라이선스 (License)

본 프로젝트의 소스 코드는 **Apache License 2.0** 조건하에 배포됩니다.
(SANE `scanimage`는 외부 프로세스 형태로 호출되어 `libsane`을 앱에 직접 링크하지 않습니다. 따라서 본 프로젝트는 GPL 파생 저작물에 해당하지 않습니다.)
