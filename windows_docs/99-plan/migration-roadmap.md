# Negaflow Windows 네이티브 이행 로드맵

> 상태: 구현 전 실행 기준  
> 기준일: 2026-08-04  
> 전제: 별도 Windows 저장소, C#/.NET WinUI 3 셸, C++20 엔진, x64·순수 ARM64, D3D11/Direct2D, 완전한 CPU 경로, 외부 프로세스 스캐너 플러그인  
> 범위: macOS Negaflow의 제품 경험을 Windows에서 99.9% 동등하게 재구현하기 위한 순서·gate·증거  
> 비범위: 이 문서는 일정 약속, 인원 산정, production 코드가 아니다.

## 0. 결론

Windows판은 macOS 코드를 기계적으로 번역하는 프로젝트가 아니다. 다음 네 자산을 고정한 뒤 Windows 네이티브 기술로 다시 구현하는 프로젝트다.

1. 제품 동작과 UI/UX 상태 계약
2. 이미지·색·측정·결함 파이프라인의 수치 계약
3. catalog·recipe·sidecar·scanner protocol의 데이터 계약
4. fixture·golden·실기기 matrix로 구성된 합격 기준

이행 순서는 다음과 같이 고정한다.

```text
기준선·권리·지원 범위 고정
  → 재현 가능한 x64/ARM64 빌드와 CLI
  → CPU scalar 정답 구현
  → 이미지 IO·색 관리·catalog 안전성
  → 한 장의 end-to-end CLI vertical slice
  → D3D11/Direct2D/WARP와 물리 GPU 동등성
  → 대형 이미지·스레딩·취소·복구
  → 좁은 C ABI와 WinUI 3 shell/canvas
  → Library·Develop·Defects·Export·Print·Settings
  → scanner host와 독립 plugin
  → 성능·접근성·hardware matrix
  → 서명·MSI·update·rollback·license/SBOM
  → Beta → Release Candidate → Stable
```

핵심 운영 규칙:

- macOS `main`을 움직이는 목표로 쫓지 않는다. exact baseline manifest와 delta ledger를 사용한다.
- x64 먼저 만든 뒤 ARM64를 나중에 붙이지 않는다. 첫 native CLI부터 두 architecture를 함께 유지한다.
- GPU부터 구현하지 않는다. 각 kernel의 CPU scalar 의미를 먼저 고정한다.
- WARP 통과를 실제 Intel/NVIDIA/AMD/Qualcomm 검증으로 말하지 않는다.
- UI가 보인다는 이유로 엔진·데이터·export 동등성이 끝났다고 보지 않는다.
- scanner는 코어 앱 완성의 전제도, 코어 process의 dependency도 아니다.
- CUDA는 v1 critical path에 없다. 범용 D3D11·CPU 경로가 끝난 뒤 별도 성능 gate를 통과해야 한다.
- 일정은 각 milestone의 증거가 만들어진 뒤 추정한다. 근거 없는 주·월 숫자를 문서에 고정하지 않는다.

---

## 1. 완료 상태의 정의

Windows v1이 완료됐다는 말은 다음이 동시에 참이라는 뜻이다.

### 제품

- import → Library → Develop → Export가 완전하다.
- Library → Print가 완전하다.
- scanner plugin이 설치된 경우 Scan → Develop → Export가 capability 기반으로 완전하다.
- plugin이 없어도 앱 시작, 가져오기, 편집, 내보내기, 인화가 완전하다.
- macOS판의 핵심 정보 구조, 상태 전이, 비활성 조건, 오류·복구, keyboard, accessibility 의미가 99.9% 동등하다.

### 이미지 품질

- 같은 source·recipe·algorithm version·ICC 조건에서 CPU scalar 기준과 승인한 허용 오차 내 일치한다.
- x64 Intel/AMD, ARM64, WARP, Intel/NVIDIA/AMD/Qualcomm GPU가 각 gate를 통과한다.
- preview와 export는 같은 현상 의미를 사용한다.
- GPU 실패가 부분 출력 또는 조용한 원본 fallback을 만들지 않는다.

### 데이터 안전

- 원본과 third-party XMP를 덮어쓰지 않는다.
- catalog migration, disk full, crash, cancellation, stale async result를 안전하게 처리한다.
- 비파괴 결과를 재구성할 수 없으면 export가 명시적으로 실패한다.
- uninstall/update/rollback이 사용자 catalog·original·export·plugin을 오소유하지 않는다.

### 배포

- x64와 ARM64가 각각 서명·timestamp·SBOM·notices·baseline manifest를 가진다.
- clean install, update, repair, uninstall, rollback rehearsal가 통과한다.
- 지원 중인 Windows·.NET·Windows App SDK·toolchain을 사용한다.
- 플러그인은 독립 서명·installer·license·SBOM·source 경계를 가진다.

### 증거 정직성

- 자동화, WARP, 물리 GPU, 실제 UI, 실제 scanner 검증을 서로 구분한다.
- 실행하지 않은 검증을 통과로 표시하지 않는다.
- known difference는 분류·근거·owner·만료일을 가진다.

---

## 2. 로드맵의 관리 단위

### 2.1 Milestone

사용자 가치 또는 아키텍처 위험 하나를 닫는 큰 경계다. 각 milestone은 다음을 가진다.

- 진입 조건
- 구현 범위
- 의도적 비범위
- 자동 검증
- 실기기·수동 검증
- 산출물
- 종료 조건
- 실패 시 대안

### 2.2 Work package

Milestone 안에서 독립적으로 검토 가능한 작은 작업이다. ID 형식 예시:

```text
GOV-001    governance/baseline
BLD-001    build/toolchain
ENG-001    native engine
IO-001     image IO
CLR-001    color
GPU-001    GPU
CPU-001    CPU/SIMD
ABI-001    interop
UI-001     WinUI
CAT-001    catalog
SCN-001    scanner
PKG-001    packaging
QA-001     validation
```

ID 체계는 실제 Windows 저장소에서 확정한다. 이 문서의 목적은 todo를 많이 만드는 것이 아니라 요구→구현→시험→릴리스 증거를 한 줄로 추적하는 것이다.

### 2.3 Gate

Gate는 checklist 개수나 코드 줄 수가 아니라 관찰 가능한 합격 기준이다. 면제할 수 있는 gate는 다음을 가져야 한다.

- 면제 사유
- 사용자 영향
- 대상 architecture/device/channel
- 완화책
- owner
- 만료일
- 재검토 조건

데이터 손실, 원본 변조, required export 재구성 실패, core/plugin license 혼합, 지원하지 않은 architecture 표시는 면제할 수 없다.

---

## 3. 작업 흐름과 의존성

### 3.1 Critical path

```text
M0 제품 기준선
  └─ M1 저장소·빌드·CI
      └─ M2 적합성 harness와 CPU scalar
          ├─ M3 이미지 IO·색·영속성
          │   └─ M4 CLI vertical slice
          │       └─ M5 GPU·WARP vertical slice
          │           └─ M6 전체 Develop graph
          │               └─ M7 대형 이미지·스케줄링
          │                   └─ M8 ABI·WinUI shell/canvas
          │                       └─ M9–M14 제품 surface
          └─ M15 scanner protocol host
                              └─ M16 hardware/performance qualification
                                  └─ M17 packaging/update/compliance
                                      └─ M18 Beta/RC/Stable
```

Scanner plugin 구현 자체는 M15 이후 별도 저장소에서 진행할 수 있지만, 코어 앱의 Stable은 scanner를 제외한 제품 범위만으로도 완전해야 한다. 특정 scanner 지원을 Stable에서 주장하려면 해당 plugin과 실기기 matrix가 별도 gate를 통과해야 한다.

### 3.2 병렬화 가능한 흐름

기준선과 contract가 확정된 뒤 병렬화할 수 있다.

- UI surface inventory와 localization preparation
- synthetic fixture와 corpus 권리 정리
- x64/ARM64 CI image 구축
- scanner protocol fixture와 mock plugin
- installer/license/SBOM spike
- 실제 hardware 확보와 driver inventory

병렬화하면 안 되는 순서:

- scalar 의미 고정 전 GPU 최적화
- catalog 불변식 고정 전 UI persistence
- capability contract 전 vendor scanner UI
- final payload 전 third-party notice 확정
- numerical conformance 전 golden 갱신 자동화

---

## 4. M0 — 제품 기준선과 출시 경계 고정

### 목적

Windows가 무엇을 이식하며 무엇을 이식하지 않는지 exact manifest로 고정한다.

### 진입 조건

- 현재 macOS 저장소를 읽을 수 있다.
- Windows 구현은 아직 production repository로 시작하지 않았다.
- 제품 owner가 baseline freeze를 승인할 수 있다.

### 작업

