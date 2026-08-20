# Windows 분리 개발 전략

기준일: 2026-08-04  
macOS 기준 커밋: `9be909c`  
상태: 실행 전략

## 1. 결론

Negaflow Windows판은 macOS 앱의 기계적 port나 공용 UI rewrite가 아니다. WinUI 3, DirectX, WIC,
Windows Color System, Win32 storage/process API 위에서 같은 제품 계약을 독립 구현한다.

```text
공유하는 것
  제품 흐름 · 상태 전이 · 수학 · schema · assets · fixture · acceptance criteria

공유하지 않는 것
  Swift/SwiftUI · Core Image graph object · AppKit behavior · platform UI code
```

목표는 메뉴 이름만 같은 앱이 아니라 다음이 동등한 앱이다.

- import/scan → develop → export/print 흐름
- 기본값과 opt-in 조건
- 원본 불변과 비파괴 재구성
- Library/Develop/Defects/Print/Scanning의 상태 전이
- 실패·취소·복구·재시작
- color/geometry/metadata contract
- keyboard/accessibility/localization
- large image와 batch 성능 품질

## 2. 사양의 우선순위

Windows 구현 중 서로 다른 자료가 충돌하면 다음 순서로 판정한다.

1. 명시된 제품 불변식과 현재 사용자 결정
2. 고정 macOS baseline의 실제 코드·테스트
3. canonical data asset와 schema
4. 현재 동작을 재현한 수치/상태 fixture
5. 문서 설명
6. 플랫폼 관례에 따른 adaptation

현재 코드가 원본 불변성과 충돌하는 등 더 위험한 legacy path를 포함할 수 있다. 그런 경우 “코드 parity”를
이유로 위험을 복제하지 않고 명시된 제품 불변식을 따른다. 예외와 근거를 decision register에 기록한다.

## 3. 고정 baseline

움직이는 `main`을 목표로 삼으면 Windows milestone이 끝나지 않는다. 각 milestone에 baseline manifest를
고정한다.

```text
baseline ID
macOS commit SHA
source inventory hash
kernel/stage manifest
preset/profile/resource hash
schema version
default parameter snapshot
test fixture version
UI surface/state inventory
known deviations/deferred deltas
```

baseline 뒤 macOS 변경은 자동 요구사항이 아니다. delta intake에서 다음으로 분류한다.

- correctness/security/data-safety fix: 우선 동시 반영
- product behavior change: 승인 후 양쪽 spec 갱신
- macOS-only platform adaptation: Windows 제외 가능
- visual polish: 현재 Windows milestone 뒤 backlog
- experimental/dirty-worktree change: commit과 검증 전 baseline 제외

현재 `9be909c` 뒤 working tree의 shader 변화처럼 미커밋 코드는 관찰할 수 있지만 확정 baseline과 섞지 않는다.

## 4. 옮기는 자산

### 4.1 canonical data

- film/develop preset JSON
- scanner profile JSON과 manifest
- product version/build metadata
- localization key와 번역 문자열
- ICC/profile asset 중 provenance와 재배포 권리가 확인된 것
- scanner protocol schema/transcript
- paper size/layout template와 physical geometry

각 asset은 source path, schema version, size, SHA-256, license/provenance를 manifest에 기록한다. generated file만
복사하지 않고 canonical source와 생성 절차를 추적한다.

### 4.2 algorithm spec

- stage order와 enable condition
- input/output color domain
- default/range/unit
- extended-linear/NaN/Inf/clamp policy
- ROI/halo/edge behavior
- measurement/reduction semantics
- orientation/crop/resize geometry
- metadata carry/drop/replace rule
- defect recipe ordering과 identity

Metal source를 HLSL로 line-by-line 번역하는 것만으로는 spec가 되지 않는다. 주변 Swift가 만든 constants,
sample domain, extent, pre/post transform까지 함께 기록한다.

### 4.3 expected behavior

- scalar numeric output
- histogram/statistics/auto parameter
- stage-specific pixel tolerance
- file dimensions/bit depth/profile/metadata
- state-machine transition
- recovery result와 preserved artifact
- UI visible/disabled/error/selection state

테스트 code 자체보다 fixture input, canonical parameter, expected report와 tolerance가 두 제품의 공유 계약이다.

## 5. 공유하지 않는 것

- Swift type graph와 Combine/ObservableObject 구조
- SwiftUI view hierarchy
- Core Image lazy graph object identity
- `UserDefaults` key-value storage 자체
- `NSOpenPanel`, `NSScreen`, `NSWorkspace` 호출
- ImageCaptureCore device API
- macOS path/bookmark/termination behavior
- Metal compilation/runtime object
- APFS clone/replace 의미

