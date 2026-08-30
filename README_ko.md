<p align="center">
  <img src="negaflow-mac/Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow 앱 아이콘">
</p>

<h1 align="center">negaflow</h1>

<p align="center">아날로그 필름을 스캔하고 현상해서 인화까지 하는 앱. macOS와 Windows에서 각각 네이티브로 동작합니다.</p>

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/ko/"><img src="https://img.shields.io/badge/website-negaflow-1F6FEB" alt="웹사이트"></a>
  <a href="#설치"><img src="https://img.shields.io/badge/version-1.1.0-EF8B26" alt="버전 1.1.0"></a>
  <a href="negaflow-mac/docs/README_ko.md"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 이상"></a>
  <a href="negaflow-windows/docs/README_ko.md"><img src="https://img.shields.io/badge/Windows-11-0078D4?logo=windows&logoColor=white" alt="Windows 11"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-6E7781" alt="Apache 2.0 라이선스"></a>
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
  <a href="https://habinsong.github.io/negaflow-site/ko/">웹사이트</a> ·
  <a href="https://habinsong.github.io/negaflow-site/ko/camera-scanning/">카메라 스캔 가이드</a> ·
  <a href="https://habinsong.github.io/negaflow-site/ko/faq/">FAQ</a>
</p>

---

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/ko/develop-dark.webp">
    <img src="docs/images/ko/develop-light.webp" alt="negaflow 현상 화면">
  </picture>
</p>

**negaflow**는 스캐너로 스캔한 필름이나 디지털 카메라로 촬영한 필름을 불러와서 현상하는 앱입니다.<br>
현상 엔진은 **Chroma Engine**, 먼지와 스크래치 복원 기능은 **GrainMend**라는 이름을 쓰며<br>
독자 개발한 프로세스 전 과정을 담았습니다. 필름을 현상하고 보정하고 인화하는 과정을 앱 하나에서 처리합니다.<br><br>
이미지 파일만 가져와도 현상과 내보내기를 쓸 수 있고, **스캐너 연결은 별도 플러그인이 있을 때만 활성화**됩니다.<br><br>

> 요즘의 아날로그 유행의 성장과 다르게 지금의 아날로그 사진 프로세스는 정체기라고 할수 있죠.<br>
> 필름을 아날로그 인화하는 방식이 아닌 이상, 아날로그를 디지털로 변환하는 과정을 거쳐야 비로소 우리 눈에 보여집니다. <br>
> <br>
> 그러나 그 모든 과정이 멈춰가고 있습니다. <br>
> 필름랩, 현상소는 점점 없어져 제조사와 제품에 대한 지원이 줄어들고 있기 때문이죠.

> <br>
> 본 프로젝트는 다양한 경험을 통해 느낀 불편함과 새로운 기능이 있었으며 좋겠다라는 생각에서 시작했습니다. <br>
> 35mm 필름과 중형 필름을 사용하면서 알게된 경험과 지식을 바탕으로 하나부터 열까지 모두 직접 개발했습니다.<br>
> 처음에는 내가 혼자 사용하며 이것저젓 만들어본 토이 프로젝트였지만 이제 negaflow는 그 이상의 어떤 무언가가 되었습니다.<br>
>
>
> <br>결국 무엇보다 '잘' 되며 편하게 사용하고, 빨라야하고 뭐든지 알아서 제대로 만든 결과물이 중요하니까요. <br>
> 독자 개발한 **negaflow**는 네이티브로 지원되며, 필름랩과 개인의 워크플로우를 다 녹여봤습니다.
>
> <br>
>
> **니엡스가 찍은 최초의 사진으로부터 200주년인 올해 여름을 기념하며.**

---

## macOS용과 Windows용을 따로 만들었습니다

negaflow는 macOS와 Windows에서 모두 동작합니다. 두 앱은 같은 코드를 공유하지 않습니다.

| | macOS | Windows |
|---|---|---|
| 화면 | SwiftUI | WinUI 3 |
| 엔진 | Swift + Core Image | C++ + Direct3D |
| 색 관리 | ColorSync | Windows ICM |

같은 사진을 넣으면 두 앱이 같은 결과를 냅니다. macOS 버전이 만들어 둔 기준 이미지를
Windows 쪽 테스트가 읽어서 화소 값까지 같은지 확인합니다.