#### GOV-001 — Exact macOS baseline

- clean commit SHA
- dirty 여부
- supported feature 목록
- product version은 참고값으로만 기록
- baseline 이후 delta 시작점

현재 결정 등록부는 `9be909c`를 조사 기준으로 기록하지만, 실제 구현 착수 시 해당 commit을 최종 baseline으로 자동 간주하지 않는다. 착수일에 clean 상태와 자산을 다시 고정한다.

#### GOV-002 — Baseline manifest

- product specification version
- catalog/sidecar/recipe/algorithm schema
- scanner protocol version
- presets/scanner profiles/localization hash
- kernel inventory와 수학 정의
- fixture/expectation/tolerance version
- known differences
- toolchain은 Windows M1에서 채움

#### GOV-003 — Surface manifest

macOS 화면을 파일 이름이 아니라 사용자 surface로 inventory한다.

- app shell/title/menu/toolbar/status
- Library grid/list/folder/sidebar/search/filter
- Canvas/zoom/pan/compare/overlay
- Develop inspector와 모든 adjustment state
- Defects detect/edit/undo/cache
- Export ordinary/quick/batch/output tab
- Print ordinary/contact sheet/profile/soft proof
- Scan discovery/capability/preview/full scan/error
- Settings/general/storage/performance/color/scanner/shortcuts
- dialogs, empty, loading, disabled, error, recovery

#### GOV-004 — 지원 범위

결정할 것:

- Windows v1 feature set
- 첫 출시 시 minimum/tested/supported Windows edition/build
- x64와 ARM64 동시 출시 여부 — 원칙상 둘 다 1급
- camera RAW를 v1에 포함할지
- Print 전체를 v1에 포함할지
- core Stable과 scanner plugin release를 같은 날 묶을지
- macOS catalog 직접 이관을 지원할지
- Windows 10을 제외하는 결정 재확인

Windows 11 24H2 Home/Pro는 2026-10-13 end of updates이므로 `24H2 후보`를 오래된 고정값으로 두지 않는다. 실제 출시 시 지원 중인 일반 소비자 OS를 기준으로 다시 결정한다.

#### GOV-005 — 권리·의존성 결정

초기 차단 결정을 닫는다.

- LittleCMS core features
- libtiff/zlib features
- SQLite provider 하나
- LibRaw 포함 여부와 선택 license
- WiX 사용 조건·비용 승인 또는 installer 대안
- TWAIN DSM 배포 방식
- Adobe RGB 등 ICC 재배포
- corpus/font/icon/profile provenance

### 자동 검증

- baseline manifest schema
- generated action/localization/asset layer와 curated surface/state/delta layer
- 모든 asset hash
- surface manifest ID unique
- delta ledger 생성
- 문서 내부 링크

### 수동 검증

- macOS baseline 앱의 주요 workflow 실제 기록
- UI screenshot만 아니라 state transition·keyboard·error path 기록
- 대표 source/recipe/export 산출물 확보

### 산출물

- immutable baseline manifest
- surface manifest
- feature inclusion/exclusion list
- open legal decisions를 승인/제외로 닫은 기록
- delta ledger
- fixture 권리 manifest

### 종료 조건

- 구현자가 `macOS 최신과 같게`라는 문장 없이 Windows v1 범위를 설명할 수 있다.
- 모든 필수 surface와 수치 stage가 stable ID를 가진다.
- 출시를 막는 license 선택이 식별됐다.

### 실패 시

기준선을 선택할 수 없으면 Windows 구현을 시작하지 않는다. moving target 위의 코드는 완료 기준을 가질 수 없다.

---

## 5. M1 — Windows 저장소·도구 체인·x64/ARM64 CI

### 목적

제품 기능 없이도 재현 가능하고 architecture가 분리된 build graph를 만든다.

### 진입 조건

- M0 baseline manifest 승인
- Windows repository 위치와 공개/비공개 정책 결정
- toolchain license 사용 권한 확인

### 작업

#### BLD-001 — 저장소 골격

[../13-build-and-deps/solution-layout.md](../13-build-and-deps/solution-layout.md)의 책임 경계를 최소 형태로 만든다.

- CMake native graph
- C#/.NET WinUI graph
- C ABI header 위치
- CLI
- tests
- shader build
- assets
- packaging
- release evidence

빈 추상 계층과 미래 plugin interface를 먼저 만들지 않는다.

#### BLD-002 — 도구 체인 고정

- supported Visual Studio/Build Tools
- MSVC toolset
- Windows SDK
- .NET LTS SDK/runtime
- Windows App SDK Stable
- CMake/Ninja
- vcpkg baseline
- NuGet lock
- shader compiler
- installer tool

#### BLD-003 — architecture preset

- x64 Debug/Release
- ARM64 Debug/Release 또는 최소 Release+test
- WARP test configuration
- no-GPU/CPU-only configuration
- x86는 core graph에 없음

#### BLD-004 — CI

필수 최소:

- x64 hosted clean restore/build/test
- ARM64 native build
- 실제 Windows ARM64 run lane
- dependency license/SBOM preview
- shader offline compile
- artifact hash/provenance
- warning/error policy

ARM64 native 실행은 x64 emulation이나 cross-compile 성공으로 대체하지 않는다. Microsoft 공식 문서도 driver는 emulation되지 않고 native ARM64가 필요하다고 설명하므로, scanner는 더 엄격한 별도 hardware gate를 가진다.

#### BLD-005 — CLI hello contract

GUI 없이 다음을 출력하는 작은 executable부터 시작한다.

- build ID
- architecture
- compiler/runtime version
- CPU feature tier
- adapter inventory 명령의 빈/기본 결과
- structured error

### 자동 검증

- clean checkout build
- locked restore
- x64 executable run
- ARM64 executable native run
- architecture mismatch artifact 검사
- C ABI symbol allowlist의 초기 빈 표면
- dependency manifest과 payload preview

### 산출물

- clean build logs
- x64/ARM64 CLI artifact
- toolchain manifest
- dependency lock
- artifact naming convention

### 종료 조건

- 두 architecture가 같은 source와 lock으로 독립 빌드·실행된다.
- cache 없이 clean restore가 가능하다.
- unresolved version이나 `latest`가 release manifest에 없다.
- production 기능은 아직 없다고 명확히 표시된다.

### 실패 시

ARM64 dependency가 막히면 ARM64를 나중으로 미루지 않는다. 해당 dependency를 대체·제외하거나 제품 범위를 다시 결정한다.

---

## 6. M2 — 적합성 harness와 CPU scalar 정답

### 목적

GPU와 UI 없이 이미지 파이프라인의 의미를 실행 가능한 계약으로 만든다.

### 진입 조건

- M1 x64/ARM64 CLI 실행
- M0 kernel/stage inventory
- fixture 권리 승인

### 작업

#### QA-001 — Fixture schema

- gradient와 extended range
- asymmetric coordinate pattern
- color patches
- alpha/transparent edge
- tiny/odd dimensions
- NaN/Inf/denormal 정책 fixture
- oversized/overflow metadata
- deterministic noise seed

#### QA-002 — Expectation levels

- exact contract
- scalar numeric
- decision output
- perceptual image
- metadata/container
- performance budget

#### ENG-001 — Pixel model

- working space
- transfer function
- premultiplication
- alpha 의미
- extended range
- coordinate origin/pixel center
- border mode
- float NaN/Inf 처리
- clipping stage

#### CPU-001 — Scalar kernel library

각 kernel은 다음을 가진다.

- 명시적 input/output domain
- parameter validation
- scalar loop
- ROI expansion
- edge policy
- cancellation granularity
- golden fixture

초기 순서:

1. matrix/exposure/basic pointwise
2. negative inversion
3. curves
4. blur/local contrast
5. histogram/statistics
6. morphology/defect primitives
7. crop/transform/resize
8. digital-film kernels

#### CPU-002 — SIMD dispatch foundation

- x64 baseline SSE2/MSVC default
- AVX2와 FMA 독립 feature detection
- OSXSAVE/XGETBV
- ARM64 NEON baseline
- forced scalar/base/AVX2 test modes
- immutable function table
- 전역 fast-math 금지

수동 SIMD는 profiling 전 최소화한다.

#### QA-003 — macOS expectation 생성

macOS baseline에서 같은 fixture·parameter의 stage report를 생성한다. 플랫폼 API가 다른 경우 다음을 기록한다.

- exact 비교 가능한 항목
- 알고리즘 사양으로 정해야 할 항목
- 허용 오차가 필요한 항목
- macOS 구현 결함으로 의심되는 항목

macOS 결과를 설명 없이 절대 정답으로 고정하지 않는다.

### 자동 검증

- scalar x64/ARM64 동일 contract
- forced feature tier
- bounds/overflow/malformed input
- tile/order independence가 해당되는 kernel
- deterministic rerun
- golden diff report