이 의미를 Windows API로 다시 구현하되 file lifecycle과 사용자 결과는 동등하게 만든다.

## 6. 기술 기준선

| 영역 | 기준 |
|---|---|
| UI | C#/.NET 10 + WinUI 3 |
| Native | C++20 |
| Shell/engine | narrow C ABI + `LibraryImport` |
| GPU | D3D11 FL 11_0 + Direct2D + DirectCompute |
| software GPU | WARP |
| CPU | scalar + measured x64 AVX2/FMA / ARM64 NEON |
| image IO | WIC + format-specific audited supplements |
| color | explicit ICC/WCS/lcms2-evaluated pipeline |
| catalog | SQLite schema semantics + verified commit/recovery |
| scanner | separate-process WIA/TWAIN/SANE adapters |
| distribution | x64/ARM64 unpackaged self-contained installer candidate |

D3D12와 CUDA는 baseline이 아니다. 실제 bottleneck과 end-to-end 이득을 입증한 optional tier 후보다.

## 7. 왜 공용 platform abstraction을 만들지 않는가

Core Image와 Direct2D는 모두 effect graph/ROI 개념을 갖지만 resource, precision, shader, cache, device-lost,
presentation 모델이 다르다. 공용 “image node” abstraction을 새로 만들면 다음이 발생한다.

- 양쪽 API의 최소공배수만 노출
- native ROI/tile optimization을 abstraction 밖으로 우회
- color/precision transition이 숨겨짐
- performance bug를 공용 layer 탓인지 backend 탓인지 분리하기 어려움
- macOS 안정 코드까지 재작성하게 됨

공통화는 compile-time type이 아니라 executable specification에서 한다.

```text
canonical fixture
      ├─ macOS implementation → report A
      └─ Windows implementation → report B
                              compare by stage contract
```

## 8. 품질 잠금 방식

### 8.1 눈으로만 비교하지 않는다

visual review는 UI와 perceptual artifact를 찾는 데 필요하지만 color algorithm correctness의 유일한 근거가
될 수 없다.

필수 수치:

- decoded dimensions/channel/precision/profile
- representative pixel probes
- min/max/mean/percentile/histogram
- automatic parameter output
- ΔE 또는 정의된 color metric가 필요한 stage
- mask/component/recipe geometry
- final file metadata와 hashable manifest

### 8.2 byte equality도 맹목적으로 요구하지 않는다

WIC/Core Image/libtiff/ICC engine과 interpolation 차이로 legitimate small difference가 날 수 있다. tolerance는
stage별로 미리 정의한다.

| 종류 | 계약 |
|---|---|
| enum/default/stage order | exact |
| dimensions/orientation/crop | exact |
| metadata policy | exact semantic |
| automatic branch/parameter | exact 또는 매우 좁은 tolerance |
| scalar math fixture | defined numeric tolerance |
| GPU pixel | CPU reference 기준 tolerance |
| codec bytes | semantic decode comparison, byte equality는 deterministic codec에서만 |

tolerance를 test 실패 뒤 넓히지 않는다. 근거와 perceptual/technical impact를 기록한다.

### 8.3 backend matrix

각 필수 operation은 가능한 조합을 비교한다.

- CPU scalar
- CPU optimized x64/ARM64
- D3D11 hardware: Intel/AMD/NVIDIA/Qualcomm
- WARP
- optional tier가 생기면 D3D12/CUDA

결과가 backend마다 기능 또는 metadata에서 달라지면 실패다.

## 9. 단계별 개발 전략

### Phase 0 — baseline extraction

산출물:

- source/file/symbol inventory
- pipeline and kernel manifest
- parameter schema/default/range/unit
- asset/provenance manifest
- catalog/sidecar/plugin schema
- UI surface/state matrix
- golden fixture pack

exit:

- 모든 주요 source symbol이 spec/test/explicit-defer 중 하나에 매핑
- committed baseline과 dirty observation 분리
- 원본/recipe/cache/output lifecycle 합의

### Phase 1 — native scalar CLI

순서:

1. canonical image representation과 overflow-safe dimensions
2. source probe/decode
3. scalar color/develop stages
4. deterministic measurement
5. geometry/orientation/resize
6. defect recipe application
7. encode/metadata/profile
8. CLI report/export

exit:

- x64와 ARM64 build
- synthetic/golden numeric conformance
- corrupt/truncated/oversized input fail-closed
- no WinUI dependency

### Phase 2 — Windows image/color/file contract

- WIC codec matrix
- TIFF/float/high-bit-depth supplement
- ICC/ICM input/working/display/output transforms
- metadata carry/drop/replace
- atomic staging/publication primitives
- local/redirected/network/removable volume behavior

