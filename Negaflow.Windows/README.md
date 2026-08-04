# Negaflow Windows

macOS용 Negaflow의 제품 계약을 Windows 네이티브 기술로 독립 구현하는 작업 공간입니다.
현재 단계는 M0 기준선, M1 native/managed 빌드·Interop 기반, 첫 M2 scalar 수치 계약과 M3 TIFF decode·입력 색상 수직 경로입니다. 제품 전체 이미지 처리나 WinUI 화면이 완성된
상태가 아니며, 이를 실행 가능한 제품으로 표시하지 않습니다.

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
- checked float32 pixel view와 scalar exposure/color-matrix
- `shoulder-print-response-v4` color/B&W negative inversion reference
- 원본 불변 Classic/BigTIFF 구조 검사와 `--probe-tiff` CLI
- Microsoft 기본 WIC의 RGB/RGBA 16-bit TIFF decode
- full decoded source를 만들지 않는 WIC row sink와 cooperative cancellation·row progress
- bounded ICC 검사와 재사용 Windows ICM row transform 기반 scanner→linear-sRGB float 변환
- 사용자 scanner TIFF 15개 read-only streaming 변환과 whole-frame 최종 float exact parity
- TIFF decode→scanner color→수동 Dmin 네거티브 반전 수직 경로
- 일반 이미지 SHA-256 기본 `끔`, 명시적 opt-in Windows CNG 순차 경로
- ABI layout과 capability 불변식을 확인하는 native test
- 현재 기준선과 canonical asset SHA-256 목록
- 설치 가능한 Visual Studio workload 선언

현재 네이티브 코드에는 제3자 라이브러리가 없습니다. Windows WIC/ICM과 Win32만 runtime API로
사용하며 MSVC runtime은 정적으로 링크합니다. 따라서 Release native CLI는 별도 VC++
Redistributable DLL 설치를 요구하지 않습니다. 관리 Interop은 외부 NuGet package가 없으며 현재 검증에는
.NET runtime 10.0.10을 사용합니다.
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
src/Native/abi/       유일한 공개 C ABI
src/Interop/          C# ABI binding, 안전한 DLL probing과 version validation
src/Cli/              WinUI 없는 첫 소비자와 분리된 command
tests/Native.UnitTests/
tests/Interop.ContractTests/
scripts/              로컬과 CI가 함께 사용할 build/test 진입점
third_party/          실제 payload 기준 공급망 manifest
```

## 다음 순서

1. 현재 수직 경로에 output encode→readback→atomic publish 연결
2. LZW code stream 의미 검증과 malformed Deflate/fuzz corpus 보강
3. macOS ColorSync golden과 Windows ICM 수치 비교
4. 필요한 경우에만 libtiff/LittleCMS dependency gate 재평가
5. 최종 working buffer의 downstream row/tile 처리와 process budget
6. 실제 ARM64 장치에서 같은 native/scalar/TIFF/hash test 실행
7. 최소 WinUI shell과 native bootstrap·기본-off SHA 설정 연결

WinUI 제품 화면은 위 수치 vertical slice 뒤에 확장합니다.
