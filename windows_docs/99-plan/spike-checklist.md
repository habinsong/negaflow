# Windows 구현 전·초기 스파이크 체크리스트

> 상태: 실행 가능한 기술 위험 제거 계획  
> 기준일: 2026-08-04  
> 상위 결정: [기술 결정 등록부](../00-overview/decision-register.md)  
> 전체 순서: [이행 로드맵](migration-roadmap.md)  
> 미해결 사실: [열린 질문](open-questions.md)

스파이크의 목적은 데모를 만드는 것이 아니라 잘못된 아키텍처를 조기에 탈락시키는 것이다. 각
스파이크는 질문 하나 이상을 닫고, 다음 milestone이 신뢰할 수 있는 artifact를 남겨야 한다.

## 1. 공통 규칙

### 1.1 스파이크도 제품 계약을 지킨다

- 원본을 덮어쓰지 않는다.
- 기능을 한 GPU·CPU 제조사에 게이팅하지 않는다.
- 낮은 bit depth·해상도·JPEG 품질로 성능을 만든 뒤 성공으로 기록하지 않는다.
- macOS 기준 결과와 다른 값을 “Windows 방식”으로 정당화하지 않는다.
- scanner mock 성공을 실제 장치 성공으로 기록하지 않는다.
- CPU scalar, WARP, 실제 GPU와 UI 성공을 서로 대체하지 않는다.
- installer 성공과 update·rollback·catalog 보존 성공을 분리한다.

### 1.2 각 스파이크 필수 산출물

~~~text
spike-id
질문과 가설
정확한 source commit
toolchain manifest
Windows build와 edition
CPU architecture/model
GPU adapter/driver 또는 WARP
입력 corpus와 license
실행 명령·수동 시나리오
expected/actual 결과
성능·메모리·수치 artifact
pass/fail 결정
후속 결정 문서 diff
폐기할 prototype 목록
~~~

prototype code를 제품 tree에 그대로 승격하지 않는다. 승격하려면 ownership, 오류 처리, 테스트,
문서와 build graph를 제품 기준으로 다시 검토한다.

### 1.3 하드 스톱

다음 gate가 실패하면 뒤 화면을 더 만드는 것으로 보상하지 않는다.

| 실패 | 멈추는 범위 |
|---|---|
| M0 법무·지원 정책 미결 | 해당 dependency·installer·profile·plugin 채택 금지 |
| x64/ARM64 native clean build 실패 | 엔진 기능 구현 확대 금지 |
| scalar↔macOS 수치 적합성 실패 | GPU 구현 금지 |
| WARP/D3D11 정밀도 실패 | WinUI canvas 통합 금지 |
| 원본 불변·catalog crash recovery 실패 | Library·scanner 확장 금지 |
| update/rollback이 catalog를 손상 | Beta/Stable 금지 |
| 실제 scanner ROI·bit depth 불일치 | 해당 장치 지원 표시 금지 |

## 2. 실행 순서 요약

| Spike | 핵심 위험 | 닫는 질문 | 결과를 소비하는 milestone |
|---|---|---|---|
| S0 | 기준선·지원 OS·라이선스·installer | Q-018~Q-021, Q-023 일부 | M0 |
| S1 | x64·ARM64 toolchain·dependency | Q-006 | M1 |
| S2 | scalar reference와 macOS 적합성 | kernel·pipeline 수치 | M2 |
| S3 | image I/O·ICC·codec | Q-001, Q-009, Q-017, Q-018 | M3 |
| S4 | D3D11·Direct2D·WARP FP32 | Q-002, Q-004, Q-011 | M5 |
| S5 | 대형 image·tile·TDR | Q-003, Q-012 | M7 |
| S6 | C ABI·WinUI canvas·app lifecycle | Q-005, Q-008 일부, Q-024 | M8 |
| S7 | catalog·migration·crash recovery | Q-023 | M3/M9 |
| S8 | WinUI 대량 Library·입력·접근성 | Q-007, Q-015 일부 | M9~M14 |
| S9 | scanner process·security·hardware | Q-013, Q-014, Q-019 | M15 |
| S10 | install·sign·update·rollback·shutdown | Q-016, Q-020, Q-022, Q-025 | M17 |
| S11 | 실제 hardware·UI·출시 matrix | Q-004, Q-008, Q-012 및 전체 | M16/M18 |

