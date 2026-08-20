# Windows 이식 열린 질문 등록부

> 상태: 구현·출시 전 미해결 증거 목록  
> 기준일: 2026-08-04  
> 범위: Negaflow Windows x64·ARM64, WinUI 3, native engine, scanner plugins, 배포  
> 정본 결정: [기술 결정 등록부](../00-overview/decision-register.md)  
> 실행 순서: [이행 로드맵](migration-roadmap.md)

이 문서는 아직 직접 증명하지 못한 항목만 관리한다. 현재 자료는 macOS 코드·테스트를 읽은 결과와
공식 Windows/upstream 자료를 포함하지만, Windows 구현·실기 결과는 아직 없다. 따라서
“공식 API가 존재한다”, “컴파일될 것으로 보인다”, “다른 앱이 쓴다”는 사실만으로 질문을 닫지 않는다.

## 1. 상태와 판정 규칙

| 상태 | 의미 |
|---|---|
| Blocker | 결론 없이 다음 milestone 또는 출시에 진입하면 제품·데이터·법무 위험이 생김 |
| Gate | 기본안은 있으나 실제 산출물·장치·수치로 통과해야 함 |
| Conditional | 기능을 제외하면 v1을 진행할 수 있으나 포함하려면 해결해야 함 |
| Deferred | v1 기준선 밖이며 재검토 조건이 생길 때만 활성화 |
| Resolved | 결정과 근거가 정본 문서에 반영됨. 이 목록에서는 회귀 감시만 함 |

질문을 닫으려면 다음 네 가지가 필요하다.

1. 재현 가능한 입력·환경·명령 또는 수동 시나리오
2. 기대값과 실패 기준
3. 결과 artifact와 정확한 toolchain·OS·hardware 식별자
4. 결론을 반영한 정본 문서와 결정 등록부 변경

단순한 성공 로그, 화면 캡처 한 장, 한 PC의 실행 결과는 전체 지원 결론이 아니다.

## 2. 요약

| ID | 질문 | 상태 | 늦어도 해결할 gate |
|---|---|---|---|
| Q-001 | WIC float TIFF decode 범위 | Gate | M3 이미지 I/O |
| Q-002 | D2D compute와 순수 D3D11 compute의 실제 비용 | Gate | M5 GPU vertical slice |
| Q-003 | Direct2D 대형 이미지 tile·ROI 동작 | Gate | M7 대형 이미지 |
| Q-004 | FP32 intermediate의 벤더별 수치 동등성 | Blocker | M5 및 M16 |
| Q-005 | C ABI와 SwapChainPanel native interop | Gate | M8 WinUI 연결 |
| Q-006 | x64·ARM64 전체 의존성 native build | Blocker | M1 |
| Q-007 | WinUI 3 ItemsView 5만 항목 성능·선택 계약 | Gate | M9 Library |
| Q-008 | 다중 모니터 ICC·Advanced Color·SDR/HDR | Blocker | M16 qualification |
| Q-009 | ImageIO↔Windows JPEG 품질 의미 매핑 | Gate | M12 Export |
| Q-010 | CIMix 중간 강도의 실제 합성 domain | Gate | M6 Develop graph |
| Q-011 | GPU 측정의 벤더 간 결정성 | Blocker | M5 측정 |
| Q-012 | 느린 GPU에서 TDR-safe tile·dispatch 예산 | Blocker | M7 및 M16 |
| Q-013 | 실제 WIA·TWAIN 장치 capability와 scan 동작 | Blocker | M15 scanner |
| Q-014 | plugin 디렉토리 DACL·소유권 검증 | Blocker | M15 scanner |
| Q-015 | Wacom·Surface Pen raw pointer 품질 | Conditional | M11 Defects |
| Q-016 | Azure Artifact Signing의 조직·지역 적격성 | Conditional | M17 signing |
| Q-017 | Adobe RGB (1998) ICC 재배포 | Conditional | M12 Export |
| Q-018 | LibRaw 선택 라이선스·link·source 제공 | Blocker | M0/M3 |
| Q-019 | TWAIN DSM app-local·system 선택과 LGPL 의무 | Blocker | M0/M15 |
| Q-020 | WiX OSMF 조건 승인 또는 installer 대안 | Blocker | M0/M17 |
| Q-021 | 출시 시점 Windows 최소·지원 OS | Blocker | M0 재검토·M18 |
| Q-022 | self-contained와 framework-dependent 실측 비교 | Gate | M17 |
| Q-023 | macOS catalog·sidecar의 Windows migration 정책 | Blocker | M3 |
| Q-024 | x64·ARM64 single-instance activation 경로 | Blocker | M8/M17 |
| Q-025 | 정상 close의 catalog 승인 실패 정책 | Blocker | M8/M17 |

## 3. 이미지 엔진·정밀도

