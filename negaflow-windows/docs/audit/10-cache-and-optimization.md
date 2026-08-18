> # ☠️ 하드코딩 · 가짜 구현 · 창작 · 병신 백엔드 · 병신 프론트엔드 = 죽음 ☠️
>
> **🔬 추측·가설 금지.** "냄새난다" 고 덮지 말고 **냄새의 원인을 찾아 없애십시오.**
> 재현하고, 스택을 잡고, 계측해서 원인을 **확정**한 뒤에 고칩니다.
> 원인을 못 잡았으면 **"못 잡았다" 고 적으십시오** — 추측으로 고친 것은 다음 사람의 함정입니다.
>
> **🌐 모르면 웹 검색을 적극적으로** 하십시오 — 특히 GPU·최적화·UI/UX 구현. 찾은 것은 출처를 남기십시오.
>
> **백엔드**: macOS Swift 파일을 **먼저 열고** 코드를 1:1 로 그대로 옮깁니다.
> 상수 하나, 임계 하나, 게이트 순서 하나도 지어내지 마십시오.
> 이름이 같다고 "있음" 으로 적지 마십시오 — **함수 안을 읽고** 판정하십시오.
>
> **프론트엔드**: ① computer-use 로 Windows 앱을 **구역별 크롭**해서 보고
> ② **Parsec 으로 macOS negaflow** 를 같은 구역으로 보고
> ③ **스크린샷 84장**(`negaflow_mac_screenshot/`)을 확인한 **뒤에만** 판정합니다.
> **모양·크기·위치·정렬·색상·내용·텍스트 안 잘림** 일곱 가지를 전부 맞춥니다.
> XAML 에 있다고 "있음" 이 아닙니다 — **화면에 보여야** 있는 것이고,
> **눌러서 값이 안 바뀌면 가짜**입니다.
>
> **저장소**: 본체 `C:\Users\habin\negaflow\`(Apache 2.0) · 스캐너 `C:\Users\habin\negaflow-scanner-sane\`(GPL).
> **두 저장소의 `negaflow-mac\` 은 절대 고치지 마십시오.** 코드 파쿠리·라이선스·특허·저작권 위반 금지.
>
> 규칙 [`00-index.md`](00-index.md) · UI 검증 [`11`](11-ui-verification-protocol.md) · 라이선스 [`12`](12-repos-and-licence.md)

---

---


# 10 — 메모리 캐시 · FIFO · 최적화 · 개발자 모드

macOS `Services/Cache/` **6파일 474줄** 을 Windows 와 대조했습니다.

---

## 1. 프레임 메모리 캐시 — Windows 에 **한 글자도 없음**

| macOS | 줄 | 하는 일 | Windows |
|---|---:|---|---|
| `FrameCacheManager.swift` | 120 | **FIFO 재등록 + 한도 초과분 축출** | **히트 0** |
| `FrameCacheResidencyStore.swift` | 122 | 어느 프레임이 상주 중인지 | **히트 0** |
| `FrameCacheBudget.swift` | 107 | 설치 메모리 → 상주 프레임 수 환산 | **히트 0** |
| `AppModel+MemoryPressure.swift` | 54 | 압력 이벤트에 축출 연결 | **히트 0** |
| `FrameCachePolicy.swift` | 49 | 압력 단계별 한도 | **히트 0** |
| `MemoryPressureMonitor.swift` | 22 | `DispatchSource.MemoryPressureEvent` 감시 | **히트 0** |

`FrameCacheManager` · `FrameCacheBudget` · `FrameCachePolicy` · `FrameCacheResidency` ·
`MemoryPressure` · `evictCleanedRaw` · `evictDeveloped` — **전부 히트 0.**

### 1.1 macOS 가 캐시하는 두 가지 (사용자가 지목한 것)

| 슬롯 | 무엇 | 프레임당 추정 |
|---|---|---:|
| **cleaned raw** | **결함 제거 원본** — 원본 해상도 16bit RGBA 한 장(6000×4000 ≈ 183MB) | `cleanedRawMegabytesPerFrame = 190.0` |
| **developed** | **현상 결과** + 변형-전 base + **정착 프록시 raw** 등 파생 버퍼 합계 | `developedMegabytesPerFrame = 170.0` |

`FrameCacheBudget.swift:9-12` 주석 원문:

> 프레임당 상주 추정치(MB). 24MP 원본 + 긴 변 3600px 현상 기준의 실무 근사값이다.
> - cleaned raw: 원본 해상도 16bit RGBA 한 장(6000×4000 ≈ 183MB).
> - developed: 현상본 + 변형-전 base + 정착 프록시 raw 등 파생 버퍼 합계.

**이 "정착 프록시 raw" 가 곧 [`01`](01-backend-gaps.md) 3.1 의 프리뷰 프록시입니다 —
Windows 가 매번 다시 디코드하는 바로 그것입니다. 캐시 계층이 없으니 캐시할 곳도 없습니다.**

### 1.2 FIFO 와 축출 정책 (그대로 옮길 값)

**FIFO**: `FrameCacheManager.swift:41` 주석 — *"FIFO 재등록 후 한도 초과분을 축출한다."*
방문한 프레임을 뒤에 다시 등록하고, 한도를 넘으면 **오래된 것부터** 내려놓습니다.

**압력 단계별 한도** (`FrameCachePolicy.swift`):

| 압력 | cleaned raw | developed |
|---|---:|---:|
| `normal` | 기본 **2** | 기본 **3** |
| `warning` | `min(기본, 1)` | `min(기본, 2)` |
| `critical` | **0** | **1** |

**예산 환산** (`FrameCacheBudget.swift`):

| 상수 | 값 | 뜻 |
|---|---:|---|
| `cleanedRawMegabytesPerFrame` | 190.0 | 결함 제거 원본 1프레임 |
| `developedMegabytesPerFrame` | 170.0 | 현상 결과 1프레임 |
| `automaticMinimumFraction` | 0.25 | 16GB 에서 설치 메모리의 25% |
| `automaticMaximumFraction` | 0.35 | 96GB 이상에서 35% |
| `automaticFractionReferenceGigabytes` | 16.0 | 기준점 |
| `automaticFractionStepGigabytes` | 16.0 | 16GB 늘 때마다 |
| `automaticFractionStep` | 0.025 | 2.5%p 씩 오름 |
| `manualMemoryFraction` | 0.70 | 수동 모드 상한 |
| `minimumCleanedRaw` / `minimumDeveloped` | 2 / 3 | 어떤 설정에서도 안 내려감 |
| `maximumCleanedRaw` / `maximumDeveloped` | 64 / 128 | 실용 상한 |

`FrameCacheBudget.swift:5-7` 주석 원문:

> 한도는 "미리 잡아 두는 양"이 아니라 **상한**이다. 실제로 방문한 프레임만 버퍼를 갖고,
> 한도를 넘으면 오래된 것부터 내려놓는다.

**판정: Windows 는 프레임 버퍼를 붙들지도, 내려놓지도 않습니다. 캐시가 없으니 매번 다시
만들고(→ 느림), 메모리 압력에 반응할 방법도 없습니다.**

---

## 2. 설정 — 메모리 캐시 탭

macOS `MemoryCacheSettingsSection.swift`(111줄)가 내는 것:

| 요소 | 내용 |
|---|---|
| 모드 `Picker` | **자동 / 수동** |
| 슬라이더 1 | **결함 제거 원본**(cleaned raw) 상주 프레임 수 |
| 슬라이더 2 | **현상 결과**(developed) 상주 프레임 수 |
| 단추 | **자동으로 되돌리기** |
| 도움말 3줄 | 설치 메모리 · 추정 사용량 · 자동/수동별 설명 |

**Windows 설정에 이 섹션이 통째로 없습니다**(`MemoryCacheSettings` 히트 0).

---

## 3. 개발자 모드

| macOS | Windows |
|---|---|
| `PresentationPreferencesStore.swift:12,37` — `developerMode` 키 저장 | `DeveloperModeToggle` (`SettingsRootView.xaml`) **있음** |
| `AppSettingsView.swift:110` — 일반 탭 토글 | 있음 |
| `DevelopAdjustmentSections.swift:39` — **`if model.developerMode`** 로 현상 인스펙터에 추가 섹션 노출 | **그 분기가 없음** |

**판정: 토글은 있는데 켰을 때 나오는 것이 없습니다.** macOS 는 개발자 모드에서
현상 인스펙터에 디버그 섹션을 냅니다(`DevelopDebugFrame.swift` 와 짝 — 그것도 히트 0,
[`01`](01-backend-gaps.md) 1.3).

---

## 4. 캔버스 배경색 (검정/회색/흰색)

| | macOS | Windows |
|---|---|---|
| 정의 | `CanvasBackground` (`allCases` = 검정·회색·흰색) | `canvasBackgroundBlack/Gray/White` 문자열 있음 |
| **어디서 고르나** | **캔버스 우클릭 메뉴** — `Shared/UI/CanvasBackgroundMenu.swift`(27줄), `Picker(.inline)` 를 `Section` 헤더와 함께 | **설정 → 인터페이스 탭의 ComboBox 하나**(`SettingsRootView.xaml:143-147`) |
| 어디에 걸리나 | 현상 캔버스(`ContentView+CenterStatus.swift:14`) · **인화 캔버스**(`ContentView+PrintWorkspace.swift:55`) · HUD 대비색(`CanvasCompareControls.swift:133`, `CanvasToolHUD.swift:75`) · 크롭 오버레이(`CropOverlay.swift:132`) | 캔버스 배경만 |

**판정 ②(백엔드는 있으나 진입점이 다름):**
값은 있는데 **현상·인화 프리뷰에서 우클릭하는 경로가 없습니다.**
그리고 macOS 는 이 값이 **HUD 글자색·컨트롤 표면 대비**까지 바꾸는데
(`hudContentColor`, `canvasControlSurface`), Windows 는 배경만 칠합니다.

---

## 5. 그 밖의 최적화 — macOS 에 있고 Windows 에 없는 것

| macOS | 무엇 | Windows |
|---|---|---|
| `DevelopFrameRenderer.metalQueue` (`DevelopFrameRenderer.swift:37`) | **단일 Metal command queue** — GPU 작업 정렬로 "빈/검은 프레임" 동기화 버블 제거 | GPU 없음 ([`04`](04-gpu-plan.md)) |
| `interactiveProxyDimension()` 256 양자화 | 창 크기 미세 변화에 **캐시 유지** | 없음 |
| `waitForDevelopSettle` 0.14초 | 드래그 중 풀해상도 렌더 안 함 | 없음 |
| `fastPreviewMaxDimension = 720` | 최초 표시용 빠른 프리뷰 | 없음 |
| `Engine/SamplingContextPool.swift` | 샘플링 컨텍스트 재사용 | 히트 0 |
| `DefectRemoval/ConcurrentResultStore.swift` | 검출 결과 동시 수집 | 히트 0 |
| `DefectRemoval/DefectParallelAccumulators.swift` | 병렬 누산기 | 히트 0 |
| 정착 패스에서만 디스크 썸네일 쓰기 (`AppModel+DevelopRendering.swift:236-238`) | 인터랙티브 패스는 건너뛰어 **디스크 IO 1회** | 없음 |

---

## 6. 할 일

| 순서 | 내용 |
|---|---|
| 1 | `FrameCacheBudget` · `FrameCachePolicy` · `FrameCacheManager`(FIFO) · `FrameCacheResidencyStore` **474줄 이식** — 위 상수 그대로 |
| 2 | Windows 메모리 압력 감시 — `DispatchSource` 대응은 `CreateMemoryResourceNotification` 또는 `QueryMemoryResourceNotification` |
| 3 | 캐시에 담을 **cleaned raw** 와 **developed(정착 프록시 포함)** 버퍼를 실제로 만들 것 ([`04`](04-gpu-plan.md) 6.1) |
| 4 | 설정 → 메모리 캐시 섹션(111줄) — 자동/수동 · 슬라이더 2 · 되돌리기 · 도움말 3줄 |
| 5 | 개발자 모드가 켤 화면 만들기(`DevelopDebugFrame` 포함) |
| 6 | 캔버스 **우클릭** 배경색 메뉴 + HUD 대비색 연동 |

---

## 최적화 방법론은 [`13-performance-playbook.md`](13-performance-playbook.md)

이 문서는 **macOS 가 무엇을 캐시하는지**(FIFO·메모리 상한·개발자 모드 상수)를 다룹니다.
**어떻게 빠르게 만들지**는 13번입니다 — 2026-08-18 실측으로 새로 확인한 것:

| 항목 | 실측 |
|---|---|
| SIMD | 히트 **11개, 전부 `flatbed_frame_*` 3파일**. 화소 파이프라인에 **없음** |
| 스레드 풀 | **없음.** `core/parallel_rows.cpp:113` 이 호출마다 `std::thread` 를 새로 만듦 |
| 컴파일러 스위치 | `/fp:precise` 는 `cmake/CompilerWarnings.cmake:12` 에 **있음**. 없는 것은 **`/arch:` · `/GL` · `/LTCG`** |
| `ArrayPool` | 관리 트리 히트 **0**. 단 `PreviewCoordinator.cs:112` 는 선할당돼 있어 문제 없음 |
| 표시 경로 | `DevelopPreviewCanvas.Present()` 가 프레임 전체 복사 — 3600×2400 이면 **34.6 MB/프레임**(산술, ms 미측정) |

**`/GL` + `/LTCG` 는 값을 안 바꾸면서 얻는 것이라 가장 먼저 시도할 것.**
`/fp:fast` 와 `/arch:AVX2` 는 **골든값을 바꿀 수 있습니다** — 켤 때마다 골든 시험과
실측 17장 dmin 을 돌리십시오.
