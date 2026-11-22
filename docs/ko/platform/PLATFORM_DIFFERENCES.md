# macOS 버전과 Windows 버전의 차이

[문서 홈](../README.md)

negaflow는 macOS용과 Windows용이 따로 있으며 두 버전은 소스 코드를 공유하는 대신 각 운영체제의 네이티브 방식으로 개발했습니다.

## 따로 만든 이유

크로스플랫폼 프레임워크를 선택하면 메뉴나 파일 대화상자가 운영체제와 어색하게 어긋나고 색 관리도 변환 계층을 한 번 더 거치게 됩니다. 반면 macOS와 Windows를 각각 네이티브로 개발하면 기능마다 두 번 만들고 두 번 시험해야 해서 품이 두 배쯤 들지만 양쪽 운영체제 모두에서 사용자가 기대하는 방식대로 자연스럽게 동작합니다.

## 공통점

출력되는 그림입니다. 똑같은 스캔 파일을 넣으면 두 버전이 일치하는 결과를 만들어 냅니다.

macOS 빌드는 `docs/verification/macos-golden`에 기준 이미지를 렌더링합니다. 이 폴더는 Git이 무시하므로 이미지는 생성한 컴퓨터에만 남습니다. Windows 엔진 테스트는 그 복사본을 읽어 픽셀 수치를 비교하므로, Windows 엔진이 어긋나면 테스트가 실패합니다.

아래 항목도 똑같이 맞춥니다.

- 필름 베이스 측정과 반전
- 모든 현상 타깃: `MAIN`, `PRINT`, `HS`, `SP`, `F135`, `HR`, `EXPIRED`, `CS`
- 톤과 커브, HSL, 컬러 그레이딩, 흑백 토닝
- 적외선 경로를 포함한 GrainMend 검출과 복원
- 인화 레이아웃과 페이지 기하
- 모든 형식의 내보내기 파일 이름과 JPEG, TIFF, DNG의 EXIF 메타데이터 정책(Windows에서 PNG 내보내기는 EXIF 메타데이터 없이 DPI와 ICC 프로파일만 포함)
- 카탈로그 형식(`library.sqlite`)

## 차이점

### 색 관리

macOS는 ColorSync, Windows는 ICM을 거칩니다. 양쪽 모두 똑같은 ICC 프로파일을 받아 반올림 범위 안에서 일치하는 결과를 냅니다. 색 관리 쪽은 눈치채지 못하게 어긋나기 쉬워 동등성 테스트로 계속 확인합니다.

화면 표시는 macOS가 디스플레이의 ColorSync 프로파일로 그립니다. Windows는 Advanced Color가 켜져 있을 때만 그렇게 동작하며 꺼져 있으면 앱 화소를 sRGB로 보고 그대로 화면에 보내므로 negaflow가 현상 캔버스와 인화 미리보기(작은 밀착 인화 타일 포함)를 그리기 직전에 모니터 ICC 33³ LUT로 변환합니다.

모니터를 교체하거나 디스플레이 설정을 변경한 뒤 앱 화면으로 돌아오면 프로파일을 자동으로 갱신하며 썸네일과 나머지 화면 요소는 sRGB로 그립니다.

### 그래픽

macOS는 현상 체인을 Core Image에서 기본 16비트 반정밀도 부동소수점 선형 정밀도(`RGBAh`)로 처리합니다. Windows에서는 Direct3D 11 컴퓨트 셰이더로 실행하되 GPU 경로가 막혀 있으면 CPU로 대체하며 양쪽 경로 모두 32비트 부동소수점(`RGBA32F`) 정밀도로 계산해 냅니다.

### 파일 위치

| | macOS | Windows |
|---|---|---|
| 앱 | `/Applications/negaflow.app` | `%LOCALAPPDATA%\Negaflow\App` |
| 카탈로그, 결함 사이드카, 레시피, 인화 템플릿 | `~/Library/Application Support/negaflow` | `%LOCALAPPDATA%\Negaflow` |
| 앱 환경설정 | `UserDefaults` (`~/Library/Preferences/com.songhabin.negaflow.plist`) | `%LOCALAPPDATA%\Negaflow` |

### 설치와 제거

macOS는 앱을 `/Applications`에 넣는 PKG로 배포하며 제거할 때는 앱을 휴지통으로 끌어다 놓습니다.

Windows 설치 프로그램은 `%LOCALAPPDATA%\Negaflow\App`에 파일을 풀고 서명 없는 로컬 앱 패키지 등록(`AllowDevelopmentWithoutDevLicense`)이 아직 허용되지 않은 환경에서만 한 번 관리자 확인을 요청합니다. 제거는 시작 메뉴의 `Uninstall negaflow`나 설정에서 실행하며 앱 폴더와 시작 메뉴 항목, 패키지 등록을 함께 지웁니다.

### 명령줄

GUI 릴리즈 설치 프로그램에는 CLI 바이너리가 빠져 있으며 명령줄 도구는 각 플랫폼의 소스 코드에서 빌드해야 얻을 수 있습니다.

macOS에서 `swift build`를 실행하면 스캐너 검색과 이미지 현상, GrainMend 작업, 벤치마크를 처리하는 `negaflow` 바이너리가 생성됩니다. 반면 Windows에서 CMake로 빌드하면 파일 한 개에 엔진 동작을 점검하는 진단 도구 `negaflow-cli.exe`가 만들어지며 이 도구는 하위 명령 대신 플래그를 받습니다.

### 서명

두 빌드 모두 유료 개발자 인증서로 서명하지 않아서 첫 실행 때 두 운영체제가 경고합니다. Mac 빌드는 ad hoc 서명이고 공증은 받지 않았으니 개인정보 보호 및 보안에서 '그래도 열기'로 허용하며 Windows 설치 프로그램은 서명이 없으니 SmartScreen에서 추가 정보를 누른 뒤 실행하세요.

## 스캐너

스캐너 플러그인은 별도 GPL 프로젝트 [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane)에서 두 운영체제를 모두 지원합니다. 별도 프로세스로 실행되어 JSON으로 통신하므로 negaflow에는 어느 플랫폼에도 SANE 코드가 없습니다.

Windows에서는 운영체제가 기본 제공하는 스캐너 드라이버 경로를 그대로 따르므로 한 PC에서 VueScan이나 SilverFast와 함께 설치해 두어도 충돌 없이 동작합니다.

## 동등성을 유지하는 방법

새 기능은 macOS에 먼저 구현한 뒤 실제 macOS 동작을 기준으로 삼아 Windows로 옮깁니다. 출력을 비교할 수 있는 구간에서는 macOS 기준 이미지로 Windows의 정답 여부를 판정하며 두 버전이 어긋나면 macOS를 정답으로 보고 Windows 쪽을 버그로 수정합니다.
