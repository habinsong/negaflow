# Windows 솔루션 구조와 빌드 경계

기준일: 2026-08-04  
상태: 제안 확정안. 아직 Windows 저장소를 생성하지 않음.

목표는 C# WinUI 셸, C++ 엔진, CLI, 테스트, 셰이더, 플러그인 계약과 설치를 한 제품으로
만들되 각 도구가 자기 영역만 소유하게 하는 것이다. 이 문서의 경로는 향후 별도 Windows
저장소의 제안 구조이며 현재 macOS 저장소에 만들라는 지시가 아니다.

## 1. 최상위 구조

```text
Negaflow.Windows/
├── Negaflow.Windows.sln
├── Directory.Build.props
├── Directory.Build.targets
├── Directory.Packages.props
├── global.json
├── NuGet.config
├── packages.lock.json
├── CMakeLists.txt
├── CMakePresets.json
├── vcpkg.json
├── vcpkg-configuration.json
├── cmake/
│   ├── CompilerWarnings.cmake
│   ├── Sanitizers.cmake
│   ├── ShaderCompile.cmake
│   └── ReproducibleBuild.cmake
├── src/
│   ├── Shell/
│   ├── Native/
│   ├── Interop/
│   ├── Cli/
│   └── ScannerProtocol/
├── shaders/
│   ├── d2d/
│   ├── compute/
│   ├── include/
│   └── manifest/
├── assets/
│   ├── presets/
│   ├── scanner-profiles/
│   ├── localization/
│   ├── icc/
│   └── licenses/
├── tests/
│   ├── Native.UnitTests/
│   ├── Native.ConformanceTests/
│   ├── Native.IntegrationTests/
│   ├── Shell.UnitTests/
│   ├── Shell.UITests/
│   ├── Scanner.ContractTests/
│   └── Packaging.Tests/
├── tools/
│   ├── FixtureCompiler/
│   ├── BaselineInspector/
│   └── ProtocolProbe/
├── packaging/
│   ├── wix/
│   ├── manifests/
│   └── signing/
├── scripts/
│   ├── build.ps1
│   ├── test.ps1
│   ├── package.ps1
│   └── verify-release.ps1
├── docs/
└── out/                     # 전부 generated, git 제외
```

## 2. 프로젝트 소유권

### `src/Shell/Negaflow.Shell.csproj`

소유:

- WinUI 3 XAML과 code-behind의 최소 연결
- MVVM 상태와 명령
- window, title bar, menu, dialog, flyout, keyboard routing
- custom `Main`, instance election, activation routing과 shutdown coordinator
- Windows 파일·폴더 picker와 shell integration
- UI Automation, Narrator, high contrast, text scale
- MRT Core 기반 현지화와 앱 언어 설정
- catalog·workflow service의 비픽셀 orchestration
- native engine request를 사용자 상태로 번역

소유하지 않음:

- 픽셀 버퍼 수학
- ICC transform 구현
- Direct2D effect 내부
- TIFF/JPEG/PNG codec 세부
- scanner driver API
- 렌더 결과의 임의 보정

### `src/Native/Negaflow.Native`

CMake가 만드는 `Negaflow.Native.dll`과 내부 정적 라이브러리다.

소유:

- 이미지 probe/decode/encode와 metadata 계약
- negative/positive/digital-film 현상 pipeline
- histogram, statistics, auto-tone 측정
- defect detection, recipe application, cleaned cache render
- crop/transform/resize와 large-image tile scheduling
- ICC 입력·작업·디스플레이·출력 변환
- D3D11, Direct2D, DirectCompute, WARP device/resource lifetime
- CPU scalar/SIMD backend
- export·print용 final pixel render
- 성능·진단 event와 crash-safe engine state

DLL의 공개 표면은 C ABI 하나다. 내부 C++ header나 STL type은 Shell에 노출하지 않는다.

### `src/Interop/Negaflow.Interop`

C ABI header의 C# binding, safe handle, marshaling, native error를 관리하는 매우 얇은 C# assembly다.