### 산출물

- conformance runner
- fixture/expectation/tolerance v1
- scalar kernel inventory
- CPU dispatch report
- known numeric differences

### 종료 조건

- 핵심 pipeline의 수학을 GUI 없이 재현할 수 있다.
- GPU kernel이 비교할 CPU reference를 가진다.
- ARM64 scalar 결과가 x64와 승인 범위 내 일치한다.
- tolerance가 실패를 숨기기 위해 일괄 확대되지 않았다.

### 실패 시

macOS 자체 의미가 불명확하면 제품 사양 결정을 먼저 한다. 불명확한 결과를 HLSL에 복제하지 않는다.

---

## 7. M3 — 이미지 IO·색 관리·영속성 기반

### 목적

실제 사진을 안전하게 열고 색을 해석하고 저장하되 원본과 catalog를 보호한다.

### 진입 조건

- M2 pixel/color contracts
- dependency/license 초기 승인
- resource budget 정책

### 작업

#### IO-001 — 입력 probe/router

- extension은 힌트
- magic/container/decoder identity 검증
- WIC standard image
- libtiff controlled fallback
- LibRaw는 M0 승인 시에만
- dimensions/sample/stride/ICC/metadata bounds
- third-party WIC codec 자동 신뢰 금지

#### IO-002 — TIFF

- 8/16-bit integer
- float input 정책
- strips/tiles
- orientation
- ICC/EXIF allowlist
- LZW/Deflate
- BigTIFF 조건
- readback
- atomic publish

#### IO-003 — JPEG/PNG/HEIF

- WIC capability corpus
- JPEG quality/subsampling mapping
- PNG 16-bit/ICC roundtrip
- HEIF codec unavailable UX
- metadata privacy
- WIC 부족 시 library 추가 gate

#### CLR-001 — LittleCMS reference

- bounded ICC bytes
- app-owned context
- input→working
- working→display
- working→output
- proofing/gamut warning
- explicit intent/BPC
- transform cache key
- GPL optional plugin 부재

#### CAT-001 — SQLite store

- provider 하나
- schema/user version 분리
- transaction/serialized writer
- lock ownership
- verified commit/readback
- catalog absent/corrupt 구분
- backup/recovery
- migration interruption

#### DATA-001 — 경로와 atomic write

- app-owned root
- source reference
- thumbnail/cache/temp/staging
- safe filename
- same-directory temporary publish
- reparse point/symlink defense
- disk full/cancel/crash

### 자동 검증

- malformed image/ICC/container corpus
- WIC/libtiff independent readback
- color transform golden
- catalog crash-point matrix
- JSON→SQLite migration if required
- source file hash unchanged
- x64/ARM64 dependency runtime

### 실기기·수동 검증

- real monitor ICC enumeration
- Advanced Color/SDR/HDR mixed displays
- long Unicode path, network/removable/sync folder behavior
- representative large scanner TIFF

### 산출물

- safe image probe/decode CLI
- color transform CLI
- atomic export primitive
- catalog fixture and migration report
- dependency/license inventory update

### 종료 조건

- 지원 format을 native sample precision과 명시한 색 의미로 읽는다.
- 원본을 한 바이트도 수정하지 않는다.
- catalog 실패가 빈 library 또는 orphan deletion으로 오해되지 않는다.
- output은 write/readback/atomic publish를 거친다.

---

## 8. M4 — CLI end-to-end vertical slice

### 목적

WinUI 없이 한 장을 `probe → decode → develop → color convert → export → readback`한다.

### 진입 조건

- M2 scalar core
- M3 IO/color/atomic output
- baseline negative inversion recipe

### 첫 vertical slice

지원 범위를 의도적으로 좁힌다.

- 하나의 검증된 TIFF input
- 하나의 working space
- manual negative inversion
- exposure/contrast/curve의 최소 조합
- 16-bit TIFF export
- embedded output ICC
- metadata allowlist
- CLI structured report

### 포함할 증거

- source hash before/after
- decoded sample report
- stage-by-stage digest/statistics
- final pixel diff
- output container/ICC/tags
- macOS baseline export 비교
- x64/ARM64 결과
- peak memory와 wall/CPU time

### 비범위

- UI
- scanner
- batch
- defect edit
- full digital film
- JPEG/PNG 최종 tuning
- GPU

### 종료 조건

- 같은 fixture와 recipe가 x64/ARM64에서 재현된다.
- macOS 기대값과 차이가 설명·승인된다.
- 실패 시 원본 또는 임시 output을 성공으로 보이지 않는다.
- 이 경로가 이후 UI가 호출할 제품 엔진의 실제 시작점이다.

---

## 9. M5 — D3D11·Direct2D·WARP vertical slice

### 목적

GPU 범용성·정밀도·복구 위험을 전체 파이프라인을 늘리기 전에 닫는다.

### 진입 조건

- M4 CPU end-to-end truth
- offline shader build
- WARP CI lane

### 선행 spike

#### GPU-001 — FP32 extended range

- `-0.5`, `0.5`, `1.5`, `3.0`
- pointwise custom effects chain
- 32-bpc float surface
- linked/unlinked 결과
- WARP와 물리 GPU

#### GPU-002 — Negative inversion

- HLSL/Direct2D custom effect
- asymmetric coordinate fixture
- CPU scalar 비교
- actual shader linking evidence
- offline compiled blob provenance

#### GPU-003 — Measurement

- histogram
- area average
- percentile/reduction policy
- deterministic decision output
- GPU difference가 허용 범위를 넘으면 CPU measurement 유지

#### GPU-004 — D2D↔DirectCompute interop

- 같은 D3D11 device/resource
- state/hazard 명시
- copy/readback count
- format support
- WARP
- device removed/OOM

#### GPU-005 — Swap chain prototype

- flip model
- SwapChainPanel 연결
- composition scale/DPI
- resize/occlusion
- device generation
- screenshot은 증거의 일부일 뿐 numeric result도 확인

### 물리 matrix

- Intel x64
- AMD x64
- NVIDIA x64
- Qualcomm ARM64
- WARP

모든 vendor가 첫 spike와 같은 날 준비될 필요는 없지만, Stable 범용성 결론 전에는 필요하다.

### 종료 조건

- extended range가 필수 graph에서 보존된다.
- negative inversion이 CPU reference와 허용 오차 내 일치한다.
- WARP에서 production shader blob이 load/execute된다.
- 적어도 한 물리 GPU와 한 ARM64 장치에서 실제 실행된다.
- device lost/OOM이 recipe를 잃지 않는다.
- 실패 시 CPU 전체 재실행 또는 명시적 오류가 된다.

### 실패 시 대안

- measurement만 CPU 결정적 경로
- 특정 local/neighborhood kernel만 CPU
- D2D 효과가 아닌 D3D11 compute
- GPU 전체 사용 불가 시 CPU complete backend

D3D12로 즉시 전환하지 않는다. [../12-performance/backend-selection.md](../12-performance/backend-selection.md)의 계측 gate가 필요하다.

---

## 10. M6 — 전체 Develop·측정·디지털 필름 그래프

### 목적

macOS baseline의 현상 의미 전체를 CPU와 GPU에서 재현한다.

### 작업 묶음

#### DEV-001 — Pipeline graph

- stage ordering
- enable/disable semantics
- default value
- parameter snapshot
- revision/session identity
- ROI propagation
- intermediate cache key
- preview/export shared semantics

#### DEV-002 — Basic adjustments

- exposure
- contrast
- white/black
- highlights/shadows
- temperature/tint
- saturation/vibrance
- curve
- channel mix if baseline includes it

#### DEV-003 — Negative workflow

- film base measurement
- manual target default
- negative inversion
- profile/preset source
- auto behavior는 explicit opt-in
- base measurement failure/recovery

#### DEV-004 — Measurement and auto parameters

- histogram/statistics
- ROI coordinate normalization
- deterministic reduction
- invalid/empty region
- stale result suppression
- vendor difference rule

#### DEV-005 — Digital/virtual development

- source mode invariant
- persisted default/legacy behavior
- complete graph selection
- deterministic noise
- grain size versioning
- blur edge parity
- intensity 0/0.5/1 tests
- missing kernel 시 partial output 금지

#### DEV-006 — Presets/versions

- canonical assets
- copy-on-write virtual copy semantics
- recipe/algorithm version
- backward read/current write
- preset update가 기존 photo를 조용히 바꾸지 않음

### 중요 현재 위험

macOS current code에서 negative source와 `isDigitalSource`가 모순된 persisted 조합일 때 UI 분기와 post-pipeline 분기가 다를 가능성이 문서 조사에서 발견됐다. Windows는 이 모순을 그대로 복제하지 않는다.

