# Windows release QA checkpoint — 2026-08-16

## 목표

Windows Negaflow 본체와 `negaflow-scanner-sane` 설치본을 실제 연결 장비(EPSON GT-X900/V700, Plustek OpticFilm 8100)와 앱 UI에서 검증한다. 이 문서는 이 작업의 체크포인트만 기록한다.

## 이번 체크포인트에서 확인한 완료 항목

| 항목 | 증거 | 결과 |
| --- | --- | --- |
| MSIX 느슨한 실행 레이아웃의 native ABI 엔진 | `dotnet build src/Shell/Negaflow.Shell.csproj -c Release -p:Platform=x64` 뒤 `AppX/Negaflow.Native.dll` 존재 및 원본 SHA-256 일치 | 통과 |
| ABI 로드가 된 앱 UI | `dotnet run --project src/Shell/Negaflow.Shell.csproj -c Release -p:Platform=x64` 후 실제 앱의 현상 캔버스, 히스토그램, 필름스트립 표시 | 통과 |
| 새 SANE 페이로드의 장치 탐색 | 페이로드 `negaflow-scanner-sane.exe detect` | GT-X900와 OpticFilm 8100 둘 다 탐지 |
| 새 SANE 설치본의 장치 탐색 | `%LOCALAPPDATA%\Negaflow\Plugins\sane\negaflow-scanner-sane.exe detect` | GT-X900와 OpticFilm 8100 둘 다 탐지 |

## 재현된 문제와 수정 내용

1. 패키지 실행 레이아웃에는 `Negaflow.Native.dll`이 없었고 앱은 `LoadFailed`를 표시했다.
   - 원인: native DLL을 일반 Build/Publish 출력에만 복사해 MSIX `AppX` 느슨한 레이아웃에 넣지 않았다.
   - 수정: Shell 프로젝트에서 native DLL을 `Content`로 선언하고 Build 뒤 `AppX` 레이아웃에도 복사한다.

2. SANE 설치본은 V700만 탐지했고 8100 `genesys` 백엔드를 열지 못했다.
   - 원인 A: 번들 SANE 동적 로더가 개발 PC의 절대 backend 경로를 사용했다.
   - 원인 B: installer payload 조립 시 `genesys` 전이 DLL 일부가 누락됐다.
   - 수정: 번들 backend 경로 환경 변수 지원을 SANE runtime에 추가했고, payload 조립 전에 UCRT64 `bin`을 PATH 앞에 넣어 `ldd`가 모든 전이 DLL을 수집하게 했다.

## 아직 미완료 또는 재검증이 필요한 항목

| 항목 | 현재 상태 | 다음 확인 |
| --- | --- | --- |
| 앱 UI의 8100 표시 | 앱은 설치 교체 전 플러그인 세션을 아직 들고 있다 | 앱 재시작 또는 플러그인 재승인 뒤 두 장비 표시 확인 |
| DPI, bit-depth, preview UI | 기존 V700 세션에서는 capabilities가 비어 잠겨 있다 | 새 설치본에서 각 장비의 `capabilities`와 UI 컨트롤을 확인 |
| 실제 최종 설치 플러그인 스캔 | 이전 번들/외부 런타임에서는 수행했으나 새 설치본은 아직 미수행 | V700와 8100 각각 프리뷰 및 실제 스캔 수행·TIFF 검증 |
| 라이브러리에서 가져온 사진의 현상 전달 | ABI 복구 뒤 기존 라이브러리 항목은 현상 화면에 표시됐다 | 15개 입력 이미지의 신규 가져오기·선택·현상 전환 확인 |
| 현상 화면의 스캐너 진입 위치 | 사용자가 좌측 탭에도 표시되어야 한다고 보고했다 | macOS 정본 화면·동작과 대조 후 같은 위치/전환으로 구현 또는 의도된 경계 기록 |
| 본체 최종 설치본 | 기존 NSIS unpackaged 실행본은 Windows App SDK XAML 초기화에서 종료되는 문제가 남아 있다 | MSIX 패키지 생성·서명 경로와 설치 후 기동을 별도 게이트로 검증 |
| 빠른 로컬 릴리스 게이트 | 아직 없음 | 패키지 ABI, 플러그인 manifest/payload, 장비 탐색 및 capabilities를 기본 1~3분 게이트로 추가 |

## 금지된 완료 주장

- 최종 설치 플러그인에서 두 장비를 실제로 스캔하기 전에는 최종 스캔 성공으로 기록하지 않는다.
- 코드 서명된 배포 MSIX를 설치해 보지 전에는 본체 설치본 준비 완료로 기록하지 않는다.
- Windows 앱 렌더링만으로 macOS UI/UX 동등성을 주장하지 않는다.
