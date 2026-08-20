# Windows 개발 환경 기준선

기준일: 2026-08-04  
상태: 설계 기준. 아직 Windows 머신에서 설치·빌드 검증하지 않음.

이 문서는 개발자 PC와 CI가 “각자 최신”을 설치해 우연히 다른 결과를 내지 않도록 도구의 역할,
핀 위치, 확인 명령과 업데이트 절차를 정의한다. 실제 Windows 저장소가 생기면 정확한 버전은
`global.json`, NuGet lock, vcpkg baseline, `CMakePresets.json`, CI image manifest가 소유한다.

## 1. 2026-08-04 권장 기준선

| 층 | 기준 | 핀 위치 | 비고 |
|---|---|---|---|
| 개발 OS | Windows 11 24H2 API 하한 image + 지원 중인 release | CI image ID와 문서 | API 하한과 고객 지원 OS를 분리 |
| IDE/MSBuild | Visual Studio 2026 안정 채널 | `.vsconfig` + CI image | Preview 채널 금지 |
| .NET SDK | .NET 10 LTS 최신 patch | `global.json` | 2026-08-04 공식 최신은 10.0.10 |
| Windows App SDK | 2.3.1 stable | 중앙 NuGet 버전 + lock | 2026-07-16 출시. 빌드 전 release channel 재확인 |
| C# TFM | `net10.0-windows10.0.26100.0` | Shell `.csproj` | 제품 최소 API surface 후보 |
| Windows SDK | 10.0.28000.2526 계열 | `.vsconfig`/CI image | 2026-07 공식 release-notes 상단 build. 새 API는 승인된 최소 OS runtime guard 필요 |
| C++ 표준 | C++20 | top-level CMake | MSVC conforming mode와 warnings 고정 |
| CMake | VS가 지원하는 검증 버전 | `CMakePresets.json` 최소 버전 | 시스템 전역 상태에 의존 금지 |
| Ninja | VS 또는 pinned tool cache | CI image | 네이티브 단독 빌드 기본 generator 후보 |
| vcpkg | 특정 commit | submodule 또는 bootstrap manifest | classic 전역 패키지 금지 |
| HLSL | Windows SDK의 FXC | SDK version | v1 D3D11/D2D DXBC 오프라인 빌드 |
| 패키지 | WiX Toolset 안정 버전 | dotnet tool manifest/lock | 배포 채널 결정 뒤 확정 |

위 숫자는 “영원한 권장 버전”이 아니다. 특히 Windows App SDK는 최신 patch를 사용해야 지원되는
정책이므로 월별 유지보수 창에서 갱신한다. 새 major/minor로 자동 부동시키지는 않는다.
24H2 Home/Pro가 2026-10-13 지원 종료이므로 개발 image 하나만으로 Stable 지원을 주장하지 않는다.

## 2. Visual Studio 구성 요소

공식 WinUI 환경 구성 파일을 설치 출발점으로 사용하되, 팀 저장소에는 실제로 설치한 component
목록을 `.vsconfig`로 고정한다. 필요한 범주는 다음과 같다.

### 필수 workload와 구성 요소

- WinUI 3 / Windows App SDK 애플리케이션 개발 workload
- .NET 데스크톱 개발과 .NET 10 SDK
- C++ 데스크톱 개발
- MSVC x64/x86 build tools
- MSVC ARM64 build tools
- CMake tools for Windows
- Windows 11 SDK 10.0.28000 계열
- MSBuild, NuGet, Git
- Windows App SDK C# project templates

`x86` build tools는 앱 본체 때문이 아니라 32비트 TWAIN 플러그인과 호스트 시험용이다. 앱과
엔진 산출물은 `x64`, `ARM64`만 만든다.

### 별도 설치 또는 Windows 기능

- Developer Mode: 개발 중 unpackaged/packaged launch와 디버깅에 필요
- Graphics Tools optional feature: D3D debug layer와 그래픽 진단
- PIX on Windows: GPU 캡처·타이밍. 릴리스 앱 의존성 아님
- Windows Performance Recorder/Analyzer: ETW CPU·IO·메모리 추적
- WinDbg: native crash dump, device-removed 이후 프로세스 분석
- Accessibility Insights for Windows: UI Automation·키보드·색 대비 검사
- Windows App Certification Kit: 배포 형태가 확정된 뒤 실행

### 설치 방식

Microsoft의 현재 WinUI quick start는 다음 구성을 권장한다.

```powershell
winget configure -f https://aka.ms/winui-config
```

이 명령은 새 개발 장비의 초기화에는 유용하지만 재현성의 최종 근거가 아니다. 실행 후 Visual
Studio Installer에서 내보낸 `.vsconfig`와 아래 진단 결과를 CI artifact로 보관한다.

