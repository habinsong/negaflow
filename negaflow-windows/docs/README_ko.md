<p align="center">
  <img src="../../negaflow-mac/Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for Windows</h1>

<p align="center">Windows 네이티브로 만든 negaflow입니다.</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.3-EF8B26" alt="버전 1.1.3\"></a>
  <a href="#"><img src="https://img.shields.io/badge/Windows-11%2024H2+-0078D4?logo=windows&logoColor=white" alt="Windows 11 24H2 이상"></a>
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
  <a href="../../negaflow-mac/docs/README_ko.md">macOS</a>
</p>

---

## 필요한 것

실행할 때:

- Windows 11 24H2 (빌드 26100) 이상, 64비트
- 35mm 작업은 메모리 8GB, 중형 필름을 다루면 16GB가 편합니다

빌드할 때:

- Visual Studio 2022, C++ 데스크톱 개발 워크로드 포함
- Windows 11 SDK (10.0.26100 이상)
- .NET 10 SDK
- CMake 3.28 이상
- 아이콘과 리소스 스크립트용 Python 3.11 이상

Arm64 기기에서도 동작합니다. 다만 Arm64 릴리즈는 x64만큼 확인하지 못했습니다.

## 설치

[Releases](https://github.com/habinsong/negaflow/releases)에서 `negaflow-1.1.3-win-x64.exe`를 내려받아 실행합니다.

관리자 권한은 필요 없습니다. 처음 실행할 때 SmartScreen이 한 번 경고하는데, 추가 정보를 누르고 실행하면 됩니다.

제거는 시작 메뉴의 `negaflow 제거`나 설정의 앱 목록에서 합니다. 라이브러리와 사진은 그대로 둡니다.

## 빌드

```powershell
git clone https://github.com/habinsong/negaflow.git
cd negaflow\negaflow-windows

# C++ 엔진 빌드
.\scripts\build.ps1 -Preset x64-release

# 앱 빌드 후 실행
.\scripts\run-app.ps1 -Architecture x64 -Configuration Release
```

`build.ps1`에는 `x64-debug`, `x64-release`, `arm64-debug`, `arm64-release`를 넘길 수 있습니다.

개발 중에 앱을 띄우는 방법은 `run-app.ps1` 하나뿐입니다. 앱이 MSIX 패키지로 빌드되기 때문에 빌드 폴더의 exe를 그냥 실행하면 뜨지 않습니다. 이 스크립트가 패키지를 만들고 현재 사용자에게 등록한 다음 앱 ID로 띄웁니다.

설치 프로그램을 만들 때:

```powershell
.\scripts\build-release.ps1 -Architecture x64
```

결과는 `out\release\win-x64`에 생깁니다.

## 점검

```powershell
# C++ 엔진 테스트
ctest --preset x64-release --output-on-failure

# 앱과 카탈로그 테스트
.\scripts\test-managed.ps1

# 엔진과 앱 경계 테스트
.\scripts\test-interop.ps1

# 위의 것을 한 번에
.\scripts\local-ci.ps1
```

엔진 테스트에는 골든 이미지 비교가 들어 있습니다. macOS 버전에서 뽑아 둔 기준 파일을 읽어서 Windows 엔진이 같은 화소를 내는지 확인합니다.

## 명령줄로 엔진 확인하기

`negaflow-cli.exe`는 엔진이 파일 하나를 어떻게 처리하는지 보는 도구입니다. 하위 명령 대신 플래그를 씁니다.

```powershell
$cli = "out\build\native\x64-release\Release\negaflow-cli.exe"

# 이 빌드가 뭔지 확인
& $cli --build-info

# 스캔 파일에 뭐가 들었는지 본다
& $cli --probe-tiff scan.tif

# 현상해서 16비트 TIFF로 저장
& $cli --export-developed-tiff16 scan.tif out.tif

# 현상 한 번에 시간이 어디서 드는지 확인
& $cli --develop-timing scan.tif

# 필름 베이스를 자동으로 찾아 무엇을 골랐는지 본다
& $cli --auto-base-probe scan.tif
```

인자 없이 실행하면 전체 목록이 나옵니다.

## 스캐너

플러그인을 설치하기 전까지 스캐너 조작은 나타나지 않습니다. SANE 장치는 [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane)이 담당하며 따로 설치해야 합니다.

플러그인은 Windows가 이미 제공하는 드라이버 경로로 스캐너와 통신합니다. 그래서 같은 컴퓨터에서 VueScan이나 SilverFast를 계속 쓸 수 있습니다.

## 문제가 생겼을 때

앱은 `%LOCALAPPDATA%\Negaflow\Logs`에 텍스트 기록을 남깁니다.

| 파일 | 남기는 내용 |
|---|---|
| `export-trace.txt` | 내보내기와 빠른 내보내기, 실패한 경우 포함 |
| `termination.txt` | 앱을 닫는 동안 있었던 일 |
| `settings-change.txt` | 바뀐 설정과 바꾼 주체 |

이 셋은 항상 켜져 있습니다. 특정 문제를 파고들 때만 켜는 기록이 둘 더 있습니다.

- `preview-trace.txt`. 같은 폴더에 `preview-trace.on`이라는 빈 파일을 만들면 켜집니다.
- `stage-trace.txt`. 앱을 띄우기 전에 환경 변수 `NEGAFLOW_STAGE_TRACE=1`을 두면 켜집니다. 현상 과정의 단계마다 화소 통계를 남깁니다.

## 폴더 구성

```
negaflow-windows/
├── src/
│   ├── Native/        크로마 엔진, GrainMend, 디코딩과 내보내기 (C++)
│   ├── Interop/       엔진과 앱을 잇는 층 (C#)
│   ├── Catalog.Core/  라이브러리 저장소 (C#)
│   ├── Shell.Core/    현상, 인화, 내보내기 로직 (C#)
│   ├── Shell/         라이브러리, 현상, 인화 화면 (WinUI 3)
│   └── Cli/           엔진 점검 도구 (C++)
├── scripts/           빌드, 테스트, 패키징 스크립트
├── tests/             엔진, 앱, 경계 테스트
└── Installer/windows/ NSIS 설치 프로그램
```

## 관련 문서

- [macOS와 Windows의 차이](../../docs/ko/platform/PLATFORM_DIFFERENCES.md)
- [크로마 엔진](../../docs/ko/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/ko/product/GRAINMEND.md)
- [제품 구조](../../docs/ko/architecture/PRODUCT_ARCHITECTURE.md)