- source mode invariant를 decode 시 검증
- invalid combination은 repair 또는 명시 오류
- UI surface와 engine graph가 동일 normalized mode 사용
- legacy migration fixture 추가

### 종료 조건

- 모든 production kernel에 CPU scalar와 GPU/CPU 선택 규칙이 있다.
- missing GPU kernel이 identity pass로 조용히 빠지지 않는다.
- preview와 export의 parameter·color·edge 의미가 일치한다.
- 기존 recipe algorithm version을 재현한다.
- x64/ARM64와 WARP 전체 conformance가 통과한다.

---

## 11. M7 — 대형 이미지·타일·스레딩·취소

### 목적

고해상도 필름 스캔과 대량 export를 bounded memory와 예측 가능한 progress로 처리한다.

### 진입 조건

- M6 full graph
- operation별 ROI/halo 정의
- CPU/GPU complete backend

### 작업

#### MEM-001 — ImageSource

- immutable source identity
- level-of-detail
- tile coordinates
- decoded tile cache
- ICC normalization boundary
- orientation/crop mapping
- eviction

#### MEM-002 — ROI/halo

- pointwise zero halo
- blur/morphology dependent halo
- crop/transform inverse mapping
- border policy
- tile seam corpus
- absolute coordinate noise

#### THR-001 — Bounded scheduler

- interactive/export priority
- worker limit
- per-job memory reservation
- decode/render/encode backpressure
- single-writer output
- cancellation token
- stale revision drop

#### GPU-006 — GPU memory budget

- adapter budget query
- working surface count
- tile residency
- staging/readback
- UMA/dedicated distinction
- eviction hysteresis
- TDR-safe dispatch size

#### EXP-001 — Progress semantics

- planning
- first-file preparation
- render
- encode
- readback/verify
- publish
- aggregate batch

0%에서 오래 도는 상태를 progress ring 하나로 숨기지 않는다.

### corpus

- 50MP
- 100MP
- 매우 긴 panorama
- multi-hundred-megapixel scanner output
- odd dimensions
- high-radius effect
- batch with heterogeneous sizes
- disk slow/full
- cancellation at every stage

### 종료 조건

- peak memory가 budget 내다.
- tile seam이 없다.
- 타일 크기/순서가 deterministic effect를 바꾸지 않는다.
- interactive 조정이 batch export에 굶지 않는다.
- cancel 후 partial final file이 없다.
- 가장 느린 대상 GPU에서 TDR를 유발하지 않는다.

---

## 12. M8 — C ABI·WinUI 3 shell·canvas vertical slice

### 목적

검증된 엔진을 좁은 경계로 WinUI 3에 연결해 실제 사용자 조작 한 줄을 완성한다.

### 진입 조건

- M4 CPU vertical slice
- M5 GPU/SwapChainPanel prototype
- M7 async/cancellation ownership
- ABI contract draft

### 작업

#### ABI-001 — Versioned C ABI

- opaque handle
- fixed-width types
- UTF-8 + explicit length
- caller/engine allocator ownership
- `struct_size`/ABI version
- request ID
- bounded event polling
- cancellation
- stable error code + diagnostic chain
- no STL/exception/COM pointer across public boundary

#### ABI-002 — C# interop

- source-generated `LibraryImport`
- `SafeHandle`
- ABI size/layout assertions
- no large pixel buffer crossing
- event dispatcher ownership
- stale request suppression
- native DLL load diagnostics

#### UI-000 — Process·activation·lifecycle

- 사용자·제품 채널별 primary UI process 하나
- custom `Main`에서 window/engine/catalog 전 instance election
- x64·ARM64 activation redirection
- main/Settings/About/Help window registry
- normal close coordinator와 latest-generation read-back
- `WM_QUERYENDSESSION`/`WM_ENDSESSION` bounded recovery bridge
- activation/close/update race와 stable terminal receipt

#### UI-001 — Shell

- AppWindow/title bar
- navigation/sidebar/toolbar/inspector/status
- command/action IDs
- window geometry
- minimum size
- high DPI/text scale skeleton
- native menu and keyboard routing

#### UI-002 — Canvas

- SwapChainPanel host
- zoom/pan/fit/100%
- pointer coordinate conversion
- DPI/monitor move
- loading/error/device lost
- frame pacing
- no CPU bitmap roundtrip per frame

#### UI-003 — Thin workflow

```text
Open one approved image
  → Library placeholder record
  → Develop one adjustment
  → canvas updates
  → Export 16-bit TIFF
  → output verified
```

### 조건부 C++/WinRT 예외

C ABI로 SwapChainPanel native interface 전달이 안정적이지 않을 때 패널 연결만 담당하는 얇은 C++/WinRT adapter를 허용한다.

- 일반 domain/engine API를 WinRT로 확장하지 않음
- x64/ARM64
- unpackaged self-contained
- lifetime and dispatcher test
- packaging/activation burden 측정

### 종료 조건

- 실제 WinUI 3 앱에서 한 장의 end-to-end workflow가 된다.
- UI thread가 decode/render/export를 동기 실행하지 않는다.
- 조정 revision이 뒤집혀 적용되지 않는다.
- 화면과 export가 같은 engine graph를 호출한다.
- x64와 실제 ARM64에서 실행된다.
- second launch가 새 catalog writer를 만들지 않고 primary로 전달된다.
- main close와 auxiliary close의 process lifetime 의미가 macOS 계약과 맞는다.
- normal close와 OS session-end의 서로 다른 deadline·복구 경계가 검증된다.

이 milestone은 제품 완성이 아니라 UI/engine 경계의 위험 제거다.

---

## 13. M9 — Library·Import·catalog UX

### 목적

사진과 폴더를 안전하게 가져오고 대규모 library를 네이티브 Windows UX로 관리한다.

### 작업

#### LIB-001 — Import

- file/folder picker
- duplicate identity
- source reference
- metadata probe
- thumbnail job
- import cancellation
- unsupported/corrupt file report
- auto-develop default OFF

#### LIB-002 — Catalog model

- film/folder/frame relationships
- virtual copy
- visible name
- search/filter/sort
- removal vs filesystem trash 분리
- relink
- unavailable source

#### LIB-003 — Grid/list virtualization

- 50,000-item fixture
- stable selection
- range/multi selection
- incremental thumbnail
- scroll position
- keyboard navigation
- drag/drop if baseline requires

#### LIB-004 — Folder tree

- expansion state persistence
- rename/create/delete semantics
- app restart
- missing/moved root
- no implicit filesystem mutation

#### LIB-005 — UI states

- empty library
- import progress
- partial failures
- offline source
- catalog recovery
- thumbnail decode error
- no search result

### 종료 조건

- large virtual library에서 memory/scroll/selection budget을 만족한다.
- import가 원본을 수정하지 않는다.
- library remove와 trash가 명확히 다르다.
- catalog 손상 시 빈 library로 시작해 자료를 삭제하지 않는다.
- folder expansion and selection state가 재시작 후 계약대로 유지된다.

---

## 14. M10 — Develop surface

### 목적

엔진에 이미 존재하는 현상 계약을 macOS판과 동등한 WinUI 3 inspector 경험으로 노출한다.

### 작업

- inspector section order
- slider/text/stepper semantics
- min/max/default/reset
- enabled/disabled logic
- manual main target default
- explicit automatic opt-in
- preset picker
- film/source mode
- crop/rotate controls
- histogram/status
- compare/before-after
- undo/redo/history/version
- keyboard focus and shortcuts
- loading/stale/error states

### UI 원칙

- ordinary control은 resting state에서 조용하다.
- stateful segmented control은 track/thumb 상태를 유지한다.
- 모든 조정은 native control semantics와 UI Automation name/value를 가진다.
- macOS chord를 그대로 복제하지 않고 Windows convention과 action identity를 보존한다.
- engine parameter range를 UI에서 재정의하지 않는다.

### 종료 조건

- baseline Develop state inventory 전체가 surface manifest에 매핑된다.
- keyboard-only로 주요 조정과 reset이 가능하다.
- rapid slider input에서 stale result가 적용되지 않는다.
- disable/enable이 recipe 값을 소실하지 않는다.
- UI numeric value와 export recipe가 일치한다.

---

## 15. M11 — Defects·결함 편집

### 목적

자동 검출, 수동 보정, recipe, cache를 비파괴로 이식한다.

### 작업

#### DEF-001 — Detection

- RGB software defect 경로
- IR input은 plugin capability와 실제 artifact가 있을 때만
- RGB Software ICE와 hardware IR/Digital ICE를 동일하다고 표현하지 않음
- deterministic thresholds
- connected component/geometry
- large image tiles

#### DEF-002 — Recipe

