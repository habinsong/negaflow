# macOS 버전과 Windows 버전의 차이

[문서 홈](../README.md)

negaflow는 macOS용과 Windows용, 두 벌입니다. 두 버전은 소스 코드를 공유하지 않고, 각각 그 시스템의 방식대로 만들었습니다.

## 두 벌로 만든 이유

크로스플랫폼 코드베이스 하나는 툴킷 하나와 그 타협을 두 시스템에 모두 들이는 일입니다. 메뉴와 파일 대화상자가 어색하게 동작하고, 색이 변환 계층을 한 번 더 지나고, 창이 시스템과 어긋납니다. 각각 네이티브로 만들면 기능마다 두 번 만들고 두 번 시험하므로 일이 두 배쯤 듭니다. 대신 두 버전 모두 사용자가 그 시스템에서 기대하는 대로 동작합니다.

## 같은 것

그림입니다. 같은 스캔을 넣으면 두 버전에서 같은 결과가 나옵니다.

macOS 빌드는 `docs/verification/macos-golden`에 기준 이미지를 렌더링합니다. 이 폴더는 Git이 무시하므로 이미지는 렌더링한 컴퓨터에만 있습니다. Windows 엔진 테스트는 그 복사본을 읽어 픽셀 값을 비교하므로, Windows 엔진이 어긋나면 테스트가 실패합니다.

아래도 같습니다.

- 필름 베이스 측정과 반전
- 모든 현상 타깃: `MAIN`, `PRINT`, `HS`, `SP`, `F135`, `HR`, `EXPIRED`, `CS`
- 톤, 커브, HSL, 컬러 그레이딩, 흑백 토닝
- 적외선 경로를 포함한 GrainMend 검출과 복원
- 인화 레이아웃과 페이지 기하
- 내보내기 파일 이름, EXIF 기록, 메타데이터 정책
- 카탈로그 형식(`library.sqlite`)

## 다른 것

### 색 관리

macOS는 ColorSync, Windows는 ICM을 씁니다. 둘 다 같은 ICC 프로파일을 받아 반올림 범위 안에서 같은 수치를 냅니다. 조용히 어긋나기 가장 쉬운 부분이라 동등성 테스트가 다룹니다.

### 그래픽

macOS는 현상 체인을 Core Image에서 돌립니다. Windows는 Direct3D 컴퓨트 셰이더에서 돌리고, GPU 경로를 쓸 수 없으면 CPU로 대체합니다.

### 파일 위치

| | macOS | Windows |
|---|---|---|
| 앱 | `/Applications/negaflow.app` | `%LOCALAPPDATA%\Negaflow\App` |
| 라이브러리와 설정 | `~/Library/Application Support/negaflow` | `%LOCALAPPDATA%\Negaflow` |

### 설치와 제거

macOS는 앱을 `/Applications`에 넣는 PKG로 배포합니다. 제거하려면 앱을 휴지통으로 끌어다 놓습니다. Windows는 관리자 권한 없이 사용자 폴더에 쓰는 설치 파일로 배포합니다. 제거는 시작 메뉴의 `Uninstall negaflow`나 설정에서 하며, 앱 폴더, 시작 메뉴 항목, 패키지 등록이 함께 지워집니다.

### 명령줄

macOS에는 스캐너 검색, 파일 현상, GrainMend 실행, 벤치마크를 하는 완전한 CLI `negaflow`가 들어 있습니다. Windows의 `negaflow-cli.exe`는 파일 하나에 엔진이 무엇을 하는지 확인하는 작은 진단 도구이고, 하위 명령 대신 플래그를 받습니다.

### 서명

두 빌드 모두 유료 개발자 인증서로 서명하지 않아서 첫 실행 때 두 시스템이 경고합니다. Mac 빌드는 ad hoc 서명이고 공증은 받지 않았으니 개인정보 보호 및 보안에서 '그래도 열기'로 허용합니다. Windows 설치 파일은 서명이 없으니 SmartScreen에서 추가 정보를 누른 뒤 실행합니다.

## 스캐너

스캐너 플러그인은 별도 GPL 프로젝트 [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane)이며 두 시스템용이 모두 있습니다. 별도 프로세스로 돌고 JSON으로 통신하므로 negaflow에는 어느 플랫폼에도 SANE 코드가 없습니다. Windows에서는 Windows가 이미 제공하는 스캐너 드라이버 경로를 쓰므로 같은 PC에서 VueScan과 SilverFast도 계속 쓸 수 있습니다.

## 맞춰 두는 방법

기능은 macOS에 먼저 들어가고, 이어서 Windows에 실제 macOS 동작에 맞춰 들어갑니다. 출력을 잴 수 있는 곳은 macOS 기준 이미지가 Windows의 정답 여부를 가립니다. 두 버전이 어긋나면 정답은 macOS이고 Windows 쪽이 버그입니다.
