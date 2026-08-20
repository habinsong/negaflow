# 멀티스레드 렌더·현상·내보내기 설계

조사 기준일: 2026-08-04  
대상: Windows 11, WinUI 3, C# 셸 + C++20 네이티브 엔진  
macOS 근거: batch export, source materialization, cleaned-raw coalescing, thumbnail persistence,
`Chromabase` image pipeline과 대응 XCTest

## 결론

Windows판은 “가능한 모든 작업을 병렬화”하지 않습니다. **변경 가능한 상태의 소유자를 한 곳으로
고정하고, 독립적인 immutable tile·file 작업만 bounded concurrency로 실행**합니다.

기준 구조:

```text
WinUI UI thread / DispatcherQueue
        │ commands, immutable snapshots
        ▼
Application job coordinator
        ├── native CPU scheduler ── decode / statistics / SIMD kernels
        ├── interactive GPU queue ─ D3D11 immediate context + DXGI present
        ├── export GPU queue ────── optional separate device/context per policy
        ├── codec lane(s) ───────── one codec graph/handle per artifact
        ├── ordered writer ──────── one writer per output file
        └── persistence lane ────── journal/catalog/cache serialized commits
```

핵심 결정:

- UI thread는 pixel decode, hash, ICC, encode, file materialization을 하지 않습니다.
- D3D11 immediate context는 한 engine queue가 직렬 소유합니다.
- `ID3D11Multithread` 보호를 켜 여러 worker가 같은 immediate context를 난사하지 않습니다.
- Direct2D factory의 multithread 보호가 D3D/DXGI 호출까지 자동 보호한다고 가정하지 않습니다.
- 하나의 Direct2D target을 여러 device context가 동시에 render하지 않습니다.
- export는 hardware D3D11, CPU SIMD, WARP 중 job 단위로 선택합니다.
- WARP는 CI·conformance·fallback에 중요하지만 모든 실제 export의 고정 기본값은 아닙니다.
- CUDA는 NVIDIA 전용 선택적 stage accelerator이며 scheduler의 기준 경로가 아닙니다.
- codec·LittleCMS·libtiff·LibRaw 객체의 수명과 thread ownership을 명시합니다.
- queue마다 byte budget과 backpressure가 있으며 task 수만 제한하지 않습니다.
- cancellation, source generation, frame/revision을 최종 적용·게시 직전에 다시 확인합니다.

---

## 1. 현재 macOS 제품에서 보존할 동시성 의미

Swift concurrency의 구현 방식을 그대로 이식하지 않고 사용자-visible 계약을 옮깁니다.

### 1.1 batch export

현재 macOS batch는 다음 특성이 있습니다.

- source를 먼저 materialize하여 cloud placeholder로 인한 중간 정지를 줄임
- 최대 동시 file 수를 bounded 값으로 제한
- worker별 고정 stride가 아니라 공유 cursor에서 다음 항목을 가져감
- 한 장이 느려도 다른 worker가 예약된 후속 항목 때문에 놀지 않음
- pause/resume/cancel 상태
- item별 running/completed/failed와 retryable state
- batch checkpoint를 durable하게 갱신

현재 구현의 `maximumConcurrent: 2`는 Windows의 영구 상수가 아니라 출발 reference입니다. Windows에서는
file 수뿐 아니라 각 job의 예상 peak RAM/VRAM·source volume·codec 특성을 보고 admission합니다.

### 1.2 source snapshot과 generation

현재 export는 background writer를 시작하기 전에 immutable snapshot과 source identity를 만들고, render 뒤와
catalog commit 전에 source/frame ownership을 다시 확인합니다.

Windows도 다음 순서를 유지합니다.

1. UI/application state에서 immutable `ExportSnapshot` 생성
2. source file identity/content generation capture
3. native job에 snapshot 전달
4. staged artifacts 생성·검증
5. source generation과 job ownership 재확인
6. journal commit intent
7. catalog transaction
8. artifact publish/final acknowledgement

background worker가 live UI model을 읽으며 현상하면 안 됩니다.

### 1.3 persist와 thumbnail

현재 제품은 cleaned-raw persist, thumbnail seed, catalog IO를 UI에서 분리하고 동일 frame의 이전 task를
취소/coalesce합니다. Windows에서도 다음을 별도 logical queue로 둡니다.

- foreground develop/export
- cleaned-raw materialization/persist
- thumbnail/mip generation
- catalog/journal serialization
- source hashing/materialization

background cache 작업이 export나 active viewport를 굶기지 않게 priority와 budget을 분리합니다.

### 1.4 결함 검출

현재 일부 결함 연산은 tile/group 단위 병렬성을 사용하지만 결과 accumulator와 component merge를 별도로
관리합니다. Windows에서도 hot loop 병렬화와 결과 결정성을 분리합니다.

- 독립 tile compute는 병렬
- shared result mutation은 금지 또는 작은 synchronized collector
- merge는 canonical tile order
- component ID는 completion order가 아니라 stable geometry key

---

## 2. thread domain과 소유권

### 2.1 UI thread

WinUI 3 UI thread가 소유합니다.

- XAML visual tree
- observable presentation state
- keyboard/focus/menu/dialog
- `SwapChainPanel` attach/detach와 logical sizing request
- small progress event 적용
- 사용자 command validation

