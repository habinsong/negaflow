# macOS 버전과 Windows 버전의 차이

[문서 홈](../README.md)

negaflow는 macOS용과 Windows용이 따로 있습니다. 두 앱은 소스 코드를 공유하지 않고, 각각 그 운영체제에서 쓰는 방식으로 만들었습니다.

이 문서는 그래서 실제로 무엇이 같고, 무엇이 달라 보이고, 한쪽에만 있는 것이 무엇인지 적었습니다.

## 따로 만든 이유

하나의 코드로 양쪽을 만들려면 툴킷 하나를 고르고 두 시스템 모두에서 그 결과를 감수해야 합니다. 메뉴가 엉뚱한 자리에 붙고, 파일 대화상자가 어색하게 동작하고, 색이 변환 층을 한 번 더 거치고, 창이 끝내 그 운영체제의 앱처럼 느껴지지 않습니다.

플랫폼마다 그 방식대로 만들면 일이 대략 두 배가 됩니다. 기능 하나를 넣을 때마다 두 번 만들고 두 번 확인해야 합니다. 대신 두 버전 모두 사용자가 쓰던 시스템에서 기대하는 대로 동작합니다.

## 같은 것

결과물입니다. 같은 스캔을 넣으면 같은 사진이 나옵니다.

말로만 그런 것이 아닙니다. macOS 빌드가 만든 기준 이미지가 저장소의 `docs/verification/macos-golden`에 들어 있습니다. Windows 엔진 테스트가 이 파일들을 읽어 화소 값을 비교합니다. Windows 엔진을 고치다가 macOS 결과에서 벗어나면 테스트가 실패합니다.

다음도 같습니다.

- 필름 베이스 측정과 반전
- 모든 현상 타깃: `MAIN`, `PRINT`, `HS`, `SP`, `F135`, `HR`, `EXPIRED`
- 톤, 커브, HSL, 컬러 그레이딩, 흑백 토닝
- GrainMend 검출과 복원, 적외선 경로 포함
- 인화 레이아웃과 페이지 배치
- 내보낸 파일 이름, EXIF 기록, 메타데이터 정책
- 카탈로그 형식. 한쪽에서 만든 라이브러리를 다른 쪽에서 읽을 수 있습니다

## 다른 것

### 색 관리

macOS는 ColorSync, Windows는 ICM을 씁니다. 둘 다 같은 ICC 프로파일을 받아 반올림 범위 안에서 같은 값을 냅니다. 조용히 어긋나기 쉬운 부분이라 기준 이미지 비교가 이 부분을 확인합니다.

### 그래픽

macOS는 현상 과정을 Core Image에서 돌립니다. Windows는 Direct3D 컴퓨트 셰이더로 처리하고, GPU를 쓸 수 없는 기기에서는 CPU로 넘어갑니다.

속도는 플랫폼보다 기기에 달렸습니다. Apple Silicon 맥이든 외장 GPU를 단 PC든 35mm 스캔 한 장은 기다릴 일 없이 처리합니다.

### 파일 위치

| | macOS | Windows |
|---|---|---|
| 앱 | `/Applications/negaflow.app` | `%LOCALAPPDATA%\Negaflow\App` |
| 라이브러리와 설정 | `~/Library/Application Support/negaflow` | `%LOCALAPPDATA%\Negaflow` |
| 기록 | 콘솔과 앱 지원 폴더 | `%LOCALAPPDATA%\Negaflow\Logs` |

### 설치와 제거

macOS는 PKG로 앱을 `/Applications`에 넣습니다. 지울 때는 다른 맥 앱과 마찬가지로 앱을 휴지통에 넣으면 됩니다.

Windows는 관리자 권한 없이 사용자 폴더에 설치합니다. 제거는 시작 메뉴의 `negaflow 제거`나 설정에서 하고, 앱 폴더와 시작 메뉴 항목, 패키지 등록을 함께 지웁니다.

### 명령줄

macOS에는 `negaflow`라는 CLI가 있습니다. 스캐너를 찾고, 파일을 현상하고, GrainMend를 돌리고, 성능을 재는 일까지 합니다. 실제로 쓰라고 만든 도구입니다.

Windows에는 `negaflow-cli.exe`가 있습니다. 파일 하나를 엔진이 어떻게 처리하는지 보는 작은 도구입니다. 하위 명령 대신 플래그를 쓰고, 평소 작업이 아니라 진단을 위한 것입니다.

### 서명

양쪽 다 유료 개발자 인증서로 서명하지 않아서 첫 실행 때 경고가 나옵니다. macOS는 개인정보 보호 및 보안에서 '그래도 열기'를, Windows는 SmartScreen에서 추가 정보를 누른 뒤 실행을 선택하면 됩니다.

## 스캐너

스캐너 플러그인은 별도 GPL 프로젝트인 [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane)이고, 이것도 양쪽 모두 있습니다. 플러그인은 별도 프로세스로 실행되고 JSON으로 주고받기 때문에, negaflow 본체에는 어느 플랫폼에서도 SANE 코드가 들어가지 않습니다.

Windows에서는 플러그인이 Windows가 이미 제공하는 스캐너 드라이버 경로를 씁니다. 아무것도 바꾸지 않아서 같은 컴퓨터에서 VueScan과 SilverFast를 계속 쓸 수 있습니다.

## 두 버전을 맞추는 방법

기능은 macOS에 먼저 들어가고, Windows는 문서로 적은 규격이 아니라 macOS의 실제 동작을 보고 만듭니다. 출력을 잴 수 있는 부분은 macOS 기준 이미지가 Windows 쪽이 맞는지 판정합니다.

둘이 다르면 macOS가 정답이고 Windows가 버그입니다.