## 3. 환경 진단 체크리스트

실제 저장소를 clone한 직후, 빌드보다 먼저 다음을 확인한다.

```powershell
dotnet --info
dotnet --list-sdks
cmake --version
ninja --version
git --version
where.exe msbuild
where.exe cl
where.exe fxc
```

Developer Command Prompt에서 아키텍처별 컴파일러 환경을 분리해 확인한다.

```powershell
cl /Bv
cmake --list-presets
dotnet workload list
```

GPU 진단은 프로그램이 선택한 실제 어댑터의 다음 값을 로그로 남겨야 한다.

- DXGI adapter description, LUID, vendor/device/subsystem/revision ID
- dedicated/shared memory와 현재 budget/usage
- D3D feature level, shader model, required format support
- driver version
- WARP 여부
- Windows build와 graphics preference

`dxdiag` 출력만으로 앱 경로를 검증하지 않는다. 앱이 생성한 장치와 포맷 capability가 근거다.

## 4. 버전 핀 설계

### .NET

`global.json`은 major만 고정하지 않고 팀이 검증한 feature band를 고정한다. 보안 patch를 받을
수 있도록 `rollForward` 정책은 의도적으로 선택하고 CI에서 실제 resolved SDK를 기록한다.

예시 정책:

```json
{
  "sdk": {
    "version": "10.0.100",
    "rollForward": "latestPatch",
    "allowPrerelease": false
  }
}
```

위 값은 구조 예시다. 저장소 생성 시 설치 가능한 검증 버전으로 교체해야 한다. `allowPrerelease`
는 항상 `false`다.

### NuGet

- `Directory.Packages.props`에서 버전을 중앙 관리한다.
- `packages.lock.json`을 커밋하고 CI restore는 locked mode로 실행한다.
- `Microsoft.WindowsAppSDK`는 stable patch를 정확히 고정한다.
- 개발자별 NuGet source를 암묵적으로 사용하지 않는다. 공개 feed와 사내 feed를 명시한다.
- native runtime asset이 x64/ARM64 모두 있는지 restore 단계에서 확인한다.

### vcpkg

- manifest mode만 사용한다.
- `builtin-baseline`을 commit SHA로 고정한다.
- x64와 ARM64 triplet을 같은 baseline에서 구성한다.
- 사내 overlay port를 만들면 patch와 upstream provenance를 함께 보관한다.
- `vcpkg integrate install`이나 개발자 전역 classic package를 빌드 근거로 쓰지 않는다.

### Windows SDK와 Visual Studio

- CI image tag 하나만 신뢰하지 않고 `cl /Bv`, SDK 디렉토리 version, MSBuild version을 artifact로 남긴다.
- Visual Studio minor update는 PR 하나로 올리고 x64/ARM64 full gate를 통과시킨다.
- IDE 자동 업데이트가 로컬 빌드만 앞서가도 release artifact는 pinned CI에서만 만든다.

## 5. 권장 작업 디렉토리와 경로 규칙

- 짧은 ASCII 경로에서도, 공백·비ASCII·긴 경로에서도 최소 한 번 빌드한다.
- 소스 경로를 바이너리에 절대경로로 심지 않는다.
- build tree는 source tree 밖 또는 `out/<preset>` 아래에 둔다.
- generated HLSL, WinUI XAML, projection, localization output을 소스 디렉토리에 쓰지 않는다.
- NuGet·vcpkg·CMake cache는 공유할 수 있어도 artifact는 preset/architecture별로 격리한다.
- Windows long paths를 켜더라도 installer와 플러그인 경로는 보수적으로 짧게 유지한다.

권장 구조 예:

```text
repo/
  src/
  tests/
  assets/
  cmake/
  packaging/
  out/
    build/x64-debug/
    build/x64-release/
    build/arm64-release/
    publish/x64/
    publish/arm64/
```

## 6. 빌드 프리셋

최소 프리셋은 다음을 포함한다.

| 프리셋 | 호스트 | 산출물 | 용도 |
|---|---|---|---|
| `x64-debug` | x64 | C++ engine/CLI/tests | ASan 가능 영역, 빠른 반복 |
| `x64-release` | x64 | 최적화된 전체 native | 성능·배포 입력 |
| `arm64-release` | x64 cross 또는 ARM64 | ARM64 native | 첫 단계부터 CI 필수 |
| `x64-warp-test` | x64 | 동일 셰이더 | vendor-independent 그래픽 gate |
| `x86-scanner-plugin` | x64 | plugin host만 | 32-bit TWAIN 후보 |

ARM64 결과를 cross-compile만 하고 성공으로 보지 않는다. ARM64 머신에서 실행하는 테스트 lane이
반드시 필요하다.

## 7. Debug·Release·검증 빌드의 차이