UI thread가 하지 않는 일:

- WIC/LibRaw full decode
- libtiff encode
- LittleCMS pixel transform
- source full hash
- SQLite long transaction
- GPU fence 대기
- process/plugin synchronous wait
- native worker completion을 blocking `.Wait()`/`.Result`로 기다림

COM을 쓰는 UI thread는 일반적으로 STA와 message pump를 유지합니다. STA에서 raw wait로 오래 막으면 COM
message 전달과 UI가 교착될 수 있으므로 async continuation과 DispatcherQueue를 사용합니다.

### 2.2 application coordinator

C# application layer가 소유합니다.

- frame/job/revision 상태 기계
- export plan과 destination reservation
- pause/resume/cancel intent
- scanner plugin process lifecycle
- catalog transaction과 export journal 연결
- native job terminal event를 domain state에 적용

native callback thread에서 ViewModel을 직접 변경하지 않습니다. bounded event queue를 drain한 뒤
`DispatcherQueue`로 UI thread에 전달하고 owner/revision을 다시 확인합니다.

### 2.3 native CPU scheduler

C++ 엔진 내부 전용 scheduler가 소유합니다.

- decode preparation
- CPU scalar/SIMD kernels
- per-tile statistics
- ICC transform
- hash/verification candidates
- encode preparation

`.NET ThreadPool`과 native pixel worker를 같은 pool로 합치지 않습니다. 긴 CPU kernel이 managed async
continuation과 UI workflow를 포화시키지 않게 합니다.

구현은 C++20 `std::jthread` 기반 fixed workers 또는 Windows private thread pool을 spike로 비교할 수 있지만,
제품 계약은 다음입니다.

- 명시적 최소/최대 worker 수
- queue별 priority/fairness
- cooperative stop token
- byte reservation admission
- worker 종료와 DLL unload 순서
- uncaught exception이 ABI를 넘지 않음

### 2.4 GPU queues

각 D3D11 immediate context는 한 logical render queue가 소유합니다.

- interactive device/context: 화면 표시와 latency-sensitive preview
- export device/context: 필요하면 별도 hardware/WARP device로 offline work

두 번째 device는 무조건 만드는 것이 아닙니다. single device에서 priority/fence가 충분한지, 별도 device가
driver·memory overhead 대비 UI isolation을 개선하는지 측정합니다.

공통 금지:

- worker 여러 개가 immediate context를 동시에 호출
- DXGI `Present`를 context owner가 아닌 임의 thread에서 호출
- mutable render target을 preview와 export가 동시에 사용
- device generation을 넘긴 texture 재사용

### 2.5 codec lane

codec object graph의 thread affinity를 단순화합니다.

- WIC decoder/frame/converter/encoder graph: 생성한 codec job 또는 worker가 소유
- libtiff `TIFF*`: 한 handle을 한 lane이 소유
- LibRaw object: 한 decode job/worker가 소유
- output stream/file handle: 한 writer가 소유
- metadata builder: artifact snapshot에서 불변 입력만 받음

여러 파일은 병렬화할 수 있지만 같은 codec handle에 동시 호출하지 않습니다.

### 2.6 persistence lane

파일 encode가 병렬이어도 durable state 변경은 순서를 가집니다.

- export journal state transition
- catalog transaction
- thumbnail/cache index
- settings write
- backup marker

SQLite serialized mode에 모든 문제를 떠넘기지 않습니다. application-level transaction owner가 논리 순서와
idempotency를 보장합니다.

---

## 3. COM apartment 계약

### 3.1 UI

window/message-loop thread는 STA입니다.

```text
CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE)
```

WinUI/Windows App SDK가 초기화를 소유하는 실제 bootstrap과 중복 호출 계약은 구현 spike에서 확인합니다.
이미 다른 mode로 초기화된 thread를 임의로 바꾸지 않습니다.

### 3.2 native workers

background worker가 WIC 같은 COM API를 직접 사용하면 각 thread가 COM을 초기화합니다.

```text
CoInitializeEx(nullptr, COINIT_MULTITHREADED)
...
CoUninitialize()  // 성공한 초기화와 균형
```

규칙:

- COM interface pointer를 apartment 사이에 raw 복사하지 않음
- agile/thread-safe 계약이 확인되지 않은 object를 worker 사이에 공유하지 않음
- worker-local graph를 job 종료 전에 release
- `RPC_E_CHANGED_MODE`를 성공으로 취급하지 않음
- callback이 들어올 수 있는 STA에서 message pump 없는 blocking wait 금지

### 3.3 WIC factory

WIC factory 자체 재사용 가능성과 개별 codec component의 threading model은 분리해 봅니다. 안전한 v1 기준은:

- engine 수명 factory 또는 검증된 factory provider는 재사용 가능
- decoder/frame/converter/encoder/stream graph는 job-local
- third-party WIC codec은 기본 allowlist에 포함하지 않음
- codec metadata에 threading model이 있어도 실제 concurrent handle 테스트 없이 같은 object 공유 금지

---

## 4. Direct2D multithreading의 정확한 의미

### 4.1 multithreaded factory

