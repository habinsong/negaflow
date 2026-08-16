# Windows 빌드와 설치 파일

기준일: 2026-08-16
상태: x64 로컬 CI에서 native/managed gate, setup 설치, unsigned loose-package identity, 실제 창 생성, 제거 통과. GitHub 실행 결과와 실제 하드웨어·UI parity 검증은 별도입니다.

## 1. 일반 사용자 설치

Negaflow 본체와 GPL SANE 스캐너 플러그인은 **서로 다른 설치 파일**입니다.
본체는 Apache-2.0 payload만 담고, 스캐너 드라이버·SANE 런타임·GPL 소스는
`negaflow-scanner-sane` 설치 파일에만 들어갑니다.

```text
Negaflow-<version>-x64-setup.exe
negaflow-scanner-sane-<version>-x64-setup.exe
```

둘 다 관리자 권한 없이 현재 사용자에게 설치합니다.

```text
%LOCALAPPDATA%\Negaflow\App\                 Negaflow 본체
%LOCALAPPDATA%\Negaflow\Plugins\sane\        별도 GPL SANE 플러그인
```

본체 설치 파일은 self-contained입니다. 따라서 최종 사용자가 Visual Studio, .NET SDK,
Windows App Runtime 또는 vcpkg를 따로 설치할 필요가 없습니다. 현재 앱의 최소 대상은
Windows 11 24H2 (build 26100) x64입니다. ARM64 설치 파일은 교차 빌드할 수 있지만,
실제 ARM64 Windows에서의 설치·실행은 아직 검증 증거가 없으므로 배포하지 않습니다.
현재 설치기는 이 최소 OS build를 별도로 판정하지 않고 앱의 manifest/Windows loader에
맡깁니다. 지원되지 않는 OS에 설치가 성공했다는 뜻은 아닙니다.

SANE 설치 파일은 플러그인, `scanimage.exe`, 필요한 SANE DLL, GPL 고지와 대응 소스를
한 번에 넣습니다. 설치 후 Negaflow를 다시 열면 **이미 승인된** SANE 플러그인에서 연결된
스캐너를 자동 탐색하고 Scanner Import 절을 엽니다. 처음 설치한 플러그인은 신뢰 경계상
실행하지 않고 승인 절만 열며, 한 번 승인한 뒤부터 자동 탐색합니다.

일부 스캐너는 Windows에 맞는 제조사/usbscan 드라이버 바인딩이 먼저 필요합니다. 이 단계는
SANE 플러그인 설치와 별개이며, 현재 서명된 INF가 없는 장치에서는 관리자 권한과 드라이버
설치가 필요할 수 있습니다. 이 제약은 SANE 저장소의 하드웨어 문서에서 관리합니다.

두 설치 파일 모두 현재 서명하지 않았습니다. SmartScreen 경고는 알려진 배포 제약이며
ADR-0027의 결정 범위입니다.

무인 설치와 제거는 NSIS 표준 형식입니다.

```powershell
.\Negaflow-<version>-x64-setup.exe /S
.\negaflow-scanner-sane-<version>-x64-setup.exe /S
```

설치 위치를 바꿀 때는 `/D=<절대경로>`를 마지막 인자로 둡니다. 제거는 Windows
"설치된 앱" 또는 각 설치 폴더의 `uninstall.exe /S`를 사용합니다. 본체를 제거해도
`Plugins\sane`은 지우지 않고, SANE 플러그인을 제거해도 본체는 지우지 않습니다.

## 2. 본체 개발 빌드와 실행

개발 빌드에는 Visual Studio 2026의 C++/C#/Windows App SDK 워크로드, Windows SDK,
.NET 10 SDK가 필요합니다. 재현 가능한 개발 환경은 `configuration.dsc.yaml`과
`.vsconfig`가 소유합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-app.ps1 -Build
```

기존 산출물을 실행만 할 때는 `-Build`를 뺍니다. x64와 ARM64 출력은 섞지 않습니다.

## 3. 본체 설치 파일 만들기

macOS의 `negaflow-mac/scripts/ci-gate.sh`와 같은 로컬 단일 진입점은 다음 명령입니다.
이 명령은 x64 Release native/managed gate, 최신 setup 생성, 임시 설치, package identity,
실제 창 생성, 제거를 순서대로 실행하고 `out\logs\local-ci-*.log`에 전체 로그를 남깁니다.
릴리스 QA에는 개별 명령이 아니라 이 게이트를 통과한 산출물만 사용합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\local-ci.ps1
```

