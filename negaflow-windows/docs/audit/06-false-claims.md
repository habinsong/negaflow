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