S0은 행정 문서만 작성하는 단계가 아니다. 실제 사용할 artifact와 배포 방식의 승인 가능성을
확인해야 한다. S2부터 S11은 현재 문서 작성 단계에서 실행한 것으로 간주하지 않는다.

## 3. S0 — 기준선·지원·라이선스 preflight

### 목적

이식 중간에 “사용할 수 없는 library/tool/profile” 또는 “출시 때 이미 지원 종료된 OS”를 발견하는
일을 막는다.

### 입력

- macOS exact commit과 dirty 상태
- preset, scanner profile, localization, fixture inventory
- 후보 dependency와 tool 목록
- Windows 11 공식 release information
- .NET·Windows App SDK support 정책
- 실제 배포 주체와 판매/수익 모델

### 작업

- [ ] macOS full commit SHA와 source archive를 고정
- [ ] 31개 custom kernel과 built-in effect 목록 hash 기록
- [ ] product, recipe, catalog, sidecar, scanner protocol version 초안
- [ ] x64·ARM64를 v1 필수 architecture로 승인
- [ ] 최소 API OS, CI OS, tested OS, supported OS를 별도 필드로 정의
- [ ] 24H2를 영구 최소선으로 쓰지 않고 출시 시 지원 release 재선정 규칙 승인
- [ ] Windows 10 포함/제외를 사용자 요구와 비용으로 결정
- [ ] LittleCMS core와 GPL plugin 제외 확인
- [ ] libtiff, zlib, SQLite exact source·license 경계 확인
- [ ] LibRaw license option과 source 제공 계획 승인 또는 v1 RAW 제외
- [ ] TWAIN DSM 배포 모델과 LGPL 의무 승인 또는 system-only 계획
- [ ] SANE가 별도 repository/process/installer/update/source bundle임을 고정
- [ ] Adobe RGB와 기타 ICC profile 재배포 권리 확인
- [ ] WiX OSMF 조건 승인 또는 대안 installer 평가 시작
- [ ] signing 주체·key custody·timestamp 기본안
- [ ] source code와 문서 corpus의 라이선스·개인정보 확인

### 실패 조건

- exact source와 license를 식별할 수 없는 dependency
- “나중에 법무가 알아서 함”만 있고 기능 제외 경로가 없음
- 출시 예상 시점에 지원 종료될 OS를 신규 설치 기본선으로 고정
- SANE 또는 vendor SDK를 코어 installer에 자동 포함
- 상업 사용 조건이 미승인인 tool을 필수 build gate로 고정

### 통과 artifact

- baseline manifest v0
- dependency/legal decision matrix
- 지원 OS 정책 초안
- forbidden component list
- 열린 질문 owner와 재검토 gate

### 통과 뒤 결정

D-002, D-004, D-010~D-012, D-015의 상태를 확인한다. 미승인 dependency는 solution에 추가하지
않는다.

## 4. S1 — x64·ARM64 clean toolchain

### 목적

x64 가정을 engine·dependency·installer에 굳히기 전에 두 architecture의 순수 native graph를
증명한다.

### 최소 solution

~~~text
Negaflow.Native
Negaflow.Cli
Negaflow.Native.Tests
Negaflow.Shell bootstrap
architecture inspector
dependency manifest generator
~~~

아직 Develop 전체나 예쁜 WinUI 화면은 만들지 않는다.

### 작업

- [ ] lock된 Visual Studio/MSVC/Windows SDK
- [ ] lock된 CMake/Ninja/vcpkg baseline
- [ ] lock된 .NET SDK/NuGet graph
- [ ] x64 Release clean build
- [ ] ARM64 Release clean build
- [ ] x64와 ARM64 CLI native 실행
- [ ] PE machine type 전수 검사
- [ ] transitive DLL/CRT/debug runtime 검사
- [ ] dependency license 파일 수집
- [ ] offline restore 또는 승인된 artifact cache rehearsal
- [ ] clean VM에서 bootstrap 실행

### dependency별 확인

| 후보 | x64 | ARM64 | runtime test | license gate |
|---|---:|---:|---:|---:|
| LittleCMS core | 필수 | 필수 | profile transform | 필수 |
| libtiff | 필수 | 필수 | read/write corpus | 필수 |
| SQLite provider | 필수 | 필수 | WAL/crash | 필수 |
| LibRaw | 조건부 | 조건부 | RAW corpus | 필수 |
| native test framework | 필수 | 필수 | test discovery | 필수 |
| WinUI 3/.NET | 필수 | 필수 | native process | 필수 |

