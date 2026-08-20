# Windows판 언어 선택

기준일: 2026-08-04  
결정: C#/.NET 10 WinUI 3 셸 + C++20 네이티브 엔진

## 결론

| 구성 | 언어·런타임 | 책임 |
|---|---|---|
| `Negaflow.Shell` | C# / .NET 10 LTS / WinUI 3 | XAML, 상태, 창, 입력, 접근성, 현지화 |
| `Negaflow.Interop` | C# source-generated P/Invoke | safe handle, ABI validation, event translation |
| `Negaflow.Native` | C++20 DLL | 이미지·색·결함·GPU·CPU·IO·export/print pixel render |
| `negaflow-cli` | C++20 executable | 수치 conformance, 진단, benchmark |
| scanner plugins | 구현별 x86/x64/ARM64 process | TWAIN/WIA/SANE/벤더 API |

C#은 픽셀 loop와 GPU resource를 소유하지 않는다. C++은 XAML visual tree와 UI 상태를 소유하지
않는다. 두 계층은 좁은 C ABI로 연결한다.

## C# 셸을 선택한 이유

### WinUI 3 제품 표면에 집중한다

현재 macOS 앱은 `Sources/negaflowApp`에 500개가 넘는 Swift 파일과 Library, Develop, Canvas,
Defects, Scan, Export, Print, Settings, Help/Recovery surface를 가진다. Windows판 UI 작업의 핵심은
언어 microbenchmark가 아니라 다음을 정확하게 재현하는 것이다.

- 상태 전이와 명령 활성 조건
- virtualization과 selection
- keyboard, menu, dialog, flyout
- UI Automation과 Narrator
- localization과 text scaling
- Windows App SDK lifecycle·windowing·deployment

C# WinUI 3는 이 표면의 공식 지원 경로이며 view model, async orchestration, 테스트와 tooling의
마찰이 적다.

### managed 성능 문제는 경계 설계로 막는다

UI 셸이 느려지는 주 원인은 “C#이라서”가 아니라 다음이다.

- 고해상도 픽셀을 managed array로 복사
- slider event마다 allocation·boxing·JSON parse
- UI thread에서 file IO 또는 native fence 대기
- 수만 item collection 전체 교체
- 과도한 property notification
- thumbnail decode를 UI thread에서 수행

Negaflow는 픽셀과 texture를 C++에 유지하고 작은 immutable command/event만 경계를 건너므로
이 문제를 구조적으로 피한다. 언어 선택을 단일 synthetic collection benchmark로 정당화하지 않는다.

## C++ 엔진을 선택한 이유

- D3D11, DXGI, Direct2D custom effect와 COM lifetime을 직접 다룬다.
- WIC, ColorSync 대체, libtiff/lcms2 등 C/C++ API와 자연스럽게 연결한다.
- x64 AVX2/FMA와 ARM64 NEON의 runtime dispatch를 통제한다.
- 대형 buffer, tile cache, allocator, thread pool의 수명과 byte budget을 명시한다.
- 같은 engine을 WinUI 없이 CLI와 native tests에서 검증한다.
- GPU backend를 바꾸어도 C ABI와 제품 parameter schema를 유지할 수 있다.

C++ 선택은 “모든 UI도 C++로 쓴다”는 뜻이 아니다. 메모리 안전을 위해 RAII, span, checked
arithmetic, sanitizers, fuzzing과 strict warning을 사용하고 C ABI 입구에서 모든 크기·범위를 검증한다.

## 경계 선택

기본: C ABI + source-generated `LibraryImport`.

- opaque handle
- fixed-width POD
- length-delimited UTF-8
- request ID와 immutable parameter snapshot
- bounded event queue
- caller-owned small buffers
- C++ exception과 STL type 비노출

C++/WinRT component를 C#에서 소비하려면 C# projection assembly와 `.winmd` 배포가 추가된다.
WinUI `SwapChainPanel`을 안전하게 native에 연결하는 스파이크가 C ABI 방식으로 실패할 때만,
패널 attach/detach만 소유하는 얇은 C++/WinRT 어댑터를 허용한다.

세부: [csharp-native-interop.md](csharp-native-interop.md)

