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


# 06 — 기존 문서의 틀린 서술

**이 저장소의 진행 문서에 사실과 다른 내용이 있습니다.** 그 문서를 믿고 일하면 없는 문제를
고치거나, 있는 문제를 못 봅니다. 실측으로 확인한 것만 적습니다.

---

## 1. `MonotoneCubic` — "가장 넓게 퍼지는 결손" (틀림)

**`docs/plan/08-missing-backend.md` 서술:**

> `MonotoneCubic` 이 없는 것이 가장 넓게 퍼집니다 — 다른 보간을 쓰고 있다면 **슬라이더를 같은
> 값에 놔도 macOS 와 결과가 다릅니다.**

**실측:**

- macOS `MonotoneCubic.swift` 를 `MonotoneCubic(` 로 전 트리 검색 → **호출처 0건.**
  macOS 에서도 이 타입은 쓰이지 않습니다.
- 실제로 점 커브를 만드는 것은 `Adjustments/ColorAdjustStages.swift` 의
  `CurveLUT.monotoneTangents` 입니다(Fritsch–Carlson).
- Windows `imaging/point_curve.cpp:158-186` 에 **그 알고리즘이 정확히** 있습니다 —
  `deltas` 계산, `(delta[i-1] + delta[i]) * 0.5`, `squared_magnitude > 9.0` 클램프,
  `3.0 / std::sqrt(...)` 까지 동일합니다.

**판정: 파일 이름만 없고 알고리즘은 이식돼 있습니다. 이 항목은 결손이 아닙니다.**

---

## 2. God object 표 10개 전부 낡음

`brief-for-agent.md` 11절 · `handoff-2026-08-17-2.md` 10절.
실측은 [`05-god-objects.md`](05-god-objects.md) 3절 — **10개 전부 이미 쪼개졌습니다**
(`negaflow_abi.cpp` 6,264줄 → 실제 **14줄**, `develop_export_abi_tests.cpp` 는 **파일 자체가 없음**).

---

## 3. "GPU 를 할 때" 문서가 있는데 GPU 코드는 0줄

`docs/plan/02-grainmend-performance.md` 는 D3D11 선택 근거와 13단계 우선순위표를 담고 있고,
`brief-for-agent.md` 는 이것을 "2단계"로 적었습니다. 그러나 실제 트리에는
`d3d11`·`ComputeShader`·`.hlsl` 등 **19개 키워드 전부 히트 0** 입니다.

**판정: 계획만 있고 착수 0. 문서가 "진행 중"으로 읽히지 않도록 상태를 명시해야 합니다.**

---

## 4. 복제 도장 "완료" 표기의 범위

`handoff-2026-08-17-2.md` 0절이 브러시를 "완료", 복제를 "진행 중"으로 적었습니다.
2026-08-18 에 복제 프론트엔드(소스 미리보기 포함)를 이식하고 시험 1,060개를 통과시켰지만,
**앱 화면에서 동작을 확인하지 못했습니다.** 인스펙터의 `복제 도장` 칩을 눌러도 캔버스 컨트롤
바가 뜨지 않았고, 클릭 미도달인지 버튼 비활성인지 가르지 못했습니다.

**판정: "시험 통과"와 "앱에서 동작"은 다릅니다. 문서에 둘을 분리해 적어야 합니다.**

---

## 5. `07-ui-gap-audit.md` 의 "미확인" 항목이 그대로 남음

그 문서 5절은 정렬 기준·정렬 방향·필름스트립 범위·필터 메뉴·빠른 필터·그리드/목록·카드 크기·
검색을 **"되는 것처럼 보이지만 확인 안 됨"** 으로 적고, *"조작해서 결과가 바뀌는지 확인하고,
안 바뀌면 그렇게 적고 고칠 때까지 비활성으로 두십시오"* 라고 했습니다.
**그 확인도, 비활성화도 하지 않았습니다.** 여전히 되는 것처럼 보입니다.

---

## 6. 검출 품질 표의 조건이 문서마다 다름

`brief-for-agent.md` 5.1 은 `Windows/macOS` 개수를 나란히 적으면서 dmin 조건을
*"위 dmin 은 임의값입니다… macOS 기준값과 같은 조건으로 재려면 dmin 을 맞춰야 합니다"*
라고 단서로 달았습니다. **단서가 붙은 수를 "일치"로 읽으면 안 됩니다.**
표에 어떤 dmin 으로 쟀는지가 없습니다.

---

## 7. 이 감사에서 바로잡은 것