| 구성 | 목적 | 켜는 것 | 금지 |
|---|---|---|---|
| Debug | 기능 반복 | D3D debug, iterator checks, 상세 로그 | 성능 수치 보고 |
| RelWithDebInfo | 프로파일 | 최적화 + symbols + ETW/PIX markers | PGO 없는 결과를 최종 기준으로 오인 |
| Release | 배포 후보 | 최적화, deterministic build 옵션, 서명 전 artifact | debug layer·runtime shader compile |
| Sanitizer lane | C++ 메모리 안전 | 지원되는 ASan/UB checks | GPU/WinUI 전체 호환을 가정 |

부동소수 옵션은 성능 때문에 임의로 fast-math로 올리지 않는다. 색·톤·통계 kernel별 수치 계약을
만족하는 경우에만 좁은 translation unit 또는 셰이더 permutation에서 허용한다.

## 8. 셰이더 도구

v1의 D3D11/Direct2D 기준선은 DXBC와 Shader Model 5.0이다.

- HLSL은 빌드 시 오프라인 컴파일한다.
- `.hlsli` include dependency를 build graph에 명시한다.
- entry point, target profile, compile flags와 source hash를 manifest에 기록한다.
- Debug는 `/Zi`, Release는 최적화 수준을 명시하고 warnings를 오류로 취급한다.
- 셰이더 blob은 architecture-independent지만 host binary와 같은 release manifest로 묶는다.
- 런타임 HLSL 컴파일러 DLL을 배포하지 않는다.

FXC는 장기적으로 새 Shader Model 기능을 위한 도구가 아니지만, Direct2D custom effect와
D3D11 SM5/DXBC라는 v1 계약에는 맞는다. D3D12/SM6 후보가 채택될 때만 DXC 산출물을 별도
backend 자산으로 추가한다.

## 9. 로컬 개발 데이터

- 실제 사용자 catalog나 원본을 테스트에 사용하지 않는다.
- synthetic fixture, 공개 라이선스 corpus, 사용 승인을 받은 private QA corpus를 분리한다.
- private corpus는 저장소·로그·crash dump에 포함하지 않는다.
- ICC profile과 scanner profile은 출처·라이선스·hash·버전을 기록한다.
- 대형 fixture는 content-addressed cache로 받되 hash 검증 후 사용한다.

## 10. 업데이트 절차

툴체인 업데이트는 다음 순서로 한 묶음씩 수행한다.

1. 공식 support/release note와 보안 공지를 확인한다.
2. 버전 하나만 올린 별도 변경을 만든다.
3. x64·ARM64 restore/build/test와 WARP golden을 실행한다.
4. 실제 Intel·AMD·NVIDIA·Qualcomm matrix의 smoke를 실행한다.
5. install/update/uninstall/rollback을 확인한다.
6. 성능 기준선과 binary size 변화를 비교한다.
7. resolved-version artifact와 이 문서의 기준일을 갱신한다.

Windows App SDK servicing patch도 회귀 가능성이 없다고 가정하지 않는다. self-contained 배포는
앱이 런타임 업데이트를 책임지므로 보안 patch를 릴리스 cadence에 포함한다.

## 11. 첫 Windows 머신에서 아직 검증해야 할 항목

- Visual Studio 2026 공식 workload가 C# WinUI, C++ ARM64, FXC를 한 번에 설치하는지
- Windows SDK 10.0.28000으로 26100 minimum API surface를 경고 없이 유지하는지
- Windows App SDK 2.3.1 unpackaged self-contained C# 앱의 publish layout
- C# WinUI 3 + native CMake를 한 solution에서 build할 때 configuration mapping
- vcpkg의 `tiff`, `lcms`, `sqlite3`, 선택 후보 라이브러리의 x64/ARM64 빌드
- WARP에서 사용할 texture format과 D2D custom effect registration
- ARM64 머신에서 전체 test discovery와 native DLL probing
- 설치되지 않은 런타임·잘못된 architecture DLL·손상된 shader asset의 오류 UX

## 공식 근거

- [Quick start: Create your first WinUI 3 app](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/set-up-your-development-environment)
- [Windows App SDK release channels](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-channels)
- [.NET support policy](https://dotnet.microsoft.com/en-us/platform/support/policy)
- [Windows SDK release notes](https://learn.microsoft.com/en-us/windows/apps/windows-sdk/release-notes)
- [Windows versions and SDK overview](https://learn.microsoft.com/en-us/windows/apps/get-started/versioning-overview)
- [vcpkg manifest mode](https://learn.microsoft.com/en-us/vcpkg/consume/manifest-mode)
- [Use FXC to compile shaders](https://learn.microsoft.com/en-us/windows/win32/direct3dtools/dx-graphics-tools-fxc-using)
