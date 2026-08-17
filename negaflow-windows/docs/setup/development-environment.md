# 개발 환경과 설치 상태

기준일: 2026-08-04
호스트: Windows x64, OS build 26200, Developer Mode 활성화

## 확인된 도구

| 항목 | 확인 값 | 상태 |
|---|---|---|
| Visual Studio | Community 2026 `18.8.12023.21` / product 18.8.2 | complete, launchable, reboot 불필요 |
| MSBuild | `18.8.2+ce25c0108` | x64/ARM64 재빌드 확인 |
| MSVC | tools `14.51.36231`, compiler `19.51.36252.0` | x64/ARM64 compiler 확인 |
| Windows SDK | `10.0.26100.0` | 확인 |
| .NET SDK/runtime | `10.0.302` / `10.0.10` | 확인 |
| CMake | `4.3.2` | 확인 |
| vcpkg tool | `2025-09-03-4580816534ed8fd9634ac83d46471440edd82dfe` | 확인 |
| vcpkg registry baseline | `146c83e9ff6e645136bc35ea910f6b0961e26465` | manifest 고정 |
| Developer Mode | registry 값 `1` | 활성화 |

## Visual Studio component 상태

확인됨:

- `Microsoft.VisualStudio.Component.VC.Tools.x86.x64`
- `Microsoft.VisualStudio.Component.VC.Tools.ARM64`
- `Microsoft.VisualStudio.Component.Windows11SDK.26100`
- `Microsoft.VisualStudio.ComponentGroup.WindowsAppDevelopment.VC`
- `Microsoft.VisualStudio.Workload.Universal`
- `Microsoft.VisualStudio.Workload.ManagedDesktop`
- `Microsoft.NetCore.Component.SDK`
- `Microsoft.VisualStudio.Component.WindowsAppSdkSupport.CSharp`

Visual Studio 본체는 2026-08-04에 18.0.2에서 18.8.2로 업데이트했습니다. 업데이트 직후 instance는
`isComplete=true`, `isLaunchable=true`, `isRebootRequired=false`였습니다. 업데이트가 기존 MSVC
`14.50.35717`을 제거했기 때문에 네 개 CMake preset을 `--fresh`로 재구성했고, 새 14.51 도구셋으로
x64 테스트와 ARM64 교차 빌드를 다시 통과시켰습니다.

같은 업데이트에서 기존 .NET SDK `10.0.100`이 제거되고 Visual Studio 18.8 지원 SDK `10.0.302`와
runtime `10.0.10`이 설치됐습니다. 공식 .NET 10.0.10 릴리스와 로컬 설치를 대조한 뒤 `global.json`을
`10.0.302`로 갱신했고 managed locked restore와 x64/ARM64 build를 통과시켰습니다.

Visual Studio 18.8의 설치 상태에는 C#용 Windows App SDK 지원 component
`Microsoft.VisualStudio.Component.WindowsAppSdkSupport.CSharp`가 포함돼 있습니다. 구형 group ID인
`Microsoft.VisualStudio.ComponentGroup.WindowsAppSDK.Cs`는 이 instance의 실제 선택 package와 일치하지
않으므로 `.vsconfig`도 현재 component ID로 바로잡았습니다. 현재 ID를 사용한 `vswhere -requires`로
Community instance 한 개를 확인했고, instance는 `isComplete=true`, `isLaunchable=true`,
`isRebootRequired=false`였습니다. 활성 installer process도 없습니다. 따라서 현재 WinUI 3 프로젝트 graph를
만드는 데 필요한 Visual Studio component 공백은 없습니다.

## 재현 선언

- `.vsconfig`: Visual Studio workload와 component 목록
- `configuration.dsc.yaml`: WinGet configuration 진입점
- `global.json`: .NET SDK 10.0.302 pin
- `vcpkg.json`: registry baseline과 runtime dependency 목록
- `CMakePresets.json`: architecture/configuration별 build root

권장 구성 명령:

```powershell
winget configure -f .\configuration.dsc.yaml --accept-configuration-agreements
```

Visual Studio 기존 instance에 `.vsconfig`를 적용할 때의 공식 형식:

```powershell
& "C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe" modify `
  --installPath "C:\Program Files\Microsoft Visual Studio\18\Community" `
  --config ".\.vsconfig" --passive --norestart
```

본체 업데이트는 `modify`와 별개입니다.

```powershell
& "C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe" update `
  --installPath "C:\Program Files\Microsoft Visual Studio\18\Community" `
  --passive --norestart
```

두 명령은 관리자 권한/UAC와 네트워크가 필요할 수 있습니다. 이 기록에서는 본체 update와 필요한
Windows App SDK C# component 설치가 모두 완료됐습니다.

## WinUI package와 실행 전제

Visual Studio component 설치 여부와 app이 참조하는 NuGet/runtime 버전은 별개입니다. 현재 source graph는
다음 component package를 중앙 고정하며 집계 `Microsoft.WindowsAppSDK` package는 사용하지 않습니다.

- `Microsoft.WindowsAppSDK.Runtime 1.8.260710003`
- `Microsoft.WindowsAppSDK.WinUI 1.8.260709004`
- `Microsoft.Windows.SDK.BuildTools 10.0.26100.7705` build-only

개발 빌드는 unpackaged, framework-dependent이므로 개발 PC에 .NET 10 runtime과 Windows App
Runtime 1.8이 필요합니다. 반면 최종 사용자용 x64 설치 파일은 self-contained publish와 App Runtime을
포함하므로 별도 .NET/Windows App Runtime 설치가 필요하지 않습니다. 실제 설치·제거 smoke와 배포 명령은
[`windows-build-and-install.md`](windows-build-and-install.md)가 소유합니다.

Visual Studio 업데이트처럼 compiler 경로가 바뀐 경우 기존 generated build tree를 직접 삭제하지 않고
다음 공식 CMake 재구성 명령을 preset별로 한 번 실행합니다.

```powershell
cmake --preset x64-debug --fresh
cmake --preset x64-release --fresh
cmake --preset arm64-debug --fresh
cmake --preset arm64-release --fresh
```

## 로컬 빌드

현재 PowerShell execution policy를 영구 변경하지 않고 실행합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -Preset x64-debug
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -Preset x64-release
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1 -Preset arm64-debug
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1 -Preset arm64-release
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-interop.ps1 -Preset x64-debug
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-interop.ps1 -Preset x64-release
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-managed.ps1 -Preset arm64-debug
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-managed.ps1 -Preset arm64-release
```

`build-managed.ps1`은 Interop, Shell.Core, WinUI Shell과 managed test project를 같은 locked solution graph로
빌드합니다. x64 Debug 셸 실행 위치는 다음과 같습니다.

```powershell
.\out\build\managed\Negaflow.Shell\x64\Debug\net10.0-windows10.0.26100.0\win-x64\Negaflow.Shell.exe
```

ARM64 명령은 x64 호스트에서 cross-build만 수행합니다. 실제 ARM64 test 실행 명령은 ARM64 Windows
runner에서 별도 기록해야 합니다.