| 항목 | 이전 서술 | 실측 |
|---|---|---|
| `MonotoneCubic` | 가장 넓은 결손 | 알고리즘 이식 완료, 이름만 없음 |
| God object 10개 | 6,264 / 4,835 / … | 14 / 329 / … 전부 분할됨 |
| GPU | "2단계 진행" | 감사 시점 **착수 0** 이었음. **2026-08-18 실제 착수**(`aa0d59f`) — `src/Native/gpu/` + 커널 1개, CPU 동치 1e-5 고정. 다만 **파이프라인 미연결·속도 미측정** |
| `DefectOverlayImage` 불투명도 | 언급 없음 | **창작 0.75** 있었음 → 제거 |
| 프리뷰 성능 원인 | "형태학이 82%" | 그것도 맞지만 **프리뷰는 매번 디코드(2,695 ms)가 더 큼** |
| `applySceneRanged` | "없음" | **이름만 없고 이식돼 있었음** — `scene_density_range` |
| `FilmBaseStatistics.swift` | "없음" | **이름만 없고 이식돼 있었음** — `coherentCluster`/`median`/`percentile` 셋 다 |
| `FilmBaseSampleGrid.swift` | "없음" | **이름만 없고 이식돼 있었음** — `SampleGrid`·`make_sample_grid` |
| `connected_component_base` 의 `candidate_peak` 관문 | 언급 없음 | **창작이었고 죽은 코드였음.** golden 8100 에서 조건이 거짓(`0.1186 < 0.0584`), 17장 전부 통과 못 함 → 제거 후 dmin **바이트 동일** |

---

## 8. 이 감사 자신의 오류 — 2026-08-18

**위 표 마지막 세 줄은 전부 같은 실수입니다: 파일명·함수명으로 찾아서 "없음" 으로 적은 것.**

> **이름이 같다고 있는 것이 아니듯, 이름이 없다고 없는 것도 아닙니다. 함수 안을 읽어야 합니다.**

**그리고 [`04-gpu-plan.md`](04-gpu-plan.md) 의 앞 판이 같은 종류였습니다.**
"무엇을 GPU 로 옮길까" 를 **Windows CPU 파일 목록에서 역으로 추측**해 커널 이름을 지어냈습니다
(`tone.hlsl`·`grading.hlsl` 따위). macOS 가 GPU 에서 **실제로** 돌리는 것을 세지 않았습니다.

2026-08-18 다시 썼습니다: `Chromabase/Engine/ChromabaseMetalKernels.swift` 를 열어
`[[stitchable]]` 커널 **32개**를 세었고, 같은 파일에서 `destCoord`·`.sample(` 히트가 **0** 인 것으로
**32개 전부 화소별**임을 확인했습니다. 이웃 연산은 Apple 내장 필터
(`CIGaussianBlur`·`CIBoxBlur`·`CIMedianFilter`·`CIAreaAverage`)가 하고 있었습니다 —
**그것이 Windows 에서 직접 만들어야 하는 부분**입니다.

---

## 9. ☠️ `digitalFilmColor` — Windows 가 **다른 알고리즘**입니다 (2026-08-18 발견)

이름만 보면 이식된 것처럼 보입니다. **안을 읽으면 아닙니다.**

| | 무엇을 하나 |
|---|---|
| **macOS** `ChromabaseMetalKernels.swift:774` | 색 행렬 3행 + 채널 리프트 → 그림자/명부 틴트 → **hue 6앵커 원형 보간 채도 변조**. `FilmEmulationProfile` 의 `mR/mG/mB`·`iieHue[6]`·`iie` 로 구동 |
| **Windows** `imaging/digital_film_color_preset.cpp` | **`apply_color_mixer` + `apply_color_grading` + `apply_primary_calibration`** 세 커널을 프리셋 값으로 순서대로 태웁니다 |

`hue` 라는 단어가 그 Windows 파일에 **한 번도 안 나옵니다**(`grep` 확인).
`DigitalFilmColorPreset` 구조체도 `mixer`·`grading`·`calibration` 세 개뿐이라
**macOS 커널의 파라미터(행렬·틴트·hue 앵커)를 담을 자리 자체가 없습니다.**

**즉 "비슷한 결과를 노린 재구성" 이지 이식이 아닙니다.**

> ☠️ **GPU 로 옮기기 전에 어느 쪽이 맞는지 정해야 합니다.**
> 지금 옮기면 **틀린 것을 빠르게 만들 뿐**입니다.
> 절차는 [`14`](14-remaining-gpu-methodology.md) 2절.