### 실패 조건

- ARM64 build가 x64 emulation으로만 실행
- architecture별 다른 dependency version
- debug CRT 또는 미기록 DLL 혼입
- exact source/license를 찾을 수 없는 binary
- clean machine이 개발자 PC의 global package에 의존

### 통과 artifact

- architecture별 dependency graph
- SBOM 초안
- compiler/linker flags
- clean build log
- PE architecture report
- native process 실행 report

Q-006은 이 artifact가 실제 ARM64 장치에서도 확인되어야 닫힌다.

## 5. S2 — scalar reference와 macOS 적합성

### 목적

GPU와 UI 전에 Windows 엔진의 수학적 정답을 고정한다.

### 첫 vertical slice

negativeInvert를 첫 kernel로 사용한다. log, pow, Dmin/Dmax, extended range와 domain 경계를 한
번에 드러내기 때문이다.

작업:

- [ ] macOS 기준 입력·parameter·output을 deterministic artifact로 export
- [ ] scalar C++ negativeInvert 구현
- [ ] color channel order와 alpha 계약
- [ ] NaN·Inf·denormal·invalid parameter 정책
- [ ] x64·ARM64 결과 비교
- [ ] tolerance가 아닌 exact 기대가 가능한 부분 분리
- [ ] 실패 pixel의 coordinate·stage·value 보고

### 전체 scalar 범위

31개 custom kernel만 옮기면 끝이 아니다.

- [ ] 18개 unary point transform
- [ ] 13개 multi-input current-coordinate combine
- [ ] blur·box mean·median·morphology
- [ ] LUT interpolation
- [ ] histogram·mean·percentile·variance
- [ ] film-base measurement와 auto parameter derivation
- [ ] deterministic noise
- [ ] resize·crop·orientation
- [ ] alpha와 mask
- [ ] virtual digital development graph

공간 producer가 필요한 9개 combine은 producer와 함께 subgraph로 시험한다. 31개를 한 pass로
합치는 것을 목표나 통과 조건으로 두지 않는다.

### corpus

- neutral·primary·secondary ramp
- negative density와 Dmin/Dmax 경계
- extreme slider min/default/max
- tiny 1×1·2×2·odd dimensions
- alpha 0·partial·1
- impulse·edge·checkerboard
- 8/16-bit integer와 float source
- real scan, digital source, virtual copy

### 실패 조건

- 평균 PSNR만 높고 neutral channel 또는 highlight가 다름
- invalid domain을 clamp해 숨김
- ARM64에서 다른 결과를 “NEON 특성”으로 허용
- preview와 export가 다른 구현을 사용
- noise가 tile·thread order에 따라 바뀜

### 통과 artifact

- versioned conformance corpus
- scalar x64·ARM64 result
- stage별 tolerance
- expected failure list
- macOS baseline generator metadata

S2가 통과하기 전에 GPU optimization을 시작하지 않는다.

## 6. S3 — image I/O·ICC·codec

### 목적

렌더 수학 이전과 이후의 decode·encode·color boundary가 픽셀을 바꾸지 않게 한다.

### Decode matrix

- [ ] JPEG 8-bit, orientation, embedded ICC
- [ ] PNG 8/16-bit, alpha
- [ ] TIFF 8/16-bit integer
- [ ] TIFF 32-bit IEEE float
- [ ] strip/tile, planar/contiguous
- [ ] LZW/Deflate/uncompressed
- [ ] BigTIFF
- [ ] malformed/truncated/oversized metadata
- [ ] conditional RAW corpus

WIC와 libtiff가 같은 파일을 모두 읽을 수 있어도 자동으로 둘 다 production route로 두지 않는다.
정확한 책임과 fallback 조건을 하나로 정한다.

### Color matrix

- [ ] ICC v2/v4 RGB input
- [ ] matrix/TRC와 LUT profile
- [ ] rendering intent
- [ ] black-point compensation 정책
- [ ] alpha와 premultiplication
- [ ] extended linear working values
- [ ] CPU LittleCMS reference
- [ ] invalid profile와 profile missing

### Export matrix