### Q-001 — WIC의 float TIFF decode 범위

상태: Gate

알고 있는 것:

- TIFF write 기준선은 libtiff다.
- WIC는 OS codec과 확장 codec을 통해 여러 포맷을 열 수 있지만 이름만으로 모든 TIFF 변종을
  지원한다고 볼 수 없다.
- Negaflow 입력에는 8/16-bit integer뿐 아니라 float, tiled/strip, planar/contiguous,
  다양한 compression·ICC·orientation 조합이 들어올 수 있다.

모르는 것:

- Windows 지원 release의 내장 TIFF decoder가 SampleFormat IEEEFP 32-bit를 어떤 조합에서 읽는가
- BigTIFF, predictor, planar layout, unusual channel count와 malformed metadata의 실제 실패 방식
- WIC 실패 뒤 libtiff fallback을 허용할 때 metadata·orientation·ICC 의미가 같은가

검증:

1. libtiff로 고정 corpus를 생성한다.
2. x64와 ARM64에서 WIC metadata query와 pixel decode를 실행한다.
3. decoded dimensions, channel order, alpha, sample type, ICC bytes, orientation, pixel values를 비교한다.
4. unsupported 조합은 명시적 capability 결과를 반환한다.
5. 실패를 8-bit decode나 임의 codec fallback으로 숨기지 않는다.

닫힘 조건:

- WIC 허용 표와 libtiff fallback 표가 [WIC 문서](../05-image-io/wic.md)에 반영되고,
  같은 corpus가 CI에 들어간다.

### Q-002 — D2D compute transform과 D3D11 compute의 비용

상태: Gate

기본안:

- point transform과 simple combine은 Direct2D custom pixel effect
- histogram, morphology, median, 큰 spatial operation은 동일 D3D11 device의 DirectCompute 후보
- D2D graph 내부에서 이점이 있는 compute transform만 ID2D1ComputeTransform 후보

모르는 것:

- D2D compute transform의 graph scheduling·intermediate 비용
- D2D와 raw D3D11 compute 사이 동일 texture 전환, hazard 처리, state restore 비용
- Intel/AMD/NVIDIA/Qualcomm UMA·dGPU에서의 crossover point

검증:

- 같은 수학과 resource format을 쓰는 D2D compute, D3D11 compute, CPU 구현을 만든다.
- 1MP, 24MP, 50MP, 100MP와 작은 ROI를 구분한다.
- shader time만이 아니라 graph 전체 GPU time, pass 수, transient bytes, CPU submit, sync와
  readback을 측정한다.
- 결과 픽셀·통계가 reference 계약을 통과해야 성능을 비교한다.

닫힘 조건:

- operation별 backend 선택표와 선택 근거가
  [backend 선택](../12-performance/backend-selection.md)에 기록된다.

### Q-003 — Direct2D 대형 이미지 tile·ROI 동작

상태: Gate

모르는 것:

- 50MP·100MP·파노라마에서 Direct2D가 실제로 만드는 tile와 intermediate surface
- SetRenderingControls, maximum bitmap size, effect input rectangle이 함께 작동하는 방식
- blur·median·affine·crop 경계의 halo와 seam
- 작은 viewport 변경이 full-frame 재렌더로 확장되는 조건

검증:

- synthetic impulse, edge, checkerboard, gradient와 실제 scan corpus를 사용한다.
- tile 크기, ROI, effect chain, scale, device memory budget을 바꾸며 ETW/RenderDoc/자체 trace를
  기록한다.
- tile order와 크기를 바꿔도 픽셀·deterministic noise가 같아야 한다.
- undocumented 8K 한계 같은 2차 보고는 재현 전 제품 사실로 기록하지 않는다.

닫힘 조건:

- [대형 이미지 설계](../06-large-images/image-source-tiling.md)의 budget과 fallback이 실제
  하드웨어 결과로 채워진다.

### Q-004 — FP32 intermediate의 벤더별 수치 동등성

상태: Blocker

알고 있는 것:

- extended-linear 음수와 1 초과 값을 보존해야 한다.
- Direct2D precision 요청은 전체 graph의 모든 내부 구현을 bit-identical하게 만든다는 보장이 아니다.
- FP16 또는 UNORM materialization은 눈에 보이지 않는 clipping·rounding 회귀를 만들 수 있다.

모르는 것:

- 32-bpc float 요청이 모든 필수 adapter·WARP·OS 조합에서 실제 graph에 어떻게 적용되는가
- shader linking 여부와 built-in effect가 중간 정밀도를 바꾸는가
- denormal, FMA, transcendental 구현 차이가 negativeInvert·tone·LUT 경계에 미치는 영향

검증 matrix:

- Intel iGPU·Arc
- AMD APU·Radeon
- NVIDIA GTX/RTX
- Qualcomm ARM64 Adreno
- WARP
- CPU scalar x64·ARM64