## CLI가 먼저인 이유

첫 실행 제품은 GUI가 아니라 C++ CLI와 engine tests다.

```text
macOS 고정 fixture
→ Windows decode·pipeline·ICC·export CLI
→ CPU scalar 골든
→ SIMD/WARP/D3D11 동등성
→ WinUI 셸과 캔버스
```

GUI를 먼저 만들면 화면이 비슷해도 이미지 결과가 다른 상태를 늦게 발견한다. CLI는 engine의 첫
소비자이자 release 이후에도 고객 파일을 안전하게 진단하는 도구다.

## .NET NativeAOT

v1 기본에서 제외한다.

- WinUI 3, Windows App SDK, C#/WinRT, reflection·XAML toolchain 조합을 전체 검증해야 한다.
- Negaflow의 큰 비용은 managed JIT가 아니라 decode/render/encode와 GPU·IO다.
- self-contained 배포만으로 runtime version 통제 목적을 달성할 수 있다.
- trim/AOT가 startup 또는 메모리에 명확한 순이득을 보인 뒤 별도 스파이크한다.

일반 .NET 10 Release publish로 먼저 기능·안정성·프로파일을 고정한다.

## Rust를 기본으로 선택하지 않은 이유

Rust의 메모리 안전성은 장점이지만 Windows App SDK/WinUI 공식 projection은 C#과 C++가 중심이고,
이 프로젝트의 native 작업은 Direct2D custom COM effect, DXGI/D3D11 resource lifetime, C/C++ codec
의존성과 밀접하다. Rust를 쓰면 unsafe Win32/COM 경계와 별도 FFI가 사라지지 않는다.

특정 독립 도구를 Rust로 만들 가능성까지 금지할 필요는 없지만, 엔진 언어를 둘로 나누는 이득이
실측되지 않았으므로 v1에서는 C++ 하나로 유지한다.

## 순수 C++ WinUI 셸을 선택하지 않은 이유

기술적으로 가능하지만 현재 목표에는 이점보다 비용이 크다.

- UI용 observable collection과 binding boilerplate
- C++/WinRT coroutine·lifetime 복잡도
- C# 중심 WinUI sample/tooling과의 간극
- UI unit test와 localization orchestration 비용
- 엔진과 셸의 책임 분리가 약해질 위험

픽셀 성능은 셸을 C++로 바꾸지 않아도 engine DLL에서 얻는다.

## 버전 정책

- .NET 10 LTS 최신 지원 patch
- Windows App SDK stable 최신 지원 patch, 정확한 버전 pin
- preview/experimental channel은 production dependency로 사용하지 않음
- C++20, MSVC stable
- x64와 ARM64를 첫 CLI부터 함께 빌드
- x86은 scanner plugin process에만 허용

2026-08-04 기준 공식 지원 표는 .NET 10.0.10과 Windows App SDK 2.3.1을 가리킨다. 구현을 시작할
때 다시 확인하고 lock file과 CI image에 실제 resolved version을 기록한다.

## 성공 조건

1. Shell UI thread에 full-resolution pixel copy가 없다.
2. ABI가 x64/ARM64에서 같은 layout test를 통과한다.
3. CLI와 Shell이 같은 engine·shader·asset manifest를 소비한다.
4. request supersession과 cancellation이 stale UI 적용을 막는다.
5. native DLL mismatch와 load failure가 복구 가능한 설치 오류로 표시된다.
6. C++/WinRT를 추가하더라도 패널 연결 이외로 API가 확산되지 않는다.

## 공식 근거

- [Windows App SDK platform overview](https://learn.microsoft.com/en-us/windows/apps/develop/platform/)
- [Get started with WinUI](https://learn.microsoft.com/en-us/windows/apps/get-started/winui-get-started-overview)
- [C++/WinRT component projection for .NET](https://learn.microsoft.com/en-us/windows/apps/develop/platform/csharp-winrt/net-projection-from-cppwinrt-component)
- [Native interoperability best practices](https://learn.microsoft.com/en-us/dotnet/standard/native-interop/best-practices)
- [.NET support policy](https://dotnet.microsoft.com/en-us/platform/support/policy)