- source-relative coordinate
- brush/sample/clone semantics
- undo/redo
- revision
- serialize/migrate
- virtual copy isolation
- no source bake

#### DEF-003 — Interaction

- mouse/pen/touch policy
- Surface Pen/Wacom pointer sampling
- pressure support는 실제 input evidence 후
- cursor/overlay
- zoom-dependent hit test
- keyboard modifier
- latency and dropped event measurement

#### DEF-004 — Cache

- cleaned-raw cache is derivative
- recipe/source/algorithm hash key
- atomic build/publish
- corrupt cache invalidation
- export reconstruction
- cache missing은 original fallback이 아님

### 종료 조건

- edit가 source hash를 바꾸지 않는다.
- recipe만으로 결과를 재구성한다.
- cache 손상·부재가 보이는 실패 또는 안전 재생성을 만든다.
- rapid edit/cancel에서 frame/revision ownership이 유지된다.
- IR capability가 없는 device/photo에 IR UI가 없다.

---

## 16. M12 — Export·batch·metadata

### 목적

ordinary, Quick Export, batch, toolbar/Output-tab 경로가 동일한 품질·진행·오류 계약을 공유한다.

### 작업

#### EXP-002 — Export plan

- source/revision snapshot
- naming template
- collision policy
- destination permission/free space
- format/bit depth/quality/DPI/ICC
- metadata policy
- existing file overwrite confirmation
- batch ordering

#### EXP-003 — Render/encode

- same develop graph
- resize/sharpen order
- output ICC
- quantization/dither
- TIFF/JPEG/PNG
- atomic temporary/write/readback/publish
- failure cleanup

#### EXP-004 — Progress

- first-file preparation separate
- per-file and aggregate
- cancel queued/in-flight
- error list
- retry policy
- completed files not rolled back unless transaction says so

#### EXP-005 — Cross-reader validation

- WIC
- libtiff where applicable
- macOS ImageIO
- representative external editor/printer workflow manual QA

### 성능 truth

다음을 낮춰 속도를 만들지 않는다.

- resolution
- quality
- DPI
- ICC transform
- bit depth

실제 loaded photo와 large virtual batch를 모두 측정한다.

### 종료 조건

- ordinary/Quick Export/toolbar/Output-tab이 같은 output contract를 사용한다.
- first-file 0% stall이 단계별 progress로 보인다.
- source와 third-party sidecar가 unchanged다.
- required develop result를 재구성하지 못하면 export가 실패한다.
- partial final file과 silent original fallback이 없다.

---

## 17. M13 — Print

### 목적

페이지·셀·작품 배치를 먼저 보여 주는 네이티브 print workflow를 구현한다.

### 작업

- printer/page capability discovery
- paper/orientation/margin
- single image layout
- contact sheet
- crop/fit/fill
- cell padding/caption if baseline
- page preview
- output profile
- soft proof/gamut warning
- rendering intent/BPC
- print spool handoff
- cancellation/error/retry
- saved preset

### 원칙

- 단순 preset 표보다 canvas/page spatial visualization을 우선한다.
- printer/device-accurate라고 말하려면 ICC와 출력 측정 증거가 필요하다.
- generic look과 measured/profile-specific result를 구분한다.
- print preview와 final page render가 같은 layout engine을 사용한다.

### 종료 조건

- single/contact sheet의 requested page geometry가 verified applied geometry와 일치한다.
- profile 없는 printer에 정확한 색이라고 주장하지 않는다.
- spool 실패가 export 성공처럼 보이지 않는다.
- actual physical print QA가 automated page raster test와 별도로 기록된다.

---

## 18. M14 — Settings·shortcuts·localization·accessibility

### 목적

모든 제품 표면을 Windows 사용자와 보조 기술이 완전하게 조작할 수 있게 한다.

### Settings

- general
- storage/cache
- performance/backend
- color/display
- export defaults
- scanner/plugin
- language
- shortcuts
- diagnostics/privacy

### Shortcuts

- stable action IDs
- Windows convention
- conflict detection
- reserved/system chords
- rebind/reset
- persistence/migration
- menu and tooltip synchronization

### Localization

- canonical string ID
- `.resw` generation/validation
- plural/format placeholder
- technical string 비현지화
- all supported language completeness
- long text/pseudolocalization
- app language restart/live behavior

### Accessibility

- UI Automation name/role/value/state
- keyboard-only
- focus order and restoration
- Narrator announcements
- high contrast
- 200% text
- 100–300% DPI
- reduced motion
- color-only state 금지
- error association

### 종료 조건

- 주요 workflow를 mouse 없이 완료한다.
- 숨은/disabled control의 automation state가 올바르다.
- 모든 visible product string이 localization contract를 따른다.
- 좁은 화면에서도 action row contract가 깨지지 않는다.
- 실제 Accessibility Insights/Narrator 수동 검증 증거가 있다.

---

## 19. M15 — Scanner host와 독립 plugin 생태계

### 목적

코어 앱의 제품 완전성을 유지하면서 Windows scanner를 외부 process로 지원한다.

### 19.1 코어 host

#### SCN-001 — Discovery/trust

- approved directories
- canonical path
- DACL/owner inspection
- signature/hash/manifest
- architecture
- protocol range
- quarantine/revocation

#### SCN-002 — Process host

- bounded startup/operation timeout
- Job Object
- stdout/stdin/stderr pipe
- max message
- UTF-8 strictness
- cancellation/grace/terminate
- cleanup
- staging directory

#### SCN-003 — Protocol

- detect
- capabilities
- preview
- scan
- cancel
- progress/event
- applied option equality
- result file hash/size/header/dimensions
- protocol major/minor negotiation

#### SCN-004 — UI

- capability-only controls
- route identity without backend jargon by default
- unavailable/plugin install guidance
- device busy/disconnected
- preview/full scan separation
- requested/detected/applied ROI diagnostics

### 19.2 Mock/contract plugin

코어 저장소에는 실제 driver 구현 대신 explicit test plugin을 둔다.

- deterministic device list
- capability variants
- delayed/out-of-order messages
- malformed/oversized output
- cancel/hang/crash
- ROI/readback mismatch
- IR/no-IR

implicit Mock fallback은 없다. demo/test mode는 명시적 opt-in이다.

### 19.3 WIA plugin

- COM apartment/thread ownership
- device/item tree
- actual property valid set
- read-back
- stream transfer
- artifact header validation
- no vendor driver redistribution
- x64/ARM64 native route

### 19.4 TWAIN plugin

- x64 first
- x86 only actual DS need
- DSM/DS state machine
- owner thread/message pump
- capability container normalization
- memory/native/file transfer
- ShowUI false evidence
- DSM license/source decision

### 19.5 SANE plugin

Windows 지원을 승인한 경우에만 별도 GPL 저장소/installer로 진행한다.

- core installer와 분리
- no link/bundle
- own LICENSE/COPYING/source/SBOM
- documented protocol only
- 실제 Windows SANE deployment feasibility
- license review of actual distribution

### 19.6 장치 인증

각 route는 다음을 구분한다.

- 발견
- 열기/capability
- virtual contract
- 실제 preview
- 실제 full scan
- required format/ROI/bit depth
- IR artifact
- x64/ARM64 driver availability

### 종료 조건

- plugin 없이 core가 완전하다.
- malformed/hung/malicious plugin이 core를 무한 대기·경로 이탈시키지 않는다.
- UI는 reported capability만 사용한다.
- `detected ROI = requested full-scan ROI = verified applied/manifest ROI`를 요구 format에서 확인한다.
- 지원 장치 주장은 실물 증거를 가진다.
- 각 plugin의 라이선스와 배포가 독립적으로 감사된다.

---

## 20. M16 — 성능·장치·호환성 qualification

### 목적

기능이 맞는 구현을 실제 target hardware에서 빠르고 안정적인 제품으로 승격한다.

### 20.1 CPU matrix

- Intel x64 baseline
- AMD x64 baseline
- Windows ARM64
- forced scalar
- x64 base
- AVX2 without FMA
- AVX2+FMA where available
- ARM64 NEON

### 20.2 GPU matrix

- Intel integrated
- Intel discrete if product scope
- AMD integrated/discrete representative
- NVIDIA representative
- Qualcomm ARM64
- WARP
- CPU-only

### 20.3 OS/display matrix

- minimum supported OS latest patch
- current Windows feature update
- Home/Pro consumer target
- high DPI single/multi monitor
- SDR only
- Advanced Color/HDR mixed displays
- remote desktop where applicable

### 20.4 Workflow benchmark

- cold/warm app start
- first library render
- 50k scroll/selection
- first image decode
- first valid Develop preview
- slider-to-frame latency
- 100% pan/frame pacing
- single export
- multi-file batch
- 50MP/100MP/panorama
- print page render
- scanner discovery/preview/full scan