- [ ] JPEG quality 의미
- [ ] PNG bit depth·alpha
- [ ] TIFF 8/16-bit·BigTIFF·compression
- [ ] ICC embed와 metadata
- [ ] atomic temp→final commit
- [ ] cancel·disk full·name collision
- [ ] Quick Export와 일반 Export 동일 품질

### 실패 조건

- unsupported float TIFF를 8-bit로 조용히 내림
- missing ICC를 임의의 camera/monitor profile로 추정
- source orientation과 pixel rotate를 중복 적용
- export 실패 시 original을 대신 복사
- encoder 차이를 slider 숫자만 같다는 이유로 승인

### 통과 artifact

- Q-001, Q-009 결과
- codec capability manifest
- ICC conformance report
- output file decoded-pixel·metadata report
- LibRaw와 Adobe RGB 포함/제외 결정

## 7. S4 — D3D11·Direct2D·WARP FP32 vertical slice

### 목적

v1 GPU 기준선이 한 장의 이미지에서 실제로 품질·복구 계약을 지킬 수 있는지 증명한다.

### 장치 생성

- [ ] D3D11 hardware device, feature level 11_0
- [ ] BGRA support와 Direct2D device/context
- [ ] required format support query
- [ ] WARP device
- [ ] DXGI budget reporting
- [ ] device-lost generation

### 첫 graph

~~~text
float source
→ negativeInvert
→ basicTone
→ one color adjustment
→ display transform
→ swap/export target
~~~

### 필수 검증

- [ ] 32-bpc float intermediate
- [ ] 음수·1 초과 값 보존
- [ ] full shader만 쓴 결과
- [ ] export function을 제공한 linking 후보 결과
- [ ] actual pass/intermediate 계측
- [ ] built-in effect와 custom equivalent 비교
- [ ] D2D compute vs D3D11 compute
- [ ] WARP 전체 graph
- [ ] CPU scalar 비교
- [ ] cancellation과 device removal

### measurement

- integer histogram
- deterministic reduction 후보
- parameter derivation
- GPU 결과가 불안정할 때 CPU final path

### 실패 조건

- linking이 안 되면 기능이 깨짐
- 한 vendor에서만 custom effect가 등록됨
- WARP에서 format·shader가 달라짐
- FP16/UNORM을 써야만 예산을 맞춤
- GPU 실패 뒤 original 또는 이전 stale frame을 성공으로 반환

### 통과 artifact

- Q-002, Q-004, Q-011 1차 결과
- WARP golden
- D3D11 shader manifest와 bytecode hash
- resource transition·lifetime trace
- device-lost recovery report

## 8. S5 — 대형 image·tile·TDR

### 목적

50MP·100MP·파노라마를 full-frame 메모리 복제와 긴 dispatch 없이 처리한다.

### dataset

- 24MP 일반 image
- 50MP high-resolution camera
- 100MP synthetic/scan
- 200MP 이상 panorama
- tall/narrow와 wide/short extreme aspect
- 16-bit TIFF, 32-bit float TIFF
- defect mask가 큰 real scan

### 시나리오

- [ ] cold decode와 warm tile cache
- [ ] fit preview, 100%, 200%, 빠른 pan
- [ ] Develop slider 연속 drag
- [ ] export one file
- [ ] large batch
- [ ] Defect auto detection
- [ ] memory pressure와 budget shrink
- [ ] device lost
- [ ] app cancel·close

### 계측

- decoded source bytes
- CPU staging bytes
- GPU resident/transient bytes
- tile cache hit/miss
- full-frame allocation count
- pass·dispatch duration
- p50/p95/p99 frame와 export time
- UI thread stall
- TDR·device removed event

### 실패 조건

- resolution·quality·bit depth·ICC를 낮춰 통과
- 디스크 cache가 없으면 OOM
- 작은 ROI 조정이 매번 full image를 처리
- tile seam, blur halo, deterministic noise discontinuity
- TdrDelay 변경을 요구

### 통과 artifact

- Q-003, Q-012 결과
- architecture별 memory budget
- operation별 tile/halo
- cache eviction·backpressure
- slow-device safe dispatch 상한

## 9. S6 — C ABI와 WinUI 3 canvas

### 목적

C# shell과 C++ engine의 lifetime·thread·presentation 경계가 제품 전체를 견딜 수 있는지 확인한다.

### ABI

