# Windows 시스템 아키텍처

기준일: 2026-08-04  
macOS 기준 커밋: `9be909c`  
상태: v1 기준안, 명시된 spike gate 전에는 구현 완료가 아님  
상위 결정: [decision register](decision-register.md)

## 1. 한 장 요약

```text
┌──────────────────── Negaflow.exe · C#/.NET 10 · WinUI 3 ────────────────────┐
│                                                                             │
│  UI/XAML     Application/Domain      Infrastructure                         │
│  windows     catalog/selection       SQLite, paths, backup                  │
│  views       workflow/jobs           export journal, diagnostics            │
│      │              │                         │                              │
│      └──────────────┴──────────┬──────────────┘                              │
│                                │ narrow versioned C ABI                      │
│                                │ commands + small bounded events             │
│  ┌─────────────────────────────▼─────────────────────────────────────────┐   │
│  │ Negaflow.Native.dll · C++20                                          │   │
│  │ image IO · color · develop · measurement · defects · render/export   │   │
│  │ CPU scalar/SIMD · D3D11 · Direct2D · DirectCompute · WARP            │   │
│  └─────────────────────────────┬─────────────────────────────────────────┘   │
│                                │ native GPU surface                          │
│                          SwapChainPanel                                      │
└───────────────────────────────┬─────────────────────────────────────────────┘
                                │ JSON/NDJSON + app-owned staging files
                                │ process boundary, never in-process link
           ┌────────────────────┴────────────────────┐
           ▼                                         ▼
  scanner-wia.exe                           scanner-twain-x86/x64.exe
  separate signed plugin                    separate signed plugin

Separate first-class consumer:
  negaflow-cli.exe → same native core/ABI, no WinUI dependency
```

아키텍처의 핵심은 언어 선택이 아니라 소유권이다.

- C#은 window, user state, catalog workflow와 transaction orchestration을 소유한다.
- C++은 pixel, color, codec, GPU resource와 compute lifetime을 소유한다.
- scanner adapter는 라이선스·비트니스·driver crash를 본체 밖에 가둔다.
- 원본과 recipe가 truth이고 GPU texture·thumbnail·cleaned raw는 재생성 가능한 파생물이다.
- macOS와 Windows는 구현 코드를 공유하지 않고 canonical spec·fixture·asset hash를 공유한다.

## 2. 프로세스 모델

### 2.1 제품 프로세스

`Negaflow.exe`는 x64 또는 순수 ARM64 native host다. C# WinUI shell이 `Negaflow.Native.dll`의 같은
architecture build를 load한다.

같은 Windows user·product channel·install identity에는 primary UI process 하나만 둔다. second launch는
window, model, engine과 catalog writer를 만들기 전에 기존 process로 activation을 전달한다. Stable/Beta는
서로 다른 instance key를 쓰지만 같은 library의 동시 write는 별도 catalog process lock이 막는다. 전체
state machine은 [앱 수명주기 명세](../08-ui/application-lifecycle.md)를 따른다.

한 프로세스 안에 두 언어가 있지만 다음을 넘기지 않는다.

- raw/full-resolution pixel array
- STL/.NET collection object
- native exception 또는 managed exception
- engine-private DirectX smart pointer
- XAML object tree ownership

canvas pixel은 native engine이 swap chain에 직접 present한다. Shell은 panel attach/detach와 logical size,
visibility, DPI, color target 같은 작은 control state만 전달한다.

### 2.2 CLI

`negaflow-cli.exe`는 WinUI 없이 C++ core 또는 동일 C ABI를 소비한다.

책임:

- input probe/decode
- canonical parameter snapshot 적용
- intermediate numeric report
- CPU/D3D11/WARP backend conformance
- image/color/metadata inspection
- deterministic fixture와 performance run

CLI는 UI 개발보다 먼저 만드는 품질 하네스다. CLI가 통과하지 않은 pixel path를 WinUI에서 보인다고 해서
기능이 완성된 것이 아니다.

### 2.3 scanner plugins

WIA, TWAIN, SANE, vendor SDK adapter는 항상 별도 executable이다.

- 본체와 binary link 없음
- architecture 독립: x86 plugin도 x64/ARM64 app과 process IPC 가능
- manifest + versioned JSON/NDJSON
- app이 만든 staging root 안의 file artifact
- bounded stdout/stderr/message/file/time
- Job Object 기반 child lifetime
- plugin-specific installer, signature, license, update 가능