### 20.5 Profiling 순서

1. reproduce with fixed fixture
2. ETW/WPR/WPA timeline
3. CPU sampling/allocations
4. GPUView and D3D markers
5. RenderDoc frame inspection
6. vendor tool only as supplementary
7. before/after same quality

PIX GPU capture를 위해 D3D11On12를 production에 도입하지 않는다.

### 20.6 최적화 순서

1. 불필요한 decode/copy/readback 제거
2. ROI/tile/cache correctness
3. pipeline graph fusion/shader linking
4. scheduling/backpressure
5. compiler auto-vectorization
6. narrow intrinsics
7. dependency codec tuning
8. vendor-specific optional tier 마지막

### CUDA gate

NVIDIA에서만 다음을 모두 만족할 때 별도 실험할 수 있다.

- D3D11·CPU 최적화 완료
- 실제 사용 workload의 명확한 병목
- end-to-end 20% 이상 또는 의미 있는 절대 시간 단축
- interop/copy/installer/toolkit 비용 포함
- 같은 output tolerance
- 모든 기능의 non-CUDA 완전 경로
- x64/ARM64/core release를 지연시키지 않음

### 종료 조건

- 각 지원 tier의 성능 baseline과 regression threshold가 있다.
- vendor-specific defect가 알려진 차이 또는 수정으로 닫혔다.
- memory/TDR/device-lost 장기 stress가 통과한다.
- 품질을 낮춰 얻은 속도는 성능 개선으로 기록되지 않는다.

---

## 21. M17 — 설치·업데이트·복구·컴플라이언스

### 목적

개발 build를 서명되고 복구 가능한 실제 배포 제품으로 만든다.

### 진입 조건

- M14 core surface complete
- M16 supported hardware matrix
- dependency/license decisions closed
- product version and channel policy

### 21.1 Packaging

- architecture-specific unpackaged self-contained stage
- MSI/Burn 또는 승인한 대안
- app/runtime/assets/licenses/SBOM
- plugin은 별도 package
- Start menu/uninstall/association 정책
- no development tree collection
- channel/user-scoped activation registration과 instance identity
- association을 채택했다면 installer-owned registration

Microsoft 공식 deployment 문서는 self-contained가 runtime 설치를 없애지만 크기·메모리·servicing 책임을 앱에 넘긴다고 설명한다. 그러므로 self-contained는 단순 편의가 아니라 정기 runtime patch를 앱 release로 흡수하는 운영 약속이다.

### 21.2 Signing

- app EXE/DLL
- installer/bootstrapper
- update metadata
- plugin executable/package independently
- timestamp
- certificate renewal/rotation/revocation
- post-sign hash and verification

### 21.3 Update

- signed metadata
- monotonic version
- architecture/channel match
- full installer hash
- staged download
- preflight
- app shutdown
- install transaction
- health check
- binary rollback
- catalog migration separate
- controlled shutdown receipt + process exit 확인
- update 중 second launch/activation gate
- Restart Manager와 app-owned close coordinator 역할 분리

### 21.4 Recovery

- clean install
- same-version repair
- upgrade from supported prior versions
- interrupted update
- disk full
- signature/timestamp failure
- feed unavailable
- rollback
- newer catalog with older binary
- plugin compatibility inventory
- normal close write/read-back/backup failure
- logoff/restart의 bounded checkpoint와 next-launch recovery
- crash/hang Application Recovery and Restart 후보 검증

### 21.5 License/SBOM

- x64/ARM64 artifact-specific SBOM
- exact licenses/notices
- LibRaw/TWAIN/SANE source compliance if present
- VC/.NET/Windows App Runtime terms
- WiX OSMF/commercial condition approval
- asset provenance

### 21.6 Clean-machine tests

- no Visual Studio
- no preinstalled app runtime assumption
- standard user
- offline install as supported
- Unicode user/path
- security software/file lock
- multiple user accounts
- plugin absent
- optional plugin installed later
- same-user second launch와 separate-user concurrent launch
- Stable/Beta side-by-side activation·catalog-lock 충돌

### 종료 조건

- install/update/repair/uninstall/rollback 증거가 x64/ARM64 각각 있다.
- signatures와 timestamps가 독립 도구로 검증된다.
- app data와 plugin ownership이 보존된다.
- source compliance와 notices가 실제 다운로드 가능하다.
- release artifact는 exact baseline manifest로 재현 가능하다.
- x64·ARM64에서 instance election, normal close, update close와 session-end 동작이 같다.

---

## 22. M18 — Beta·Release Candidate·Stable

### 22.1 Internal alpha

입구:

- M8 vertical slice
- data-safety invariants
- crash/support bundle

목표:

- 개발자 외 실제 사용 흐름 발견
- UI 구조와 input 문제 조기 검출
- 대표 hardware 확보

금지:

- scanner support 마케팅
- color accuracy 과장
- release-ready 표현

### 22.2 Closed beta

입구:

- M9–M14 surface complete
- M16 최소 hardware matrix
- signed test installer/update
- privacy/support policy

목표:

- 다양한 library/monitor/GPU/CPU
- 실제 장기 catalog
- recovery와 updater
- known differences

### 22.3 Release Candidate

입구:

- feature freeze
- dependency freeze
- exact baseline manifest
- 모든 required gate 통과
- no expired exceptions

RC 중 허용:

- release-blocking defect 수정
- security/loss prevention
- docs/notice correction

RC 중 금지:

- 새 feature
- 대형 dependency update
- pipeline 의미 변경
- unmeasured optimization

### 22.4 Stable

출시 결정에 필요한 evidence index:

- product/surface parity report
- numeric conformance report
- x64/ARM64 build and run
- CPU/GPU matrix
- actual WinUI QA
- scanner hardware report for claimed devices
- performance report
- data migration/recovery report
- installer/update/rollback report
- signing/notarization equivalent evidence
- SBOM/license/source compliance
- known differences/release notes

### 22.5 출시 후

- crash/update failure triage
- dependency security monitoring
- OS/driver servicing smoke
- macOS delta triage
- performance trend
- support matrix freshness
- postmortem for escaped severe defects

---

## 23. 제품 surface별 추적표

| Surface | Engine prerequisite | UI milestone | 필수 품질 gate | 실제 QA |
|---|---|---|---|---|
| Shell | ABI/event model | M8 | lifetime/stale request/instance/close | x64+ARM64 window/input/activation/session-end |
| Library | catalog/thumbnail/import | M9 | 50k virtualization, data safety | real folder/library |
| Canvas | GPU/device/tiling | M8/M7 | pixel/DPI/device lost | multi-monitor/pan |
| Develop | full graph/measurement | M10/M6 | preview/export parity | rapid edits/keyboard |
| Defects | detection/recipe/cache | M11 | non-destructive reconstruction | mouse/pen/large image |
| Export | render/encode/atomic IO | M12 | container/ICC/readback | real batch/destinations |
| Print | page/color pipeline | M13 | geometry/profile | actual physical print |
| Settings | stable services | M14 | persistence/migration | restart/high contrast |
| Shortcuts | action IDs | M14 | conflict/focus | keyboard-only |
| Scan | protocol/plugin host | M15 | capability/applied ROI | actual devices/formats |

Surface가 완료됐다고 하려면 [../08-ui/parity-contract.md](../08-ui/parity-contract.md)의 기능·정보 구조·시각·입력·데이터·접근성·성능 축을 모두 평가한다.

---

## 24. 각 단계에서 유지할 x64·ARM64 규율

### 매 dependency 추가

- x64 restore/build/run
- ARM64 restore/build/run
- license/feature parity
- architecture-specific transitive binary
- SBOM diff

### 매 ABI 변경

- fixed-width layout
- x64/ARM64 size/alignment assertions
- C++/C# contract test
- old/new ABI compatibility decision

### 매 SIMD 변경

- scalar forced
- x64 base
- AVX2/FMA separation
- ARM64 NEON
- numeric and performance report

### 매 package

- architecture label
- PE architecture scan
- clean machine
- cross-architecture install rejection
- native ARM64 launch

Windows on ARM의 x64 emulation은 core ARM64 build의 대체가 아니며 scanner kernel driver를 emulation하지도 않는다.

---

## 25. GPU 범용성 승격 규칙

### Kernel 상태

```text
specified
  → scalar-passed
  → warp-passed
  → intel-passed
  → amd-passed
  → nvidia-passed
  → qualcomm-passed
  → production-approved
```

모든 kernel이 모든 vendor에서 GPU로 실행될 필요는 없다. 특정 kernel을 CPU로 배치해도 기능·품질·성능 예산을 만족하면 범용 제품이 될 수 있다. 중요한 것은 backend에 따라 기능이 사라지거나 결과 의미가 바뀌지 않는 것이다.