- [ ] opaque engine/document/render handles
- [ ] fixed-width POD와 size/version
- [ ] UTF-8와 explicit buffer length
- [ ] caller/callee allocation ownership
- [ ] immutable parameter snapshot
- [ ] request/session/revision identity
- [ ] bounded progress/error event queue
- [ ] cancellation

### Canvas

- [ ] SwapChainPanel attach/detach
- [ ] DXGI flip-model present
- [ ] resize, minimize, restore
- [ ] DPI 100/125/150/200%
- [ ] zoom/pan/fit
- [ ] XAML overlay와 native image coordinate
- [ ] before/after compare
- [ ] clipping overlay
- [ ] monitor 이동
- [ ] device lost

### Instancing·activation·close

- [ ] custom `Main`에서 window/engine/catalog 생성 전 instance election
- [ ] x64와 native ARM64 `AppInstance` cold/warm activation
- [ ] 2/10/100 process launch race에서 primary 하나
- [ ] redirect success/failure 뒤 secondary resource·process cleanup
- [ ] Stable/Beta와 Windows user별 scope 분리
- [ ] main/Settings/About/Help window ownership
- [ ] `AppWindow.Closing.Cancel` 기반 async catalog read-back
- [ ] close 중 activation과 newer dirty generation race
- [ ] `WM_QUERYENDSESSION`/`WM_ENDSESSION` bridge

### lifetime stress

- document open/close 1,000회
- panel attach/detach 10,000회
- rapid resize·DPI switch
- engine shutdown 중 callback
- GC pressure
- app suspend-equivalent close·restart

### 실패 조건

- C#이 frame pixel을 marshal
- UI thread에서 decode/render wait
- stale request가 다른 document에 적용
- C++이 XAML object graph를 장기 소유
- panel unload 후 native reference cycle
- second process가 redirect 전에 catalog writer 또는 main window를 만듦
- ARM64만 다른 instance/close semantics를 사용
- normal close와 5초 session-end path를 같은 blocking save로 처리

### 통과 artifact

- Q-005, Q-024 결과
- ABI header hash와 projection test
- lifetime/state diagram
- leak·crash report
- canvas screenshot만이 아니라 pixel golden과 input trace
- instance/activation/close state trace와 architecture별 race report

## 10. S7 — catalog·migration·crash recovery

### 목적

UI보다 먼저 원본 불변, catalog 원자성, migration과 recovery를 증명한다.

### 기본 시나리오

- [ ] empty new catalog
- [ ] 1만·5만 frame import
- [ ] same source virtual copies
- [ ] folder move·rename·offline volume
- [ ] source relink
- [ ] sidecar conflict
- [ ] cache delete·rebuild
- [ ] backup·restore
- [ ] schema migration
- [ ] process kill during each write phase
- [ ] disk full·permission denied·corrupt DB

### macOS→Windows migration

- [ ] catalog direct-open 가능 여부
- [ ] export/import interchange가 필요한지
- [ ] bookmark와 path translation
- [ ] Unicode normalization과 case
- [ ] shared source identity
- [ ] reversible journal
- [ ] unsupported version error

### 실패 조건

- missing/corrupt catalog를 empty catalog로 처리
- recovery 중 orphan cleanup
- rawScanURL 원본 overwrite
- export reconstruction 실패 시 original fallback
- migration 중 원본 또는 제3자 XMP 수정
- virtual copy 삭제가 shared source 삭제로 이어짐

### 통과 artifact

- Q-023 결정
- crash-point matrix
- schema compatibility table
- backup/restore hash report
- source relink UX contract

## 11. S8 — WinUI 3 Library·입력·접근성

### 목적

예쁜 정적 화면이 아니라 macOS 제품의 상태·입력·접근성 계약을 native WinUI 3로 옮길 수 있는지
확인한다.

### Library 5만 항목

- [ ] ItemsView + UniformGridLayout virtualization
- [ ] thumbnail async decode와 stale apply 방지
- [ ] multi-select와 shift range
- [ ] keyboard navigation와 focus
- [ ] drag/drop
- [ ] filter·sort·stack
- [ ] compare·survey·filmstrip
- [ ] scroll anchor와 resize
- [ ] cold/warm cache

### inspector control