plugin이 catalog, recipe directory, export journal을 직접 열지 못하게 한다. capability와 artifact만 host가
검증해 domain model로 받아들인다.

### 2.4 아직 만들지 않는 process

- 항상 실행되는 background service
- cloud sync daemon
- GPU broker process
- in-process scanner COM bridge
- CUDA 전용 product executable

필요성이 실측되기 전 process를 추가하지 않는다. crash 격리가 필요한 scanner driver만 처음부터 분리한다.

## 3. 논리 계층

```text
Presentation
  WinUI Views / Controls / Windows / UI Automation
        │
Application
  commands / jobs / revisions / cancellation / user-facing state
        │
Domain
  catalog models / develop snapshot / defect recipe / scan workflow / export plan
        │
Infrastructure                   Native Engine
  SQLite / paths / backup        image/color/render/codec/GPU/CPU
  picker / journal / plugin  ◄──► narrow C ABI
        │                             │
        └──── files/manifests ────────┘
```

의존 방향은 아래로만 흐른다.

- View가 SQLite statement를 직접 실행하지 않는다.
- catalog model이 XAML control type을 보관하지 않는다.
- native core가 WinUI namespace 또는 managed assembly를 참조하지 않는다.
- plugin protocol이 main app의 private C# DTO serializer에 종속되지 않는다.
- persistence가 현재 화면 selection을 truth로 추정하지 않는다.

## 4. Shell 책임

Shell은 단순한 얇은 view가 아니라 비픽셀 제품 workflow를 소유한다.

### 4.1 UI

- main/Settings/auxiliary AppWindow
- instance election, activation routing, main close와 session-end coordination
- Library/Develop/Print workspace shell
- menu, toolbar, context menu, shortcut, access key
- dialog, picker, drag/drop, shell activation
- theme, localization, scaling, high contrast
- UI Automation와 keyboard focus
- loading/empty/error/recovery state

### 4.2 domain/application state

- roll/frame/folder/collection/stack/selection
- per-frame develop parameters와 revisions
- defect recipe identity와 undo/redo
- scan session/job workflow
- export batch/recipe/naming plan
- print layout/workspace state
- settings와 shortcut overrides
- backup/restore/archive maintenance state

### 4.3 storage orchestration

- catalog snapshot/commit/recovery
- app-owned defect sidecar lifecycle
- thumbnail/cache index
- backup generation, restore drill, pending restore marker
- export artifact commit journal
- source relink/bookmark-equivalent recovery
- storage location and volume status

pixel encoding과 ICC transform은 native가 하되, 사용자가 보는 transaction과 catalog acknowledgement는 Shell
application service가 소유한다.

## 5. Native engine 책임

### 5.1 platform-neutral core

- parameter validation과 canonical defaults
- negative/positive/digital develop math
- film base와 automatic parameter derivation
- histogram/statistics semantics
- defect detect/recipe application math
- crop/orientation/resize geometry
- ROI, halo, tile planning
- deterministic scalar reference

가능한 pure core에는 Win32/COM/DirectX header를 넣지 않는다. 그렇다고 macOS Swift를 자동 번역하거나 한
소스 tree를 공유하려 하지는 않는다. algorithm contract와 fixture가 공유 경계다.

### 5.2 Windows platform layer

- WIC/libtiff 등 codec
- metadata decode/encode contract
- Windows Color System/lcms2 후보
- path/file handle, staging output
- D3D11/DXGI/Direct2D device
- Direct2D custom effect registration
- DirectCompute resource/dispatch
- swap chain/presentation
- ETW/PIX marker와 device diagnostics

### 5.3 engine runtime

- image session and immutable snapshots
- render request queue와 priority
- tile/cache residency
- native worker pool
- D3D immediate-context serialization
- request cancellation/supersession
- device generation and recovery
- bounded event queue

## 6. Shell ↔ Native C ABI

### 6.1 왜 C ABI인가

C++/WinRT component를 C#에서 쓰는 것은 가능하지만 `.winmd`와 C#/WinRT projection artifact, activation과
배포 표면이 추가된다. Negaflow가 필요한 것은 object graph projection이 아니라 다음의 작은 command/event
경계다.

