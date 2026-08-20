# Windows 계측, 프로파일링, GPU 디버깅 설계

기준일: 2026-08-04  
상태: 공통 계측 구조 결정, 도구 version과 vendor plugin은 사용 시점에 고정  
관련 문서:

- [CI와 테스트](ci-and-testing.md)
- [실행 backend](backend-selection.md)
- [GPU portability](gpu-vendor-portability.md)
- [large-image tiling](../06-large-images/image-source-tiling.md)
- [multithreaded export](../07-threading/multithreading-export.md)
- [known failures](known-failure-modes.md)

## 1. 결론

Negaflow Windows는 한 profiler에 의존하지 않는다. 문제 층에 따라 다음 순서로 사용한다.

```text
항상 존재하는 product instrumentation
  ETW + structured stage reports + correlation IDs
        │
        ├── API correctness
        │     D3D11/DXGI/D2D debug layers + InfoQueue
        │
        ├── frame/resource correctness
        │     RenderDoc D3D11 capture
        │
        ├── system-wide latency/memory/IO/GPU scheduling
        │     WPR/WPA + GPUView
        │
        ├── managed/runtime hotspots
        │     Visual Studio profiler + EventPipe/dotnet-trace
        │
        ├── D3D11 hardware timing overview
        │     Visual Studio GPU Usage
        │
        ├── crash/race/replay
        │     WinDbg + dumps + selective TTD
        │
        └── vendor-specific counters
              Intel/AMD/NVIDIA/Qualcomm tools after common evidence
```

PIX는 CPU timing capture에는 사용할 수 있지만 v1 D3D11/Direct2D GPU 분석의 주력 도구가 아니다. Microsoft의
현재 PIX 문서는 GPU 기능을 D3D12 또는 D3D11On12 application 대상으로 설명한다. Negaflow는 PIX를 쓰기 위해
production backend를 D3D11On12로 바꾸지 않는다.

프로파일링의 목표는 “GPU 사용률이 높다” 같은 단일 숫자가 아니라 다음 질문에 답하는 것이다.

- 사용자가 느낀 지연은 어느 transaction/phase인가
- CPU, GPU, memory, storage, codec, catalog, UI thread 중 무엇이 critical path인가
- 정확한 input/recipe/backend/device/driver에서 재현되는가
- optimization 전후 품질과 data-safety contract가 같은가
- x64/ARM64와 Intel/AMD/NVIDIA/Qualcomm/WARP에서 병목이 같은가

## 2. 공식 근거

