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
> ③ **스크린샷 50장**(`C:\Users\habin\맥negaflow 스크린샷\`)을 확인한 **뒤에만** 판정합니다. 폴더·파일 전체 목록은 [`11`](11-ui-verification-protocol.md) 1.3절.
> **모양·크기·위치·정렬·색상·내용·텍스트 안 잘림** 일곱 가지를 전부 맞춥니다.
> XAML 에 있다고 "있음" 이 아닙니다 — **화면에 보여야** 있는 것이고,
> **눌러서 값이 안 바뀌면 가짜**입니다.
>
> **화면 도구 — 자세히.** `windows-mcp` / `windows-gui` MCP 는 **절대 금지.** 켜지 말고 호출하지 말고 대용으로도 쓰지 마십시오. Windows 앱·Parsec 맥 화면은 **computer-use 만.** computer-use 도 **꼭 필요할 때만** 씁니다(토큰). **씁니다:** 이 작업에서 화면에 보이는지·눌러서 값이 바뀌는지·잘림/정렬/색을 새로 판정해야 하고 코드·단위시험·스크린샷 50장·기존 로그로는 부족할 때. **쓰지 않습니다:** 백엔드·네이티브·시험만 고칠 때, 스크린샷 폴더+Swift/XAML 으로 충분할 때, 방금 본 화면을 다시 찍을 때, "일단 띄워 보자" 탐색. 쓸 때도 전체를 반복 찍지 말고 **해당 구역만 크롭.** 전문은 [`00`](00-index.md) · [`11`](11-ui-verification-protocol.md).
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

## 1. 프레임 메모리 캐시 — **2026-08-19 이식됨. 설정 탭만 없음**

| macOS | 줄 | Windows |
|---|---:|---|
| `FrameCacheManager.swift` | 120 | `FrameResidency.cs` — developed FIFO 재등록·축출·선택 프레임 보호 |
| `FrameCacheBudget.swift` | 107 | `FrameCacheBudget.cs` + native `frame_cache_budget.*`. 비율은 그대로, **한 프레임 비용만 실제 바이트**(Rgba32F 16바이트라 macOS 8바이트 추정의 2배) |
| `FrameCachePolicy.swift` | 49 | `FrameCachePolicy.cs` |
| `FrameCacheResidencyStore.swift` | 122 | developed 는 `FrameResidency`. cleaned raw 는 `decode.cpp` FIFO |
| `AppModel+MemoryPressure.swift` | 54 | **없음** |
| `MemoryPressureMonitor.swift` | 22 | **없음** — `CreateMemoryResourceNotification` 미배선 |

### 1.1 macOS 가 캐시하는 두 가지 (사용자가 지목한 것)

| 슬롯 | 무엇 | 프레임당 추정 |
|---|---|---:|
| **cleaned raw** | **결함 제거 원본** — 원본 해상도 16bit RGBA 한 장(6000×4000 ≈ 183MB) | `cleanedRawMegabytesPerFrame = 190.0` |
| **developed** | **현상 결과** + 변형-전 base + **정착 프록시 raw** 등 파생 버퍼 합계 | `developedMegabytesPerFrame = 170.0` |

`FrameCacheBudget.swift:9-12` 주석 원문:

> 프레임당 상주 추정치(MB). 24MP 원본 + 긴 변 3600px 현상 기준의 실무 근사값이다.
> - cleaned raw: 원본 해상도 16bit RGBA 한 장(6000×4000 ≈ 183MB).
> - developed: 현상본 + 변형-전 base + 정착 프록시 raw 등 파생 버퍼 합계.

**이 "정착 프록시 raw" 가 곧 [`01`](01-backend-gaps.md) 3.1 의 프리뷰 프록시입니다.**

프리뷰 raw 2슬롯은 `preview_raw_store`(프레임 키 + mutex + `shared_ptr`)입니다.
프로세스 전역 2슬롯은 지웠습니다([`07`](07-user-reported.md) H).

**아직 없는 것:** 메모리 압력 감시, 설정 → 메모리 캐시 섹션(자동/수동 슬라이더).
예산 상수는 코드에 있고 UI 가 없습니다.

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

**판정: FIFO 상주는 있습니다. 압력 이벤트와 설정 탭이 없습니다.**

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
| `DevelopFrameRenderer.metalQueue` | 단일 GPU 큐 | `gpu_device` 컨텍스트 하나. [`15`](15-gpu-handoff.md) |
| `interactiveProxyDimension()` 256 양자화 | 창 미세 변화에 캐시 유지 | **있음.** `DevelopPreviewProxy` |
| `waitForDevelopSettle` 0.14초 | 드래그 중 정착 안 함 | **있음.** `PreviewCoordinator` |
| `fastPreviewMaxDimension = 720` | 최초 빠른 프리뷰 | 상수 있음. 앱 체감 미측정 |
| `SamplingContextPool` | 샘플링 컨텍스트 재사용 | 히트 0 |
| `ConcurrentResultStore` · `DefectParallelAccumulators` | 검출 동시 수집 | 히트 0 |
| 정착 패스에서만 디스크 썸네일 | 인터랙티브는 건너뜀 | `RememberDeveloped`/`Publish` 를 정착에서만 |

---

## 6. 할 일

| 순서 | 내용 | 상태 |
|---|---|---|
| 1 | FIFO·예산·상주 | **닫음.** 1절 |
| 2 | 메모리 압력 감시 | **없음** |
| 3 | cleaned raw / developed 버퍼 | **닫음.** 디코드 FIFO + 프리뷰 raw + developed 상주 |
| 4 | 설정 → 메모리 캐시 섹션 | **없음** |
| 5 | 개발자 모드 화면 | 토글만 있음 |
| 6 | 캔버스 우클릭 배경 + HUD 대비 | HUD `CanvasHudChrome` 은 있음. 우클릭 메뉴는 없음 |

---

## 최적화 방법론은 [`13-performance-playbook.md`](13-performance-playbook.md)

이 문서는 **macOS 가 무엇을 캐시하는지**(FIFO·메모리 상한·개발자 모드 상수)를 다룹니다.
**어떻게 빠르게 만들지**는 13번입니다 — 2026-08-18 실측으로 새로 확인한 것:

| 항목 | 실측 |
|---|---|
| SIMD | 히트 11개, 전부 `flatbed_frame_*`. 화소 파이프라인에 없음 |
| 스레드 풀 | **있음.** `row_block_pool` 영속 워커. 예전 호출마다 `std::thread` 는 지움 |
| 컴파일러 스위치 | `/fp:precise` 있음. `/arch:` · `/GL` · `/LTCG` 없음 |
| 표시 경로 | 정착에서만 34.6 MB 복사. 인터랙티브는 비트맵 두 벌 재사용 |

**`/GL` + `/LTCG` 는 값을 안 바꾸면서 얻는 것이라 가장 먼저 시도할 것.**
`/fp:fast` 와 `/arch:AVX2` 는 **골든값을 바꿀 수 있습니다** — 켤 때마다 골든 시험과
실측 17장 dmin 을 돌리십시오.


---

## 2026-08-20 확인

이 문서의 표는 그대로 유효합니다. 이날 캐시·예산 코드는 건드리지 않았습니다.
다만 Release 빌드 스위치가 하나 늘었습니다 — `/Zi` `/DEBUG` `/OPT:REF` `/MAP`(심볼).
**코드 생성은 바뀌지 않으므로 위 실측 숫자는 다시 재지 않아도 됩니다**
([`13`](13-performance-playbook.md) 22절). `/GL`·`/LTCG` 는 여전히 안 켰습니다.
