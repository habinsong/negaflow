# Negaflow Windows

macOS용 Negaflow의 제품 계약을 Windows 네이티브 기술로 독립 구현하는 작업 공간입니다.
현재 단계는 M0 기준선, M1 native/managed 빌드·Interop 기반, M2 scalar 네거티브·톤 수치 계약, M3 TIFF
decode·입력 색상·검증된 PNG16/TIFF16 출력 경계, M4 단일 이미지 CLI와 M8 WinUI 셸 기반입니다. 제품 전체
이미지 처리나 실제 제품 기능이 완성된 상태는 아닙니다.

## 고정 기준

- macOS 제품 기준선: `2fa1d6297378673b58b8bec72025e968ccc3125c`
- 설계 문서 조사 기준: `9be909c43edd7e04ba98cdc9d6a0c688739e343e`
- Windows 기술 경계: C#/.NET 10/WinUI 3 셸, C++20 엔진, 좁은 C ABI
- 네이티브 대상: x64와 순수 ARM64
- GPU 기준선: D3D11, Direct2D, DirectCompute, WARP 검증, 완전한 CPU 경로

두 커밋 사이의 디지털 필름 명부 범위 수정은 correctness 변경으로 분류해 Windows 기준선에
포함했습니다. 자세한 내용은 `baseline/known-deltas.json`에 있습니다.

## 현재 제공하는 것

- architecture별로 격리된 CMake 프리셋
- C++20 네이티브 코어와 좁은 C ABI DLL
- .NET 10 source-generated `LibraryImport`와 절대 경로 ABI bootstrap
- build ID, architecture, CPU capability를 구조화해 출력하는 CLI
- checked float32 pixel view와 scalar exposure/color-matrix/basic-tone/parametric-curve
- `shoulder-print-response-v4` color/B&W negative inversion reference
- 원본 불변 Classic/BigTIFF 구조 검사와 `--probe-tiff` CLI
- Microsoft 기본 WIC의 RGB/RGBA 16-bit TIFF decode
- full decoded source를 만들지 않는 WIC row sink와 cooperative cancellation·row progress
- bounded ICC 검사와 재사용 Windows ICM row transform 기반 scanner→linear-sRGB float 변환
- 사용자 scanner TIFF 15개 read-only streaming 변환과 whole-frame 최종 float exact parity
- TIFF decode→scanner color→수동 Dmin 네거티브 반전 수직 경로
- macOS 수식 순서의 노출·기본 톤·4-band 파라메트릭 커브 scalar와 bounded 동적 측정
- working float→sRGB16→Microsoft WIC PNG encode→pixel·ICC readback→기존 파일 비덮어쓰기 게시
- working float→sRGB16→무압축 Classic TIFF encode→최소 IFD·pixel·ICC readback→비덮어쓰기 게시
- content를 읽지 않는 source file 상태 전후 관찰과 PNG16/TIFF16 공통 단계별 CLI report
- 일반 이미지 SHA-256 기본 `끔`, 명시적 opt-in Windows CNG 순차 경로
- Swift 기준 치수와 6개 언어를 쓰는 WinUI 3 Library/Develop/Print/Settings 셸
- 현재 모니터 작업영역 최대화와 Windows 오른쪽 caption button runtime inset
- Settings의 일반 이미지 SHA-256 기본 `끔` 표시·저장 기반
- ABI layout과 capability 불변식을 확인하는 native test
- 현재 기준선과 canonical asset SHA-256 목록
- 설치 가능한 Visual Studio workload 선언

현재 네이티브 엔진 코드에는 제3자 라이브러리가 없습니다. Windows WIC/ICM과 Win32만 runtime API로
사용하며 MSVC runtime은 정적으로 링크합니다. 따라서 Release native CLI는 별도 VC++ Redistributable
DLL 설치를 요구하지 않습니다. 관리 Interop도 외부 NuGet package가 없습니다.

WinUI 셸은 `Microsoft.WindowsAppSDK.Runtime 1.8.260710003`과
`Microsoft.WindowsAppSDK.WinUI 1.8.260709004`를 직접 고정합니다. 현재 unpackaged build는
framework-dependent이므로 .NET 10 runtime과 Windows App Runtime 1.8이 필요합니다. 정확한 package graph,
license와 배포 gate는 `third_party/manifest/components.json`에 기록합니다.
상세 진행률, 구현 설명, 설치·검증 기록은 [`docs/README.md`](docs/README.md)에서 시작합니다.