`D2D1_FACTORY_TYPE_MULTI_THREADED` factory에서 만들어진 Direct2D object는 Direct2D API 호출에 대한
내부 보호를 받을 수 있습니다. 그러나 호출은 직렬화될 수 있고, 이것만으로 application snapshot의
atomicity가 생기지 않습니다.

즉 다음 두 문장은 다릅니다.

- API data race를 막는다.
- 하나의 frame이 일관된 text/brush/effect/parameter snapshot으로 그려진다.

두 번째는 앱이 context별 mutable state와 immutable request snapshot을 갖춰야 합니다.

### 4.2 D3D/DXGI는 자동 보호 대상이 아님

Direct2D가 같은 underlying resource를 간접 접근하는 동안 다른 thread가 D3D/DXGI를 직접 호출하면
Direct2D factory lock만으로 안전하지 않습니다. 필요한 경우 `ID2D1Multithread::Enter/Leave`로 D3D/DXGI
구간을 보호하며 반드시 RAII로 균형을 보장합니다.

다만 Negaflow의 기본 전략은 큰 lock을 자주 잡는 것이 아니라 **context owner queue로 호출을 직렬화**하는
것입니다. lock은 외부 호출 경계를 안전하게 만드는 보조 수단이지 scheduler가 아닙니다.

### 4.3 target 규칙

`ID2D1DeviceContext::SetTarget` 공식 계약상 같은 bitmap/command list에 여러 device context가 동시에
render할 수 없습니다.

- target은 한 render pass owner만 소유
- source로 읽는 resource와 target으로 쓰는 resource의 hazard를 명시
- `BeginDraw`/`EndDraw` 범위가 overlap하지 않게 함
- target 재사용 전 flush/fence/EndDraw 완료 확인
- command list를 immutable하게 닫은 뒤에만 공유

### 4.4 별도 factory/device

Microsoft 문서는 서로 다른 single-threaded Direct2D factories의 resources가 underlying D3D devices와
contexts도 서로 다르면 충돌하지 않는다고 설명합니다. 이는 offline export isolation 후보입니다.

그러나 별도 device는 다음 비용도 가집니다.

- shader/effect/resource cache 중복
- source upload 중복
- UMA/system memory pressure
- device-lost 두 domain 복구
- GPU scheduling이 물리적으로 완전히 격리된다는 보장 없음

따라서 “별도 factory면 UI가 절대 막히지 않는다”고 약속하지 않고 실제 Intel/AMD/NVIDIA/Qualcomm에서
latency를 측정합니다.

---

## 5. D3D11 multithreading

### 5.1 immediate context

Microsoft의 기본 규칙은 한 번에 한 thread만 immediate context를 사용하고, DXGI 작업 특히 `Present`도
같은 thread에서 수행하는 것입니다.

Negaflow는 이를 다음처럼 고정합니다.

```text
worker threads
  prepare immutable constants/resources/tile payloads
            │
            ▼
GPU owner queue
  bind → dispatch/draw → copy/readback request → signal
            │
            ▼
completion handling
  fence/query 확인 → result publish
```

`ID3D11Multithread::SetMultithreadProtected(TRUE)`로 공유 immediate context를 여러 worker에서 호출하는 방식은
기본이 아닙니다. 공식 문서도 그 보호가 각 immediate-context call overhead를 늘린다고 설명합니다.

### 5.2 device object creation

`ID3D11Device` resource creation은 context command submission과 구분됩니다. 그래도 driver의
`D3D11_FEATURE_DATA_THREADING`을 query합니다.

- `DriverConcurrentCreates`
- `DriverCommandLists`

runtime emulation이 가능하다는 이유로 성능이 동일하다고 가정하지 않습니다. 지원이 약한 driver에서는
background resource creation이 foreground render를 막을 수 있으므로 upload/resource creation도 GPU queue로
모읍니다.

### 5.3 deferred context

deferred context는 여러 thread가 command list를 기록하고 immediate context에서 재생할 수 있습니다.
하지만 다음 제약이 있습니다.

- 한 command list 자체는 single-threaded record
- 여러 command list를 immediate context에서 동시에 재생할 수 없음
- `Map`, query, state restore에 제약/비용
- image tile graph가 단순 dispatch 몇 개라면 recording overhead가 이득보다 클 수 있음
- driver가 command lists를 native하게 잘 지원하지 않을 수 있음

따라서 v1 기준은 immediate-context owner queue입니다. PIX/ETW에서 CPU command recording이 병목이고
`DriverCommandLists`가 지원되며 여러 vendor에서 이득이 확인될 때만 특정 tile pass에 deferred context를
도입합니다.

### 5.4 synchronization

D3D11의 resource visibility/hazard를 CPU mutex만으로 해결하지 않습니다.

- 동일 resource의 SRV/UAV/RTV binding hazard 해제
- dispatch 간 필요한 unbind/copy 순서
- readback staging map 전에 GPU completion 확인
- shared texture면 명시적 keyed mutex/fence 계약
- device generation과 job ID 검증

busy polling으로 UI 또는 worker core를 태우지 않습니다. completion queue와 bounded wait를 사용하고,
cancel은 GPU 작업을 강제로 중간 중단시킨다고 약속하지 않습니다. 취소된 결과를 버리는 것이 기본입니다.

---

## 6. backend 선택은 job 단위

### 6.1 기준

