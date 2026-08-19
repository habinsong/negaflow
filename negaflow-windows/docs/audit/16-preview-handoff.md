> # ☠️ 하드코딩 · 가짜 구현 · 창작 · 병신 백엔드 · 병신 프론트엔드 = 죽음 ☠️
>
> 프리뷰 GPU 왕복은 **커널 이식이 아닙니다.** 죽은 커널 10개를 다시 만들지 마십시오.
> 해상도를 깎아 속도를 사지 마십시오(`07` H.9 되돌림).

# 16 — 프리뷰 인수인계 (2026-08-19)

`00-index` 가 이 파일을 “가장 먼저 읽으라”고 가리킵니다. `07` H 가 원인과 숫자를 가집니다.

## 0. 30초

| | 직전 H.12 ① | H.12 ① 닫힌 뒤 | **지금 H.12 ②** |
|---|---:|---:|---:|
| 마지막 회수 | 단계마다 float | float 1회 | **BGRA8 1회** |
| `develop` | 113 | 55.5 | **54.5** |
| `tone_adjust` | 75 | 19.3 | **0.02** |
| `output` | 81 | 64–78 | **7.01** |
| 단계 합 | 298 | 154–168 | **65.0** |
| 벽시계 두 번째 | 298 | 182–196 | **92.8** |
| CLI 작업 집합 봉우리 | — | 508 MB | **557 MB** |

원본: `OpticFilm8100_frame_1.tiff` 5088×3401, 상자 3600, RTX 4060 Ti, `NEGA_TIMING=1`,
`negaflow-cli --develop-timing … x2 nocurve`.
지문 `8e71bb980e3d3e25` (두 번째=첫 번째). 앞 판 CPU 8비트 지문
`f6f4ab3dbcd1f25` 와 다름 — UAV UNORM 반올림 vs CPU `*255+0.5`. 단위시험 최대
**1 코드**.

## 1. 무엇을 했나

macOS `renderDisplayCGImage` 는 DisplayGamutMap → SoftProof → OutputDither 뒤
`context.createCGImage(..., format: .RGBA8)` 한 번으로 평가합니다.

Windows `write_preview` 는 상주 화상이 이미 상자 크기이고 클리핑 오버레이가 없으면
`GpuAccelerator::try_encode_preview_bgra` 로 같은 수식(`tone_safe_unit_rgb` ·
proof · `linear_to_srgb` · `display_dither_offset`)을 GPU 에서 돌려 BGRA8 만 내립니다.
상자 평균·오버레이·GPU 실패는 호스트를 내린 뒤 기존 CPU 경로입니다.

- 톤 상주는 **내리지 않음**. 핑퐁 슬롯을 적용 횟수로 잇습니다.
- `GpuResidentScope` 는 publish 까지 유지합니다. 항등 film_look / grain / finish 는
  낡은 호스트를 훑지 않습니다. 실제로 만지는 단계는 `flush_resident` 뒤 CPU.
- `record_gpu_bgra_download` — 회수 1회, 바이트는 화소×4.

시험: `native.gpu_accelerator`
`invert_then_tone_is_one_host_round_trip` (float 내리기 1, 오차 1.43e-06) +
`invert_then_tone_preview_is_one_bgra_download` (신쇄 `write_preview` →
`try_encode_preview_bgra`, 올리기 1 · 내리기 1 · `downloaded_bytes = w*h*4`,
8비트 ≤1 코드). Debug/Release 각 2회.

x64 Debug `ctest -C Debug` **101/101**. GOAL-PROMPT 기준도 native **101/101**.

## 2. 하지 말 것

- GPU 커널 3.1–3.8 다시 이식, 죽은 커널 10개
- `interactiveProxyDimension` 을 1024…3600 / 256 밖으로 접기
- 스테이징 `MOVNTDQA` (이미 기각, 더 느림)
- invert→tone 상주를 다시 짜기

## 3. 다음 한 걸음

1. H.12 ③ **재서 기각.** `GpuMipHalve` 로 측정 입력을 ≤256 프록시로 줄이면
   `native.gpu_accelerator` `tone_path_runs_on_gpu` GPU/CPU 최대 오차
   **2.55e-04**(허용 1e-5), 밴드 2.48e-04. 같은 숫자 Debug 두 번.
   `GpuAreaAverage` 는 영역 평균 하나라 백분위 격자를 대체하지 못함.
   값은 바꾸지 않고 풀해상도 내리기를 유지. 새 커널은 아직 없음.
2. 앱 `run-app` x64 Release: A4 abort 재현 여부, 슬라이더 벽시계, 작업 집합
   (~1GB/렌더 주장은 **앱에서 못 쟀다**. CLI 봉우리는 557 MB).
3. 현상 메뉴: 모든 보정 초기화는 붙임. 이전/이후·결함 메뉴·A4 `run-app` 은 남음.

## 4. 확인 못 한 것

- 앱에서 슬라이더를 끄는 체감
- GPU 경로 작업 집합이 렌더마다 ~1GB 늘어나는지 (CLI 는 아님)
- A4 `0xc0000409` 가 이 패치가 들어간 `run-app` 에서 사라졌는지
- 내장 GPU / WARP 제품 경로(단위시험 WARP 왕복은 통과)
- 상자 평균이 남는 경로(상주 크기가 미리보기와 다를 때)의 GPU 축소
- 커브 켠 `tone_adjust` 중간 왕복


---

## 2026-08-20 — 이 경로에서 죽던 자리

프리뷰 상주 사슬 자체는 그대로입니다. 다만 `pipeline/develop_export.cpp` 가
`GpuResidentScope` 를 **단계 출력보다 뒤에** 선언해, 소멸 역순으로 상주 범위가 먼저 죽으며
`flush_resident()` 가 **이미 사라진 출력**에 내려썼습니다(앱 강제 종료).
선언 순서를 바꿔 고쳤습니다 — [`01`](01-backend-gaps.md) 9.1.

**여기에 단계를 더 붙일 사람에게:** 상주 범위는 그것이 채우는 버퍼보다 **먼저** 선언합니다.

숫자(단계 합 65.0 ms 등)는 다시 재지 않았습니다. 이 고침은 수명 순서만 바꿉니다.
앱 슬라이더 벽시계는 **여전히 못 쟀습니다**.