### Fallback 상태

- shader compile/load failure: 해당 backend 미사용
- dispatch/device error: entire request를 safe boundary에서 CPU로 재실행
- device removed: device generation 증가, derived cache 폐기, recipe 유지
- memory budget: 작은 tile 또는 CPU
- known bad driver: scoped quarantine

부분 GPU 결과와 부분 CPU 결과를 조립할 수 있는 operation만 명시적으로 지원한다. 그렇지 않으면 전체 graph를 한 backend에서 재실행한다.

---

## 26. macOS 변화 흡수 절차

Windows 구현 중 macOS가 바뀌면 다음 순서를 사용한다.

1. baseline 이후 diff 탐지
2. delta ID 생성
3. 제품 사양 변경인지 구현 수정인지 분류
4. 보안/데이터 손실/중대 결함 여부 판정
5. 현재 milestone에 흡수할지 다음 sync window로 미룰지 결정
6. fixture/expectation/schema 영향
7. Windows 구현
8. 양쪽 conformance
9. baseline 승격

즉시 흡수 우선순위:

- 데이터 손실 방지
- 보안 취약점
- 원본 불변성
- export correctness
- catalog corruption
- license/provenance

기본적으로 다음은 현재 milestone을 흔들지 않고 backlog로 둔다.

- 신규 편의 기능
- 시각 미세 조정
- 실험 알고리즘
- 측정되지 않은 성능 최적화

상세 운영은 [maintenance.md](maintenance.md)를 따른다.

---

## 27. 데이터·catalog 이관 정책

### 27.1 Windows 내부 version migration

첫 개발 build부터 schema version과 migration fixture를 사용한다. `아직 출시 전`이라는 이유로 매번 DB를 삭제하는 습관을 만들지 않는다.

### 27.2 macOS → Windows catalog

자동 지원으로 가정하지 않는다. M0에서 다음 중 하나를 결정한다.

- v1 미지원, source file 재가져오기
- 공통 logical export/import manifest
- read-only macOS catalog importer
- future cross-platform catalog schema

지원한다면:

- 원본 경로/volume identity 차이
- macOS bookmark와 Windows path/relink
- app-owned thumbnail/cache 재생성
- recipe/algorithm version
- virtual copy identity
- folder state
- unavailable source
- third-party XMP 불변
- migration rollback

macOS SQLite 파일을 Windows에서 그냥 열 수 있다는 사실만으로 semantic migration을 완료했다고 보지 않는다.

### 27.3 downgrade

binary rollback과 catalog rollback을 분리한다. 새 앱이 catalog를 migration한 뒤 이전 앱이 열 수 있는지 명시하지 않았다면 updater가 자동 binary rollback만 수행해서는 안 된다.

---

## 28. 시험 피라미드와 실행 시점

### Commit마다

- format/lint/static contracts
- native unit
- shell unit
- forced scalar
- x64 build/run
- ARM64 build and scheduled native run
- shader compile
- link/license manifest sanity

### Pull request마다

- conformance relevant subset
- WARP
- image IO malformed corpus
- ABI layout
- catalog fixture
- surface state tests
- artifact diff

### Nightly

- full x64/ARM64 conformance
- WARP full graph
- large image/stress
- fuzz/regression corpus
- dependency/SBOM/advisory scan
- installer unsigned smoke

### Scheduled physical lab

- Intel/AMD/NVIDIA/Qualcomm
- minimum/current OS
- multi-monitor/Advanced Color
- scanner route matrix
- pen/input hardware

### Release candidate

- signed clean-machine install/update/rollback
- actual UI click-through
- physical print
- claimed scanner full matrix
- performance baseline
- license/source access

자동화가 실제 UI와 장치를 대체하지 않는다. 실제 장치 QA가 unit test를 대체하지도 않는다.

---

## 29. 증거 artifact 규격

각 gate 결과는 최소 다음을 기록한다.

- build/baseline ID
- source commits
- architecture
- OS build/edition
- CPU/GPU/device/driver
- dependency/toolchain versions
- fixture/recipe/algorithm version
- command 또는 수동 scenario
- raw result artifact
- pass/fail/skip
- 허용 오차 또는 성능 budget
- reviewer/date
- known issue link

Screenshot만으로 numeric parity를 증명하지 않는다. 로그만으로 visual/interaction parity를 증명하지 않는다.

---

## 30. 위험 우선순위와 조기 소각

### R0 — 즉시 막아야 할 위험

| 위험 | 조기 gate | 실패 시 |
|---|---|---|
| FP32 extended range clamp | M5 GPU-001 | GPU working-space 재설계 또는 CPU |
| ARM64 dependency/실행 | M1 | dependency 대체·범위 수정 |
| LibRaw/TWAIN/WiX license | M0 | 제외·대안·별도 배포 |
| catalog 원본/손실 | M3 | UI 진행 금지 |
| baseline 불명확 | M0 | 구현 시작 금지 |

### R1 — 아키텍처 위험

| 위험 | gate |
|---|---|
| C ABI/SwapChainPanel lifetime | M5/M8 |
| D2D shader linking·resource copy | M5 |
| measurement vendor 결정성 | M5/M6 |
| tile seam/memory/TDR | M7 |
| self-contained runtime/installer | M17 early spike |

### R2 — 제품 위험

| 위험 | gate |
|---|---|
| Library 50k virtualization | M9 |
| rapid Develop stale result | M10 |
| Defects pen latency/cache | M11 |
| first export progress | M12 |
| print color/geometry | M13 |
| scanner capability truth | M15 |

위험을 늦게 발견할수록 UI와 데이터 위에 잘못된 전제가 쌓인다. R0/R1 spike는 feature 수를 늘리기 전에 끝낸다.

---

## 31. 구현하지 않을 것

### v1 critical path에서 제외

- 크로스플랫폼 UI framework
- Swift/C++ 공용 pixel abstraction
- D3D12 필수 backend
- DirectML/ONNX로 일반 필터 구현
- CUDA 필수 기능
- x86 core app
- ARM64EC core
- runtime HLSL compile
- OpenCV 전체
- cloud catalog dependency
- implicit Mock scanner fallback
- source in-place bake
- unsupported OS/device 자동 주장

### 측정 전 제외

- Highway 필수 의존성
- libjpeg-turbo/libpng/libdeflate 대체 경로
- vendor-specific GPU extension
- scanner vendor SDK
- remote GPU blocklist
- MSIX/Store 전용 channel

필요성이 실제 증거로 생기면 decision register를 갱신하고 해당 gate부터 시작한다.

---

## 32. 구현 상태 dashboard 제안

파일 수나 체크박스 총량을 진행률로 사용하지 않는다. 다음 축을 각각 표시한다.

| 축 | 예시 상태 |
|---|---|
| Product surfaces | 7/10 conformance passed |
| Engine operations | 28/34 scalar, 22/34 WARP, 18/34 full vendor |
| Architecture | x64 ready, ARM64 blocked/ready |
| Data safety | 12/12 non-waivable gates |
| Hardware | vendor/device matrix evidence |
| Scanner | route/device/format certification |
| Packaging | install/update/rollback |
| Compliance | dependency approvals/SBOM/source |

종합 percentage가 필요하면 사전에 고정된 weighted milestone으로만 계산한다. 작업 중 분모를 늘려 진척률을 조작하지 않는다.

### 권장 milestone weight 예시

실제 착수 전에 product owner가 확정한다. 아래는 구조 예시일 뿐 현재 개발 진행률이 아니다.

| 영역 | weight |
|---|---:|
| M0–M3 기준·빌드·scalar·IO/color/data | 20 |
| M4–M7 engine/GPU/large image | 25 |
| M8–M14 WinUI 제품 surfaces | 30 |
| M15 scanner core/plugin boundary | 5 |
| M16 hardware/performance | 10 |
| M17–M18 distribution/release | 10 |

Scanner가 별도 release라면 core v1 score와 scanner certification score를 합치지 않는다.

---

## 33. 단계별 의사결정 종료표

| 결정 | 닫아야 할 시점 | 늦으면 생기는 문제 |
|---|---|---|
| exact macOS baseline | M0 | moving target |
| Windows supported OS | M0, M17 재확인 | 출시 직전 EOS |
| LibRaw 포함/license | M0/M3 | IO·installer 재설계 |
| WiX 조건/대안 | M0, M17 | package blocked |
| SQLite provider | M3 | native DB 중복 |
| measurement CPU/GPU | M5 | PC별 auto result |
| SwapChainPanel ABI | M5/M8 | interop 재작성 |
| tile/memory policy | M7 | large image failure |
| macOS catalog migration | M0/M9 | 사용자 데이터 혼란 |
| TWAIN DSM 배포 | M15 전 | plugin compliance 재작업 |
| scanner device claims | M15 | 과장된 지원표 |
| self-contained/runtime | M17 early spike | 설치/servicing 회귀 |
| CUDA | M16 이후 | 범용 critical path 오염 |