한 stage가 GPU에서 빠른지만 보지 않고 end-to-end 비용을 봅니다.

```text
decode location
+ upload
+ kernel chain
+ global reduction sync
+ readback
+ ICC/quantize
+ encode
+ UI interference
```

### 6.2 hardware D3D11

적합 후보:

- source/output가 이미 GPU-resident인 interactive develop
- 여러 pointwise/spatial stage를 연속 실행
- upload/readback을 amortize할 큰 image/batch
- VRAM/DXGI budget에 여유

부적합 가능:

- 작은 proxy
- codec와 ICC가 CPU에 있고 GPU round trip이 한 번뿐
- low-memory/UMA pressure
- interactive canvas와 export가 경합

### 6.3 CPU scalar/SIMD

CPU가 기준 또는 더 나은 후보:

- canonical scalar truth와 수치 검증
- small image/proxy
- codec/ICC 인접 stage
- irregular branch-heavy defect logic
- GPU unavailable/device lost
- x64와 ARM64에서 autovec/intrinsics가 충분한 loop

Intel·AMD를 별도 product path로 나누지 않고 x64 ISA capability로 dispatch합니다. ARM64는 NEON baseline을
측정하며 scalar fallback을 유지합니다.

### 6.4 WARP

WARP는 D3D software device로 다음에 사용합니다.

- GPU 없는 CI에서 D3D/Direct2D shader/effect graph 실행
- hardware 결과와 별도 conformance reference
- hardware device 생성/복구 실패 fallback
- CPU 구현이 없는 D3D-only stage의 임시 호환 경로

하지만 “file output이면 WARP가 항상 권장”이라고 해석하지 않습니다. Direct2D 정밀도 문서의 특정
권장 문맥이 Negaflow 전체 pipeline의 성능·결정성·스레드 모델을 자동 결정하지 않습니다.

- WARP도 CPU 시간을 사용해 native CPU kernels와 경쟁
- WARP 결과의 bit identity를 모든 OS build에서 무조건 약속하지 않음
- WIC software render target과 WARP D3D device는 같은 개념이 아님
- hardware GPU가 end-to-end 빠르고 정확성 gate를 통과하면 export에 사용할 수 있음

### 6.5 CUDA

CUDA는 NVIDIA가 감지됐다는 이유로 batch 전체를 옮기지 않습니다.

- optional separately shipped component
- 단일 stage 또는 연속 chain의 큰 이득이 측정될 때
- D3D11 interop/copy overhead 포함
- 동일 CPU/D3D11 결과와 tolerance gate
- 실패 시 job 시작 전/재시도 경계에서 baseline backend 선택
- CUDA binary가 없어도 모든 기능 동작

artifact 중간에서 CUDA와 baseline 결과를 임의 혼합하지 않습니다.

---

## 7. bounded pipeline

### 7.1 stage graph

일반 export의 실행 흐름:

```text
Materialize/Probe
      ↓
Snapshot/Validate
      ↓
Decode producer
      ↓ bounded queue A
Develop/Defect workers
      ↓ bounded queue B
Resize/Sharpen/ICC/Quantize
      ↓ ordered reorder buffer
Single artifact writer
      ↓
Readback verification
      ↓
Journal + catalog + publish
```

global measurement가 있으면 decode/partial-stat pass와 render pass 사이에 deterministic merge barrier가
들어갑니다.

### 7.2 queue는 item 수와 byte 수를 모두 제한

타일 네 개가 항상 같은 메모리를 쓰지 않습니다. queue capacity는 다음 둘을 모두 만족해야 합니다.

- maximum items
- reserved bytes

큰 halo/float intermediate tile 하나가 작은 thumbnail tile 수십 개보다 클 수 있습니다.

### 7.3 backpressure

consumer가 느리면 producer를 멈춥니다.

- encoder가 느리면 processed tile 생성 제한
- GPU readback이 느리면 dispatch 제한
- disk가 느리면 batch file admission 감소
- output reorder buffer가 차면 다음 sequence 근처 tile 우선
- memory pressure면 prefetch와 background cache부터 중단

unbounded future/task 생성 뒤 semaphore 안에서 대기시키지 않습니다. admission 전에 budget을 획득합니다.

### 7.4 worker 수

`hardware_concurrency()` 값을 그대로 사용하지 않습니다.

결정 요인:

- physical/logical core topology
- x64/ARM64
- CPU kernel의 bandwidth/compute 성격
- codec 자체 내부 threading
- LittleCMS transform cost
- source/destination가 같은 disk인지
- active interactive workload
- RAM/VRAM budget

초기 후보를 1, 2, 4, P-core count 등으로 benchmark하고 stage별 upper bound를 둡니다.

---

## 8. tile 내부와 file 사이 병렬성

### 8.1 두 축을 동시에 최대로 하지 않음

```text
file concurrency × tiles per file × internal codec threads
```

세 값을 모두 크게 하면 oversubscription과 memory 폭증이 생깁니다.

예:

- 2 files × 4 tile workers × OpenMP decoder 8 threads = 64 runnable threads 가능
- 각 worker가 16 MiB float tile 4개를 잡으면 단순 buffer만 512 MiB 이상