설치 파일 컴파일에는 NSIS 3이 한 번 필요합니다.

```powershell
winget install --id NSIS.NSIS --exact
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-release.ps1 -Architecture x64
```

스크립트는 다음 순서로 실행합니다.

1. CMake x64 Release native DLL을 빌드합니다.
2. WinUI 셸을 self-contained로 publish하고 LICENSE/NOTICE/third-party notice를 넣습니다.
3. NSIS user-scope 설치 파일과 SHA-256 파일을 `out\release\win-x64\`에 만듭니다.

같은 버전의 설치 파일을 다시 만들려면 실수로 기존 artifact를 덮지 않도록
`-Overwrite`를 명시해야 합니다. 생성 직후에는 다음 smoke를 실행합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-installer.ps1 `
  -InstallerPath .\out\release\win-x64\Negaflow-<version>-x64-setup.exe
```

이 smoke는 임시 사용자 경로로 무인 설치한 뒤 `Negaflow.Shell.exe`, native DLL,
uninstaller를 확인하고 무인 제거까지 수행합니다. GUI 실행이나 실제 스캐너 탐색을
성공으로 주장하지는 않습니다.

## 4. 지속 점검과 GitHub Release

`.github/workflows/windows.yml`의 `installer-smoke` job은 x64 native/managed check 뒤에
같은 self-contained publish, NSIS 컴파일, 무인 설치·제거 smoke를 실행하고 설치 파일과
SHA-256을 artifact로 올립니다. GitHub Release에는 이 job의 검증이 끝난 x64 setup.exe와
동일 이름의 `.sha256`만 올립니다.

Release를 올리기 전에 별도 SANE 저장소에서 그 버전에 맞는
`negaflow-scanner-sane-<version>-x64-setup.exe`와 `.sha256`을 생성해 함께 첨부합니다.
두 프로젝트는 라이선스 경계 때문에 하나의 설치 파일이나 하나의 release payload로 합치지
않습니다.

## 5. 검증 경계

- x64 installer smoke는 파일 배치·설치·제거만 확인합니다.
- actual scanner detect/scan은 SANE 설치본과 실제 하드웨어/드라이버가 있어야 합니다.
- ARM64 cross-build는 ARM64 기기 설치·실행 증거가 아닙니다.
- macOS golden·UI/이미지 parity는 이 Windows 설치 검증으로 대체되지 않습니다.

## 6. 2026-08-16 로컬 검증

- `scripts/build-release.ps1 -Architecture x64`로 본체 설치 파일을 생성했습니다.
- `scripts/verify-installer.ps1`가 무인 설치·`Negaflow.Shell.exe`·native DLL·self-contained
  .NET runtime(`hostfxr.dll`, `coreclr.dll`)·`Microsoft.WindowsAppRuntime.dll`·무인 제거를 확인했습니다.
- `scripts/ci-gate.ps1 -Preset x64-release -IncludeArm64Cross`는 x64 CTest 71/71,
  관리 단위 assertion 1,626개, ARM64 네이티브·관리 교차 빌드까지 통과했습니다. ARM64는 실행하지 않았습니다.

## 7. 2026-08-17 로컬 CI 검증

- `scripts/local-ci.ps1`에서 native CTest 71/71, catalog 721 assertions, shell 905 assertions,
  setup 생성·임시 설치·package identity 등록·실제 창 생성·제거를 통과했습니다.
- 로그: `out\logs\local-ci-20260817-000901.log`
- 설치 파일 SHA-256: `d43909ab55f3c16164e5e3445f19d318bf782d52180e89f0bcfc97b228d97f6d`
- unsigned loose-package 등록이므로 Windows Developer Mode가 등록을 허용해야 합니다. 이는 코드 서명된
  MSIX 검증이 아니며 macOS UI/UX·이미지 품질 parity 또는 실제 스캐너 검증을 대체하지 않습니다.