- source-generated `LibraryImport`
- `SafeHandle` 기반 native object lifetime
- fixed-width enum/struct의 ABI size assertion
- UTF-8 string input과 caller-owned output buffer
- callback 대신 pollable/bounded event queue wrapper
- request ID와 cancellation wrapper

UI view model이나 이미지 알고리즘을 넣지 않는다. native DLL probing 실패를 한곳에서 진단한다.

### `src/Cli/negaflow-cli.exe`

WinUI 없이 `Negaflow.Native`의 내부 C++ API 또는 같은 C ABI를 소비한다.

- fixture probe/decode/render/export
- pipeline parameter JSON 입력
- intermediate stage dump
- ICC·metadata inspection
- CPU/GPU/WARP backend 지정
- benchmark와 deterministic conformance

CLI는 제품 UI 우회용 숨은 수정 도구가 아니다. 품질 잠금, CI, 진단을 위한 공식 소비자다.

### `src/ScannerProtocol/Negaflow.ScannerProtocol`

본체와 플러그인이 공유하는 소스 라이브러리가 아니라 버전된 wire contract의 구현이다.

- manifest schema validation
- v1 JSON request/response
- v2 NDJSON stream envelope
- capability token과 applied-options equality
- file result hash/size/dimensions validation
- bounded message, timeout, cancellation, process lifetime
- test vectors와 protocol fixtures

플러그인은 이 프로젝트 바이너리를 링크해야만 호환되는 구조로 만들지 않는다. JSON schema와
golden transcript가 진짜 호환 경계다.

## 3. Native 내부 모듈

큰 `Negaflow.Native.dll` 하나를 배포하더라도 소스와 테스트 책임은 정적 라이브러리로 나눈다.

```text
src/Native/
├── include/negaflow/         # C++ 내부 API. 설치·외부 공개 안 함
├── abi/                      # 유일한 공개 C ABI 구현
├── core/                     # IDs, Result, cancellation, logging, math policy
├── imageio/                  # WIC/libtiff/metadata/atomic writer
├── color/                    # ICC, working space, soft proof, output transform
├── develop/                  # pipeline graph, adjustments, presets
├── measurement/              # histogram/statistics/auto parameters
├── defects/                  # detect/recipe/render/cache
├── render/
│   ├── common/               # graph, ROI, tile, resource budget
│   ├── cpu/                  # scalar + dispatched SIMD
│   ├── d3d11/                # device, compute, textures, staging
│   ├── d2d/                  # custom effects, effect graph, composition
│   └── warp/                 # 별도 코드가 아니라 adapter selection/testing
├── export/                   # batch plan, naming contract, render/encode handoff
├── print/                    # page render primitives, print-owned output surface
├── persistence/              # app-owned binary cache/recipe helpers
└── diagnostics/              # ETW provider, markers, adapter dump
```

모듈마다 자체 백엔드 interface를 무분별하게 만들지 않는다. CPU·GPU 차이가 실제로 필요한
pixel operation 집합에만 좁은 execution backend를 둔다. 파일 IO, naming, recipe, pipeline
parameter는 backend와 독립이다.

## 4. 빌드 시스템 분담

| 도구 | 소유 범위 |
|---|---|
| CMake | C++ DLL/CLI/tests, HLSL build, vcpkg dependency graph |
| MSBuild/dotnet | C# Shell/Interop/tests, WinUI XAML generation, publish |
| top-level PowerShell | preset 선택, 두 그래프 순서, artifact staging, 검증 |
| WiX | 설치·upgrade·repair·uninstall |
| CI workflow | 깨끗한 환경, matrix, signing 단계 분리, artifact provenance |

Visual Studio solution의 project dependency만 CI의 유일한 orchestration으로 쓰지 않는다. 개발자
IDE에는 편의를 제공하지만 CI는 `scripts/build.ps1`의 명시적 단계와 exit code를 사용한다.

### 권장 빌드 순서

1. restore: NuGet locked mode, vcpkg manifest
2. generate: CMake preset, HLSL manifest, localization validation
3. native build: DLL, CLI, native tests
4. native tests: unit → conformance → WARP integration
5. stage native runtime: architecture별 고정 디렉토리
6. managed build: Interop → Shell
7. managed/unit/UI static tests
8. publish: x64 또는 ARM64 self-contained layout
9. packaging: WiX payload manifest
10. verify: clean VM install, launch, upgrade, uninstall, signatures