v1에서는 third-party 내부 threading을 가능한 한 끄거나 고정하고 app scheduler가 outer concurrency를
소유합니다. 그래서 LibRaw OpenMP는 초기 OFF이며, libtiff/codec 자체 threading은 명시적으로 확인합니다.

### 8.2 file-level fairness

macOS의 shared cursor 교훈을 유지합니다.

- worker에 file index를 stride로 미리 배정하지 않음
- 다음 runnable file을 central coordinator가 선택
- 한 cloud/download/RAW 파일이 다른 worker의 후속 파일을 붙들지 않음
- 그러나 한 file에서 너무 많은 tile을 독점하지 않도록 quantum/weighted fairness

### 8.3 time-to-first-file

39장 batch에서 전체 throughput만 보지 않습니다.

- 첫 artifact가 언제 완성되는지
- 진행률이 0%에서 얼마나 머무는지
- preparation/materialization을 별도 phase로 보이는지
- 작은 파일이 큰 파일 뒤에서 무한 대기하는지

다음 파일을 일부 predecode할 수 있지만 현재 파일의 writer와 memory budget을 침해하지 않는 범위로 제한합니다.

---

## 9. library별 thread 계약

### 9.1 WIC

- worker thread별 COM MTA 초기화
- decoder/frame/converter/encoder graph는 job-local
- 하나의 stream/decoder를 여러 worker가 동시에 호출하지 않음
- `CopyPixels` region 호출의 실제 병렬 효율은 codec별 측정
- encoder property bag은 initialize 전에 설정하고 writer owner만 변경
- third-party codec은 allowlist 밖

### 9.2 libtiff

- `TIFF*` handle 하나당 단일 owner
- per-handle `TIFFOpenOptions` limits와 ExtR handlers
- 다른 output 파일은 독립 handle로 병렬 가능
- 같은 output의 strip/tile write 순서는 writer가 관리
- global legacy error handler에 job context를 억지로 공유하지 않음
- BigTIFF 선택은 preflight에서 확정, 쓰는 중 자동 전환 금지

### 9.3 LibRaw

- `LibRaw` instance 하나당 단일 decode job
- 같은 instance를 tile workers가 직접 공유하지 않음
- OpenMP 초기 OFF
- full decode가 끝나면 immutable decoded tiles로 분배
- cancellation은 API 호출이 즉시 멈춘다고 가정하지 않고 결과 폐기/timeout 정책 별도
- CDDL/LGPL 선택과 adapter DLL 배포 경계는 thread 설계와 별도로 준수

### 9.4 LittleCMS

- profile bytes와 parsed immutable identity cache 분리
- transform cache key에 profiles/intent/flags/pixel formats/engine version 포함
- 공식 thread-safety 계약이 허용하는 transform 실행이라도 input/output buffer는 겹치지 않게 partition
- error context는 job/thread를 식별
- 하나의 output row/region을 두 worker가 동시에 쓰지 않음
- `cmsDoTransformLineStride` row partition은 작은 image에서 overhead가 이득인지 측정

### 9.5 zlib/codec helpers

- compression stream state는 output writer 소유
- app worker pool 위에 library internal threads가 중첩되지 않게 설정 확인
- Deflate level·predictor를 thread 수에 따라 몰래 바꾸지 않음

---

## 10. snapshot과 상태 일관성

### 10.1 immutable request

native job에 전달되는 snapshot 최소 항목:

- request/job/owner/frame ID
- frame revision와 source generation
- source path/handle identity snapshot
- develop/defect/local-adjustment parameters
- crop/orientation geometry
- output format/size/DPI/quality/compression
- canonical input/output ICC bytes digest
- metadata policy
- artifact layout
- verification level

job 시작 후 live settings를 다시 읽지 않습니다.

### 10.2 progress는 상태가 아님

progress callback은 coalesce/drop 가능하지만 terminal result는 정확히 한 번 전달합니다.

- terminal용 event queue capacity 예약
- monotonic phase/fraction
- 오래된 revision progress를 UI에 적용하지 않음
- `preparing`, `materializing`, `measuring`, `rendering`, `encoding`, `verifying`, `publishing` 구분
- 0% 장기 체류를 단일 spinner로 숨기지 않음

### 10.3 stale result

작업이 성공했어도 다음 중 하나면 current frame에 적용하지 않습니다.

- frame이 catalog에서 제거됨
- virtual copy ownership이 바뀜
- source URL/generation이 바뀜
- develop/defect revision이 바뀜
- export destination reservation이 해제/교체됨
- session이 cancel/supersede됨

export artifact가 이미 staging에 있다면 journal 규칙으로 폐기하거나 recoverable state로 남기며, stale 결과를
현재 편집의 성공으로 표시하지 않습니다.

---

## 11. cancellation

### 11.1 cooperative points

- source materialization poll 사이
- file/tile decode 전후
- tile kernel stage 사이
- global partial merge 전
- GPU submission 전과 completion 뒤
- reorder buffer 대기
- encoder strip 사이
- hash chunk 사이
- publish 전 최종 gate

codec 또는 GPU call 중 즉시 중단이 불가능할 수 있습니다. UI에는 “취소 요청됨”과 terminal “취소됨”을
구분할 수 있습니다.

### 11.2 취소 후 보장