## 빌드

먼저 Visual Studio 2026과 Windows 11 SDK를 포함한 개발 환경을 구성합니다.

```powershell
winget configure -f .\configuration.dsc.yaml --accept-configuration-agreements
```

이 구성은 `.vsconfig`를 사용해 C#, 네이티브 C++, WinUI 3, x64, ARM64 도구를 같은 목록으로
재현합니다. 이후 PowerShell에서 빌드합니다.

Visual Studio에 포함된 vcpkg 도구를 사용하며, 제3자 port 버전은 `vcpkg.json`의 정확한
`builtin-baseline`으로 고정합니다. 현재 runtime port dependency는 0개입니다.

```powershell
./scripts/build.ps1 -Preset x64-debug
./scripts/test.ps1 -Preset x64-debug
./scripts/test-interop.ps1 -Preset x64-debug
```

managed solution build가 끝나면 x64 Debug 셸은 다음 위치에서 실행할 수 있습니다.

```powershell
.\out\build\managed\Negaflow.Shell\x64\Debug\net10.0-windows10.0.26100.0\win-x64\Negaflow.Shell.exe
```

Release 빌드:

```powershell
./scripts/test.ps1 -Preset x64-release
./scripts/test-interop.ps1 -Preset x64-release
./scripts/build-managed.ps1 -Preset arm64-debug
./scripts/build-managed.ps1 -Preset arm64-release
```