- [Instrument code with ETW](https://learn.microsoft.com/en-us/windows-hardware/test/weg/instrumenting-your-code-with-etw)
- [Windows Performance Recorder](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/windows-performance-recorder)
- [Windows Performance Analyzer](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/windows-performance-analyzer)
- [Profile DirectX apps with WPR/GPUView](https://learn.microsoft.com/en-us/windows/win32/direct2d/profiling-directx-applications)
- [GPUView overview](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/using-gpuview)
- [Install GPUView](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/installing-gpuview)
- [D3D11 debug layer](https://learn.microsoft.com/en-us/windows/win32/direct3d11/using-the-debug-layer-to-test-apps)
- [DXGI debug interface](https://learn.microsoft.com/en-us/windows/win32/api/dxgidebug/nn-dxgidebug-idxgidebug)
- [Visual Studio GPU Usage](https://learn.microsoft.com/en-us/visualstudio/profiling/gpu-usage?view=vs-2022)
- [Visual Studio profiling tools](https://learn.microsoft.com/en-us/visualstudio/profiling/profiling-feature-tour?view=vs-2022)
- [PIX overview](https://learn.microsoft.com/en-us/windows/win32/direct3dtools/pix/articles/general/pix-overview)
- [RenderDoc repository](https://github.com/baldurk/renderdoc)
- [dotnet-trace](https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-trace)
- [WinDbg overview](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/windbg-overview)
- [Restart Manager](https://learn.microsoft.com/en-us/windows/win32/rstmgr/about-restart-manager)

## 3. 도구 역할과 한계

| 도구 | 가장 잘 답하는 질문 | Negaflow 용도 | 한계 |
|---|---|---|---|
| ETW/TraceLogging | app/system event가 언제 일어났나 | 모든 operation correlation | instrumentation 설계 필요 |
| WPR/WPA | CPU scheduling, IO, faults, memory, system timeline | end-to-end 병목 | trace가 크고 분석 숙련 필요 |
| GPUView | CPU submission과 GPU DMA/scheduling 관계 | stall, queue, present, contention | shader 내부 source hotspot 아님 |
| D3D11 debug layer | API/resource misuse인가 | 개발·CI correctness | 성능 측정 overhead 큼 |
| D2D debug level | D2D usage/warnings | effect/device-context 오류 | Release benchmark에 끔 |
| RenderDoc | 특정 D3D11 frame/resource/shader 상태 | texture, pass, draw/dispatch read-back | 고수준 D2D graph 의미를 자동 복원하지 않음 |
| VS GPU Usage | D3D10/11/12 GPU timing overview | x64 hardware timing/CPU-GPU view | Direct2D 자체 미지원, ARM64 VS Graphics Diagnostics 미지원 |
| PIX | CPU capture; D3D12/11on12 GPU | 보조 CPU 분석 | native D3D11 baseline GPU 주력 아님 |
| dotnet-trace | managed runtime/events | GC, allocation, async, managed stacks | native/kernel/GPU 전체 timeline 아님 |
| WinDbg/dump/TTD | crash, hang, state history | rare race/device-removal analysis | recording overhead/storage/privacy |
| vendor tools | hardware counters/compiler details | common trace로 좁힌 뒤 | vendor별 지원/API/version 편차 |

하나의 도구가 “지원하지 않음”을 전체 플랫폼 한계로 확대하지 않는다. 예를 들어 Visual Studio GPU Usage가
Direct2D를 직접 이해하지 못해도 D3D11 debug, RenderDoc, ETW/GPUView, app markers로 분석할 수 있다.

## 4. build mode를 분리한다

### 4.1 correctness-debug

- D3D11 debug layer
- D2D information debug level
- DXGI live-object reporting
- strict asserts and validation
- symbols
- small deterministic scenario

이 결과는 API correctness에 쓰고 performance budget에 쓰지 않는다.

### 4.2 profiled Release

- Release optimization
- PDB/symbols 분리 보존
- debug layer off
- ETW markers on
- optional detailed counters/markers
- production shader blobs
- same installer/runtime layout when possible

병목 분석의 기본이다.

### 4.3 shipping Release

- low-overhead operational ETW events
- privacy-safe diagnostics
- detailed per-tile/pixel events off
- crash dump policy
- support-triggered bounded capture

profiling용 code path가 shipping semantics를 바꾸지 않게 한다.

## 5. ETW provider 설계

### 5.1 provider 분리

과도하게 많은 provider를 만들지 않고 책임별 keyword를 둔다.

```text
Negaflow.Core
  AppLifecycle, Operation, Scheduler, Memory, Error

Negaflow.Render
  Decode, Develop, Measurement, D3D, D2D, Tile, Export, Print

Negaflow.Storage
  Catalog, Sidecar, Cache, Backup, Publish, Update

Negaflow.ScannerHost
  Plugin, Process, Protocol, Artifact
```

C#과 C++ event를 같은 operation ID로 연결한다. provider GUID/name, event IDs, field type은 versioned manifest로
관리한다.

### 5.2 operation identity

모든 user-visible transaction은 128-bit random/collision-safe operation ID를 가진다.

- import ID
- preview/render request ID
- export job/batch/file ID
- print job/page ID
- scanner session/request ID
- catalog transaction ID
- update transaction ID

source path, filename, scanner serial을 ID로 쓰지 않는다. support bundle에서는 ID가 session 밖의 사용자를
추적하지 않게 한다.

### 5.3 span event

```text
OperationStart
  operationId, parentId, kind, revision, backend, priority

StageStart
  operationId, stageId, tile/region summary, input bytes

StageStop
  operationId, stageId, status, duration, output bytes, counters

OperationStop
  operationId, status, terminal reason, totals
```

start/stop 쌍이 없어도 process crash에서 분석 가능하도록 event sequence와 phase를 포함한다. duration을 double
seconds와 integer ticks로 중복 저장하지 말고 units를 고정한다.

### 5.4 event level

| level | 예시 | shipping 기본 |
|---|---|---|
| error | data safety failure, device removed, corrupt artifact | on |
| warning | fallback, budget pressure, retry | on |
| info | operation start/stop, backend selection | on, 낮은 빈도 |
| verbose | tile/pass/allocation details | off |

pixel/scanline마다 ETW event를 만들지 않는다. summary counter와 sampled verbose trace를 사용한다.

## 6. stage taxonomy

공통 stage 이름은 macOS/Windows 보고서를 비교할 수 있게 안정적으로 둔다.

### import/decode

- probe
- open
- metadata
- decodePreview
- decodeFull
- orientation
- sourceRegistration
- thumbnail
- catalogCommit

### develop

- parameterSnapshot
- sourceTileAcquire
- filmBase
- inversion
- tone
- colorAdjustments
- detail
- defectMask
- defectRender
- outputColor
- present

### measurement

- histogramPartial
- histogramMerge
- percentile
- autoParameters
- decisionApply

### export

- plan
- prepareFirstFile
- decode
- render
- resize
- outputSharpen
- colorTransform
- encode
- metadata
- fsync
- atomicPublish
- catalogCommit

### scanner

- pluginVerify
- detect
- capabilities
- open
- warmup
- preview
- RGB
- IR
- transfer
- artifactVerify
- publish
- close

## 7. marker 규칙

- stable ASCII stage ID와 localized UI text 분리
- one span per meaningful scheduling unit
- tile coordinate는 verbose/sample mode에서만
- width/height/format은 numeric, path는 제외
- byte counts는 exact integer
- duration은 consumer 계산을 우선
- cancellation/failure/skip를 별도 status
- cache hit/miss와 reason
- backend/adapter identity는 privacy-safe key + separate local details
- revision/session ID로 stale result를 분석

“render” 한 span 안에 decode, ICC, encode, publish를 숨기지 않는다.

## 8. CPU profiling

### 8.1 WPR/WPA

system-wide critical path를 본다.

- sampled CPU stacks
- context switches/ready time
- thread scheduling/priority
- disk/file IO
- page faults
- memory commit/working set
- GPU kernel events
- app ETW spans

PDB와 symbol server path를 build ID로 연결한다. symbols가 없어서 모든 native stack이 address로만 보이는 trace를
성능 근거로 승인하지 않는다.

### 8.2 Visual Studio CPU Usage

좁은 재현에서 managed/native hotspot과 call tree를 빠르게 확인한다. instrumentation/profiler overhead를
benchmark 값과 섞지 않는다.

### 8.3 EventPipe/dotnet-trace

다음에 유용하다.

- managed sampled thread stacks
- GC collections
- allocation events
- exception/Task/network events
- headless/remote capture

현재 `dotnet-trace` profile 이름과 sampling behavior는 version에 따라 바뀔 수 있으므로 command와 tool version을
capture manifest에 기록한다. managed trace만으로 native engine 또는 kernel/GPU 병목을 결론 내리지 않는다.

### 8.4 CPU counter 해석

총 CPU %만 보지 않는다.

- UI thread ready/running/wait
- render queue utilization
- worker pool occupancy
- thread creation
- lock contention
- migration across cores/NUMA if relevant
- cycles/instructions/cache misses when supported
- x64 AVX2/FMA vs scalar
- ARM64 NEON vs scalar
- thermal/power mode

## 9. D3D11/D2D correctness

### 9.1 D3D11 debug layer

debug device flag를 지원 SDK layer가 설치된 개발/test 환경에서만 활성화한다. layer가 없어서
`DXGI_ERROR_SDK_COMPONENT_MISSING`이 나오는 것을 product GPU unsupported로 오인하지 않는다.

InfoQueue policy:

- corruption/error는 test failure
- warning은 allowlist 없이 기본 조사
- known benign message suppress에는 message ID, reason, removal condition
- operation ID/stage와 함께 drain
- duplicate flood cap

### 9.2 D2D debug

Direct2D factory debug level을 debug/diagnostic build에서 사용한다. factory type과 multithread guard 사용이 맞는지
확인한다. 경고를 무시하고 performance capture부터 하지 않는다.

### 9.3 live objects

shutdown test에서 DXGI/D3D live-object report를 수집한다.

- device/context
- texture/buffer/view
- swap chain
- query
- D2D bitmap/effect/brush

intentional process-lifetime singleton은 allowlist reason을 가진다. “OS가 정리한다”는 이유로 per-operation leak을
무시하지 않는다.

## 10. RenderDoc

### 10.1 주 용도

- D3D11 resource creation/bindings
- shader bytecode와 constant values
- texture format/dimensions/subresources
- SRV/UAV/RTV conflicts
- dispatch/draw ordering
- render target contents
- CPU-to-GPU uploads와 read-back resources
- unexpected intermediate/pass
- frame diff 원인

RenderDoc는 공식 repository가 D3D11/D3D12/Vulkan 등을 지원하는 frame-capture debugger라고 설명한다.
capture version을 고정하고 release notes의 vendor-specific known issue를 확인한다.

### 10.2 Direct2D 해석 한계

Direct2D는 D3D11 위에서 동작하므로 underlying GPU activity/resource를 capture할 수 있지만 RenderDoc가
Negaflow의 high-level D2D effect graph, ROI mapping, color intent를 자동으로 설명해 주는 것은 아니다.

따라서 app marker/manifest와 함께 본다.

- logical effect/stage ID
- shader blob hash
- property snapshot hash
- expected input/output resource
- precision/color-space contract

### 10.3 capture 규칙

- approved non-private fixture
- one bounded operation/frame
- exact app/RenderDoc/driver version
- debug markers
- no production user catalog/image
- capture artifact access control
- capture overhead로 timing 판단 금지

## 11. Visual Studio GPU Usage

Microsoft 문서는 GPU Usage가 D3D10/11/12 app을 지원하고 CPU start, GPU start, GPU duration 등을 보여준다고
설명한다. Negaflow D3D11 hardware path의 high-level timing overview에 유용하다.

주의:

- Direct2D API 자체는 지원 대상으로 명시되지 않음
- GPU/driver timing instrumentation 필요
- unattributed events가 생길 수 있음
- ARM64 Visual Studio에서 Graphics Diagnostics 미지원이라는 현재 문서 제한
- tool 아래 실행 overhead

따라서 x64 lab에서 bottleneck 분류에 쓰고 ARM64 release evidence의 유일한 profiler로 두지 않는다.

## 12. PIX

### 12.1 허용 용도

- any Windows app 대상 CPU timing capture
- function summary/call graph/memory/file IO 같은 지원 기능
- future D3D12 optional tier가 실제 도입될 때 GPU capture

### 12.2 v1 GPU 주력이 아닌 이유

current PIX documentation은 GPU capability가 D3D12 또는 D3D11 via D3D11On12에 동작한다고 명시한다.
Negaflow baseline은 native D3D11 + Direct2D이며 D3D11On12를 도입하지 않는다.

금지:

- PIX GPU capture를 위해 production backend를 11on12로 변경
- capture용 backend 결과를 baseline performance로 사용
- PIX가 capture 못 했다는 이유로 D3D11 architecture를 폐기

## 13. WPR/WPA와 GPUView

### 13.1 WPR profile

Negaflow custom WPR profile 후보:

- CPU sampling/stacks
- context switch/dispatcher
- disk/file IO
- virtual memory/page faults
- heap profile only when needed
- DirectX graphics kernel/GPU events
- Negaflow ETW providers
- .NET runtime provider selected level

항상 모든 high-volume provider를 켜지 않는다. 목적별 profile을 둔다.

```text
negaflow-interaction.wprp
negaflow-export.wprp
negaflow-memory.wprp
negaflow-gpu.wprp
negaflow-startup.wprp
```

### 13.2 WPA

같은 timeline에서 다음을 correlation한다.

- app ETW stage
- CPU utilization and stacks
- ready/thread waits
- disk IO
- hard faults
- memory commit/working set
- GPU queue
- present/compositor
- GC pause/allocation

한 profiler의 aggregate table보다 critical path를 우선한다.

### 13.3 GPUView

GPUView는 DirectX graphics kernel이 기록한 command buffer submission, resource event, driver timing,
context switches, page faults 등을 ETL에서 본다.

주요 질문:

- CPU가 GPU에 늦게 제출하는가
- GPU가 다른 process/context에 의해 지연되는가
- queue가 비는가 또는 과도하게 쌓이는가
- present/vsync가 병목인가
- resource paging과 memory pressure가 있는가
- copy/read-back가 compute/render를 serialize하는가

GPUView trace는 수백 MB 이상이 될 수 있으므로 30–60초 이내 bounded reproduction, 충분한 disk, retention
cleanup을 사용한다.

## 14. memory 측정

### 14.1 process/system

동일 timeline에서:

- private bytes
- working set/private working set
- committed bytes
- peak working set/commit
- handle/thread count
- system available physical memory
- system available commit/commit limit
- page faults, hard faults, reads/writes

한 counter로 “메모리 부족”을 정의하지 않는다.

### 14.2 managed

- GC heap size/generation
- allocation rate
- LOH/POH when relevant
- collection count/pause
- pinned objects
- finalizer queue
- native interop ownership and SafeHandle count

managed heap이 작아도 native pixel buffers와 D3D resources가 클 수 있다.

### 14.3 native CPU

- image/tile buffers
- decoder/encoder allocations
- lcms transform/cache
- SQLite page/cache
- native heap fragmentation
- scratch arenas
- allocation lifetime by operation

### 14.4 GPU

- DXGI local/non-local `Budget`
- `CurrentUsage`
- reservation
- tile cache logical bytes
- in-flight reservation
- source/intermediate/mask/swapchain/export resources
- eviction/recreate counts

UMA에서 shared memory를 physical RAM과 GPU memory로 단순 이중 합산하지 않는다. OS budgets와 process/system
commit을 함께 본다.

### 14.5 leak test

```text
open fixture
perform operation
close/release
quiesce
repeat N times
compare retained resources after warm plateau
```

cache warm-up과 leak을 구분한다. cache capacity, eviction, reconstruct cost를 report한다.

## 15. storage와 file IO

WPA/File IO, app spans, codec reports로 다음을 구분한다.

- source read
- decode read amplification
- temp/staging writes
- TIFF/JPEG compression
- cache read/write
- SQLite WAL/checkpoint/fsync
- backup copy/hash/read-back
- export atomic publish
- update download/install

IO bytes가 많다는 이유만으로 불필요하다고 결론 내리지 않는다. durability를 위한 flush/read-back와 accidental
duplicate copy를 call stack/stage로 구분한다.

환경:

- NVMe/SATA/external USB
- NTFS local
- redirected/network folder
- OneDrive placeholder/hydration if in scope
- antivirus on/off 비교는 보안 baseline을 끄라는 결론이 아니라 원인 분리용

## 16. startup profiling

### cold

- process creation
- WinUI/.NET initialization
- Windows App SDK self-contained load
- native DLL load
- engine/device creation
- settings/catalog open
- first Library query
- first visible frame

### warm

- OS file cache 영향
- existing shader/cache/catalog
- second window/app relaunch

cold/warm을 같은 그래프 평균으로 섞지 않는다. updater의 first launch health check와 일반 startup도 분리한다.

## 17. interaction profiling

### slider/curve

event chain:

```text
pointer input
  → UI state update
  → parameter snapshot/revision
  → native enqueue
  → stale work cancel/supersede
  → tile render
  → present
```

측정:

- input-to-enqueue
- queue wait
- render CPU/GPU
- present
- dropped/superseded requests
- cache hit/miss
- UI thread longest task

“render 8 ms”만으로 interaction이 빠르다고 결론 내리지 않는다. queue wait와 present까지 포함한다.

### zoom/pan

- visible ROI calculation
- source/tile availability
- cache/prefetch
- upload
- compose/present
- frame pacing
- memory budget trim

## 18. export profiling

첫 파일 준비와 batch steady state를 분리한다.

- source open/decode
- graph compile/cache
- first tile/time to progress
- render tiles
- GPU↔CPU transfer
- ICC
- encode/compress
- metadata
- fsync/publish
- catalog commit
- next-file overlap

39장 single exports와 contact sheet를 실제 product quality/DPI/ICC로 측정한다. progress 0% spinner 문제는
first-file preparation과 display throttling을 별도 span으로 본다.

## 19. scanner profiling

scanner speed는 hardware exposure/transport와 host overhead를 나눈다.

- plugin verification/launch
- detect/capabilities
- device open
- lamp warm-up
- preview exposure/transfer
- full RGB exposure/transfer
- IR
- artifact fsync/hash/decode validation
- catalog registration
- cancel request → backend return/process kill

adapter stdout progress가 없으면 host가 가짜 정밀 progress를 만들지 않는다. phase timestamp만 기록한다.

WIA/TWAIN raw diagnostic는 별도 protected bundle이며 vendor/model/serial privacy를 처리한다.

## 20. update/installer profiling

- feed check
- download and resume
- SHA-256/AuthentiCode verification
- catalog checkpoint/backup
- app shutdown
- MSI transaction
- first healthy launch
- migration
- rollback

서명/backup 검증이 느리다고 생략하지 않는다. 다운로드와 사용 중 background checkpoint scheduling으로 사용자
대기만 줄일 수 있는지 본다.

## 21. device-lost와 crash

### 21.1 device removed

기록:

- adapter/device/driver identity
- last operation/stage/shader
- device removed reason HRESULT
- memory budget/usage
- outstanding work/resource counts
- retry count
- WARP/CPU fallback result
- D3D debug messages in diagnostic build

D3D12 DRED를 D3D11 baseline tool처럼 쓰지 않는다.

### 21.2 dumps

- minidump type policy
- symbols/source build ID
- exception/context/thread stacks
- managed/native mixed stack
- privacy review
- original pixel buffer inclusion risk

full dump는 이미지 pixel, file path, profile data를 포함할 수 있으므로 자동 public upload하지 않는다.

### 21.3 WinDbg/TTD

WinDbg는 native ARM64를 포함한 crash/hang 분석과 TTD를 제공한다. TTD는 rare race/state corruption에
선택적으로 쓴다.

- bounded scenario
- approved fixture
- recording overhead 고려
- trace size/retention/access control
- source/symbol exact match
- production user data recording 금지

TTD 재생에서 보인 timing을 performance 수치로 사용하지 않는다.

## 22. vendor tools

common ETW/RenderDoc/debug evidence로 범위를 좁힌 뒤 사용한다.

| vendor | 후보 질문 |
|---|---|
| Intel | EU occupancy, sampler/cache, Intel iGPU bottleneck |
| AMD | wave/cache/memory behavior, driver-specific stall |
| NVIDIA | shader/throughput/memory, optional CUDA comparison |
| Qualcomm | ARM64 Adreno/UMA/power behavior |

tool/API support matrix는 release마다 바뀐다. 사용 전 current official documentation에서 D3D11, device,
driver, ARM64 support를 확인한다. 한 vendor tool의 metric 이름을 공통 product telemetry schema로 만들지 않는다.

## 23. capture manifest

모든 성능 evidence에:

```text
schemaVersion
scenario and fixture hash
app version/build/commit
configuration
OS build
architecture
CPU model/core count
memory
GPU/driver/feature level
display/power state
backend
tool/version/capture settings
warmup/measured iterations
operation IDs
input dimensions/format without private path
recipe/profile hashes
start/end time
trace/report hashes
known perturbations
```

필드가 빠진 오래된 report는 trend 참고일 수 있지만 release budget pass 증거로 쓰지 않는다.

## 24. benchmark report

scenario result:

- status and failure reason
- iteration count
- p50/p95/min/max
- coefficient/variance measure
- stage durations
- throughput
- CPU time/wall time
- peak working set/private/commit
- GPU budget/current peak
- IO bytes/latency
- cache hits/misses
- cancellation/progress latency
- quality/conformance report hash

성능과 품질 report를 hash로 연결한다. 더 빠른 artifact가 정확한 output이 아니면 optimization pass가 아니다.

## 25. baseline과 예산

### 25.1 applicability

budget은 다음이 맞을 때만 적용한다.

- architecture
- hardware class
- minimum memory
- OS/driver range
- configuration
- fixture version
- power mode

다르면 pass가 아니라 `invalid evidence` 또는 다른 budget class다.

### 25.2 regression 판단

- multiple measured iterations
- environment noise 확인
- absolute product SLA와 relative baseline 둘 다
- p95와 peak memory
- quality parity
- before/after trace

한 run의 평균 차이로 optimization을 승인하지 않는다.

### 25.3 baseline 갱신

- 원인과 code change
- old/new evidence
- quality report
- hardware identity
- reviewer
- budget 변경 이유

느려진 값을 맞추려고 숫자만 높이지 않는다.

## 26. privacy와 security

기본 event에서 제외:

- absolute file path와 filename
- username/SID
- image pixels/thumbnail
- scanner serial
- full ICC profile bytes
- update/plugin credentials
- raw command line with user paths

대체:

- per-bundle random salt hash
- dimensions/format/byte counts
- product-owned stable enum
- signer/profile/file content hash when non-sensitive and needed

ETL, dump, RenderDoc capture에는 low-level data가 포함될 수 있으므로 자동 redact 가능하다고 가정하지 않는다.
수집 전에 consent와 scope를 보여주고 protected retention을 사용한다.

## 27. 도구 overhead

- debug layer capture를 benchmark로 사용 금지
- RenderDoc/TTD 아래 timing 사용 금지
- ETW verbose event overhead 측정
- heap stack tracing은 memory scenario에만
- GPUView verbose trace는 짧게
- antivirus/thermal/background process 기록
- profiler 없는 control run

도구를 켜서 bug가 사라지거나 생기는 경우 그것 자체를 evidence로 기록한다.

## 28. symptom playbook

### UI slider가 끊김

1. app operation spans
2. WPR CPU scheduling/UI thread
3. queue supersession/cache
4. GPUView/VS GPU Usage
5. RenderDoc resource/pass if GPU bottleneck

### export 0%가 오래 지속

1. first-file preparation spans
2. decode/graph/ICC/encode separation
3. file IO and hard faults
4. progress throttling events
5. 39-frame steady state comparison

### memory가 계속 증가

1. logical cache counters
2. managed GC/EventPipe
3. native heap/working set/commit
4. DXGI budgets/live objects
5. repeat-close plateau test

### GPU device removed

1. removed reason and last stage
2. debug layer reproduction
3. memory budget timeline
4. RenderDoc only if capture itself stable
5. vendor tool/driver matrix
6. WARP/CPU recovery

### 색이 다름

1. input/profile/intent/working-space manifest
2. stage numeric reports
3. resource formats/precision
4. ICC transform output
5. monitor/output measurement

GPU utilization부터 보지 않는다.

### scanner가 멈춤

1. host/plugin phase timeline
2. process/stdout/stderr caps
3. backend owner thread state
4. transfer/cancel deadline
5. USB/device/driver evidence
6. process kill/reopen

## 29. 흔한 오판

- CPU 100%이므로 CPU-bound라고 결론: GPU wait 중 worker/spin일 수 있음
- GPU 100%이므로 GPU 최적화: queue에 긴 low-value work가 쌓였을 수 있음
- working set 감소이므로 해결: commit/leak/cache thrash가 남을 수 있음
- hard faults 낮으므로 memory pressure 없음: UMA/budget/commit/standby reclaim 가능
- RenderDoc capture가 정상이라 race 없음: capture가 timing을 바꿈
- WARP가 빠르므로 hardware GPU 불필요: workload/driver/size가 다름
- hardware가 빠르므로 CPU fallback 불필요: device failure와 작은 ROI는 별도
- PIX capture 불가라 architecture 문제: v1 backend와 PIX GPU scope가 다름
- profile 존재라 color accurate: 측정 없음
- scanner transfer가 완료라 exact ROI: header/artifact/read-back 검증 필요

## 30. 자동화

자동 report script 후보:

- scenario launch and fixed seed
- ETW provider start/stop
- stage JSON extraction
- process/memory counters
- DXGI adapter/budget report
- output quality hash/report
- environment manifest
- budget applicability check

WPR/GPUView/RenderDoc의 모든 분석을 CI에서 자동 판정하려 하지 않는다. 정형 metric은 자동화하고 complex trace는
human analysis artifact로 연결한다.

## 31. hardware lab 운영

- machine image와 driver change log
- automatic update maintenance window
- fixed power plan and thermal stabilization
- display/sleep/background app control
- clean boot/reboot protocol
- local artifact cache and source hash
- exact signed/unsigned candidate policy
- machine health baseline
- quarantined machine if unexpected drift

self-hosted runner가 개발자의 일반 workstation과 섞여 interactive workload 영향을 받지 않게 한다.

## 32. 완료 기준

- stable ETW provider/event/stage schema가 C#과 C++을 연결함
- operation ID로 UI input부터 publish까지 critical path를 찾을 수 있음
- D3D11/D2D debug layer warning/error gate가 있음
- RenderDoc capture와 logical shader/effect manifest가 연결됨
- WPR/WPA/GPUView profile이 CPU/GPU/memory/IO를 함께 수집함
- managed EventPipe와 native/system trace 역할이 분리됨
- PIX를 쓰기 위해 D3D11On12를 도입하지 않음
- x64와 ARM64에서 사용 가능한 도구 차이를 문서화함
- Intel/AMD/NVIDIA/Qualcomm/WARP report가 같은 scenario IDs를 사용함
- performance report와 quality report hash가 연결됨
- user image/path가 기본 trace에 들어가지 않음
- capture overhead 없는 control run이 있음
- symptom playbook으로 재현부터 원인까지 증거를 연결함

도구를 설치했거나 capture 한 장을 얻은 것은 완료가 아니다. 정확한 scenario, 환경, stage, output quality,
before/after 결과가 연결될 때만 성능 판단 근거가 된다.