- 새 tile/file admission 없음
- 완료된 stale tile을 cache current revision으로 승격하지 않음
- encoder finalize가 됐어도 publish하지 않음
- destination reservation 해제
- app-owned incomplete staging만 journal 소유권 확인 후 정리
- source와 third-party XMP는 절대 삭제/덮어쓰기 하지 않음
- terminal event 정확히 한 번

### 11.3 pause

pause는 cancel과 다릅니다.

- 이미 실행 중인 작은 unit은 안전 지점까지 완료 가능
- 새 file/tile admission을 막음
- memory pressure면 paused job의 재생성 가능 cache는 evict 가능
- durable batch checkpoint에 남은/완료/실패 상태 기록
- resume 시 source generation과 destination availability 재검증

---

## 12. 오류와 예외 경계

### 12.1 C++ 내부

- worker entry에서 모든 exception capture
- stable native error domain/code/context로 변환
- exception이 C ABI를 넘지 않음
- `std::terminate`를 정상 error handling으로 사용하지 않음
- allocation/codec/DirectX/Win32 오류 category 보존

### 12.2 C ABI

- opaque job handle lifetime
- terminal state를 한 번만 consume 또는 명시적 query
- callback 중 engine reentrancy 금지 여부 문서화
- callback payload pointer는 호출 범위 밖 보관 금지
- shell이 job handle을 닫아도 native in-flight cleanup 수명 보장

### 12.3 thread failure

한 tile worker 실패로 process가 바로 죽지 않게 하지만, 오류를 숨기고 나머지 tile을 성공 artifact로 조립하지
않습니다.

- job cancel propagation
- first causal error 보존
- secondary cancellation errors는 diagnostics에만
- staging artifact publish 금지
- 다른 독립 batch item은 정책에 따라 계속 가능

---

## 13. device lost

`DXGI_ERROR_DEVICE_REMOVED`·`DXGI_ERROR_DEVICE_RESET`이면 해당 device-dependent object를 다시 만들어야
합니다. `GetDeviceRemovedReason`을 먼저 진단에 저장합니다.

### 13.1 interactive path

1. GPU queue가 새 submission 중지
2. device generation 증가
3. UI에 recoverable rendering state 전달
4. 모든 old-generation D2D/D3D resources 폐기
5. preferred hardware adapter 재생성
6. 실패하면 WARP/CPU 표시 fallback
7. current revision viewport 재요청

### 13.2 export path

- 아직 publish하지 않은 artifact는 전체 job을 깨끗한 staging에서 재시작
- CPU/WARP retry는 option snapshot과 source generation이 여전히 유효할 때만
- 이미 쓴 앞 strip과 새 backend 뒤 strip을 섞지 않음
- 반복 `DEVICE_HUNG`/`INVALID_CALL`은 자동 무한 재시도하지 않고 결함으로 보고
- hardware driver update 같은 정상 removal과 app command bug를 reason code로 구분

---

## 14. scheduling policy

### 14.1 logical priorities

| class | 예 | 정책 |
|---|---|---|
| interaction | pan/zoom/brush/slider latest revision | 짧은 latency, stale coalescing |
| foreground | user-started export, scan finalization | 지속 progress와 starvation 방지 |
| maintenance | thumbnail, mip, cleaned-raw persist | pressure 시 축소/중지 |
| prefetch | 인접 사진/viewport | 가장 먼저 취소 |

OS `THREAD_PRIORITY_HIGHEST`로 문제를 해결하지 않습니다. queue admission, work quantum, memory reservation,
backend separation을 먼저 사용합니다.

### 14.2 fairness

가능한 weighted scheduler 예:

```text
interaction burst 최대 N units
→ foreground 최소 1 unit
→ 남는 budget에서 maintenance
→ idle일 때 prefetch
```

정확한 N은 측정 전 확정하지 않습니다. 목표는 slider 중 export가 영원히 멈추지 않고, export 중 canvas가
수백 ms씩 멎지 않는 것입니다.

### 14.3 heterogeneous CPU

ARM64/현대 x64의 heterogeneous cores를 vendor별 하드코딩하지 않습니다.

- OS scheduler와 process power mode 존중
- latency-sensitive와 background class 분리
- busy spin 금지
- processor group/NUMA 최적화는 64 logical processors 이상 실제 병목이 확인될 때
- battery saver/thermal 상태에서 concurrency를 낮추는 정책은 측정 후

---

## 15. progress와 사용자 경험

### 15.1 phase model

```text
queued
materializing source
preparing snapshot
measuring
rendering
encoding
verifying
publishing
completed / failed / cancelled
```

파일별 progress와 batch aggregate를 분리합니다.

- aggregate는 file count만으로 계산하지 않고 phase weight 후보를 측정
- exact duration 예측을 약속하지 않음
- 첫 파일 준비가 오래 걸리면 구체 phase 표시
- encode가 끝났어도 verify/publish 전 “완료” 표시 금지

### 15.2 callback rate

tile마다 UI callback을 직접 보내지 않습니다.

- native event coalescing
- 시간/변화 threshold
- terminal event는 coalesce 금지
- UI drain batch 크기 제한
- event queue saturation에서 progress는 drop 가능, error/terminal capacity 보존

---

## 16. deadlock 방지 규칙