한쪽을 만든 다음 옮겨 붙인 것이 아니라, 플랫폼마다 그 방식대로 처음부터 다시 만들었습니다.
대신 두 버전 모두 그 운영체제의 다른 앱과 똑같이 동작합니다.

- [macOS 문서](negaflow-mac/docs/README_ko.md)
- [Windows 문서](negaflow-windows/docs/README_ko.md)
- [macOS와 Windows의 차이](docs/ko/platform/PLATFORM_DIFFERENCES.md)

---

## 설치

[GitHub Releases](https://github.com/habinsong/negaflow/releases)에서 현재 버전을 내려받습니다.

### macOS

| 설치 파일 | 지원하는 Mac |
|---|---|
| `negaflow-1.1.0-mac-universal.pkg` | Apple Silicon, Intel |
| `negaflow-1.1.0-mac-arm64.pkg` | Apple Silicon 전용 |

대부분의 Mac은 Universal PKG를 쓰면 됩니다. 실리콘 맥(M 시리즈)은 arm64 PKG를 써도 됩니다.

1. 사용하는 Mac에 맞는 PKG를 내려받습니다.
2. PKG를 열고 설치 프로그램의 안내를 따릅니다.
3. `/Applications`에서 **negaflow**를 실행합니다.

PKG는 `negaflow.app`을 `/Applications`에 바로 설치합니다.
직접 설치할 때 쓸 DMG와 ZIP도 같은 릴리스 페이지에 있습니다.
애플 개발자 인증이 없어서 처음 실행할 때는 설정의 개인정보 보호 및 보안에서
'그래도 열기'를 눌러야 합니다.

### Windows

| 설치 파일 | 지원하는 PC |
|---|---|
| `negaflow-1.1.0-win-x64.exe` | Windows 11 (x64) |

1. 설치 파일을 내려받아 실행합니다.
2. 언어를 고르고 안내를 따릅니다.
3. 시작 메뉴에서 **negaflow**를 실행합니다.

설치는 사용자 폴더 안에서만 이뤄지고 관리자 권한이 필요 없습니다.
제거는 시작 메뉴의 `negaflow 제거`나 설정의 앱 목록에서 합니다.
서명하지 않은 설치 파일이라 SmartScreen이 한 번 경고합니다. 추가 정보를 눌러 실행하면 됩니다.

> 실제 스캐너를 연결하려면 별도 스캐너 플러그인이 필요합니다.<br>
> SANE 스캐너는 [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane)을 씁니다. macOS와 Windows 모두 지원합니다.

---

## 기능

- 필름 베이스 측정과 컬러·흑백 필름 반전
- 노출, 대비, 커브, HSL, 컬러 그레이딩, 흑백 토닝
- 선명도, 노이즈 제거, 그레인, 비네팅, 할레이션
- 먼지와 스크래치를 복원하는 GrainMend와, 스캐너 적외선 채널을 쓰는 GrainMend IR
- 롤, 폴더, 컬렉션, 별점, 스택과 가상 사본
- 확대, 자르기, 회전, 비교 보기, 히스토그램과 잘림 표시
- 카메라, 렌즈, 필름, 노출 기록을 내보낸 파일의 EXIF에 기록
- 롤 단위 촬영 기록과 카메라·렌즈·필름으로 찾는 라이브러리 검색
- JPEG와 16비트 TIFF 내보내기, ICC 프로파일과 인화 레이아웃
- 레이아웃별 검정·회색·흰색 시트, 무광·유광·러스터·실크 미리보기, 사진용·ISO 용지와 in/cm 눈금자
- C-print 인화소·인화지 설정과 인화소 ICC 소프트 프루프 미리보기
- 가져오기 진행률, 폴더별 현상 프로세스·타깃 일괄 적용과 처리 진행률
- 접은 상태를 기억하는 폴더 목록, 사진 드래그 이동, 파일 탐색기와 Finder 변경 자동 반영
- 현상 프로세스, 타깃, 톤·색·디테일, 크롭과 방향을 함께 옮기는 프리셋과 복사·붙여넣기
- 단일 이미지, 콘택트 시트, 사진 패키지, 사용자 패키지, 시아노타입, 유리건판, 젤라틴의 7가지 인화 레이아웃
- 콘택트 시트는 합성한 한 파일로, 한 장씩 보는 레이아웃은 여러 파일로 내보내며 진행률을 함께 보여줍니다

컬러와 흑백, 네거티브와 포지티브를 모두 다루고 보정 내용은 원본과 따로 저장합니다.

---

## Chroma Engine

**Chroma Engine**은 필름 반전과 현상을 담당하는 엔진입니다.<br>
네거티브를 반전하기 전에 빛이 닿지 않은 영역에서 필름 베이스를 측정합니다.<br>
자동 측정이 맞지 않으면 스포이드로 영역을 고르거나 RGB 값을 직접 넣을 수 있습니다.<br>
기본 현상은 `MAIN`과 수동 보정이고, 자동 톤과 자동 화이트 밸런스, 자동 레벨과 자동 색상은 직접 눌렀을 때만 적용됩니다.
<br><br>
고를 수 있는 현상 대상은 이렇습니다.

- `MAIN`: 일반 현상
- `PRINT`: 프린터 ICC를 쓰는 출력
- `HS`, `SP`: 미니랩 계열 현상
- `F135`, `HR`: 랩 장비 계열 현상
- `EXPIRED`: 오래된 필름 복구

출력에는 sRGB, Display P3, Adobe RGB나 사용자 RGB ICC를 쓸 수 있습니다.<br>
반전과 색 처리 순서는 [크로마 엔진 문서](docs/ko/product/CHROMA_ENGINE.md)에 있습니다.

---

## GrainMend

**GrainMend는 필름의 먼지, 핀홀, 스크래치와 유제 손상 같은 결함을 복원합니다.**

| GrainMend RGB | 사용 과정 |
| ----- | ------------------------- |
| 자동 | 사진 전체에서 결함을 찾고 복원합니다. |
| 가이드 | 사용자가 지정한 영역 안에서 결함을 찾습니다. |
| 브러시 | 복원할 자리를 직접 칠합니다. |
| 복제 도장 | 지정한 위치의 픽셀을 다른 곳에 복제합니다. |

**GrainMend RGB**의 자동과 가이드 도구는 주변 질감을 참고해 결함을 메웁니다.<br>
사진 속 선이나 격자를 스크래치로 착각해 지우지 않도록 방향과 주변 구조도 함께 살핍니다.<br>
수정 결과는 GrainMend 레이어로 남습니다.<br><br>

> 자동 기능은 보편적인 결함을 제거합니다. 안전하게 적용하기 어려울 만큼 후보가 몰리면 사진을 바꾸지 않고 멈춘 뒤 가이드 사용을 안내합니다. <br>
> 가이드는 스캔 과정에서 생긴 먼지 제거에 특화되어 있습니다. 브러시는 자동으로 찾지 못한 결함을 직접 복원하고, 복제 도장은 사용자가 고른 원본 픽셀을 복사합니다. <br>

각 **GrainMend RGB** 레이어는 강도를 바꾸거나 마스크를 확인하고, 따로 끄거나 지울 수 있습니다.

**GrainMend IR**은 스캐너 플러그인이 적외선 채널을 주면 IR 검출 결과도 같은 편집 기록에 더합니다.<br><br>

**GrainMend RGB**는 하드웨어 적외선 클리닝과는 다른 소프트웨어 방식이고,<br>
**GrainMend IR**은 스캐너의 적외선 채널을 쓰지만 Digital ICE, iSRD, SRDx의 구현이나 호환 모드는 아닙니다.

동작 방식과 품질·성능 기준은 [GrainMend 문서](docs/ko/product/GRAINMEND.md)에 있습니다.

---

## 필름 프로파일

번들에는 직접 촬영한 필름 자료로 만든 스캐너 프로파일 15개가 들어 있습니다.<br>
프로파일에 기록한 이미지 관측값은 모두 928개입니다. 현재 상태는 전부 `realOnly`입니다.
<br>

`realOnly`는 실제 스캔 자료로 만들었지만 독립된 기준 스캔 쌍으로 정확도를 검증한 단계는 아니라는 뜻입니다.<br>
프로파일은 스캐너 이름만 보고 자동으로 적용하지 않습니다. 사용자가 직접 골라야 합니다. 파일과 목록의 SHA-256도 함께 제공합니다.

<br>

`928`장은 각 프로파일의 관측값을 더한 수치입니다. 같은 필름이 여러 장비에 중복 집계될 수 있어서 서로 다른 사진 928장을 뜻하지는 않습니다. 실제 928장의 스캔본을 하나씩 확인하며 오검출 파일은 제외했고, 실측값을 바탕으로 프로파일을 만들었습니다.<br><br>
자료 구성과 만든 과정은 [필름 프로파일 문서](docs/ko/product/FILM_PROFILES.md)에 적었습니다.

---

## 기본 사용 순서

1. 이미지 파일을 가져오거나 설치된 플러그인으로 스캔합니다.
2. 필름 종류를 고르고 필름 베이스를 측정합니다.
3. 크로마 엔진에서 색과 톤을 조절합니다.
4. 필요한 사진에 GrainMend를 적용합니다.
5. 비교 보기와 히스토그램으로 결과를 확인한 뒤 인화하거나 내보냅니다.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/ko/library-dark.webp">
    <img src="docs/images/ko/library-light.webp" alt="negaflow 라이브러리 화면">
  </picture>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/ko/print-dark.webp">
    <img src="docs/images/ko/print-light.webp" alt="negaflow 인화 화면">
  </picture>
</p>

<br><br>
**사람이 사용하기 쉽게 만들었습니다. 단축키, 폴더 경로, 프리셋, 보정 등 모든 것을 커스텀해서 사용할 수 있습니다.<br>
AI가 만든 어떤 이상한 UI/UX로 구성된 앱이 아닌, 사람이 사용하기 편하게 만든 앱이기에 사진을 취미로 한다면 쉽게 사용할 겁니다.**

## 라이브러리에서 인화까지

이미지를 불러오기만 했을 때는 현상하지 않습니다. 원본 썸네일과 폴더를 먼저 만들고, 현상은
폴더의 프로세스와 타깃을 고른 뒤 **적용**을 누르거나 현상 화면으로 들어갔을 때 시작합니다.
자동 현상이 필요하면 설정의 작업 흐름에서 기본값을 켤 수 있고, 기본값은 꺼짐입니다.

폴더를 접거나 펼친 상태는 앱을 다시 열어도 남습니다. 사진은 폴더 사이로 끌어 옮길 수 있고,
같은 이름의 파일이 있으면 번호를 붙여 원본을 덮어쓰지 않습니다. 파일 탐색기나 Finder에서
원본이나 폴더를 옮기거나 이름을 바꾸면 라이브러리도 해당 폴더만 다시 읽어 위치를 맞춥니다.

현상 설정 복사와 붙여넣기, 사용자 프리셋에는 프로세스, 타깃, 필름 베이스, 톤, 색, 디테일,
크롭, 회전, 뒤집기와 기울기 보정이 들어갑니다. 여러 사진을 선택하면 선택한 사진 모두에
한꺼번에 적용합니다.

인화 화면의 프린터 출력 프로파일은 페이지 배치를 마친 전체 결과에 적용됩니다. 사진 패키지에
같은 사진을 여러 번 넣거나 여러 사진을 섞어도 빠지는 항목이 없습니다. 이 프로파일은 현상
화면의 미리보기에는 들어가지 않습니다.

자세한 사용 방법과 각 동작이 원본 파일에 미치는 영향은
[라이브러리에서 인화까지](docs/ko/product/WORKFLOW.md)에 적었습니다.

## 직접 빌드하기

플랫폼마다 필요한 도구와 명령이 다릅니다. 자세한 내용은 각 문서에 있습니다.

**macOS**

```bash
git clone https://github.com/habinsong/negaflow.git
cd negaflow

# Release 빌드 후 실행
bash scripts/run-app.sh

# 실행하지 않고 빌드만
bash scripts/run-app.sh build
```

macOS 14 이상과 Xcode 26이 필요합니다. 엔진과 CLI만 빌드할 때는 `swift build`를 씁니다.
[macOS 문서](negaflow-mac/docs/README_ko.md)에 더 적어 뒀습니다.

**Windows**

```powershell
git clone https://github.com/habinsong/negaflow.git
cd negaflow\negaflow-windows

# 엔진 빌드
.\scripts\build.ps1 -Preset x64-release

# 앱 빌드 후 실행
.\scripts\run-app.ps1 -Architecture x64 -Configuration Release
```

Windows 11과 Visual Studio 2022, .NET 10 SDK가 필요합니다.
[Windows 문서](negaflow-windows/docs/README_ko.md)에 더 적어 뒀습니다.

## 스캐너

negaflow 본체는 스캐너 모델을 추측해 기능을 열지 않습니다.<br>
플러그인이 알려 준 해상도, 비트 심도, 스캔 영역, 노출과 IR 기능만 씁니다.

SANE 장치는 별도 GPL 프로젝트인
[`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane)이 담당합니다.<br>
플러그인은 별도 프로세스로 돌고 JSON으로 주고받습니다.<br>
**negaflow**에는 SANE 코드를 넣거나 링크하지 않습니다.

## 저장소 구성

```
negaflow/
├── negaflow-mac/       macOS 앱과 엔진 (Swift)
├── negaflow-windows/   Windows 앱과 엔진 (C#, C++)
└── docs/               두 버전이 함께 쓰는 문서
```

**macOS**

| 모듈 | 역할 |
| ------------- | ----------------------------- |
| `Chromabase` | 크로마 엔진, GrainMend, 프로파일과 내보내기 |
| `ScannerKit` | 스캐너 기능 확인과 외부 플러그인 연결 |
| `negaflowApp` | 라이브러리, 현상, 스캔과 내보내기 화면 |
| `negaflowCLI` | 현상, 스캔, 벤치마크와 자체 점검 명령 |

**Windows**

| 모듈 | 역할 |
| ------------- | ----------------------------- |
| `Native` | 크로마 엔진, GrainMend, 내보내기 (C++) |
| `Interop` | 엔진과 앱 사이의 연결 |
| `Catalog.Core` | 라이브러리 저장소 |
| `Shell.Core` | 현상, 인화, 내보내기 로직 |
| `Shell` | 라이브러리, 현상, 인화 화면 (WinUI 3) |

모듈 사이의 데이터 흐름은 [제품 구조 문서](docs/ko/architecture/PRODUCT_ARCHITECTURE.md)에 있습니다.

## 문서

| 문서 | 내용 |
| -------------------------------------------------- | ------------------------------- |
| [크로마 엔진](docs/ko/product/CHROMA_ENGINE.md) | 필름 베이스, 반전, 색 처리와 현상 순서 |
| [GrainMend](docs/ko/product/GRAINMEND.md) | 결함 검출과 복원, IR, 편집 기록, 성능과 품질 기준 |
| [필름 프로파일](docs/ko/product/FILM_PROFILES.md) | 촬영 자료 분석과 프로파일 생성 |
| [라이브러리에서 인화까지](docs/ko/product/WORKFLOW.md) | 가져오기, 폴더 동기화, 일괄 현상, 설정 복사와 인화 프로파일 |
| [제품 구조](docs/ko/architecture/PRODUCT_ARCHITECTURE.md) | 앱, 엔진, 스캐너, 저장과 내보내기 구조 |
| [macOS와 Windows의 차이](docs/ko/platform/PLATFORM_DIFFERENCES.md) | macOS와 Windows에서 다른 점과 같은 점 |
| [macOS 문서](negaflow-mac/docs/README_ko.md) | macOS 설치, 빌드, CLI |
| [Windows 문서](negaflow-windows/docs/README_ko.md) | Windows 설치, 빌드, 엔진 점검 |

---
## 라이선스

**negaflow**는 [Apache License 2.0](LICENSE)으로 배포됩니다.

**negaflow**는 Kodak, Fujifilm, Noritsu, LaserSoft Imaging이나 다른 상표권자와 제휴하거나 후원받지 않습니다.<br>
제품명은 호환 대상이나 측정 대상을 가리킬 때만 씁니다. 자세한 내용은 [상표 고지](TRADEMARKS.md)에 있습니다.