---

## 34. 첫 12개 실행 work package

Windows 구현을 실제로 승인했을 때 최초 순서는 다음과 같다.

1. `GOV-001` — clean macOS baseline SHA와 asset hash 고정
2. `GOV-002` — product/surface/kernel/schema manifest v1
3. `GOV-005` — LibRaw·WiX·TWAIN DSM·ICC 법무 차단 항목 결정
4. `BLD-001` — 최소 Windows repository/CMake/.NET layout
5. `BLD-002` — supported toolchain/vcpkg/NuGet lock
6. `BLD-003` — x64/ARM64 CLI build/run
7. `QA-001` — synthetic fixture/expectation/tolerance schema
8. `ENG-001` — pixel/color/coordinate/edge math policy
9. `CPU-001` — scalar negative inversion vertical kernel
10. `IO-001` — bounded TIFF probe/decode
11. `CLR-001` — LittleCMS input→working reference
12. `M4` — one-image CLI TIFF round-trip report

WinUI project template는 build graph 검증에 필요한 최소 shell만 만들 수 있지만, 제품 화면 확장은 12번의 수치 vertical slice 뒤에 한다.

---

## 35. 첫 사용자 사용 가능 build와 출시 build의 차이

### 첫 내부 사용 가능 build

- 한 장 import
- basic Develop
- native canvas
- 16-bit TIFF export
- x64/ARM64
- CPU + 한 GPU/WARP
- 개발용 unsigned/내부 signed package

이 build는 다음을 의미하지 않는다.

- 99.9% UI/UX parity
- full format support
- scanner support
- production color accuracy
- safe migration/updater
- release licensing completion

### Beta 후보

- 모든 core surface
- data recovery
- full vendor matrix의 최소 subset
- signed installer/update
- support bundle/privacy
- license/SBOM

### Stable

- M18 완료 정의 전체

이 구분을 release status와 UI에 명확히 표시한다.

---

## 36. 문서→구현 연결표

| 구현 영역 | 먼저 읽을 문서 |
|---|---|
| 전체 아키텍처 | [../00-overview/architecture.md](../00-overview/architecture.md), [../00-overview/decision-register.md](../00-overview/decision-register.md) |
| 수치 파이프라인 | [../01-render-engine/pipeline-shape.md](../01-render-engine/pipeline-shape.md), [../02-shaders/kernel-inventory.md](../02-shaders/kernel-inventory.md) |
| GPU | [../12-performance/backend-selection.md](../12-performance/backend-selection.md), [../12-performance/gpu-vendor-portability.md](../12-performance/gpu-vendor-portability.md) |
| CPU | [../16-cpu/simd-and-dispatch.md](../16-cpu/simd-and-dispatch.md), [../16-cpu/accelerate-replacement.md](../16-cpu/accelerate-replacement.md) |
| Color | [../04-color-management/color-pipeline.md](../04-color-management/color-pipeline.md), [../04-color-management/lcms2.md](../04-color-management/lcms2.md) |
| Image IO | [../05-image-io/wic.md](../05-image-io/wic.md), [../05-image-io/libtiff.md](../05-image-io/libtiff.md), [../05-image-io/libraw.md](../05-image-io/libraw.md) |
| Large image | [../06-large-images/image-source-tiling.md](../06-large-images/image-source-tiling.md), [../07-threading/multithreading-export.md](../07-threading/multithreading-export.md) |
| C#/C++ | [../09-language-choice/csharp-native-interop.md](../09-language-choice/csharp-native-interop.md) |
| WinUI | [../08-ui/parity-contract.md](../08-ui/parity-contract.md), [../08-ui/feature-map.md](../08-ui/feature-map.md), surface별 문서 |
| Catalog | [../14-persistence/catalog-and-storage.md](../14-persistence/catalog-and-storage.md) |
| Digital film | [../15-digital-film/virtual-development.md](../15-digital-film/virtual-development.md) |
| Scanner | [../10-scanner/plugin-architecture.md](../10-scanner/plugin-architecture.md), [../10-scanner/protocol-contract.md](../10-scanner/protocol-contract.md), [../10-scanner/twain-wia.md](../10-scanner/twain-wia.md) |
| Distribution | [../11-distribution/deployment-channels.md](../11-distribution/deployment-channels.md), [../11-distribution/update-and-rollback.md](../11-distribution/update-and-rollback.md) |
| Build/deps | [../13-build-and-deps/solution-layout.md](../13-build-and-deps/solution-layout.md), [../13-build-and-deps/vcpkg-cmake.md](../13-build-and-deps/vcpkg-cmake.md) |
| License/SBOM | [../13-build-and-deps/third-party-licenses.md](../13-build-and-deps/third-party-licenses.md) |
| CI/profiling | [../12-performance/ci-and-testing.md](../12-performance/ci-and-testing.md), [../12-performance/profiling-tools.md](../12-performance/profiling-tools.md) |
| Maintenance | [maintenance.md](maintenance.md) |

---

## 37. 공식 근거와 출시 시 재확인할 페이지

- [Windows App SDK deployment overview](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/deploy-overview)
- [Self-contained Windows App SDK deployment](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps)
- [Distribute an unpackaged WinUI 3 app](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/unpackage-winui-app)
- [Windows on Arm FAQ](https://learn.microsoft.com/en-us/windows/arm/faq)
- [Add Arm support to a Windows app](https://learn.microsoft.com/en-us/windows/arm/add-arm-support)
- [Windows 11 release information](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information)
- [Windows App SDK release channels](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-channels)
- [.NET support policy](https://dotnet.microsoft.com/en-us/platform/support/policy)
- [Direct2D custom effects](https://learn.microsoft.com/en-us/windows/win32/direct2d/custom-effects)
- [Direct3D 11 compute shader overview](https://learn.microsoft.com/en-us/windows/win32/direct3d11/direct3d-11-advanced-stages-compute-shader)
- [WIA overview](https://learn.microsoft.com/en-us/windows/win32/wia/-wia-startpage)

---

## 38. 최종 release approval 질문

Stable 승인자는 다음 질문에 artifact로 답할 수 있어야 한다.

1. Windows판이 어느 exact macOS 제품 사양을 구현했는가?
2. 기준선 이후 macOS delta 중 무엇을 포함·제외했는가?
3. 같은 photo/recipe가 x64·ARM64·각 GPU에서 얼마나 다른가?
4. preview와 export가 같은 graph임을 무엇으로 증명했는가?
5. GPU가 없거나 실패해도 기능이 완전한가?
6. 원본과 third-party XMP가 바뀌지 않았는가?
7. catalog migration 실패와 binary rollback을 어떻게 복구하는가?
8. WinUI 주요 workflow를 실제로 조작했는가?
9. 지원한다고 적은 scanner/format/ROI를 실제 장치에서 검증했는가?
10. 코어 payload에 GPL scanner code가 없음을 어떻게 확인했는가?
11. 모든 x64/ARM64 파일의 source·license·SBOM이 있는가?
12. installer/update/rollback을 clean machine에서 실행했는가?
13. 현재 OS/runtime/SDK가 지원 중인가?
14. known difference와 면제가 만료되지 않았는가?
15. 사용자가 문제 발생 시 원본과 catalog를 잃지 않고 복구할 수 있는가?

하나라도 근거 없이 `예`라고 답해야 한다면 Stable 준비가 끝난 것이 아니다.

---

## 39. 로드맵 완료 정의

이 로드맵 자체가 구현 가능한 상태라는 기준은 다음과 같다.

- 모든 핵심 아키텍처 결정이 milestone에 연결된다.
- x64와 ARM64가 첫 build부터 마지막 installer까지 분리 추적된다.
- CPU scalar, WARP, 물리 GPU의 역할이 혼동되지 않는다.
- WinUI surface가 engine/data prerequisite 뒤에 배치된다.
- scanner가 독립 process·repository·license·release로 배치된다.
- 배포, update, rollback, 데이터 migration이 별도 gate를 가진다.
- dependency/license/SBOM이 마지막 문서 작업이 아니라 M0부터 시작된다.
- 각 milestone의 종료가 실행 가능한 증거로 정의된다.
- 실패 시 대안이 제품 범용성과 데이터 안전을 보존한다.
- CUDA, D3D12, vendor SDK 같은 선택적 기술이 critical path를 장악하지 않는다.

이 순서를 지키면 Windows판은 macOS 소스의 불완전한 번역본이 아니라, 동일한 Negaflow 제품 계약을 Windows의 네이티브 UI·그래픽·CPU·장치 모델 위에서 재현한 독립 제품이 된다.