lock order를 문서화합니다. 가능하면 중첩 lock 자체를 피합니다.

예시 order:

```text
job state
→ memory reservation
→ cache shard
→ GPU submission
```

다음은 금지합니다.

- UI thread에서 native terminal을 blocking wait
- GPU queue가 UI Dispatcher completion을 기다림
- writer lock을 잡고 catalog transaction 시작
- Direct2D multithread lock을 잡은 채 file IO/codec/GPU completion wait
- callback을 호출하면서 engine global mutex 유지
- cancellation destructor가 자기 worker thread join
- scanner plugin stdout reader와 process exit waiter가 서로 pipe close를 기다림

RAII lock과 scoped ownership을 사용하되, 긴 codec·kernel·IO 호출 중 global lock을 유지하지 않습니다.

---

## 17. 테스트

### 17.1 scheduler unit tests

- 각 item 정확히 한 번 실행
- worker별 stride가 아닌 shared runnable queue
- concurrency upper bound
- byte budget upper bound
- pause 후 새 admission 없음
- resume 후 남은 item만
- cancel terminal 정확히 한 번
- priority burst 뒤 foreground starvation 없음
- failure가 다른 item 상태를 오염시키지 않음

### 17.2 race tests

- frame/revision 변경 직전/직후 result apply
- source 동일 path 교체
- export destination hard link/reparse collision
- cancel과 completion 동시 발생
- pause와 failure 동시 발생
- device lost와 readback 동시 발생
- catalog commit intent와 process crash 경계
- app close와 worker/job handle release

ThreadSanitizer가 Windows/MSVC 전체 조합에서 적용되지 않더라도 deterministic stress barrier와 fault injection을
별도로 둡니다. 가능한 portable core는 Clang sanitizer job을 추가 검토합니다.

### 17.3 backend matrix

동일 fixture를 다음에서 실행합니다.

- CPU scalar, worker 1
- CPU SIMD, worker 1/N
- D3D11 hardware
- WARP
- optional CUDA가 있으면 해당 stage

비교:

- pixel numeric tolerances
- histogram/statistics
- tile order 독립성
- artifact dimensions/ICC/metadata
- cancellation과 partial publication

WARP 통과만으로 Intel/AMD/NVIDIA/Qualcomm driver 검증을 대체하지 않습니다.

### 17.4 codec concurrency

- 같은 파일 handle을 공유하지 않는지 instrumentation
- JPEG/PNG/TIFF/RAW file concurrency 1/2/4
- same disk vs separate disk
- codec internal threading on/off 후보
- corrupt/truncated inputs concurrent 처리
- cancellation과 disk-full

### 17.5 실제 사용자 시나리오

- 39장 single-image export
- 39장 print/contact sheet 네 layout
- ordinary export와 Quick Export
- Develop/Print, toolbar/Output-tab 진입
- 첫 파일 준비와 진행률 분리
- export 중 pan/zoom/slider
- 100 MP/16-bit TIFF와 RAW
- 8/16/32 GB x64, ARM64
- hardware GPU + WARP fallback

자동화된 통과와 실제 click-through UI QA는 별도 증거로 기록합니다.

---

## 18. 성능 측정

### 18.1 지표

- UI input-to-present p50/p95/p99
- first visible tile
- export time-to-first-file와 total throughput
- queue wait vs active compute
- decode/ICC/encode breakdown
- CPU utilization과 runnable threads
- context submission time, GPU busy, upload/readback
- peak process commit/working set
- DXGI Budget/CurrentUsage
- cache hit/eviction
- cancellation latency

### 18.2 도구

- ETW/WPA: CPU sampling, disk/file IO, thread scheduling, memory
- GPUView: GPU queue와 present contention
- PIX: D3D11 events, resource lifetime, shader/pass timing
- Visual Studio Concurrency Visualizer 후보
- native structured spans와 stable job IDs

diagnostic marker가 사용자 file path나 pixel 내용을 포함하지 않게 합니다.

### 18.3 비교 원칙

- 동일 input·output options·ICC·bit depth·quality
- warm/cold cache 분리
- first run과 steady state 분리
- 전원/thermal/adapter/driver 기록
- 평균뿐 아니라 tail latency
- UI workload 없는 export와 interactive 동시 export 둘 다

해상도·DPI·JPEG quality·ICC·결함 품질을 낮춘 결과를 성능 향상으로 기록하지 않습니다.

---

## 19. 구현 단계

### Phase A — ownership skeleton

- immutable native job snapshot
- bounded event queue와 terminal reservation
- CPU scheduler, cancellation, byte reservation
- UI Dispatcher 적용과 revision gate

완료 조건: stress test에서 stale result/duplicate terminal/deadlock 없음.

### Phase B — CPU + codec export

- WIC/libtiff/LibRaw/LittleCMS job-local ownership
- processing tile pipeline
- ordered writer와 backpressure
- journaled staging/publish

완료 조건: 모든 포맷과 artifact 조합, cancel/disk-full/source-change recovery.

### Phase C — interactive D3D11

- immediate-context owner queue
- Direct2D target ownership
- viewport priority
- device generation/recovery

완료 조건: pan/zoom/slider 중 race 없이 current revision만 표시.

### Phase D — GPU export 후보