PowerShell 실행 정책이 스크립트를 막는 기본 Windows 환경에서는 정책을 영구 변경하지 않고 다음처럼
현재 프로세스에만 허용할 수 있습니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -Preset x64-debug
```

한 픽셀의 네거티브 반전 수치를 CLI로 확인할 수 있습니다.

```powershell
.\out\build\native\x64-debug\Debug\negaflow-cli.exe --negative-invert 0.72 0.72 1.55 color
```

TIFF를 디코드하지 않고 header와 첫 IFD, tag/strip 범위를 읽기 전용으로 확인할 수 있습니다.

```powershell
.\out\build\native\x64-debug\Debug\negaflow-cli.exe --probe-tiff C:\path\scan.tiff
```

Microsoft 기본 WIC로 허용된 TIFF를 16-bit sample까지 decode해 구조화된 통계를 확인할 수 있습니다.

```powershell
.\out\build\native\x64-debug\Debug\negaflow-cli.exe --decode-tiff-wic C:\path\scan.tiff
```

scanner 입력 정책을 적용해 working linear-sRGB float buffer까지 검증할 수 있습니다. 결과에는 ICC
경로의 16-bit intermediate 여부, row copy 횟수와 application-owned peak buffer가 포함되며 pixel이나
경로는 출력하지 않습니다.

```powershell
.\out\build\native\x64-debug\Debug\negaflow-cli.exe --prepare-scanner-tiff C:\path\scan.tiff
```

working 변환 뒤 명시한 채널별 film-base 투과율로 color 또는 B&W 네거티브를 수동 반전할 수 있습니다.
이 진단 경로는 장면 통계를 이용한 자동 보정을 하지 않고, 파일을 출력하지 않으며 이미지 SHA-256도
계산하지 않습니다.

    .\out\build\native\x64-debug\Debug\negaflow-cli.exe --develop-negative-tiff C:\path\scan.tiff 0.72 0.32 0.15 color

같은 수직 경로를 16-bit opaque sRGB PNG로 내보낼 수 있습니다. 목적지는 절대 경로이고 기존 파일이
없어야 합니다. 게시 전에 PNG 구조, 전체 RGB16 pixel과 ICC bytes를 다시 읽어 확인하며 source와
artifact SHA-256은 계산하지 않습니다.

```powershell
.\out\build\native\x64-debug\Debug\negaflow-cli.exe --export-developed-png16 C:\path\scan.tiff C:\path\result.png 0.72 0.32 0.15 color
```

macOS 기본 export와 같은 무압축 16-bit opaque sRGB TIFF로도 내보낼 수 있습니다. 게시 전 단일 IFD,
구조 tag allowlist, 전체 RGB16 pixel과 ICC bytes를 확인합니다. source metadata는 복사하지 않으며 Make,
Model, Software, DateTime, Artist, Copyright, XMP, EXIF, GPS와 알 수 없는 tag는 허용하지 않습니다.

```powershell
.\out\build\native\x64-debug\Debug\negaflow-cli.exe --export-developed-tiff16 C:\path\scan.tiff C:\path\result.tiff 0.72 0.32 0.15 color
```

노출·대비·파라메트릭 커브 네 구간을 적용하려면 여섯 값을 모두 덧붙입니다. 범위는 노출 `[-5, 5]`,
나머지는 `[-1, 1]`입니다.

```powershell
.\out\build\native\x64-debug\Debug\negaflow-cli.exe --export-developed-tiff16 C:\path\scan.tiff C:\path\result.tiff 0.72 0.32 0.15 color 0.5 0.25 0.1 -0.1 0.2 -0.2
```

두 export command는 source를 읽기 전후에 file identity·크기·최종 수정 시각만 비교하고, SHA-256은
계산하지 않습니다. 결과에는 decode+color, develop, tone, output의 byte·memory·wall-time과 검증 상태가
들어가며 경로와 file identity 값은 들어가지 않습니다. 동적 커브는 target·percentile 계약을 macOS와
맞추고 비공개 Core Image 축소 filter 대신 명시적 `portable_area_v1`을 사용했다는 사실을 report합니다.

이미지 SHA-256은 기본 작업에서 계산하지 않습니다. 사용자가 명시적으로 필요할 때만 다음 opt-in
command를 사용합니다.

```powershell
.\out\build\native\x64-debug\Debug\negaflow-cli.exe --sha256-image C:\path\scan.tiff
```

versioned 합성 fixture의 수치 오차 보고서는 별도 실행 파일로 출력합니다.

```powershell
.\out\build\native\x64-debug\Debug\negaflow-conformance.exe
```

ARM64는 빌드 프리셋과 실제 장치 실행 검증을 분리합니다. x64 PC에서 cross-compile에 성공한
것만으로 ARM64 지원을 주장하지 않습니다.

## 디렉터리

```text
baseline/             고정 macOS 기준선과 자산 hash
cmake/                공통 compiler 정책
docs/                 결정과 현재 검증 상태
src/Native/core/      Windows 네이티브 공통 기반
src/Native/color/     ICC 구조와 순수 색상 수학
src/Native/imageio/   WIC decode와 소유형 sample
src/Native/imaging/   scanner source→working 정책과 ICM adapter
src/Native/output/    sRGB16 변환, WIC PNG/TIFF readback과 단일 파일 게시
src/Native/abi/       유일한 공개 C ABI
src/Interop/          C# ABI binding, 안전한 DLL probing과 version validation
src/Shell.Core/       UI 비종속 표시 상태, 기본값과 적응형 배치 계산
src/Shell/            WinUI 3 main/Settings 창, localization과 화면 셸
src/Cli/              WinUI 없는 첫 소비자와 분리된 command
tests/Native.UnitTests/
tests/Interop.ContractTests/
tests/Shell.UnitTests/
scripts/              로컬과 CI가 함께 사용할 build/test 진입점
third_party/          실제 payload 기준 공급망 manifest
```

## 다음 순서

1. M4 tone의 실제 macOS runtime golden·pixel diff와 CPU time·canonical stage digest 보강
2. LZW code stream 의미 검증과 malformed Deflate/fuzz corpus 보강
3. macOS ColorSync golden과 Windows ICM 수치 비교
4. 필요한 경우에만 libtiff/LittleCMS dependency gate 재평가
5. 최종 working buffer와 출력의 downstream row/tile 처리·process budget
6. 실제 ARM64 장치에서 같은 native/scalar/TIFF/hash/PNG test 실행
7. WinUI 셸의 축소 폭·DPI·High Contrast·keyboard matrix와 실제 catalog 연결

현재 WinUI는 실행 가능한 화면 기반일 뿐 실제 제품 기능 완료를 의미하지 않습니다.