### 이 항목을 어떻게 찾았나

`grep -ril digitalFilmColor negaflow-windows/src` 가 **4 히트**를 냈습니다.
히트 수만 보고 "있음" 으로 적을 뻔했습니다. **파일을 열어서** 아닌 것을 확인했습니다 —
8절이 적은 *"이름이 같다고 있는 것이 아니다"* 의 **세 번째 사례**입니다.

---

## 10. ☠️ [`04`](04-gpu-plan.md) 0.3절의 "선행 조건" 셋이 전부 오판이었습니다 (2026-08-18)

| 적었던 것 | 실제 | 어떻게 확인했나 |
|---|---|---|
| `digitalFilmColor` — **"3D LUT(`Texture3D`) 필요"** | 텍스처 샘플링이 **한 줄도 없습니다.** 완전 화소별. 3D LUT 는 `ScannerTargetGrade` 의 `CIColorCube` 이고 **다른 커널 얘기**였습니다 | `:774` 본문을 읽음 |
| `noritsuTexture` — **"이웃 접근"** | 입력이 `src`+`blurred` 두 장인 **화소별** 커널. 이웃 연산은 가우시안이고 `GpuGaussianBlur` 는 **이미 delta 0**. 이식한 `digitalHalation`(블러 3장 입력)과 **같은 모양** | `:505` 본문을 읽음 |
| `filmGrain`·`digitalFilmGrainDensity` — **"씨앗 규칙을 macOS 와 대조해야 함"** | **이미 정해져 있습니다.** Windows CPU 가 좌표 해시 필드를 쓰고(`digital_film_grain.cpp:25-36`, 전부 uint32 → HLSL 에서 비트 단위 재현 가능), 헤더가 *"statistical, not pixel-exact"* 계약을 명시합니다 | `digital_film_grain.h:41-44` 와 `.cpp` 를 읽음 |

**셋 다 macOS 커널 본문을 안 읽고 적은 것입니다.** 04 앞 판(8절)과 **같은 실수를 축소판으로**
반복했습니다 — 그때는 파일 목록에서 추측했고, 이번에는 커널 이름과 주석 한 줄에서 추측했습니다.

> **규칙: "왜 막혔나" 를 적을 때도 근거를 열어야 합니다.**
> "됐다" 만 증명이 필요한 것이 아닙니다. **"안 된다" 도 증명이 필요합니다** —
> 틀린 장애물은 되지도 않을 일을 미루게 만듭니다.

---

## 11. ☠️ 9절이 **죽은 커널과 산 커널을 견줬습니다** (2026-08-19 정정)

9절은 `digitalFilmColor`(macOS `:774`)와 Windows `digital_film_color_preset.cpp` 를 견주고
*"다른 알고리즘"*, *"GPU 로 옮기기 전에 어느 쪽이 맞는지 정해야 한다"* 고 적었습니다.

**틀렸습니다. 그 macOS 커널은 죽어 있습니다.**

| 확인한 것 | 결과 |
|---|---|
| `digitalFilmColor` 를 부르는 곳 | `DigitalFilmLook.swift:97` 의 `DigitalFilmColor.apply` **하나** |
| `DigitalFilmColor.apply` 를 부르는 곳 | **없습니다.** `.swift` 1,035개 전수 grep — 정의만 남아 있습니다 |
| 그럼 무엇이 도나 | `DigitalFilmLook.swift:68` 의 **`DigitalFilmColorPresetStage`** 입니다 |
| `DigitalFilmColorPresetStage` 가 하는 일 | `digitalToDisplayGamma` → `ColorMixerStage` → `ColorGradingStage` → `CalibrationStage` → `digitalToLinearLight` → `CIMix` |

**Windows `digital_film_color_preset.cpp` 는 바로 그 산 스테이지를 옮긴 것입니다.**
mixer·grading·calibration 세 개뿐인 이유가 그것이고, `hue` 가 안 나오는 이유도 그것입니다.
9절이 *"담을 자리 자체가 없다"* 고 적은 것은 **담을 필요가 없는 것**이었습니다.

### 같은 확인을 나머지에도 했습니다 — **옮기면 안 되는 것이 6개**입니다

[`04`](04-gpu-plan.md) 0.3절이 *"CPU 판부터 없음 (7)"* 으로 적은 것 중 **다섯**이
여기 해당합니다. 호출 사슬을 끝까지 따라간 결과입니다:

| macOS 커널 | 유일한 호출부 | 그 호출부를 부르는 곳 |
|---|---|---|
| `digitalSceneReconstruct` | `DigitalSceneReconstruct.apply` | **없음** |
| `digitalFilmDensity` | `DigitalFilmDevelop.exposeDensity` | `DigitalFilmDevelop.apply` → **없음** |
| `digitalInterImage` | `DigitalFilmDevelop.interImage` | 〃 |
| `digitalPrintPaper` | `DigitalFilmDevelop.printOnPaper` | 〃 |
| `digitalReversalTransmit` | `DigitalFilmDevelop.transmit` | 〃 |
| `digitalFilmColor` | `DigitalFilmColor.apply` | **없음** |

이미 알려진 넷(`scannerLowSatChroma`·`scannerMidtoneChroma`·`gamutSoftClip`·
`highlightDesaturate`)과 합치면 **옮기면 안 되는 것이 10개**입니다.
**소스에 있다는 이유로 옮기면 macOS 에 없는 효과를 만들어 냅니다.**

살아 있는 둘은 `digitalToDisplayGamma`·`digitalToLinearLight` 이고,
`DigitalFilmColorPresetStage` 가 도메인 왕복에 씁니다. **그 둘은 이식했습니다**(`ba1c063`).

### 어떻게 찾았나

`grep -rn --include=*.swift '"digitalFilmColor"' .` 로 **커널 이름 문자열**을 세고,
히트가 난 함수의 이름으로 다시 grep 해 **호출 사슬을 끝까지** 따라갔습니다.
9절은 커널 본문 두 개를 나란히 읽는 데서 멈췄습니다 — **본문을 읽는 것만으로는
부족합니다. 그 함수가 불리는지도 봐야 합니다.**

---

## 12. ☠️ `noritsuTexture` — Windows CPU 판이 **이미 있습니다** (2026-08-19 정정)

[`14`](14-remaining-gpu-methodology.md) 3절이 *"Windows CPU 판이 없습니다
(`grep noritsuTexture` → win=0). **CPU 부터**입니다"* 라고 적었습니다.

**있습니다.** `imaging/scanner_target_grade.cpp:86` `apply_noritsu_texture` 입니다.
`apply_scanner_target_grade` 가 `target == ScannerTargetStyle::noritsu` 일 때 부릅니다(`:181`).
macOS 커널의 게이트 두 개(`lo < 0 || hi > 1`, `lumaO <= 1e-5`), 플로어
`max(yO*0.45, min(yO, 0.008))`, 공통 축소까지 그대로 있습니다.

**틀린 이유: camelCase 커널 이름으로 grep 했습니다.** Windows 는 snake_case 이므로
`noritsuTexture` 로는 영원히 0 히트입니다. 남은 것은 **GPU 이식뿐**입니다.

> **규칙: 이식 여부를 커널 이름으로 grep 하지 마십시오.** 두 저장소의 명명 규칙이
> 다릅니다. 개념어(`noritsu`·`halation`·`grain`)로 찾고, 찾은 파일을 **열어서** 판정하십시오.

---

## 13. `film_scan_denoise` GPU 오케스트레이터 — **제품 경로에 있습니다** (2026-08-19 정정)

[`04`](04-gpu-plan.md) 0.4절 5번과 [`14`](14-remaining-gpu-methodology.md) 7.2절이
*"타일을 도는 코드는 지금 **시험 안에만** 있습니다"* 라고 적었습니다.

**아닙니다.** `gpu/gpu_film_scan_stage.cpp` 가 `make_tile`(CPU 와 같은 512/18)로 타일을 돌고,
`pipeline/gpu_accelerator.cpp` `apply_film_scan_denoise` 가 그것을 부르며,
`stages/finish.cpp` 가 그 진입점을 씁니다. 문서가 쓰인 뒤에 배선된 것을 반영하지 못했습니다.

---

## 14. ☠️ `target_grade` **0.00 ms** 는 "빠르다" 가 아니라 **"안 돌았다"** 였습니다 (2026-08-19)

`--develop-timing` 의 단계 표에 `target_grade` 가 계속 **0.00 ms** 로 찍혔습니다.
그 줄을 보고 "그 단계는 비용이 없다" 로 읽었습니다. **틀렸습니다.**

그 단계는 `request.develop_target` 이 `main` 이 아닐 때만 돕니다(`stages/grade.cpp:56`).
계측 CLI 가 기본값 `main` 으로만 재고 있었으므로 **한 번도 안 돈 것**입니다.

타겟을 켜고 재니:

| 단계 | `main`(기본) | `noritsu` |
|---|---:|---:|
| `develop` | 201.00 ms | 349.08 ms |
| `tone_adjust` | 176.10 ms | 452.84 ms |
| **`target_grade`** | **0.00 ms** | **58,995.23 ms** |
| 전체 | **584.71 ms** | **60,536.19 ms** |

**엔진에서 가장 비싼 단계입니다.** 전체의 **97.5%** 이고, 두 번째로 비싼 단계의
**130배**입니다. 문서가 GPU 대상을 고를 때 이 단계를 한 번도 후보에 올리지 않은 이유가
그 0.00 이었습니다.

### 무엇이 그렇게 비싼가

`apply_profile_grade` 가 화소마다 `transformed_srgb` 를 **두 번**(정방향·역방향) 돌리고
`gamut_scale` 로 섞습니다. 그 안이 전부 `double` 이고 `log`·`exp`·`pow`·`fmod` 가
화소마다 여러 번 돕니다. 게다가 `noritsu` 는 프로파일 그레이드를 **두 번**
(기본 + 상대 시그니처) 태우고 그 위에 장치 질감까지 얹습니다.

> **규칙: 0.00 ms 를 보면 먼저 "그 단계가 돌았는가" 를 물으십시오.**
> 계측기의 기본값이 그 단계를 건너뛰면, 표는 조용히 "비용 없음" 처럼 보입니다.
> `--develop-timing` 에 `noritsu`·`sp3000`·`f135`·`hr` 를 넣은 이유가 그것입니다.


---

## 15. 문서가 낡아 "없다" 고 적힌 것들 (2026-08-19 기계 대조로 정정)

### 15.1 단축키 "74 vs 55 · 없는 것 24개" → **66 vs 64 · 없는 것 4개**

[`09`](09-shortcuts-and-settings.md) 1.1·1.2 가 낡았습니다. 두 열거자를 기계로 뺐습니다:

```
enum WorkflowShortcutAction (Swift)  66 케이스
enum WorkflowShortcutAction (C#)     64 케이스
없는 것 4: toggleScannerSimulator · addFlatbedFrame · removeFlatbedFrame · openHelp
Windows 에만 2: Undo · Redo (macOS 는 표준 편집 메뉴의 .undoRedo 를 갈아 끼움)
```

없는 4개는 전부 **아직 없는 메뉴(스캐너·도움말)** 에 붙는 것들입니다.

### 15.2 문자열 오류 11건 중 **2건은 오류가 아니었습니다**

- `filmLookDigitalOnly` 의 `Digital B&amp;W` — `.resw` 는 XML 이므로 `&amp;` 가 정상
  이스케이프이고 `ResourceLoader` 는 `Digital B&W` 를 돌려줍니다. WinUI 는 `&` 를
  단축키 밑줄로 먹지 않습니다.
- `namedFrameCopyDisplayFormat` 의 `{0} 사본 %d` — `{0}` 은 macOS `%@` 자리를 대신하는
  이름 칸이고 `LibraryWorkspaceCopy.cs:24` 가 이름을 끼웁니다. 숫자 치환기가 `%d` 만
  알기 때문에 나눠 둔 것이며 주석에 그 이유가 적혀 있습니다.

나머지 9건은 실제 오류였고 2026-08-19 에 고쳤습니다([`07`](07-user-reported.md) F).

### 15.3 ☠️ `scripts/sync-swift-ui-strings.ps1` 은 **깨져 있고 돌리면 문자열을 지웁니다**

- 경로가 저장소 재편 전 그대로입니다: `<repo>/Sources/negaflowApp/...` 를 찾다가
  `DirectoryNotFoundException` 으로 죽습니다. 지금 자리는 `negaflow-mac/Sources/...`.
- 더 위험한 것: 이 스크립트는 `baseline/swift-ui-string-map.json`(**92개 항목**)만 보고
  `Resources.resw` 를 **통째로 다시 씁니다.** 지금 resw 에는 **685개**가 있으므로
  `-Check` 없이 돌리면 **593개가 사라집니다.**
- CI 는 이 스크립트를 부르지 않습니다(`grep` 히트는 문서 2곳뿐).

**그래서 고치지 않고 그대로 두었습니다.** 필요한 것은 생성기가 아니라 **대조기**입니다 —
resw 항목의 `<comment>` 에 이미 `AppLocalizedPhrase.<key>` 같은 원본 심볼이 적혀 있으므로,
그것을 macOS 표와 언어별로 비교만 하고 **쓰지 않는** 검사기를 따로 만들어야 합니다.