- [ ] slider + editable numeric value
- [ ] keyboard fine/coarse nudge
- [ ] one gesture = one undo
- [ ] reset과 default indication
- [ ] validation·disabled state
- [ ] Narrator value/range
- [ ] 200% text scaling

### 입력·접근성

- [ ] mouse·precision touchpad
- [ ] keyboard-only full workflow
- [ ] raw pen prototype
- [ ] high contrast
- [ ] light/dark
- [ ] Narrator·UI Automation
- [ ] six locales
- [ ] localized layout expansion

### 실패 조건

- virtualization 때문에 focus/selection 의미가 달라짐
- thumbnail completion이 재사용 container의 다른 frame에 적용
- custom canvas overlay가 접근성 tree에서 사라짐
- macOS shortcut를 modifier 이름만 바꿔 Windows convention을 무시
- unsupported scanner control을 disabled placeholder로 노출

### 통과 artifact

- Q-007 결과
- surface별 state-transition recording
- accessibility automation report
- keyboard scenario trace
- 100–200% DPI/text scale snapshots

## 12. S9 — scanner plugin·security·hardware

### 목적

라이선스·비트니스·driver failure가 코어 앱을 오염시키지 않는 외부 프로세스 경계를 증명한다.

### protocol

- [ ] hello/protocol negotiation
- [ ] enumerate/capability
- [ ] preview/scan request
- [ ] progress/result/error
- [ ] request ID와 session identity
- [ ] manifest와 artifact hash
- [ ] bounded stdout/stderr
- [ ] timeout·cancel·kill
- [ ] version mismatch
- [ ] unknown field forward compatibility

### process security

- [ ] canonical path
- [ ] owner SID·DACL
- [ ] reparse point·hard link 거부
- [ ] signature·hash
- [ ] approval record
- [ ] post-open/pre-exec replacement 방지
- [ ] restricted environment·working directory
- [ ] no inherited privileged handle
- [ ] output path containment

### adapters

- [ ] WIA 2.0 COM
- [ ] TWAIN x64
- [ ] TWAIN x86
- [ ] ARM64 host + driver reality
- [ ] optional SANE separate package

### hardware

- [ ] actual device/driver identity
- [ ] capability snapshot
- [ ] preview
- [ ] full scan
- [ ] requested/applied/decoded ROI
- [ ] bit depth·channel·ICC
- [ ] cancel·disconnect·driver UI
- [ ] process crash·restart

### 실패 조건

- implicit mock fallback
- model name으로 capability 추정
- USB enumerate를 지원 선언으로 사용
- x86 adapter 성공을 ARM64 kernel driver 지원으로 사용
- SANE binary를 core installer에 묶음
- plugin 실패가 core Library/Develop를 중단

### 통과 artifact

- Q-013, Q-014, Q-019 결과
- protocol conformance suite
- architecture/device matrix
- sandbox/ACL report
- plugin별 license/SBOM/source bundle

## 13. S10 — install·sign·update·rollback

### 목적

개발자 PC가 아닌 clean 사용자 환경에서 앱과 데이터를 안전하게 설치·서비스한다.

### 비교할 배포 모델

- unpackaged self-contained
- unpackaged framework-dependent
- WiX MSI
- Burn 또는 승인된 대안 bootstrapper
- 미래 packaged-with-external-location은 package identity 요구가 있을 때만
- full MSIX는 별도 미래 gate

### 필수 시나리오

- [ ] x64 clean install
- [ ] ARM64 clean install
- [ ] offline install
- [ ] per-user/per-machine 결정
- [ ] repair
- [ ] modify
- [ ] uninstall
- [ ] previous version upgrade
- [ ] interrupted upgrade
- [ ] binary rollback
- [ ] catalog forward-only migration 차단
- [ ] plugin 독립 update
- [ ] signature·timestamp offline/online verification
- [ ] expired signing certificate with valid timestamp
- [ ] corrupt update metadata
- [ ] downgrade attack
- [ ] low disk
- [ ] running app/engine/plugin process
- [ ] controlled app shutdown receipt + process exit
- [ ] Restart Manager close/restart
- [ ] `WM_QUERYENDSESSION` 5초 이내 응답과 다음 launch recovery
- [ ] normal close write/read-back/backup failure policy
- [ ] update 중 second launch와 activation redirection
- [ ] file association을 채택했다면 install/repair/uninstall/rollback ownership

### self-contained 비교 수치