필수 fixture:

- 음수와 1 초과 ramp
- neutral ramp와 saturated primary
- Dmin/Dmax 경계
- log/pow domain 경계
- LUT cell boundary
- blur halo와 alpha
- NaN·Inf·denormal 정책 probe

닫힘 조건:

- stage별 tolerance와 실패 시 CPU/WARP fallback이 정해지고,
  [정밀도 문서](../01-render-engine/precision-and-clipping.md)의 release matrix가 통과한다.

### Q-009 — JPEG 품질 슬라이더 의미

상태: Gate

문제:

macOS ImageIO의 0…1 품질과 Windows encoder의 0…100 또는 codec-specific 품질을 숫자만 선형
변환하면 같은 UI 값이 다른 파일 크기·artifact를 만들 수 있다.

검증:

- 동일 RGB input과 ICC로 macOS·Windows를 각각 encode한다.
- 0, 25, 50, 75, 85, 90, 95, 100과 실제 preset 값을 측정한다.
- subsampling, progressive, metadata와 codec version을 고정한다.
- decoded pixel PSNR/SSIM만 보지 않고 파일 크기, ringing, chroma edge, metadata를 함께 본다.

닫힘 조건:

- 사용자가 보는 품질 값의 의미와 플랫폼별 encoder parameter table이
  [export 문서](../05-image-io/export-formats.md)에 고정된다.

### Q-010 — CIMix 중간 강도의 합성 domain

상태: Gate

문제:

디지털 필름 룩 강도 0 또는 1에서는 linear-light 합성과 display-domain 합성 차이가 감춰진다.
macOS CIMix의 실제 working/output color-space 동작을 추측해서 옮기면 중간 강도에서 색과 명도가
달라진다.

검증:

- 강도 0.25, 0.5, 0.75를 필수로 비교한다.
- neutral, saturated color, highlight, shadow fixture를 사용한다.
- Core Image graph의 명시 color space와 Windows blend 전후 transfer를 기록한다.
- 양쪽 결과가 맞지 않으면 “더 보기 좋은 쪽”이 아니라 기준 제품 의미를 결정 등록부에 올린다.

닫힘 조건:

- [가상 현상 문서](../15-digital-film/virtual-development.md)의 합성 domain이 실행 증거로
  확정된다.

### Q-011 — GPU 측정의 결정성

상태: Blocker

문제:

histogram, mean, percentile, film-base measurement가 자동 현상 파라미터를 만든다. GPU reduction의
덧셈 순서가 벤더·driver마다 달라 임계값을 넘으면 같은 사진이 다른 recipe를 얻는다.

검증:

- histogram은 integer bin exactness를 우선한다.
- floating reduction은 고정 partial layout과 CPU final reduction을 비교한다.
- thread-group permutation과 tile order를 바꿔 반복한다.
- 결과 통계뿐 아니라 그 통계로 생성된 최종 recipe와 export pixel을 비교한다.

결정 규칙:

- 허용 오차 안에서도 recipe가 달라지면 측정 경로를 CPU 결정 구현으로 고정한다.
- GPU 측정은 CPU보다 빠르다는 이유만으로 자동 승인하지 않는다.

닫힘 조건:

- 모든 필수 backend에서 재현 가능한 보고서가
  [측정 문서](../03-measurement/histogram-and-statistics.md)에 연결된다.

### Q-012 — TDR-safe tile과 dispatch 예산

상태: Blocker

문제:

수억 pixel scan을 하나의 긴 dispatch로 보내면 느린 GPU에서 TDR에 닿을 수 있다. 사용자에게
TdrDelay registry 변경을 요구하는 것은 제품 해법이 아니다.

검증:

- 가장 느린 지원 Intel iGPU와 Qualcomm UMA를 기준으로 한다.
- point, blur, median/morphology, histogram, defect detector를 따로 측정한다.
- tile 크기와 batch dispatch 수를 올리며 p95·p99 GPU duration과 UI responsiveness를 기록한다.
- export 장시간 부하, 배터리·thermal, display render 동시 실행을 포함한다.
- device removal 주입 뒤 recipe와 작업 queue가 보존되는지 확인한다.

닫힘 조건:

- operation별 최대 tile/work budget과 watchdog-safe cancellation point가
  [대형 이미지 문서](../06-large-images/image-source-tiling.md)에 고정된다.

## 4. ABI·아키텍처·UI

### Q-005 — C ABI와 SwapChainPanel interop

상태: Gate

기본안:

- 일반 엔진 호출은 opaque handle과 고정폭 POD를 쓰는 C ABI
- SwapChainPanel 연결에만 얇은 C++/WinRT adapter를 허용할 수 있음
- C#은 texture·pixel buffer를 프레임마다 marshal하지 않음