- opaque engine/session/canvas/job handle
- fixed-width POD
- length-delimited UTF-8
- immutable parameter snapshot
- request ID, progress, terminal result
- bounded small arrays such as histogram

따라서 기본은 source-generated P/Invoke (`LibraryImport`) + `SafeHandle`이다. `SwapChainPanel` 연결만 이
방법으로 안정성을 입증하지 못하면 얇은 C++/WinRT adapter를 허용한다.

### 6.2 경계를 넘는 것

Shell → Engine:

- validated path 또는 app-owned asset handle
- image/session command
- canonical develop/defect/output snapshot
- canvas logical size, DPI, visibility
- render/export priority와 cancellation

Engine → Shell:

- request/job state
- progress phase와 fraction
- small histogram/statistics/sample value
- output manifest/hash/dimension/metadata summary
- stable error domain/code + localization key
- adapter/backend/memory diagnostic

넘지 않는 것:

- full image pixels
- unmanaged pointer를 해석하는 managed code
- XAML element를 장기 소유하는 native engine
- callback thread에서 직접 UI mutation

### 6.3 async model

```text
Shell validates UI state
→ immutable snapshot + request_id + owner_id + revision
→ native queue
→ worker/render/IO
→ bounded event queue
→ Shell drains small event batch
→ UI DispatcherQueue
→ owner/revision 재확인
→ current result만 apply
```

progress는 coalesce할 수 있지만 terminal event는 한 번 반드시 전달한다. queue saturation 때 terminal용
reserved capacity를 보존한다.

