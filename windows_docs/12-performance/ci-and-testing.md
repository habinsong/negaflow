# Windows CI, 테스트, 골든 동등성 설계

기준일: 2026-08-04  
상태: test architecture 결정, Windows 구현 전 job 이름·runner 계약은 후보  
관련 문서:

- [실행 backend](backend-selection.md)
- [GPU vendor portability](gpu-vendor-portability.md)
- [프로파일링 도구](profiling-tools.md)
- [solution layout](../13-build-and-deps/solution-layout.md)
- [CMake와 vcpkg](../13-build-and-deps/vcpkg-cmake.md)
- [UI parity contract](../08-ui/parity-contract.md)
- [scanner hardware validation](../10-scanner/hardware-validation-matrix.md)
- [배포 채널](../11-distribution/deployment-channels.md)

## 1. 결론

Windows 이식의 CI는 한 개의 `windows-latest` build로 끝내지 않는다. 다음 네 증거층을 분리한다.

```text
Layer 1 — hosted deterministic
  static contracts + x64/ARM64 build + CPU scalar/SIMD + WARP

Layer 2 — OS integration
  WinUI/COM/WIC/DirectX/persistence/installer clean-machine tests

Layer 3 — physical hardware lab
  Intel + AMD + NVIDIA + Qualcomm ARM64 + real monitors/storage

Layer 4 — real scanner and visual QA
  device/driver/plugin matrix + human click-through + accessibility
```

핵심 원칙:

1. CPU scalar 구현은 수치 oracle이고 항상 빌드·실행된다.
2. WARP는 D3D11/Direct2D/shader/resource 계약을 hosted CI에서 실행하지만 실제 GPU 검증을 대체하지 않는다.
3. x64와 ARM64는 compile만이 아니라 architecture-native tests를 실행한다.
4. Intel/AMD/NVIDIA/Qualcomm은 같은 기능과 허용 오차를 통과한다. NVIDIA GPU runner 하나는 이 matrix가 아니다.
5. macOS 현재 동작은 frozen fixture/report로 옮기고, platform bug와 제품 invariant 충돌은 승인된 delta로 분리한다.
6. UI 자동화 통과는 real visual QA를 대체하지 않는다.
7. mock scanner 통과는 physical scanner 지원 증거가 아니다.
8. performance budget은 runner class/driver/OS를 고정한 evidence에만 적용한다.
9. package smoke와 signed public release gate를 분리한다.
10. local gate와 CI는 같은 underlying commands를 호출한다.

## 2. 현재 macOS repository에서 가져올 운영 자산

### 2.1 현재 workflow

2026-08-04 source snapshot에는 다음 workflow가 있다.

| workflow | 현재 책임 | Windows 이식에서 가져올 패턴 |
|---|---|---|
| `.github/workflows/ci.yml` | static, Swift strict concurrency, GUI test build, unsigned release smoke | 빠른 static failure, 독립 job, release smoke 분리 |
| `performance.yml` | opt-in core/full benchmark와 JSON report | benchmark를 일반 PR wall time에서 분리 |
| `distribution.yml` | protected signing/notarization environment | build와 signing 권한 분리, final artifact 재검증 |
| `defect-corpus.yml` | pinned FILM-R v2 corpus 평가 | 외부 corpus provenance와 quality gate 분리 |

현재 workflow는 macOS runner용이며 Windows에서 그대로 실행할 command가 아니다. 운영 의미를 옮기고 플랫폼
toolchain은 새로 구성한다.

### 2.2 현재 local/CI entry points

- `scripts/ci-gate.sh`
- `scripts/ci/verify-static.sh`
- `scripts/ci/build-swift.sh`
- `scripts/ci/build-gui-tests.sh`
- `scripts/run-performance-suite.sh`
- `scripts/run-library-query-performance.sh`
- `scripts/profile-resource-usage.py`
- `scripts/performance/*`

Windows도 top-level gate 하나가 동일한 하위 commands를 실행한다. CI YAML에만 존재하는 복잡한 build logic을
만들지 않는다.

### 2.3 현재 test truth

현재 `Tests/`는 Chromabase, ScannerKit, app domain/UI, CLI 계약을 XCTest로 검증한다. synthetic image fixture,
temp catalog, mock scanner, external-process fixture가 이미 있다. 별도 opt-in workflow에는 pinned external
FILM-R corpus도 있다.