- single-device scheduling 측정
- 별도 export device 후보
- hardware vs CPU vs WARP end-to-end benchmark
- device-lost whole-job retry

완료 조건: UI tail latency, throughput, memory와 numeric gates로 기본 policy 결정.

### Phase E — 선택 최적화

- deferred contexts는 command recording 병목일 때만
- CUDA는 NVIDIA 특정 stage에서 큰 순이익일 때만
- topology/NUMA 조정은 실제 고-core 장치 근거가 있을 때만

---

## 20. 금지 사항

- UI thread에서 export/decode/hash/codec blocking 작업
- 같은 D3D11 immediate context를 worker들이 동시 호출
- `ID3D11Multithread`를 scheduler 대용으로 사용
- Direct2D lock이 D3D/DXGI와 application state atomicity까지 해결한다고 가정
- 하나의 Direct2D target을 여러 contexts가 동시에 render
- WARP를 모든 export의 무조건 기본/결정적 byte reference로 선언
- hardware GPU가 있으면 모든 stage를 GPU로 보냄
- NVIDIA 감지만으로 CUDA 전체 pipeline 선택
- 한 codec/LibRaw/libtiff handle을 여러 worker가 공유
- unbounded task/future 생성 후 semaphore 내부 대기
- file concurrency와 tile concurrency와 codec internal threads를 모두 최대화
- completion order로 통계 merge/component ID/output sequence 결정
- 취소 뒤 완료된 staging을 publish
- device lost 뒤 artifact 중간에서 backend 혼합
- source/recipe/revision 재검증 없이 background 결과 적용

---

## 21. 미결정 항목

실제 spike 전 확정하지 않습니다.

- native scheduler 구현을 `std::jthread` pool로 할지 private Windows thread pool로 할지
- 기본 CPU worker 수와 file concurrency
- interactive/export가 D3D11 device를 공유할지 분리할지
- deferred context가 특정 GPU tile stage에 이득인지
- WARP와 hand-written CPU kernel의 stage별 손익분기점
- codec internal threading을 허용할 조합
- progress phase weight
- heterogeneous core/power-state tuning
- CUDA 후보 stage와 distribution 방식

---

## 공식 출처

- [Multithreaded Direct2D Apps](https://learn.microsoft.com/en-us/windows/win32/direct2d/multi-threaded-direct2d-apps)
- [D2D1_FACTORY_TYPE](https://learn.microsoft.com/en-us/windows/win32/api/d2d1/ne-d2d1-d2d1_factory_type)
- [ID2D1Multithread](https://learn.microsoft.com/en-us/windows/win32/api/d2d1_1/nn-d2d1_1-id2d1multithread)
- [ID2D1DeviceContext::SetTarget](https://learn.microsoft.com/en-us/windows/win32/api/d2d1_1/nf-d2d1_1-id2d1devicecontext-settarget)
- [Introduction to Multithreading in Direct3D 11](https://learn.microsoft.com/en-us/windows/win32/direct3d11/overviews-direct3d-11-render-multi-thread-intro)
- [Immediate and Deferred Rendering](https://learn.microsoft.com/en-us/windows/win32/direct3d11/overviews-direct3d-11-render-multi-thread-render)
- [How to check Direct3D 11 driver threading support](https://learn.microsoft.com/en-us/windows/win32/direct3d11/overviews-direct3d-11-render-multi-thread-support)
- [ID3D11Multithread](https://learn.microsoft.com/en-us/windows/win32/api/d3d11_4/nn-d3d11_4-id3d11multithread)
- [Processes, Threads, and Apartments](https://learn.microsoft.com/en-us/windows/win32/com/processes--threads--and-apartments)
- [Initializing the COM Library](https://learn.microsoft.com/en-us/windows/win32/learnwin32/initializing-the-com-library)
- [SetThreadpoolThreadMaximum](https://learn.microsoft.com/en-us/windows/win32/api/threadpoolapiset/nf-threadpoolapiset-setthreadpoolthreadmaximum)
- [Using the Windows thread pool functions](https://learn.microsoft.com/en-us/windows/win32/procthread/using-the-thread-pool-functions)
- [DXGI error codes](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/dxgi-error)
- [Handling device-lost scenarios in Direct3D 11](https://learn.microsoft.com/en-us/windows/uwp/gaming/handling-device-lost-scenarios)
- [Using Direct2D for server-side rendering](https://learn.microsoft.com/en-us/windows/win32/direct2d/server-side-rendering-overview)

## 연결 문서

- [Windows 시스템 아키텍처](../00-overview/architecture.md)
- [대용량 이미지 타일링](../06-large-images/image-source-tiling.md)
- [실행 백엔드 선택](../12-performance/backend-selection.md)
- [GPU 벤더 범용성](../12-performance/gpu-vendor-portability.md)
- [C# native interop](../09-language-choice/csharp-native-interop.md)
- [WIC](../05-image-io/wic.md)
- [libtiff](../05-image-io/libtiff.md)
- [LibRaw](../05-image-io/libraw.md)
- [LittleCMS](../04-color-management/lcms2.md)
- [내보내기 포맷](../05-image-io/export-formats.md)
- [catalog와 storage](../14-persistence/catalog-and-storage.md)
- [CI와 테스트](../12-performance/ci-and-testing.md)
