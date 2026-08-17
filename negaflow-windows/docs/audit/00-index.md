> # ⛔ 창작 금지 — 이 줄부터 읽으십시오
>
> # **macOS Swift 파일을 먼저 열고, 코드를 1:1 로 그대로 옮깁니다.**
>
> ## 하지 말 것
>
> - **설명만 보고 다시 쓰기 금지.** 파일을 **열어서** 함수·상수·순서를 그대로 베낍니다.
> - **"비슷하게" 금지.** 상수 하나, 임계 하나, 게이트 순서 하나도 지어내지 않습니다.
> - **Swift 에 없는 것을 넣지 않습니다.** Swift 에 있는 것을 빼지 않습니다.
> - **이름이 같다고 "있음" 으로 적지 않습니다.** 함수 안을 읽고 판정합니다.
> - **시험이 통과했다고 "된다" 고 보고하지 않습니다.** 앱에서 확인한 것만 "된다" 입니다.
>
> ## 파일 하나를 고치기 전에 반드시
>
> ```
> 1. 대응하는 macOS Swift 파일을 찾는다        ← 못 찾으면 손대지 않는다
> 2. 그 파일을 처음부터 끝까지 읽는다           ← 발췌 금지
> 3. Windows 파일을 나란히 놓고 줄 단위로 댄다
> 4. 다른 곳을 Swift 쪽에 맞춘다               ← 반대 방향 금지
> 5. 주석에 옮겨 온 Swift 심볼 이름을 적는다
> ```
>
> ## 왜
>
> **창작 때문에 이 이식은 이미 30회 넘게 되돌렸습니다.** 사용자 요구는 완성된 macOS 앱의
> 1:1 복제입니다. 지어낸 것은 **반드시 틀리고**, 반드시 다시 지워야 하고, "됐다"는 보고를
> 전부 못 믿게 만듭니다.
>
> **이 문서에 적힌 "창작" 항목들이 그 증거입니다.**
> 덮개 불투명도 `0.75`, `ABI 0.48 · X64`, 캡슐 `CornerRadius 999`, 노이즈 감소 엔진,
> 필름 베이스 추정(→ **이미지가 검게 터짐**), 아이콘 56개 — 전부 지어낸 것이고 전부 틀렸습니다.

---

# negaflow Windows 감사 — 2026-08-18

**사용자 지시로 macOS 원본 코드와 Windows 코드를 직접 대조해 만든 문서입니다.**
"있음/없음"을 파일 이름으로 판정하지 않았습니다 — 개념 키워드로 **코드 본문**을 훑고,
의심스러운 것은 **파일을 열어 함수·상수 단위로 대조**했습니다.

> 이 문서 묶음은 `docs/plan/07`, `docs/plan/08` 과 `docs/progress/*` 를 **대체**합니다.
> 그 문서들에 틀린 내용이 있습니다 — [`06-false-claims.md`](06-false-claims.md) 에 목록이 있습니다.

---

## 0. 문서 지도

| 문서 | 내용 |
|---|---|
| [`01-backend-gaps.md`](01-backend-gaps.md) | 엔진 159개 파일 대조. 없는 것·얇은 것·창작·문제 |
| [`02-frontend-gaps.md`](02-frontend-gaps.md) | 3뷰 + 인스펙터. 없는 것·백엔드 미연결·창작 |
| [`03-feature-status.md`](03-feature-status.md) | 기능 단위 미구현·가짜·창작 |
| [`04-gpu-plan.md`](04-gpu-plan.md) | **GPU 이식 계획** — GrainMend·보정·현상·프리뷰·인화 전부 |
| [`05-god-objects.md`](05-god-objects.md) | 500줄 초과 전체(실측) |
| [`06-false-claims.md`](06-false-claims.md) | **기존 문서의 틀린 서술** |
| [`07-user-reported.md`](07-user-reported.md) | **사용자 실사용 보고 전체** — 크래시·메뉴막대·창작 판정 |
| [`08-icons-and-chrome.md`](08-icons-and-chrome.md) | 아이콘 117 vs 56, 바·캡슐 배치 |
| [`09-shortcuts-and-settings.md`](09-shortcuts-and-settings.md) | **단축키 74 vs 55** · 설정 8탭 전체 내용 대조 |
| [`10-cache-and-optimization.md`](10-cache-and-optimization.md) | **메모리 캐시·FIFO·축출 상수** · 개발자 모드 · 캔버스 배경 우클릭 |

---

## 1. 규모 (실측)

| | macOS | Windows |
|---|---:|---:|
| 소스 파일 | 749 Swift | 292 C++(.cpp/.h) + 416 C#/XAML |
| 엔진 | `Chromabase/` 159파일 | `src/Native/` |
| 앱 | `negaflowApp/` 529파일 | `src/Shell/` · `src/Shell.Core/` |
| 스캐너 | `ScannerKit/` 50파일 | 별도 저장소 |

기능별 줄 수:

| 영역 | macOS | Windows | 비 |
|---|---:|---:|---:|
| Library | 14,876 | 5,478 | **37%** |
| Develop | 8,333 | 12,452 | 149% |
| Print | 6,037 | 2,671 | **44%** |
| Canvas | 2,654 | (Develop 에 포함) | — |
| Defects | 6,517 | 11,622(네이티브 포함) | 178% |
| Export | 7,034 | 2,703 | **38%** |
| Scanning | 4,446 | 별도 저장소 | — |