exit:

- supported format matrix에 unknown silent downgrade 없음
- profile/dimension/bit-depth readback
- disk-full/read-only/replace/crash fault tests

### Phase 3 — GPU/WARP

- D3D11/D2D device and extended-linear formats
- custom effects and shader manifest
- D2D graph/ROI/linking
- DirectCompute reductions/spatial kernels
- tile/VRAM/device-lost
- WARP CI path

exit:

- Intel/AMD/NVIDIA/Qualcomm/WARP conformance
- 50MP/100MP bounded memory
- no mandatory D3D12/CUDA
- CPU fallback complete

### Phase 4 — catalog/domain/infrastructure

- SQLite schema/migration/verified commit
- settings
- app-owned defect sidecar and cleaned cache identity
- backup/restore/archive
- source relink and filesystem monitoring
- export commit journal
- support bundle/diagnostics

exit:

- corrupt/missing/future catalog blocked safely
- 50k frame performance
- crash recovery and restore drill
- source original unchanged

### Phase 5 — WinUI shell and canvas

- localization/resource foundation
- app/window lifecycle
- workspace shell
- C ABI lifetime/event bridge
- SwapChainPanel
- keyboard/focus/accessibility primitives
- deterministic sample catalog

exit:

- x64/ARM64 unpackaged run
- rapid attach/detach/resize/DPI/GC/device-lost
- no full image managed copy
- keyboard/high contrast/text scale smoke

### Phase 6 — vertical product slices

권장 순서:

1. Library browse/select/import
2. Develop basic controls + preview/export parity
3. Canvas crop/compare/pixel sampler
4. Export/Quick Export transaction
5. Defects tools + persistence/rebuild
6. Print workspace + raster package export
7. Settings/backup/recovery/legal
8. advanced Library organization/culling/duplicates

각 slice는 UI만 만들지 않는다.

```text
state → native request → pixels/data → persistence → failure/recovery → UI Automation
```

### Phase 7 — scanner plugins

- protocol host and mock conformance plugin
- WIA adapter spike
- TWAIN x64/x86 adapter spike
- capability-driven scanning UI
- preview/full-scan/ROI/applied-options evidence
- trust/install/update/revoke
- actual target device matrix

plugin 없이도 import/develop/export 제품이 완전해야 한다.

### Phase 8 — release engineering

- self-contained x64/ARM64 payload
- installer/upgrade/repair/uninstall
- Authenticode/timestamp/signature verification
- SBOM/NOTICE/license
- crash dump/symbol retention
- update rollback/recovery
- clean VM and hardware certification matrix

ad-hoc signed 또는 미서명 local artifact를 배포 준비 완료라고 부르지 않는다.

## 10. vertical slice gate

각 기능은 다음을 전부 만족해야 done이다.

1. macOS source/state inventory 연결
2. Windows UI visible/disabled/error state
3. canonical parameter/schema
4. CPU/GPU execution과 fallback
5. persistence/restart
6. cancellation/stale ownership
7. data-safety fault path
8. localization/accessibility/keyboard
9. x64/ARM64
10. measured performance and honest residual risk

예: Export 화면이 보이고 파일 하나가 생성돼도 transaction recovery, ordinary/Quick entry, 39-photo batch,
ICC/DPI/quality가 검증되지 않았으면 Export 완료가 아니다.

## 11. UI/UX parity 방법

UI는 screenshot 복제가 아니라 상태 계약으로 이식한다.

각 surface 문서에 기록:

- layout hierarchy와 resizable behavior
- control order, default, range, unit
- selection/hover/focus/disabled/loading/empty/error
- keyboard shortcut와 focus movement
- context menu/drag/drop
- asynchronous progress/cancel
- restart persistence
- accessibility name/role/value
- Windows-native adaptation과 의도적 차이

visual QA는 real app, sample catalog, real scaling/theme/input에서 한다. XAML compile이나 screenshot 한 장은
click-through QA를 대신하지 않는다.

## 12. CPU/GPU 우선순위

성능 최적화 순서:

1. algorithm/IO 단계 자체 제거 또는 reuse
2. full-frame intermediate와 copy 감소
3. tile/ROI/cache/scheduling
4. scalar correctness와 compiler auto-vectorization
5. measured CPU SIMD
6. D3D11/D2D/DirectCompute
7. backend-specific optional tier

CPU가 충분히 빠른 metadata, small ROI, deterministic reduction은 CPU에 둔다. GPU가 빠르다는 가정으로
upload/readback과 sync를 무시하지 않는다.

CUDA는 NVIDIA에서만 고려하며 Intel/AMD/Qualcomm 사용자의 기능/품질을 낮추지 않는다.

## 13. scanner 전략