세부 계약은 [C# native interop](../09-language-choice/csharp-native-interop.md)을 따른다.

## 7. GPU 아키텍처

### 7.1 v1 기준선

| 영역 | 기준 |
|---|---|
| device | D3D11, feature level 11_0 minimum |
| shader | SM 5.0 offline DXBC |
| pointwise graph | Direct2D custom effects |
| reduction/spatial 후보 | same-device DirectCompute |
| presentation | flip-model swap chain + SwapChainPanel |
| software GPU | WARP |
| CPU | scalar truth + measured SIMD hot path |

같은 D3D11/DXGI device를 Direct2D와 compute가 공유한다. D3D12는 필수 baseline이 아니며, PIX/ETW가
D3D11 고유 병목을 입증할 때만 measured optional tier로 추가한다.

### 7.2 adapter 범위

- Intel integrated/Arc
- AMD Radeon
- NVIDIA GeForce/RTX
- Qualcomm Adreno on ARM64
- Microsoft WARP

기능은 모든 target에서 같고 속도만 달라야 한다. vendor string으로 output math를 선택하지 않는다.

### 7.3 CUDA

CUDA는 NVIDIA-only 선택적 module 후보다.

- D3D11/CPU 기능이 먼저 완전해야 함
- canonical input/output contract 공유
- resource interop, sync, installer, driver 비용 포함 end-to-end 측정
- 긴 batch 20% 이상 또는 명확한 절대 시간 이득
- NVIDIA가 아니어도 UI·file format·quality 차이 없음

CUDA-specific preset이나 기능을 만들지 않는다.

### 7.4 device generation

모든 GPU-derived object는 device generation에 속한다.

```text
device removed/hung/reset
→ 새 GPU submission 중지
→ reason/build/request evidence 기록
→ old swap chain/effect/texture/query 폐기
→ adapter/device/effect registry 재생성
→ source + recipe + current revision에서 rerender
```

catalog, recipe, selection, undo, export plan은 GPU object가 아니므로 보존한다.

## 8. CPU 아키텍처

### 8.1 target

- x64: Intel과 AMD 한 binary
- ARM64: Qualcomm 등 순수 ARM64 binary
- x86: app/engine 없음, scanner plugin에만 허용
- ARM64EC: 없음

### 8.2 execution

```text
scalar reference
→ compiler auto-vectorization report
→ measured hot loop only
   x64 AVX2/FMA
   ARM64 NEON
→ 필요할 때만 dispatch helper
```

ISA는 CPUID와 OS context support를 함께 확인한다. unsupported instruction을 process-wide minimum으로 만들지
않는다. 작은 ROI·metadata·deterministic measurement·GPU failure에서도 CPU path는 first-class다.

### 8.3 pool

- UI/managed ThreadPool과 native pixel worker pool을 분리
- foreground interaction, final export, thumbnail/prefetch priority를 구분
- task count를 logical core 수와 memory bandwidth 측정에 맞춤
- per-task full-frame allocation 금지
- cancellation 뒤 result commit에서 revision 재확인

## 9. 렌더·측정 분리

현상 parameter 일부는 image statistics에서 만들어진다. reduction의 부동소수 순서가 backend마다 달라지면
같은 입력의 final tone이 달라질 수 있다.

계약:

- stage별 input color domain과 precision을 manifest에 기록
- histogram bin/domain과 percentile algorithm 고정
- deterministic CPU reference 유지
- GPU partial reduction을 쓰더라도 final combine order 고정
- tolerance를 넘으면 해당 measurement만 CPU로 fallback
- preview와 export가 같은 canonical parameter result를 사용

렌더 pixel tolerance와 parameter exactness를 구분한다. small interpolation difference를 허용하더라도 auto
parameter가 다른 branch로 넘어가는 것은 허용하지 않는다.

## 10. image/data flow

### 10.1 import/develop

```text
user-selected source
→ Shell validates/imports reference
→ catalog source identity + metadata
→ Native probe/decode
→ source tiles/cache
→ measurement
→ canonical develop snapshot
→ D2D/CPU graph
→ display transform
→ swap chain
```

원본은 reference 또는 사용자가 명시적으로 app-owned folder로 옮긴 file이다. import 자체가 원본을 수정할
권한이 아니다.

### 10.2 defects

```text
immutable source
  + ordered app-owned defect recipe
  + recipe/source identity
→ incremental/ROI clean render
→ memory cache / regenerable cleaned-raw cache
→ develop pipeline
```

defect recipe sidecar가 truth다. cleaned-raw TIFF는 identity가 맞을 때만 사용할 수 있는 파생 cache다.
Windows는 종료 시 scanner original에 cleaned pixels를 bake하지 않는다.

### 10.3 export

```text
catalog snapshot + source identity + defect recipe + develop/output recipe
→ reconstruct required non-destructive result
→ Native final render/encode into app-owned staging
→ dimension/profile/metadata/hash verification
→ Shell commit journal
→ destination publication
→ readback/manifest acknowledgement
```

필수 result를 재구성할 수 없으면 original로 silently fallback하지 않고 job이 실패한다.

### 10.4 scan

```text
validated capability + exact request
→ plugin process
→ app-owned scan staging artifact
→ host validates requestID/options/hash/size/dimensions/ROI
→ atomic adoption as scanner original
→ catalog + preview/develop
```

USB enumeration이나 process exit code만으로 scan 성공을 인정하지 않는다.

## 11. 영속 데이터

| 데이터 | truth | 저장 | 삭제 정책 |
|---|---|---|---|
| imported/scanned original | 사용자 source | user-selected/managed path | 명시적 source delete만 |
| catalog | app | SQLite primary + recovery | maintenance transaction만 |
| develop parameters | app | catalog/schema | frame/virtual-copy delete에 따라 |
| defect recipe | app | versioned atomic sidecar | frame/recipe transaction만 |
| cleaned raw | derived | app cache + identity | 재생성 가능할 때만 evict |
| thumbnail | derived | disk cache | clear 가능 |
| scan preview | ephemeral | session cache | ownership 확인 후 정리 |
| export/print artifact | user output | destination | app cache clear로 삭제 금지 |
| backup generation | recovery | internal/external backup | retention policy transaction |
| settings | app preference | atomic versioned document | reset preference only |

missing/corrupt catalog는 empty catalog가 아니다. catalog를 열지 못한 상태에서 orphan cleanup, source delete,
cache sweep를 실행하지 않는다.

## 12. SQLite catalog

macOS의 현재 primary는 SQLite이며 portable archive/backup에서는 canonical JSON snapshot이 쓰일 수 있다.
Windows는 schema meaning, version, migration, incremental commit verification을 이식한다.

Shell에서 사용할 provider는 x64/ARM64, native dependency, backup/restore, failure injection을 통과한 뒤
확정한다. provider convenience API가 transaction semantics를 바꾸지 못한다.

필수:

- `user_version`/app schema version 분리
- process lock과 single writer policy
- explicit transaction
- prior valid primary/recovery preservation
- write 후 incremental/full verification
- corrupt/future schema fail-closed
- 50k frame workload measurement
- backup에 WAL/SHM 상태를 어설프게 복사하지 않음
- archive는 portable canonical representation

WAL, synchronous, mmap, checkpoint 정책은 실제 Windows NTFS/redirected/network volume에서 측정 후
결정한다. macOS benchmark 결과는 schema 유지의 근거지만 Windows VFS tuning의 증거는 아니다.

## 13. 파일 시스템과 transaction

### 13.1 path class

- internal app data: `%LOCALAPPDATA%\Negaflow`
- user originals/exports: Known Folder 또는 explicit picker path
- plugin install/trust: app-owned per-user directory
- temporary staging: operation-scoped app-owned directory

path string만 identity로 쓰지 않는다. file/volume ID, normalized absolute path, expected type, size/hash와
operation owner를 가능한 범위에서 함께 확인한다.

### 13.2 atomicity

- temp/staging은 destination과 같은 volume을 우선
- file handle을 통해 validate/write/replace race를 줄임
- replace 전 existing destination을 journal/quarantine
- publish 후 readback/metadata/hash 확인
- crash recovery가 ambiguous transaction을 숨기지 않음
- NTFS, ReFS 후보, FAT/exFAT, SMB, OneDrive에서 보장 차이를 검증

`MoveFileEx`/replace가 모든 filesystem에서 동일한 durability를 준다고 가정하지 않는다.

## 14. scanner licensing/security boundary

process separation의 목적:

- GPL/other license 결합 위험을 줄이는 배포 구조
- x86/x64 bitness isolation
- vendor driver crash/hang containment
- privilege와 filesystem scope 제한
- independent update/revocation

하지만 “process면 법적으로 무조건 분리”라는 결론은 문서화하지 않는다. 출시 전 실제 source, binary,
installer, IPC coupling을 법률 검토한다.

host security:

- manifest schema/version/size validation
- publisher signature와 executable/manifest hash approval
- identity change 시 approval 폐기
- absolute executable path와 safe DLL search
- inherited handle 최소화
- Job Object kill-on-close, timeout/cancel
- bounded pipe/stdout/stderr
- app-owned staging root만 artifact로 인정
- reparse point/hardlink/file replacement 방어
- output bytes/hash/dimensions/format/applied options 재검증

## 15. concurrency와 ownership

| 실행 영역 | 소유 |
|---|---|
| UI thread | XAML tree, focus, view model apply |
| managed application tasks | catalog/plugin/journal orchestration |
| native control queue | engine/session/request lifecycle |
| native render queue | D3D immediate context, D2D draw, present |
| native CPU pool | bounded tile/kernel work |
| codec/IO tasks | decode/encode/readback/file operations |

규칙:

- UI thread에서 disk/GPU fence/process wait 금지
- native worker가 managed delegate를 임의 호출하지 않음
- D3D11 immediate context는 engine queue가 직렬화
- object owner와 request revision을 completion 직전에 확인
- shutdown은 새 요청 차단 → cancel → bounded terminal → canvas detach → engine dispose 순서
- app termination을 무한 대기하지 않음

## 16. error 모델

### 16.1 stable error

native/plugin/infrastructure error는 다음을 가진다.

- domain
- stable code
- severity
- request/job/session ID
- optional HRESULT/Win32/SQLite code
- localized message key와 safe arguments
- retry/recovery action
- redacted diagnostic detail

raw exception text를 UI copy로 사용하지 않는다. path/user metadata를 telemetry에 넣지 않는다.

### 16.2 user state

- recoverable job failure: current recipe와 selection 유지
- engine fatal: catalog write를 중지하고 safe recovery surface
- catalog invalid: library blocked, empty로 가장하지 않음
- GPU lost: derived resource 재생성
- plugin crash: plugin job만 실패, host/library 유지
- export ambiguous: journal recovery 전 성공/실패로 임의 확정하지 않음

## 17. diagnostics

최소 evidence:

- product/native/ABI/schema/build ID
- OS/architecture
- adapter LUID/driver/feature level/backend
- request/job phase timing
- queue depth, cancellation, supersession
- CPU/GPU/cache/VRAM budget
- decode/render/encode/publish stage
- catalog transaction/checkpoint/verification
- plugin manifest/protocol/trust/process exit

pixel, path, filename, image metadata는 기본 trace에서 제외한다. support bundle은 per-bundle salted identifier와
집계값만 사용한다.

## 18. 배포 아키텍처

v1 후보:

- x64 installer + x64 self-contained app/native payload
- ARM64 installer + ARM64 self-contained app/native payload
- WiX MSI/Burn candidate
- every EXE/DLL/installer Authenticode signed
- shader/asset/license manifest
- plugin은 별도 artifact/approval/update

installer는 Shell과 Native/ABI/assets를 한 product version으로 원자적으로 upgrade한다. old Shell + new DLL
같은 mixed state는 startup version negotiation에서 fail closed한다.

MSIX/packaged-with-external-location은 package identity가 필요한 실제 요구가 생기면 별도 spike한다. framework
지원 여부를 scanner/plugin distribution 가능성으로 오인하지 않는다.

## 19. 품질 기준선

Windows의 truth manifest:

- macOS commit SHA
- source fixture/data asset hash
- preset/profile schema/hash
- kernel/stage manifest
- canonical parameter defaults
- expected numeric reports/tolerance
- file output contract
- UI surface/state inventory
- intentionally deferred delta

같은 입력에서 byte-identical을 무조건 요구하지 않는다. codec, interpolation, ICC implementation 차이는
stage-specific tolerance로 평가한다. 그러나 enum/default/stage order/metadata/geometry/automatic branch 결과는
의도 없이 달라지면 안 된다.

## 20. 위험과 spike gate

### 20.1 반드시 먼저 증명

1. C# C ABI load/layout/lifetime: x64 + ARM64
2. `SwapChainPanel` attach/detach: unpackaged, GC stress, device lost
3. D2D custom effect linking과 extended-linear precision
4. D2D ↔ DirectCompute resource handoff
5. WARP의 필수 shader/format
6. WIC/libtiff/ICC output round trip
7. 50MP/100MP tile/VRAM/working-set
8. SQLite migration/commit/recovery: NTFS와 redirected/network storage
9. 50k `ItemsView` virtualization
10. plugin process timeout/cancel/artifact/trust
11. installer clean install/upgrade/repair/uninstall
12. Intel/AMD/NVIDIA/Qualcomm/WARP conformance
13. x64/ARM64 single-instance activation과 normal close/session-end race

### 20.2 전환 조건

- C ABI panel attach가 불안정 → panel-only C++/WinRT adapter
- D3D11 고유 병목이 입증됨 → optional D3D12 tier spike
- NVIDIA에 end-to-end threshold 이득 → optional CUDA module
- GPU deterministic measurement 실패 → measurement CPU final
- Toolkit Settings control blocker → basic WinUI local composition
- unpackaged가 required product integration을 막음 → packaged-with-external-location spike

한 spike 실패가 전체 아키텍처를 무제한 재설계할 권한은 아니다. 미리 적은 대안 범위 안에서 전환한다.

## 21. 금지 목록

- macOS/Windows 공용 UI 또는 pixel abstraction을 새로 만듦
- C#에서 full-resolution pixel loop
- C++에서 XAML state tree
- C++/WinRT object graph로 전체 engine projection
- 본체 process에 scanner SDK/DLL load
- D3D12 FL 12_0 또는 CUDA로 기능 gating
- ARM64를 x64 emulation으로 출시
- source original 또는 third-party XMP in-place write
- cleaned cache를 recipe truth로 사용
- corrupt catalog를 empty로 처리하고 cleanup
- export 재구성 실패 시 original silent fallback
- runtime HLSL compile을 production 기본 경로로 사용
- backend별 preset/output semantics

## 22. 관련 문서

- [전략](strategy.md)
- [호환성 매트릭스](compatibility-matrix.md)
- [solution layout](../13-build-and-deps/solution-layout.md)
- [C# native interop](../09-language-choice/csharp-native-interop.md)
- [backend selection](../12-performance/backend-selection.md)
- [UI parity](../08-ui/parity-contract.md)
- [scanner plugin architecture](../10-scanner/plugin-architecture.md)
- [catalog and storage](../14-persistence/catalog-and-storage.md)
- [product invariants](../99-plan/product-invariants.md)