**Library·Print·Export 가 macOS 의 절반도 안 됩니다.**

---

## 2. 이번 감사의 가장 큰 발견 셋

### 2.1 GPU 코드가 **한 줄도** 없습니다

Windows 전 트리를 19개 키워드로 훑은 결과입니다.

| 키워드 | 히트 파일 수 |
|---|---:|
| `d3d11` · `D3D11` · `Direct3D` · `ID3D11Device` | **0** |
| `ComputeShader` · `compute_shader` · `.hlsl` | **0** |
| `DirectML` · `DirectCompute` · `CUDA` · `OpenCL` · `Vulkan` | **0** |
| `ID2D1` · `Direct2D` · `DXGI` · `Win2D` · `CanvasDevice` | **0** |

`.hlsl`/`.cso`/`.fx` 셰이더 파일도 **0개**입니다.

같은 조사를 macOS 에 하면:

| 키워드 | 히트 파일 수 |
|---|---:|
| `CIImage` | **83** |
| `CIContext` | 27 |
| `CIFilter` | 13 |
| `MTLCommandQueue` | 1 (`DevelopFrameRenderer`) |

**macOS 는 이미지 파이프라인 전체가 CoreImage → Metal GPU 입니다. Windows 는 전부 스칼라
CPU C++ 입니다.** 사용자가 겪는 "뭘 해도 수 초"의 절반이 여기서 옵니다.
계획은 [`04-gpu-plan.md`](04-gpu-plan.md).

### 2.2 프리뷰가 슬라이더 한 칸마다 원본 TIFF 를 **다시 디코드**합니다

`src/Native/pipeline/develop_export.cpp:101` `run_develop` 은 호출마다
`observe_source_before` → `decode_source` 를 지나갑니다.
`src/Native/pipeline/export/stages/decode.cpp` 에 `cache`/`preloaded`/`reuse` 는 **히트 0** 입니다.

macOS 는 정반대입니다:

- `DevelopFrameRenderer.swift:11-31` — 인터랙티브 프록시(표시 크기 적응, 256 양자화,
  1024~3600)와 정착 프록시(3600) **두 단계**
- `AppModel+DevelopRendering.swift:355-390` — `cachedInteractivePreviewRaw` /
  `cachedSettledPreviewRaw` 두 슬롯에 **디코드 결과를 캐시**
- `DevelopFrameRenderer+Input.swift:51-52` — 주석 원문:
  *"요청 치수 캐시가 없어도 정착(풀) raw 프록시가 있으면 GPU 다운스케일로 파생한다.
  수십 MP 원본을 디스크에서 재디코딩(수백 ms)하는 대신 한 번의 Lanczos 축소로 끝난다."*
- `AppModel+DevelopRendering.swift:334` — 정착 대기창 **0.14초**

즉 macOS 는 슬라이더를 끄는 동안 **디코드를 0회** 합니다. Windows 는 매번 5088×3401
16bit TIFF 를 다시 읽습니다(실측 2,695 ms).

### 2.3 `run_develop` 가 프리뷰·검출·내보내기 **한 경로**입니다

`develop_export.cpp:101` 의 `run_develop(request, preview, control, detect)` 하나에
프리뷰(`PreviewTarget`), 검출(`DetectTarget`), 내보내기가 모두 들어갑니다. 그래서 프리뷰
한 장에도 내보내기와 같은 준비 비용(관찰·해시·디코드)이 붙습니다.

---

## 3. 판정 요약

| 분류 | 개수 | 상세 |
|---|---:|---|
| 엔진 — 완전히 없음 | **28개 개념** | [`01`](01-backend-gaps.md) 1절 |
| 엔진 — 있으나 macOS 의 절반 이하 | **6개 서브시스템** | [`01`](01-backend-gaps.md) 2절 |
| 프론트 — 없음 | **11개 표면** | [`02`](02-frontend-gaps.md) |
| 프론트 — 백엔드 미연결 | **6개** | [`02`](02-frontend-gaps.md) 3절 |
| 창작(macOS 에 없음) | **4개** | [`03`](03-feature-status.md) 4절 |
| GPU | **전부 없음** | [`04`](04-gpu-plan.md) |
| God object(500줄 초과) | **28개**(src) + 7개(tests) | [`05`](05-god-objects.md) |
| 기존 문서의 틀린 서술 | **6건** | [`06`](06-false-claims.md) |

---

## 4. 이 감사가 검증한 방법

```bash
# 개념 키워드로 코드 본문 훑기 (파일 이름이 아니라)
grep -ril -- "<keyword>" src --include=*.cpp --include=*.h --include=*.cs --include=*.xaml

# 히트 0 = 한 글자도 없음 → "없음" 확정
# 히트 있음 → 파일을 열어 함수·상수 단위로 대조 → "얇음/다름/맞음" 판정
```

**히트가 있다고 "있음"으로 적지 않았습니다.** 예: `MonotoneCubic` 은 히트 0 이지만
그 알고리즘(Fritsch–Carlson PCHIP)은 `point_curve.cpp:158-186` 에 **정확히 이식돼
있습니다** — 이름만 없습니다. 기존 문서가 이것을 "가장 넓게 퍼지는 결손"으로 적은 것은
틀렸습니다([`06`](06-false-claims.md) 1절).