managed project의 임의 `PostBuild`에서 CMake 전체를 다시 실행하지 않는다. 증분 빌드가 불투명해지고
여러 configuration이 같은 output을 덮어쓸 수 있다.

## 5. 산출물 staging

architecture와 configuration을 경로에 반드시 포함한다.

```text
out/
├── build/native/x64-debug/
├── build/native/x64-release/
├── build/native/arm64-release/
├── build/shell/x64-release/
├── build/shell/arm64-release/
├── stage/x64-release/
│   ├── Negaflow.exe
│   ├── Negaflow.Native.dll
│   ├── shaders/
│   ├── assets/
│   └── licenses/
├── stage/arm64-release/
└── packages/
```

staging 규칙:

- 동일 파일명을 architecture 사이에 공유 디렉토리로 복사하지 않는다.
- C# publish가 native DLL의 오래된 복사본을 재사용하지 않게 content hash를 확인한다.
- shader·preset·profile은 manifest에 size와 SHA-256을 기록한다.
- PDB와 source map 성격의 진단물은 symbol artifact로 분리하되 release build ID로 연결한다.
- installer 입력은 `stage/`만 사용하고 개발 build tree를 직접 수집하지 않는다.

## 6. 데이터 자산 경계

macOS와 Windows가 공유할 수 있는 것은 source asset 또는 중립 schema다.

| 자산 | 공유 방식 | 금지 |
|---|---|---|
| film/scanner presets | canonical JSON + schema + hash | Swift decode 결과를 그대로 복사 |
| localization keys | key manifest + 번역 값 | Swift enum을 Windows runtime에 포함 |
| test vectors | input + parameter + expected numeric report | 플랫폼별 예상값을 이유 없이 별도 관리 |
| ICC profiles | license 검증된 원본 + hash | OS profile을 저장소에 무단 복사 |
| HLSL/Metal | 알고리즘 사양과 골든 공유 | 전처리기로 한 소스를 억지로 공용화 |
| shortcut IDs | stable action ID와 의미 | macOS key chord를 그대로 복제 |
| scanner protocol | schema/transcript | Swift module binary 공유 |

asset compiler가 필요하면 canonical source와 generated output의 hash 관계를 검증한다. 생성물만
수정하는 흐름을 허용하지 않는다.

## 7. 테스트 프로젝트 구조

### Native.UnitTests

- pure math, edge policy, ROI, tile, naming primitives
- scalar kernel과 CPU dispatch
- corrupt dimensions, overflow, truncated buffer
- catalog와 무관한 app-owned sidecar serialization

### Native.ConformanceTests

- macOS 고정 baseline fixture
- decoded pixel, stage output, histogram/statistics, final output
- CPU scalar, CPU SIMD, D3D11 hardware, WARP 간 허용 오차
- ICC transform과 metadata contract

### Native.IntegrationTests

- WIC/libtiff read/write round trip
- D3D device lost·OOM·adapter switch
- large-image tile eviction와 cancellation
- atomic export and disk-full simulation

### Shell.UnitTests

- view model state transition
- disabled/loading/error/recovery state
- shortcut conflict and persistence
- localization completeness
- native event ordering, stale request suppression

### Shell.UITests

- UI Automation ID 기반 핵심 workflow
- Library → Develop → Export와 Library → Print
- keyboard-only, high contrast, 200% text
- window resize, DPI/monitor movement
- dialogs and cancellation

### Scanner.ContractTests

- v1/v2 transcript
- malformed/oversized/out-of-order message
- capability token stale/replay
- applied options mismatch
- timeout/cancel/child process cleanup
- output outside allowed directory, symlink/reparse-point attack

### Packaging.Tests

- clean install, upgrade, downgrade rejection, repair, uninstall
- x64 payload on x64 and ARM64 payload on ARM64
- architecture mismatch error
- signature and timestamp validation
- user catalog/cache/plugin preservation policy