따라서 Windows 정책은 “실제 이미지는 모두 금지”가 아니다. 정확한 구분은 다음과 같다.

- private 사용자 사진·실스캔을 repository/CI artifact로 사용 금지
- deterministic synthetic fixture를 기본 unit/conformance에 사용
- license·version·hash가 고정된 공개 corpus는 별도 opt-in quality job에서 사용 가능
- physical scanner/monitor/printer evidence는 access-controlled lab artifact로 관리
- corpus가 없는 환경에서 quality job을 pass로 위장하지 않음

test 개수는 계속 변하므로 문서에 영구 상수로 박지 않는다. migration manifest에서 test class/contract mapping을
추적한다.

## 3. 공식 근거와 runner 현실

- [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [GitHub larger runners](https://docs.github.com/en/actions/reference/runners/larger-runners)
- [Windows ARM64 hosted runner GA announcement](https://github.blog/changelog/2025-08-07-arm64-hosted-runners-for-public-repositories-are-now-generally-available/)
- [GitHub runner images](https://github.com/actions/runner-images)
- [Self-hosted runners](https://docs.github.com/en/actions/reference/runners/self-hosted-runners)
- [Create a WARP device](https://learn.microsoft.com/en-us/windows/win32/direct3d11/overviews-direct3d-11-devices-create-warp)
- [D3D11 device creation](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/nf-d3d11-d3d11createdevice)
- [Direct3D 11 debug layer](https://learn.microsoft.com/en-us/windows/win32/direct3d11/using-the-debug-layer-to-test-apps)
- [CTest](https://cmake.org/cmake/help/latest/manual/ctest.1.html)
- [Floating point comparisons in Catch2](https://github.com/catchorg/Catch2/blob/devel/docs/comparing-floating-point-numbers.md)
- [GoogleTest floating-point assertions](https://google.github.io/googletest/reference/assertions.html#floating-point-comparison)

### 3.1 ARM64 hosted runner

GitHub는 2025-08-07 public repository용 Windows ARM64 standard hosted runner를 GA로 발표했고 label은
`windows-11-arm`이다. private repository는 plan과 larger-runner availability가 다를 수 있다.

따라서 계획은 조건부다.

- public repository이고 label 사용 가능: native ARM64 hosted build/test
- private repository: ARM64 larger runner 또는 protected self-hosted ARM64 machine
- availability가 없으면 cross-compile만 하고 “ARM64 테스트 완료”라고 하지 않음

runner image/tool version은 floating `latest`만 믿지 않고 job report에 exact image version을 기록한다.

### 3.2 GPU runner

현재 GitHub larger-runner 문서는 Windows GPU larger runner와 NVIDIA Tesla T4 class를 제공한다. 예전의
“hosted Actions에는 GPU가 없다”는 일반화는 더 이상 정확하지 않다.

그러나 이것은 다음을 해결하지 않는다.

- Intel iGPU
- AMD dGPU/iGPU
- Qualcomm Adreno ARM64
- hybrid GPU와 monitor movement
- consumer driver versions
- WDDM device removal/driver update

NVIDIA GPU runner는 optional D3D hardware smoke 또는 CUDA 후보 benchmark에 쓸 수 있지만 vendor-portability
release gate는 physical/self-hosted lab이 소유한다. 가격·SKU는 바뀌므로 문서에 고정하지 않는다.

## 4. runner matrix

### 4.1 PR 필수

| job | runner 후보 | 결과 |
|---|---|---|
| static-contracts | Windows x64 hosted | schema, boundary, license/provenance, docs links |
| native-x64 | Windows x64 hosted | CMake restore/build/CTest Debug+Release 핵심 |
| shell-x64 | Windows x64 hosted | .NET locked restore/build/unit |
| warp-conformance-x64 | Windows x64 hosted | production shaders/effects와 read-back |
| integration-x64 | Windows x64 hosted | WIC/lcms/libtiff/SQLite/process contracts |
| native-arm64 | `windows-11-arm` 또는 approved runner | native CMake build/test |
| shell-arm64 | same ARM64 runner | native ARM64 publish/unit/smoke |
| package-smoke | Windows x64 + ARM64 | unsigned installer layout/static validation |

PR에서 signing credential을 사용하지 않는다. package smoke는 structure와 install logic fixture를 검사하지만
public release readiness를 주장하지 않는다.

### 4.2 main/nightly

- full CPU scalar/SIMD conformance
- full WARP conformance
- large virtual library
- corruption/failure injection
- sanitizer-supported native jobs
- fuzz corpus replay
- localization/accessibility static checks
- package clean install/upgrade/repair/uninstall VM
- performance smoke with non-gating trend report

### 4.3 scheduled hardware lab

| class | 최소 대표 | 목적 |
|---|---|---|
| Intel | integrated GPU + Intel/AMD x64 CPU | common laptop, UMA/budget |
| AMD | Radeon iGPU/dGPU | wave/driver/memory behavior |
| NVIDIA | consumer GeForce class | discrete GPU, optional CUDA comparison |
| Qualcomm | native ARM64 Adreno | ARM64 CPU/GPU/UMA/product install |
| WARP | supported Windows builds | software D3D contract |
| CPU-only | x64 Intel/AMD + ARM64 | fallback와 SIMD dispatch |

각 machine은 OS build, GPU driver, BIOS/firmware relevant identity, power mode, monitor, memory를 report한다.

### 4.4 release manual lab

- physical scanner matrix
- color-managed multi-monitor
- HDR/SDR mixed display if in scope
- Wacom/Surface Pen
- 100/125/150/200% DPI와 text scaling
- high contrast/Narrator/keyboard
- actual installer/download/SmartScreen
- print output target if direct printer path in scope

## 5. job graph

```text
static-contracts ───────────────┐
dependency-restore-x64 ─► native-x64 ─► integration-x64 ─┐
                         └► warp-conformance-x64 ─────────┤
dependency-restore-arm64 ► native-arm64 ─► shell-arm64 ───┤
shell-x64 ────────────────────────────────────────────────┤
                                                         ▼
                                                  package-smoke
                                                         │
                                    manual protected release only
                                                         ▼
                                                   signing/install QA
```

독립 job은 병렬로 실행하되 build artifact를 넘길 때 hash와 architecture/configuration을 확인한다. 서로 다른 job이
같은 mutable cache output을 쓰지 않는다.

## 6. toolchain pinning

report할 항목:

- Windows runner image/version
- Windows SDK version
- MSVC compiler/toolset
- CMake/Ninja
- vcpkg baseline commit
- .NET SDK/runtime
- Windows App SDK NuGet exact version
- test framework exact version
- FXC/compiler version과 flags
- WiX version
- Python version if build verification scripts use it

lock files와 manifests가 있어도 runner image update가 결과를 바꿀 수 있다. scheduled “next image” job으로
변경을 미리 탐지한다. `windows-latest` migration 날 처음 실패를 보는 운영을 피한다.

## 7. dependency restore와 cache

### 7.1 locked restore

- NuGet lock/locked mode
- vcpkg manifest와 fixed baseline
- CMake preset
- source archive hash
- architecture/configuration 분리

### 7.2 cache key

최소:

```text
OS image
architecture
compiler/toolset
vcpkg baseline
triplet
manifest/lock hash
port patches/features
configuration-relevant options
```

cache hit는 dependency provenance 증거가 아니다. 정기 clean restore와 source/license hash verification을 둔다.
cache corruption 시 rebuild 가능해야 한다.

### 7.3 supply-chain gate

- unexpected network access
- dependency version drift
- license expression/file drift
- source URL/hash drift
- new transitive dependency
- binary architecture mismatch
- prebuilt binary provenance

release build가 PR용 untrusted cache를 검증 없이 재사용하지 않는다.

## 8. build configurations

### 8.1 required

```text
x64 Debug
x64 Release
ARM64 Debug or RelWithDebInfo
ARM64 Release
```

Release-specific optimizer/undefined behavior를 잡기 위해 unit/conformance 일부는 Release에서도 실행한다.

### 8.2 compiler warnings

- high warning level
- new project code warning zero
- narrowing/conversion/overflow risk
- C ABI layout static assertions
- exceptions cannot cross ABI
- analyzers for C# nullable/threading/interop
- HLSL warnings as errors

third-party headers의 warning을 무작정 전역 suppress하지 않고 system/external include 경계로 격리한다.

### 8.3 reproducibility

두 clean build의 hash가 달라질 수 있는 timestamp/signing 영역을 분리한다. unsigned payload의 reproducible
manifest를 비교하고, signed artifact는 provenance와 final hash로 관리한다.

## 9. test project 계층

### 9.1 Native.UnitTests

- parameter validation
- ROI/rect/halo/tile math
- curve/LUT interpolation
- negative inversion scalar kernels
- histogram/statistics scalar logic
- defect geometry/components
- naming and size math
- checked arithmetic and allocation bounds
- SIMD dispatch selection
- cancellation token semantics

### 9.2 Native.ConformanceTests

- frozen macOS stage reports
- CPU scalar vs SIMD
- CPU vs WARP
- WARP vs hardware report input
- shader constants/layout
- precision/clipping
- ICC transforms
- image IO metadata
- full pipeline recipe

### 9.3 Native.IntegrationTests

- WIC/libtiff/LibRaw candidates
- SQLite transaction/recovery
- Direct2D/D3D11 resource ownership
- device-lost and WARP recreation
- tile cache eviction
- disk full/permission/long path
- atomic export publish
- multi-frame batch cancellation

### 9.4 Shell.UnitTests

- state transitions
- settings validation/persistence
- stale async result suppression
- selection/filter/sort
- export/scan progress model
- error/recovery copy
- localization key completeness
- shortcut conflict resolution
- native event ordering

### 9.5 Shell.UITests

- Library → Develop → Export
- Library → Print output surface
- scanner absent/installed/permission/error/demo opt-in
- keyboard-only
- Narrator/UI Automation properties
- high contrast
- text scaling
- window resize/minimum width
- DPI/monitor movement
- dialogs, cancel, retry, relaunch restoration

### 9.6 Scanner.ContractTests

- exact v1/v2 transcripts
- malformed/oversized/out-of-order NDJSON
- duplicate/late terminal events
- timeout/cancel/process tree cleanup
- capability/read-back/applied mismatch
- artifact path/reparse attacks
- RGB/IR geometry
- WIA property fixture
- TWAIN container/state fixture

### 9.7 Packaging.Tests

- clean install
- previous stable upgrade
- repair
- uninstall
- failed upgrade rollback
- architecture mismatch
- signature/timestamp
- mixed payload rejection
- catalog/source/plugin preservation
- offline install

## 10. test framework 선택

native framework는 GoogleTest 또는 Catch2 중 **하나만** 선택해 manifest에 고정한다. 이 문서의 tolerance
개념이 특정 matcher 문법을 제품 계약으로 만들지 않는다.

선택 gate:

- vcpkg/CMake integration
- x64/ARM64
- parameterized fixtures
- custom numeric/image diagnostics
- test discovery/CTest
- startup and binary size
- license/provenance
- sanitizer/fuzz integration

managed test framework도 existing .NET/WinUI tooling과 CI report format으로 하나를 정한다. production assembly가
test framework를 참조하지 않는다.

## 11. canonical fixture format

### 11.1 fixture package

```text
fixture-id/
  manifest.json
  input/
  parameters.json
  expected/
    decode.json
    measurement.json
    develop.json
    export.json
  profiles/
  licenses/
```

manifest fields:

- schema version
- fixture ID/version
- source/provenance/license
- input size/SHA-256
- pixel format/color encoding/orientation
- parameter schema/version
- macOS commit/build used to generate expected data
- stage algorithm IDs
- expected report hashes
- per-metric tolerance policy ID
- approved platform delta IDs

### 11.2 fixture categories

- tiny exact synthetic patterns
- gradients and ramps
- impulses/checkerboards/edges
- out-of-range float values
- film-base and negative synthetic spectra/patches
- crop/orientation/alpha variants
- corrupt/truncated/oversized metadata
- public licensed RAW/TIFF/JPEG corpus
- defect masks and known components
- large virtual image generator

large virtual fixtures should generate deterministic tiles without allocating the whole notional image.

### 11.3 private evidence

physical scanner charts, printer targets, licensed/private photos can remain outside the public repository. Their result report
must still record fixture identity, access policy, hash, device, driver and procedure. Absence on public CI is a documented
skip, not a pass.

## 12. macOS baseline 생성

### 12.1 source of truth

현재 macOS code를 매 Windows test 때 원격 호출하지 않는다. 검토된 macOS commit에서 canonical CLI/report를
생성해 versioned fixture로 고정한다.

```text
fixed source input + fixed parameter snapshot
  → macOS baseline command
  → stage reports + expected artifacts
  → review/hash/freeze
  → Windows conformance
```

### 12.2 baseline review

baseline 생성도 자동 정답이 아니다.

- current code path가 실제 product path인지
- debug/demo/automatic branch가 섞이지 않았는지
- source original을 건드리지 않는지
- OS/profile/codec version
- non-deterministic metadata
- known product bug

를 검토한다.

### 12.3 approved delta

Windows가 repository product invariant를 지키기 위해 macOS legacy behavior를 의도적으로 복제하지 않는 경우
delta record를 만든다.

- ID
- affected stage/surface
- old macOS behavior
- Windows behavior
- reason: data safety, platform-native translation, bug fix
- user-visible impact
- approver/date
- future macOS alignment plan

platform difference를 모두 tolerance로 숨기지 않는다.

## 13. 수치 비교 정책

### 13.1 exact가 필요한 것

- enum/route/default selection
- dimensions/ROI/stride
- histogram bin index when decision contract requires
- connected-component labels after canonical ordering
- threshold branch outcome
- auto-parameter quantized output
- metadata keys/values where specified
- filename/collision sequence
- state/event order
- schema serialization

float arithmetic이 중간에 있어도 product decision이 달라지면 exact contract가 필요하다.

### 13.2 tolerance가 필요한 것

일반 형태:

```text
absError = |actual - expected|
relError = absError / max(|actual|, |expected|, scaleFloor)
pass = absError <= absTolerance OR relError <= relTolerance
```

0 근처에서 relative-only comparison을 쓰지 않는다. ULP는 동일 format과 연산 의미가 명확한 작은 kernel에만
사용한다.

### 13.3 stage별 policy

| stage | 비교 |
|---|---|
| pure integer/geometry | exact |
| scalar float primitive | abs+rel, 필요한 경우 ULP |
| fused SIMD/FMA | abs+rel + decision exact |
| shader pixel output | per-channel error distribution |
| histogram/statistics | bin/report + downstream decision |
| ICC transform | numeric + perceptual ΔE policy |
| final image | pixels + metadata + dimensions + visual review |
| codec | decoded pixels/metadata; byte identity는 codec contract일 때만 |

“검출 알고리즘은 넉넉하게, 색 변환은 타이트하게” 같은 주관적 한 줄 대신 metric별 수치와 근거를 fixture
policy에 둔다.

## 14. image comparison

한 가지 max-error로 전체 이미지를 판단하지 않는다.

최소 report:

- image dimensions/channel format
- finite/NaN/Inf counts
- max absolute error
- mean absolute error
- RMS error
- percentile errors: p50/p95/p99/p99.9
- pixels over threshold count/fraction
- per-channel summary
- edge/flat/highlight/shadow region summary
- first/worst coordinates
- optional diff image artifact

threshold는 stage와 output bit depth에 따라 다르다. “다른 pixel 비율”을 허용하더라도 crop border 전체가 한
pixel 밀린 geometry bug를 통과시키지 않도록 spatial pattern도 검사한다.

### 14.1 extended range

0 미만/1 초과 float를 clamp한 뒤 비교하지 않는다. clamp stage 이전 fixture는 extended-linear 값을 그대로
검사한다. NaN/Inf는 explicit policy 없이는 즉시 실패다.

### 14.2 premultiplication

straight/premultiplied alpha를 manifest에 기록한다. alpha 0 RGB 값 비교가 의미 있는지 stage마다 결정한다.

## 15. CPU scalar와 SIMD

### 15.1 scalar oracle

- 모든 supported architecture에서 존재
- no global fast-math
- bounds/NaN/denormal policy 명시
- small deterministic fixtures
- optimization-independent result report

scalar가 곧 double-precision mathematical truth라는 뜻은 아니다. product pipeline의 declared float semantics를
구현한다. 필요하면 offline high-precision oracle을 별도로 둔다.

### 15.2 dispatch tests

- forced scalar
- automatic dispatch
- forced supported AVX2/FMA
- forced ARM64 NEON
- unsupported ISA force request rejection
- environment/flag cannot bypass capability check
- same output/tolerance
- base binary startup before dispatch에 advanced instruction 없음

### 15.3 sanitizer와 undefined behavior

MSVC/Windows에서 사용할 수 있는 sanitizer 범위를 실제 toolchain으로 확인한다. 지원하지 않는 조합을 pass로
표시하지 않는다. 별도 clang-cl job이 제품 compiler와 다르면 보조 evidence로 분류한다.

## 16. WARP conformance

### 16.1 검증하는 것

- D3D11 device creation and required feature level
- BGRA/Direct2D interop
- production shader blob load
- constant-buffer layout
- SRV/UAV/RTV ownership
- effect registration
- ROI/halo/tile behavior
- float format support
- render/read-back
- device recreation
- CPU oracle comparison

### 16.2 검증하지 않는 것

- Intel/AMD/NVIDIA/Qualcomm driver correctness
- VRAM/dGPU behavior
- hybrid graphics
- real monitor color
- hardware throughput/power
- vendor-specific compiler optimization

### 16.3 hosted environment

WARP job은 actual adapter type과 feature level을 assert한다. hosted VM이 예상치 않게 hardware/remote adapter를
선택했는데 WARP test로 이름만 붙는 것을 막는다.

OS build가 바뀌어 WARP 결과가 바뀌면 무조건 golden을 갱신하지 않고 runtime/precision/stage report를 비교한다.

## 17. physical GPU conformance

### 17.1 report identity

- GPU description, vendor/device IDs
- adapter LUID privacy-safe hash
- driver version/date
- OS build
- feature level
- required format support
- dedicated/shared memory and budget
- CPU/architecture
- power mode
- D3D debug layer availability
- test build/hash

### 17.2 required scenarios

- cold/warm device creation
- all production shader/effect paths
- 32-bpc and approved 16-bpc intermediates
- tile boundary/halo
- histogram/measurement decision parity
- device removed/recreate
- memory budget pressure
- 50MP/100MP preview/export
- multiple simultaneous jobs under scheduler limits
- CPU/WARP fallback

### 17.3 driver update

driver version 변화는 evidence environment 변화다. 기존 pass를 자동 승계하지 않는다. quick conformance 후 full
scheduled suite를 실행하고 known-bad driver block/diagnostic 정책은 실제 regression 근거가 있을 때만 추가한다.

## 18. UI test strategy

### 18.1 세 층

1. view-model/state unit tests
2. UI Automation 기반 interaction tests
3. real screen visual/manual QA

unit test가 버튼 배치/포커스/고대비를 증명하지 않고 screenshot이 state persistence를 증명하지 않는다.

### 18.2 automation identity

- stable action/view IDs
- localized visible text에 selector 의존 금지
- role/name/value/state
- live regions
- keyboard focus order
- popup/dialog ownership

UI harness는 실제 WinUI 3 process를 launch하고 input을 보낸다. framework는 Windows App SDK/CI 환경에서
spike 후 고정하며, 폐기된 도구 이름을 아키텍처 계약으로 박지 않는다.

### 18.3 visual matrix

- 100/125/150/200% display scale
- 100–200% text scale
- light/dark/high contrast
- compact and large window
- multiple monitor/profile move
- English, 한국어, 日本語, 简体中文, Français, Deutsch
- empty/loading/error/recovery states
- real photos represented by approved non-private fixtures

visual snapshot 차이는 font rasterization/compositor 차이를 이유로 전체 mask하지 않는다. layout geometry와
content hierarchy를 먼저 비교하고 pixel anti-aliasing은 별도 tolerance로 다룬다.

## 19. persistence tests

- clean catalog create
- current macOS canonical fixture import
- schema migration
- migration crash before/after commit
- corrupt/truncated catalog
- missing catalog with existing app data
- WAL/checkpoint/reopen
- backup sequence/integrity
- source move/relink/bookmark replacement
- virtual copy source ownership
- original recycle impact plan
- cache corruption/rebuild
- redirected/network/cloud folder
- disk full/read-only/permission
- long path/Unicode/case behavior

테스트는 `%LOCALAPPDATA%`, `%APPDATA%`, Documents, registry를 temp/test-owned root로 격리한다. 실제 user
Negaflow data root를 발견하면 test가 실패해야 한다.

## 20. image IO와 color tests

### 20.1 WIC/libtiff/LibRaw

- format magic vs extension
- 8/16/float sample formats
- alpha/orientation
- ICC/EXIF/XMP metadata
- tile/strip/BigTIFF
- truncated/oversized values
- decompression bomb budgets
- codec thread/cancellation
- encode temp + atomic publish

### 20.2 color

- ICC v2/v4
- matrix/TRC and LUT profiles
- rendering intents
- black point compensation policy
- malformed profiles
- transform cache key/invalidation
- ColorSync baseline vs LittleCMS/WCS
- monitor profile change
- untagged policy
- extended-linear boundaries

ICC가 parse됐다는 결과는 device-accurate color proof가 아니다. measured monitor/printer evidence는 별도다.

## 21. export and print tests

- ordinary/Quick Export paths
- one and 39-frame batch
- JPEG/TIFF/PNG as supported
- original/custom dimensions
- DPI metadata
- output sharpening stage/order
- ICC embed/convert
- name collisions
- cancel at decode/render/encode/publish
- disk full and permission
- restart journal recovery
- contact sheet geometry/text/profile
- final decoded-pixel and metadata validation

속도를 위해 quality/DPI/ICC를 낮춘 fixture를 performance proof로 쓰지 않는다.

## 22. scanner tests

### 22.1 hosted

- mock is explicit opt-in
- protocol v1/v2 fixtures
- process timeout/output cap
- manifest/trust/path validation
- artifact header/geometry
- WIA property emulator fixtures
- TWAIN state/container emulator fixtures

### 22.2 physical

- actual plugin and driver identity
- requested/applied/header/artifact ROI chain
- all 35mm/120 formats
- 300-DPI preview policy
- 8/16-bit
- polarity
- IR/multi-exposure only if reported
- cancel/unplug/reopen
- x64/ARM64 and x86 adapter route

physical suite가 없으면 UI/protocol feature는 `Compatible Target`이지 `Verified`가 아니다.

## 23. fuzzing and hostile inputs

우선순위:

- image container parsers
- ICC profile parser boundary
- metadata dimensions/offsets/counts
- scanner JSON/NDJSON
- catalog/sidecar serialization
- update feed/manifest
- C ABI input structs

fuzzer 발견 input은 최소화하고 license/privacy-safe regression corpus로 넣는다. crash만 아니라 timeout, memory
budget, integer overflow, path traversal, state-machine violation을 outcome으로 본다.

## 24. fault injection

공통 fault points:

- allocation failure
- disk full/short write/fsync failure
- permission/reparse change
- device removed
- codec failure after partial output
- catalog commit failure
- process crash/hang
- cancellation race
- stale async completion
- corrupted cache
- update crash/power loss

production code에 unrestricted hidden debug bypass를 만들지 않는다. test injection은 compile/test-only boundary와
stable named fault points를 가진다.

## 25. performance tests

### 25.1 PR

hosted runner에서는 severe regression smoke만 수행한다.

- algorithm accidentally O(n²)
- unbounded allocation
- shader compile/load explosion
- query path catastrophic regression

shared VM timing의 작은 변화로 PR을 실패시키지 않는다.

### 25.2 controlled lab

- fixed hardware/driver/OS/power
- warmup and measured iterations
- median/p95 and variance
- fixture/hash/configuration
- CPU/GPU/memory/IO timeline
- threshold applicability

macOS의 environment-aware JSON budget pattern을 가져온다. report environment가 budget applicability와 맞지 않으면
pass/fail이 아니라 invalid evidence다.

### 25.3 benchmark drift

baseline 갱신에는:

- code/algorithm reason
- before/after reports
- quality parity
- hardware identity
- reviewer approval

가 필요하다. 느려진 budget을 단순히 올려서 green으로 만들지 않는다.

## 26. local gate

개념적 진입점:

```text
scripts/win/ci-gate.ps1
  → verify-static
  → restore locked dependencies
  → native build/test
  → managed build/test
  → WARP conformance when available
  → artifact manifest checks
```

환경 flag는 실행 범위를 늘리거나 명시적으로 skip할 수 있지만 default gate의 실패를 success로 바꾸지 않는다.
각 skip은 reason과 missing prerequisite를 출력한다.

CI YAML은 같은 scripts를 호출하고 결과만 병렬화한다. IDE-only build step을 hidden prerequisite로 두지 않는다.

## 27. static contracts

- forbidden macOS imports/API names in Windows tree
- no GPL scanner/SANE linkage in core
- dependency lock and license inventory
- C ABI symbol allowlist
- struct size/offset/calling convention
- HLSL manifest/source/blob hashes
- localization keys/placeholders
- schema versions and generated files
- package payload allowlist
- secret/private corpus patterns
- docs relative links
- stale TODO/open-question status references
- version consistency

static grep alone으로 runtime behavior를 증명하지 않는다. boundary drift를 빠르게 막는 첫 layer다.

## 28. artifacts and reports

PR failure artifact:

- test result XML/log
- minimal diff/report
- D3D info queue messages
- WARP read-back diff for non-private fixtures
- crash dump/symbol link under retention policy
- environment manifest

제외:

- user images/catalog
- scanner serial/full path
- production signing credentials
- licensed private corpus bytes
- unredacted memory dump without access control

artifact retention은 목적별로 정하고 public repository exposure를 고려한다.

## 29. flaky test policy

- automatic blind retry로 green 처리하지 않음
- first failure와 retry 결과 모두 보존
- deterministic seed/report
- quarantine에는 owner, issue, expiry, product risk
- flaky failure가 data corruption/security/release 영역이면 quarantine 금지
- timeout을 늘리기 전에 deadlock/runner load 분리
- physical hardware intermittency도 support risk로 추적

같은 failure가 재시도 성공했다고 해결된 것이 아니다.

## 30. signing/release workflow

protected release environment만 signing authority를 사용한다.

1. required PR/main gates green
2. exact commit release build
3. source/dependency/SBOM/provenance check
4. unsigned candidate functional tests
5. protected signing
6. signature/timestamp revalidation
7. clean x64/ARM64 install/upgrade/rollback
8. hardware/visual/scanner release evidence
9. exact signed hash promotion

signing이 성공해도 hardware/visual/scanner QA가 자동 완료되지 않는다.

## 31. release gate matrix

| gate | PR | main | scheduled | release |
|---|---:|---:|---:|---:|
| static/boundary | 필수 | 필수 | 필수 | 필수 |
| x64 build/unit | 필수 | 필수 | 필수 | 필수 |
| ARM64 native build/unit | 필수 가능 시 | 필수 | 필수 | 필수 |
| CPU scalar/SIMD | 핵심 | full | full | full |
| WARP | 핵심 | full | full | full |
| Intel/AMD/NVIDIA | no | no | full lab | 필수 최신 evidence |
| Qualcomm ARM64 | no | no | full lab | 필수 최신 evidence |
| UI automation | smoke | full | full | full |
| visual/accessibility | no | sampled | scheduled | manual 필수 |
| scanner physical | no | no | scheduled | supported device 필수 |
| package install | smoke | VM | full | signed full |
| performance budget | smoke | report | controlled | release report |

## 32. 증거 등급

| 등급 | 증거 | 허용 주장 |
|---|---|---|
| C0 | compile/static | 빌드 가능 후보 |
| C1 | unit/contract | isolated behavior 통과 |
| C2 | WARP/integration | Windows API/software D3D 경로 통과 |
| C3 | physical GPU/OS | 해당 hardware 조합 통과 |
| C4 | real UI/device | 실제 workflow 통과 |
| C5 | signed clean release | 배포 artifact의 해당 matrix 통과 |

C2를 C3로, automated C3를 click-through C4로 표현하지 않는다.

## 33. 금지

- x64 cross-compile 성공을 ARM64 runtime support로 표시
- WARP pass를 모든 GPU vendor pass로 표시
- NVIDIA T4 하나를 범용 GPU matrix로 표시
- mock scanner pass를 장치 support로 표시
- UI test build 성공을 UI test 실행으로 표시
- screenshot snapshot만으로 accessibility/interaction 완료
- byte-identical codec output을 모든 OS build에 무조건 요구
- tolerance를 넓혀 decision branch 차이를 숨김
- golden 값을 이유 없이 갱신
- private 사용자 이미지/catalog를 CI artifact로 upload
- performance shared-runner noise로 예산을 자동 완화
- package smoke를 signed install QA로 표시
- test retry 성공으로 flaky issue 종료

## 34. 완료 기준

- x64와 ARM64가 native build와 tests를 실행함
- CPU scalar, SIMD, WARP가 같은 versioned fixtures를 비교함
- Intel/AMD/NVIDIA/Qualcomm physical report가 release와 연결됨
- macOS baseline provenance와 approved delta가 추적됨
- exact decision과 tolerant pixel metric이 분리됨
- persistence/original-safety failure injection이 있음
- scanner protocol test와 physical evidence가 분리됨
- WinUI automation과 manual visual/accessibility QA가 모두 있음
- package install/upgrade/rollback이 signed exact artifacts에서 통과함
- local gate와 CI가 같은 commands를 호출함
- report environment가 없거나 맞지 않으면 invalid evidence로 실패함

이 조건 전에는 “Windows CI가 green”을 “Negaflow Windows가 검증됨”으로 표현하지 않는다. CI는 필요한 증거를
조직하는 체계이며, 실제 hardware·색·scanner·사용 경험을 자동으로 대신하지 않는다.