WIA와 TWAIN을 경쟁 종교처럼 하나 고르지 않는다.

- WIA: Windows-native API, film item/property를 device evidence로 평가
- TWAIN: vendor data source와 advanced film scanner 호환을 실제 장치로 평가
- SANE: 별도 GPL plugin으로 필요할 때 지원
- vendor SDK: license/redistribution/architecture가 허용될 때 별도 plugin

장치별 capability, 300-DPI positioned preview, transparency/IR, requested/applied ROI, bit depth, cancellation,
artifact quality로 adapter를 선택한다. USB 발견은 지원 증거가 아니다.

## 14. data safety 전략

- imported/scanned original과 third-party XMP 불변
- recipe/parameters app-owned, versioned, atomic
- derived cache는 identity가 맞을 때만 사용
- catalog corrupt/missing 상태에서 cleanup 금지
- source deletion과 library removal 분리
- virtual copy source ownership 명확화
- export reconstruction failure는 visible failure
- restore는 safe startup transaction
- ambiguous journal은 사용자에게 숨기지 않음

Windows filesystem API가 macOS와 다르므로 행동을 그대로 흉내 내지 않고 invariant를 Windows handle/volume
semantics로 구현한다.

## 15. 의존성 전략

추가 dependency는 다음을 통과해야 한다.

- stdlib/Windows SDK/current dependency로 해결 불가
- x64/ARM64 native artifact
- active maintenance와 pinned version
- license/provenance/SBOM
- reproducible restore/build
- security update policy
- binary size/startup/working-set 비용
- failure/fallback plan

초기 후보:

- SQLite
- libtiff 또는 WIC 보강 codec
- lcms2가 WCS/D2D만으로 충족되지 않을 때
- Windows Community Toolkit SettingsControls가 prototype을 통과할 때

OpenCV 전체, cross-platform UI, general plugin framework는 범위보다 크므로 도입하지 않는다.

## 16. 문서 운영

각 문서는 다음 header를 갖는다.

- 기준일
- macOS baseline
- 상태: 결정/조건부/후보/실측 필요
- source evidence
- official external evidence
- acceptance/failure criteria

문서가 구현보다 앞설 수는 있지만, 실행하지 않은 검증을 “지원/통과/완료”로 쓰지 않는다. version·API·OS
지원처럼 변하는 사실은 release planning 때 다시 공식 문서로 확인한다.

## 17. 병렬 개발 시 ownership

향후 여러 개발자가 병렬 작업할 때 경계를 명시한다.

- baseline/spec owner
- native core/color owner
- render/GPU owner
- catalog/storage owner
- WinUI surface owner
- scanner protocol/plugin owner
- release/QA owner

공유 file을 동시에 광범위하게 refactor하지 않는다. feature branch가 다른 backend 결과를 새로운 truth로
만들지 않게 conformance fixture를 central gate로 둔다.

## 18. 중단·회귀 조건

다음이 보이면 기능 확장을 중단하고 기반을 고친다.

- original 또는 third-party sidecar가 수정됨
- CPU/GPU/vendor별 final semantics가 갈림
- corrupt catalog가 empty로 열림
- stale async result가 다른 frame에 적용됨
- cache clear가 user output/source에 닿음
- UI thread가 codec/GPU/process wait로 막힘
- ARM64가 compile-only이고 실제 실행되지 않음
- plugin crash가 host를 종료
- preview와 export가 다른 recipe/math를 사용
- tolerance가 실패할 때마다 넓어짐
- signed/installer evidence 없이 release-ready 선언

## 19. 완료 정의

Windows v1은 다음을 모두 만족할 때만 완료다.

- 지원 기능·의도적 제외가 compatibility matrix와 일치
- baseline conformance가 x64/ARM64와 필수 backend에서 통과
- 모든 핵심 surface의 normal/error/recovery 상태가 parity contract 통과
- 원본/recipe/catalog/export/backup fault injection 통과
- scanner는 실제 지원 device matrix에만 지원 표기
- Intel/AMD/NVIDIA/Qualcomm CPU/GPU matrix 실측
- installer clean install/upgrade/repair/uninstall/signature 통과
- accessibility/localization/scaling real UI QA
- 알려진 risk와 미검증 항목이 release note에 남음

## 20. 관련 문서

- [architecture](architecture.md)
- [decision register](decision-register.md)
- [compatibility matrix](compatibility-matrix.md)
- [UI parity contract](../08-ui/parity-contract.md)
- [backend selection](../12-performance/backend-selection.md)
- [solution layout](../13-build-and-deps/solution-layout.md)
- [spike checklist](../99-plan/spike-checklist.md)
- [maintenance](../99-plan/maintenance.md)