- installer/download bytes
- installed bytes
- cold/warm launch
- private working set
- app-local runtime files
- servicing update turnaround
- patch/update delta

### 실패 조건

- unsigned helper/DLL/plugin
- installer가 실행 중 파일을 직접 덮어씀
- app update가 SANE plugin을 자동 교체
- binary rollback이 catalog rollback을 가장
- uninstall이 원본·catalog를 동의 없이 삭제
- self-contained runtime CVE가 자동으로 고쳐진다고 가정
- WiX 사용 조건 미승인
- updater가 shutdown receipt 없이 process name만 보고 강제 종료
- session-end handler에서 full backup/render를 시작해 deadline 초과
- close 실패를 catalog clean으로 기록

### 통과 artifact

- Q-016, Q-020, Q-022, Q-025 결론
- signed architecture별 installer
- payload manifest와 SBOM
- update transaction log
- rollback·repair matrix
- clean VM video/log
- normal close/update/logoff/restart/crash recovery matrix

## 14. S11 — 실제 출시 hardware·UI matrix

### 목적

WARP와 한 개발 PC의 성공을 제품 지원으로 과장하지 않는다.

### CPU·GPU

| 군 | 최소 검증 |
|---|---|
| Intel x64 | 오래된 지원 하한 iGPU, 일반 iGPU, Arc |
| AMD x64 | APU, 일반 Radeon |
| NVIDIA x64 | GTX/RTX 세대와 laptop hybrid |
| Qualcomm ARM64 | native ARM64 Adreno 장치 |
| CPU | Intel x64, AMD x64, ARM64 scalar/native |
| Software | WARP |

실제 model 목록은 release hardware manifest에서 고정한다.

### OS

- 지원할 Windows release의 clean VM과 실제 PC
- latest cumulative update
- 지원 종료가 가까운 release의 upgrade path
- Home/Pro와 필요 시 Enterprise
- locale·timezone variation

### Display

- SDR single monitor
- different-ICC dual monitor
- SDR + HDR/Advanced Color
- 100/125/150/200% DPI
- hybrid GPU
- remote desktop 조건부

### Workflows

- import → develop → export
- scan → preview → full scan → develop → export
- Library 5만 frame
- 50MP·100MP·panorama
- Defect Removal interactive·batch
- Quick Export와 ordinary Export
- single print와 contact sheet
- crash·cancel·restart·device lost
- install·update·rollback

### 품질·성능 보고

- decoded pixel과 stage-specific tolerance
- ICC·metadata
- p50/p95/p99 latency
- peak CPU/GPU/RAM/disk
- sustained batch와 thermal
- UI thread frame·input latency
- failure/recovery outcome

### Stable 실패 조건

- 필수 vendor군 하나가 비어 있음
- ARM64가 compile-only
- 스캐너 capability/ROI 증거 누락
- manual UI·Narrator QA 미실행
- 성능을 낮은 quality로 맞춤
- open Blocker가 waiver·만료일 없이 남음
- 실제 installer bytes의 license/SBOM 불일치

## 15. 스파이크 결과 기록 템플릿

~~~markdown
# Sx / run-id

## 질문
- Q-...

## 가설
- ...

## 환경
- source commit:
- baseline manifest:
- Windows:
- CPU:
- architecture:
- GPU/driver:
- toolchain:
- dependency lock:

## 입력
- corpus:
- license:
- dimensions/formats:

## 방법
1. ...

## 기대값
- ...

## 결과
- numeric:
- performance:
- memory:
- logs/artifacts:

## 판정
- pass / fail / inconclusive
- 이유:

## 결정 영향
- D-...
- 갱신 문서:

## 후속
- ...
~~~

inconclusive는 pass가 아니다. 환경 오류와 제품 오류를 구분하되 해결 전 다음 hard gate로 진입하지
않는다.

## 16. 현재 문서 단계의 경계

이 체크리스트는 앞으로 실행할 계획이다. 현재 문서 작성 작업에서 다음을 수행하거나 통과했다고
주장하지 않는다.

- Windows source 생성
- Visual Studio/CMake build
- x64·ARM64 실행
- D3D11/WARP pixel test
- WinUI 3 UI test
- scanner hardware test
- installer·signing test

현재 완료된 것은 위험을 구체적인 질문, 순서, 입력, 실패값과 artifact로 바꾼 것이다.