검증:

- x64·ARM64, unpackaged self-contained Release에서 실행한다.
- ISwapChainPanelNative 획득과 SetSwapChain ownership을 확인한다.
- panel unload/reload, window resize, DPI, monitor 이동, device lost, 앱 종료를 반복한다.
- COM apartment, callback thread, GC lifetime, final release 순서를 추적한다.
- 10,000회 attach/detach와 창 재생성에서 leak·use-after-free가 없어야 한다.

닫힘 조건:

- 한 가지 interop 경계와 lifetime diagram이
  [C#↔C++ 문서](../09-language-choice/csharp-native-interop.md)에 확정된다.

### Q-006 — x64·ARM64 전체 의존성 native build

상태: Blocker

대상:

- libtiff와 compression feature
- LittleCMS core
- SQLite provider
- LibRaw 후보
- native test framework
- WinUI 3/.NET self-contained payload
- installer toolchain
- scanner adapter별 x64·x86·ARM64 조합

검증:

- 같은 vcpkg baseline과 lock된 NuGet graph로 clean build한다.
- x64 binary가 ARM64 payload에 섞이지 않았는지 PE machine type을 전수 검사한다.
- debug/release CRT 혼입, static/dynamic runtime, transitive DLL을 검사한다.
- Windows ARM64 장치에서 native process인지 확인한다.
- x64 emulation 성공을 ARM64 지원 증거로 쓰지 않는다.

닫힘 조건:

- [개발 환경](../13-build-and-deps/development-environment.md)과
  [CMake/vcpkg](../13-build-and-deps/vcpkg-cmake.md)의 clean-room gate가 통과한다.

### Q-007 — ItemsView 5만 항목 성능과 선택 계약

상태: Gate

모르는 것:

- 50,000 frame에서 ItemsView + UniformGridLayout의 container realization·recycling 비용
- 다중 선택, shift range, keyboard focus, drag/drop, dynamic filter가 virtualization을 깨는 조건
- thumbnail async decode 완료 시 scroll anchor와 selection이 흔들리는지
- Narrator와 UI Automation peer가 virtualized item에서 올바르게 동작하는지

검증:

- 1천·1만·5만 virtual catalog를 사용한다.
- cold/warm cache, 빠른 wheel, scrollbar thumb drag, keyboard page 이동, selection range,
  filter reset, resize, 100–200% DPI를 측정한다.
- frame time, realized container 수, managed/native memory, decode queue, stale thumbnail apply를 기록한다.
- macOS 기준 동작과 사용자-visible selection semantics를 비교한다.

닫힘 조건:

- scroll·selection·memory 예산과 실패 기준이
  [Library surface](../08-ui/surfaces/library.md)에 기록된다.

### Q-008 — 다중 모니터 ICC와 SDR/HDR 혼합

상태: Blocker

모르는 것:

- WinUI 3 창의 output 이동·DPI·Advanced Color 변경 이벤트를 가장 안정적으로 결합하는 방법
- display ICC identity, adapter LUID, DXGI output, SDR white level의 수명
- 창이 두 모니터에 걸친 동안 preview transform을 어느 기준으로 선택할지
- HDR surface와 SDR soft-proof·gamut overlay를 동시에 표시할 때의 ownership

검증:

- ICC가 다른 SDR 모니터 두 대
- SDR + HDR/Advanced Color 모니터
- 내장 GPU + dGPU/외장 모니터
- profile 변경, HDR toggle, sleep/wake, remote desktop, device reset
- window drag 중 frame-by-frame profile switch와 cache invalidation

닫힘 조건:

- 실제 측정 장치와 ICC hash를 포함한 결과가
  [색 관리](../04-color-management/color-pipeline.md)와
  [canvas](../08-ui/surfaces/canvas.md)에 반영된다.

### Q-015 — Wacom·Surface Pen raw pointer 품질

상태: Conditional

기본안:

Defect brush와 clone stamp는 잉크 문서가 아니라 image mask 편집이므로 PointerPoint 기반 raw
pointer path를 우선한다. InkPresenter는 요구를 만족하는지 비교 대상으로만 둔다.

검증:

- Surface Pen과 대표 Wacom tablet
- pressure range·tilt·eraser·barrel button·hover
- coalesced point, sample rate, latency, dropped sample
- 100–200% DPI와 multi-monitor
- mouse fallback과 keyboard modifier
- stroke 중 zoom/pan·undo·cancel·device disconnect

닫힘 조건:

- brush geometry와 pressure mapping이 macOS 동작·golden mask와 맞고,
  [Defects surface](../08-ui/surfaces/defects.md)에 device matrix가 기록된다.

Pen이 v1 지원 범위에서 제외되면 mouse 기능을 완전하게 유지하고 UI에서 지원한다고 표시하지 않는다.

### Q-024 — x64·ARM64 single-instance activation 경로

상태: Blocker

제품 기준안:

- 사용자·제품 채널별 primary UI process 하나
- second launch는 새 window, AppModel, engine, catalog writer를 만들기 전에 기존 process로 redirect
- Stable/Beta/Internal은 별도 key와 data root
- 실제 library process lock은 instance election과 별도

불확실성:

- Windows App SDK의 lifecycle migration guide는 현재 제시한 single-instance code가 x64 target에서
  기대대로 동작한다는 주의를 둔다.
- 2026-07-11 갱신된 일반 multi-instance 안내는 같은 API와 custom entry point를 architecture 제한 없이
  설명하지만, 이것만으로 Negaflow ARM64 artifact가 검증되지는 않는다.
- 이 문구만으로 ARM64 미지원이라고 결론 내릴 수 없지만 ARM64가 검증되었다고도 볼 수 없다.
- unpackaged self-contained bootstrap, custom C# `Main`, STA와
  `RedirectActivationToAsync` completion 순서를 실제 artifact로 확인해야 한다.
- primary가 closing/unregister 중일 때 redirect가 실패하거나 다른 process로 순환할 수 있다.

검증:

- x64 Intel/AMD와 native ARM64에서 custom `Main` build/run
- 실제 unpackaged self-contained와 packaged comparison artifact
- 2/10/100 process cold-launch race
- warm Launch와 승인된 File activation
- primary startup·catalog blocked·normal close·update gate 각 phase에서 second launch
- separate Windows users와 Stable/Beta side-by-side
- redirect success/failure/cancel 뒤 secondary process와 resource cleanup

대안 gate:

`AppInstance`가 지원 matrix를 만족하지 못하면 single-primary 제품 계약을 버리지 않는다. user SID와
channel identity로 제한한 election primitive와 authenticated local activation channel을 대안으로
비교한다. architecture마다 서로 다른 UX를 허용하지 않는다.

닫힘 조건:

- x64·ARM64에서 같은 instance/activation conformance가 통과하고
  [앱 수명주기 명세](../08-ui/application-lifecycle.md)와 D-017이 실제 선택 mechanism으로 갱신된다.

### Q-025 — 정상 close의 catalog 승인 실패 정책

상태: Blocker

관찰한 충돌:

- macOS model은 종료 commit/read-back 실패를 `false`로 보고하고 unsaved error와 preview를 보존한다.
- 현재 app delegate는 그 결과에서 동기 save를 한 번 더 시도한 뒤 결과와 무관하게 종료 reply를
  `true`로 보낸다.
- snapshot 준비 실패의 `.terminateCancel`도 delegate 수준에서는 `.terminateNow`가 된다.
- 관련 app-level test는 명시적 Quit이 이 실패 때문에 취소되지 않는 현재 동작을 고정한다.

결정 후보:

| 후보 | 데이터 안전 | macOS 현재 동작 parity | UX/운영 비용 |
|---|---|---|---|
| A. 실패해도 종료 | 낮음. 마지막 verified generation까지만 보존 | 가장 가까움 | 간단하지만 변경 손실 위험 |
| B. 정상 close 취소 | 높음 | 현재 delegate와 차이 | recovery surface·retry 필요 |
| C. bounded retry 뒤 사용자 선택 | 선택에 따라 다름 | 일부 차이 | 가장 복잡, 명시적 discard 의미 필요 |

기준안은 B다. main X/Exit 같은 정상 사용자 close는 창을 유지하고 retry/recovery를 제공한다. 그러나
`WM_QUERYENDSESSION`, critical shutdown, crash, kill, power loss에서는 dialog나 긴 async commit을
보장할 수 없으므로 평상시 autosave·journal·atomic write로 복구한다.

검증:

- write/read-back/backup 실패 각각
- commit 중 newer dirty generation
- uncommitted defect gesture bake 실패
- active export publish와 scanner finalization
- normal X, Alt+F4, menu Exit, installer close, logoff/restart를 분리
- x64·ARM64와 slow/full/offline storage
- 사용자가 Retry/Return/승인된 Discard 중 선택했을 때 정확한 catalog·temp state

닫힘 조건:

- macOS 제품 의도와 Windows 데이터 안전 정책이 승인되고 두 플랫폼의 의도된 delta가 parity register,
  lifecycle spec, catalog tests와 release notes에 기록된다.

## 5. 스캐너·보안

### Q-013 — 실제 WIA·TWAIN 장치 동작

상태: Blocker

문서만으로 확정할 수 없는 것:

- 장치가 WIA 2.0 item tree와 film source를 실제로 어떻게 보고하는가
- TWAIN Data Source의 32/64-bit, DSM version, native/file/memory transfer 안정성
- resolution, bit depth, scan area, exposure, IR capability의 실제 적용
- cancel·paper/film jam·USB disconnect·driver UI·process crash
- ARM64 장치의 kernel driver와 adapter availability

검증 순서:

1. Windows Device Instance ID와 driver package/version 기록
2. adapter enumerate
3. capability snapshot
4. preview 요청과 결과 manifest
5. full scan 요청
6. requested ROI = plugin applied ROI = decoded artifact geometry 비교
7. bit depth·channel·ICC·orientation·hash 검증
8. cancel·timeout·disconnect·재시작

닫힘 조건:

- 장치별 결과가 [하드웨어 검증 매트릭스](../10-scanner/hardware-validation-matrix.md)에
  artifact-backed 상태로 들어간다.

### Q-014 — plugin 디렉토리 DACL·소유권 검증

상태: Blocker

문제:

macOS의 “현재 사용자 소유, group/other writable 아님”을 Windows mode bit로 직역할 수 없다.
승인한 plugin binary가 다른 사용자나 낮은 권한 process에 의해 바뀔 수 있으면 hash 승인만으로
부족하다.

검증:

- per-user plugin root의 owner SID와 canonical DACL
- inheritance, explicit ACE, deny/allow precedence
- Users, Everyone, Authenticated Users, service SID, administrator 권한
- junction, symlink, reparse point, hard link와 path traversal
- installer와 updater가 ACL을 약화시키지 않는지
- binary open 후 실행 전 교체하는 TOCTOU

닫힘 조건:

- unsafe ACL과 reparse point를 거부하는 규칙, atomic install·approval·launch 순서가
  [plugin 보안 문서](../10-scanner/plugin-security-and-lifecycle.md)에 실행 증거로 반영된다.

### Q-019 — TWAIN DSM 배치와 LGPL 의무

상태: Blocker

결정해야 할 것:

- OS/system-installed DSM만 사용할지
- x64·x86 DSM을 plugin과 app-local 배포할지
- 정확한 DSM release와 license
- 수정 여부와 source offer/notice
- application이 DSM을 찾는 search order와 DLL planting 방지
- vendor Data Source와 DSM의 bitness matrix

검증:

- clean machine, system DSM 있음/없음, app-local DSM 있음/없음
- x64·x86 adapter가 잘못된 DSM을 로드하지 않음
- signature/hash와 loaded module path 진단
- replacement/relink 권리 및 license bundle 검토

닫힘 조건:

- 배포 단위와 license 의무가
  [WIA/TWAIN 문서](../10-scanner/twain-wia.md)와
  [서드파티 라이선스](../13-build-and-deps/third-party-licenses.md)에 승인된다.

## 6. 배포·라이선스·지원 수명

### Q-016 — Azure Artifact Signing 적격성

상태: Conditional

모르는 것:

- Negaflow를 배포할 법인·개인 주체와 지역이 현재 서비스 eligibility를 만족하는지
- onboarding, identity validation, certificate profile, quota와 비용
- 서비스 장애 시 release continuity
- installer, PE, MSIX 미래 채널의 지원 범위

대안:

- 신뢰 가능한 CA의 OV/EV code-signing certificate
- 조직 보안 정책에 맞는 hardware/cloud key custody
- timestamp service redundancy

닫힘 조건:

- 실제 계정으로 onboarding과 test signature를 완료하고 clean VM에서 trust chain을 검증하거나,
  대체 인증서 경로가 승인된다.

### Q-017 — Adobe RGB (1998) ICC 재배포

상태: Conditional

모르는 것:

- Adobe 제공 profile bytes를 Windows installer에 동봉할 권리
- OS 설치 profile을 안정적으로 참조할 수 있는지
- LittleCMS로 생성한 matrix/TRC profile을 “Adobe RGB (1998)”로 표시할 수 있는지와 수치 동등성

대안:

1. 사용자가 설치한 system profile을 명시적으로 선택
2. 재배포 가능한 별도 working/output profile 사용
3. profile을 포함하지 않고 feature를 숨김

닫힘 조건:

- 법적 사용권과 ICC hash·색채 수치가 모두 승인되어야 UI에 이름을 노출한다.

### Q-018 — LibRaw 선택 라이선스와 제품 경계

상태: Blocker

결정해야 할 것:

- LGPL-2.1 또는 CDDL-1.0 중 어떤 선택 조건으로 소비할지
- dynamic DLL, 수정 파일, build patch와 source 제공 방식
- Windows x64·ARM64 build
- camera RAW quality가 macOS ImageIO/RAW 기준과 충분히 동등한지
- unsupported camera와 embedded preview fallback 정책

닫힘 조건:

- license option, linkage, exact source, source archive, notices, modification inventory와 품질 corpus가
  [LibRaw 문서](../05-image-io/libraw.md)에 승인된다.

LibRaw를 제외하면 camera RAW import를 지원한다고 표시하지 않는다. 일반 TIFF/JPEG import와 scanner
workflow는 독립적으로 진행할 수 있다.

### Q-020 — WiX OSMF 승인 또는 installer 대안

상태: Blocker

알고 있는 것:

- 현재 WiX source는 MS-RL이며 repository는 별도의 Open Source Maintenance Fee 정책을 안내한다.
- 수익을 창출하는 사용에 fee가 필요하다는 upstream 설명이 있다.
- 현재 배포 설계는 MSI/Burn을 후보로 삼았지만 tool 사용 조건 승인은 아직 구현 증거가 아니다.

결정:

1. 실제 사용할 WiX major/version과 조직 사용 방식에 대해 조건·비용을 승인한다.
2. 승인하지 않으면 기능이 동등한 installer tool을 평가한다.

대안 평가 항목:

- MSI upgrade/repair/uninstall
- bootstrapper와 prerequisite
- x64·ARM64
- deterministic build
- code signing
- rollback
- silent enterprise deployment
- SBOM·license
- 유지보수와 상업 사용 조건

닫힘 조건:

- 구매/법무 기록 또는 대안 결정과 clean install/update/rollback 결과가
  [배포 채널](../11-distribution/deployment-channels.md)에 반영된다.

### Q-021 — 출시 시점 Windows 최소·지원 OS

상태: Blocker

현재 사실:

- Windows 11 feature update는 edition별 servicing 기간이 다르다.
- 2026-08-04 기준 Windows 11 24H2 Home/Pro end of updates는 2026-10-13이다.
- 25H2는 기존 장치의 일반 지원 release이며, 26H1은 공식 자료상 2026년 신형 장치용이고
  24H2/25H2 기존 장치의 일반 in-place update가 아니다.

구분해야 할 축:

- TargetPlatformMinVersion: API load 가능 하한
- CI baseline image
- hardware lab tested versions
- 고객 지원 release
- 신규 설치 허용 release
- 기존 설치의 grace period

결정 규칙:

- Stable 시점에 Microsoft 지원이 끝난 Home/Pro release를 신규 사용자 기본 지원선으로 고정하지 않는다.
- Windows 10의 기술적 실행 가능성을 제품 지원으로 오인하지 않는다.
- 최소 OS를 올리기 전에 catalog·source 접근과 update 경로를 보존한다.
- 지원 종료 OS에서 조용히 실행을 막기보다 정책과 보안 위험을 명시한다.

닫힘 조건:

- Beta와 Stable 직전의 공식 release information, driver·API matrix와 실제 VM 결과로
  [호환성 매트릭스](../00-overview/compatibility-matrix.md)를 갱신한다.

### Q-022 — self-contained와 framework-dependent 배포 비교

상태: Gate

현재 기본 후보:

architecture별 unpackaged self-contained 배포.

검증할 tradeoff:

| 항목 | self-contained | framework-dependent |
|---|---|---|
| payload·disk | 더 큼 | 더 작음 |
| start memory·code sharing | 불리할 수 있음 | shared runtime 이점 |
| runtime version 통제 | 앱이 고정 | shared servicing 영향 |
| 보안·servicing owner | 앱이 rebuild·재배포 | runtime servicing 채널 |
| offline install | payload 완결 가능 | runtime installer 필요 |
| clean repair | installer가 전체 소유 | runtime 상태도 진단 필요 |

실측:

- x64·ARM64 clean VM
- cold/warm launch
- private working set, disk bytes, installer bytes
- runtime missing/corrupt
- patch release 업데이트와 rollback
- side-by-side app version
- offline enterprise 설치

닫힘 조건:

- 실제 수치와 운영 책임을 비교한 뒤 D-011을 최종 결정으로 승격하거나 변경한다.

### Q-023 — macOS data의 Windows migration 정책

상태: Blocker

결정해야 할 것:

- Windows가 macOS catalog.sqlite를 직접 열 수 있는가
- sidecar·recipe·preset·profile 중 플랫폼 중립 정본은 무엇인가
- macOS absolute path, bookmark, volume identity를 어떻게 가져올지
- 대소문자, Unicode normalization, forbidden filename, path length
- virtual copy와 shared source ownership
- migration 실패·재시도·rollback
- 한 library를 두 OS가 동시에 쓰는 것을 허용할지

기본 안전안:

- 원본은 복사하거나 덮어쓰지 않는다.
- Windows catalog는 새 사본에서 migration한다.
- source는 explicit relink와 content identity로 확인한다.
- 실패한 migration이 빈 catalog나 orphan cleanup을 유발하지 않는다.
- 새 schema 저장 전 verified backup과 migration journal을 만든다.

닫힘 조건:

- 지원/비지원 migration 경로와 reversible test corpus가
  [catalog와 storage](../14-persistence/catalog-and-storage.md)에 확정된다.

## 7. 해소되었거나 v1에서 미룬 항목

| 과거 질문 | 현재 상태 | 결론 |
|---|---|---|
| Win2D를 main canvas·histogram에 쓸 것인가 | Resolved | raw Direct2D/D3D11 기준선. Win2D는 채택하지 않음 |
| HLSL 2021을 v1 필수로 쓸 것인가 | Resolved | v1은 FXC·SM5·DXBC와 portable subset. 필요 없음 |
| D3D12 FL 12_0·SM6를 최소선으로 할 것인가 | Resolved | 제외. D3D11 FL 11_0·SM5 기준선 |
| D3D11On12로 D2D와 D3D12를 항상 연결할 것인가 | Resolved | v1에 사용하지 않음 |
| DirectML로 일반 이미지 필터를 만들 것인가 | Resolved | 제외 |
| Work Graphs를 baseline으로 쓸 것인가 | Resolved | 제외 |
| CUDA를 완전히 금지할 것인가 | Resolved | NVIDIA 전용 후순위 후보. 기능 gate 금지 |
| Google Highway를 필수로 넣을 것인가 | Resolved | 후보. 반복되는 hot-loop 필요와 실측 뒤 판단 |
| x64 baseline을 SSE4.2로 올릴 것인가 | Resolved | 올리지 않음. SSE2/MSVC default |
| ARM64EC를 쓸 것인가 | Resolved | 순수 ARM64. x86/x64 scanner는 외부 process |
| sparse package/MSIX를 v1 기본 배포로 할 것인가 | Resolved | 아님. unpackaged 기본, package identity는 후속 spike |
| MSIX의 catalog virtualization | Deferred | 미래 full MSIX channel을 승인할 때 재활성 |
| NVIDIA 11on12 특정 driver crash | Deferred | v1이 11on12를 쓰지 않음. D3D12 tier 때 재검증 |
| Intel Arc의 SM6 세부 version | Deferred | v1 SM5에 불필요. D3D12/SM6 tier 때 재검증 |
| Agility SDK 최소 OS | Deferred | v1 D3D11 기준선에 불필요 |

Deferred 항목은 삭제하지 않는다. 다만 현재 critical path나 완료율에 포함하지 않고 재활성 조건을
명확히 둔다.

## 8. 질문 운영 규칙

### 8.1 새 질문 추가

다음을 모두 적는다.

- 고유 ID
- 모르는 사실
- 이미 확인한 사실
- 사용자·품질·데이터·법무 영향
- 검증 장치·입력·명령
- 기대값과 실패값
- 마지막으로 해결해야 할 milestone
- 결과를 반영할 정본 문서

### 8.2 질문 닫기

- 결과 artifact 링크
- OS·driver·toolchain·architecture
- corpus version
- pass/fail 수치
- 남은 지원 범위
- decision register 변경

를 남긴다. “테스트해 봤고 됨”으로 닫지 않는다.

### 8.3 시간에 따라 변하는 질문

Q-016, Q-020, Q-021, Q-022처럼 service, 비용, policy, version에 의존하는 항목은 한 번 닫혀도
Beta·RC·Stable에서 다시 연다. [유지보수 문서](maintenance.md)의 baseline manifest에 확인일과
공식 URL을 기록한다.

## 9. 공식 참고

- [Windows 11 release information](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information)
- [Windows App SDK deployment overview](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/deploy-overview)
- [Self-contained Windows App SDK apps](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps)
- [Unpackaged Windows App SDK apps](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/deploy-unpackaged-apps)
- [Direct2D custom effects](https://learn.microsoft.com/en-us/windows/win32/direct2d/custom-effects)
- [Direct2D effect shader linking](https://learn.microsoft.com/en-us/windows/win32/direct2d/effect-shader-linking)
- [Direct3D 11 compute shaders](https://learn.microsoft.com/en-us/windows/win32/direct3d11/direct3d-11-advanced-stages-compute-shader)
- [Windows on Arm](https://learn.microsoft.com/en-us/windows/arm/add-arm-support)
- [App instancing with the app lifecycle API](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/applifecycle/applifecycle-instancing)
- [Application lifecycle functionality migration](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/migrate-to-windows-app-sdk/guides/applifecycle)
- [Registering for Application Recovery](https://learn.microsoft.com/en-us/windows/win32/recovery/registering-for-application-recovery)
- [WIA overview](https://learn.microsoft.com/en-us/windows-hardware/drivers/image/windows-image-acquisition-drivers)
- [TWAIN DSM repository](https://github.com/twain/twain-dsm)
- [WiX Toolset repository and OSMF notice](https://github.com/wixtoolset/wix)
- [LibRaw licensing](https://www.libraw.org/about)