## 8. 공개 ABI와 헤더 배치

공개 C ABI header는 하나의 작은 디렉토리에만 둔다.

```text
src/Native/abi/include/negaflow_abi.h
src/Native/abi/include/negaflow_abi_version.h
```

규칙:

- `extern "C"`, 명시적 calling convention, export macro
- `uint32_t`, `uint64_t`, `float`, byte span, opaque handle만 사용
- `bool`, `wchar_t`, `size_t`, STL, exceptions, COM smart pointer를 경계에 노출하지 않음
- struct는 `struct_size`와 `abi_version`으로 tail extension 가능하게 함
- allocator ownership을 함수 이름과 문서에 명시
- 같은 함수가 C#과 CLI contract test에서 호출됨
- symbol allowlist로 DLL export가 늘어나지 않았는지 CI 검사

세부는 [../09-language-choice/csharp-native-interop.md](../09-language-choice/csharp-native-interop.md)를
따른다.

## 9. 플러그인은 같은 solution의 하위 DLL이 아니다

TWAIN/WIA/SANE/벤더 플러그인은 본체 release graph와 분리한다.

- 본체 저장소에는 protocol schema, host, mock conformance plugin만 둔다.
- 실제 플러그인은 별도 저장소·라이선스·CI·서명·버전·installer를 가질 수 있다.
- app installer가 모든 플러그인을 묵시적으로 포함하지 않는다.
- plugin discovery는 manifest와 trust policy를 통과한 executable만 대상으로 한다.
- x86 plugin artifact 때문에 앱 전체 solution에 x86 configuration을 확산하지 않는다.

## 10. 구성·feature flag 정책

compile-time flag는 backend와 진단에만 제한한다.

허용 후보:

- `NEGAFLOW_ENABLE_D3D11`
- `NEGAFLOW_ENABLE_WARP_TESTS`
- `NEGAFLOW_ENABLE_CUDA_EXPERIMENT` — 기본 OFF, 정식 package 미포함
- `NEGAFLOW_ENABLE_PRIVATE_CORPUS_TESTS` — CI secret이 아니라 corpus presence로 결정

기능 flag로 제품 기능을 벤더별로 나누지 않는다. `Defects`, `Print`, `Export` 같은 제품 surface는
항상 빌드되고 backend availability에 따라 같은 기능의 실행 경로만 바뀐다.

## 11. dependency 방향

```text
Shell ───────────────► Interop ─────────────► C ABI
  │                                           │
  ├──► Shell services                         ▼
  │                                    Negaflow.Native.dll
  └──► Scanner host ── JSON/NDJSON ──► plugin process

CLI ──────────────────────────────────► Native internal/API
Native tests ─────────────────────────► Native modules
Shell tests ──────────────────────────► Shell + fake Interop contract
```

금지되는 역방향:

- Native가 Shell assembly나 XAML type을 참조
- native render thread가 UI object를 직접 mutate
- plugin이 catalog DB를 직접 열거나 앱 cache 내부를 해석
- Shell이 native private header/struct layout을 복제
- 테스트 편의를 위해 production layer가 test framework를 참조

## 12. 첫 스파이크에서 구조를 승인하는 조건

1. x64·ARM64에서 같은 C ABI DLL을 C#과 CLI가 로드한다.
2. `SafeHandle` dispose, process exit, cancellation 중 native leak이 없다.
3. C ABI 경계로 픽셀 버퍼를 복사하지 않고 SwapChainPanel에 표시한다.
4. unpackaged self-contained publish 후 native DLL과 shader probing이 안정적이다.
5. Debug/Release, x64/ARM64가 output을 덮어쓰지 않는다.
6. CMake만 실행해 CLI와 native tests를 WinUI 없이 빌드할 수 있다.
7. dotnet/MSBuild 실패가 native build의 오래된 artifact를 조용히 사용하지 않는다.
8. payload manifest가 설치 파일을 완전하게 열거한다.

이 조건을 통과하기 전에는 Windows 저장소에 기능별 수백 개 프로젝트를 만들지 않는다.
