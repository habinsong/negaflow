> # ☠️ 하드코딩 · 가짜 구현 · 창작 · 병신 백엔드 · 병신 프론트엔드 = 죽음 ☠️
>
> **🔬 추측·가설 금지.** 재현하고, 계측해서 원인을 **확정**한 뒤에 고칩니다.
> 원인을 못 잡았으면 **"못 잡았다" 고 적으십시오.**
>
> **백엔드**: macOS Swift 파일을 **먼저 열고** 코드를 1:1 로 그대로 옮깁니다.
> 상수 하나, 임계 하나, 게이트 순서 하나도 지어내지 마십시오.
>
> **저장소**: 본체 `C:\Users\habin\negaflow\`(Apache 2.0) · 스캐너 `C:\Users\habin\negaflow-scanner-sane\`(GPL).
> **두 저장소의 `negaflow-mac\` 은 절대 고치지 마십시오.**
>
> 규칙 [`00-index.md`](00-index.md) · 무엇을 옮기나 [`04`](04-gpu-plan.md) ·
> 어떻게 빠르게 [`13`](13-performance-playbook.md) · 틀린 서술 [`06`](06-false-claims.md)

---

# 15 — GPU 인수인계 (2026-08-19)

**이 문서만 읽고도 이어서 할 수 있게** 쓴 것입니다. 무엇을 했고, 무엇이 남았고,
**어떤 실수를 하지 말아야 하는지**를 순서대로 답니다.

---

## 0. 30초 요약

| 경로 | 처음 | 지금 | |
|---|---:|---:|---:|
| 필름 스캔 프리뷰 | 911.35 ms(2026-08-18 기준선) | **584.71 ms** | |
| 디지털 필름 룩 | 37,016.98 ms | **641.93 ms** | **−98.3%** |
| **노리츠 타겟** | **60,536.19 ms** | **1,287.55 ms** | **−97.9%** |

이번 세션에서 이식·배선한 것: 밀도 그레인 · 헐레이션(배선만 빠져 있었음) ·
스톡 색 프리셋 · 33³ 필름 색 큐브 · 아큐턴스 · **필름 룩 사슬 오케스트레이터** ·
실측 `CIVibrance` 33³ 표(흐린 장면 vibrance + 컬러 모델) · **스캐너 타겟 프로파일
그레이드**. 그리고 **전송 경로**(업로드 45→8 ms, 다운로드 99→55 ms)와
**작업 텍스처 풀**.

---

## 1. ☠️ 다음 사람이 반드시 지킬 규칙 일곱

이번 세션에서 **실제로 틀렸던 것**에서 나온 규칙만 적습니다.

### 규칙 1 — 커널 본문을 읽는 것으로 끝내지 마십시오. **호출부를 끝까지 따라가십시오**

`digitalFilmColor`·`digitalSceneReconstruct`·`digitalFilmDensity`·`digitalInterImage`·
`digitalPrintPaper`·`digitalReversalTransmit` **여섯은 macOS 에서 죽은 코드**입니다.
정의는 있는데 살아 있는 진입점에 닿지 않습니다. 04·14 문서가 이 여섯을 "이식 대상"
으로 적어 두었고, 그중 하나를 두고 *"Windows 가 다른 알고리즘이다"* 라고 판정까지
했습니다 — **죽은 커널과 산 커널을 견준 것**이었습니다([`06`](06-false-claims.md) 11절).

```
grep -rn --include=*.swift '"커널이름"' negaflow-mac/     # 커널을 부르는 함수를 찾고
grep -rn --include=*.swift 'ThatFunction'   negaflow-mac/  # 그 함수를 부르는 곳을 다시 찾고
# ... 살아 있는 진입점(앱 화면·파이프라인)에 닿을 때까지 반복
```

닿지 않으면 **옮기지 마십시오.** 옮기면 macOS 에 없는 효과를 만듭니다.
지금까지 확인된 "옮기면 안 되는 것" 은 **10개**입니다(위 6개 + `scannerLowSatChroma`·
`scannerMidtoneChroma`·`gamutSoftClip`·`highlightDesaturate`).

### 규칙 2 — 이식 여부를 **커널 이름으로 grep 하지 마십시오**

macOS 는 camelCase, Windows 는 snake_case 입니다. `noritsuTexture` 로 검색해
"Windows 에 없다" 고 적었지만 **`apply_noritsu_texture` 로 이미 있었습니다**
([`06`](06-false-claims.md) 12절). 개념어(`noritsu`·`halation`·`grain`)로 찾고,
**파일을 열어서** 판정하십시오.

### 규칙 3 — **0.00 ms 를 보면 "그 단계가 돌았는가" 부터 물으십시오**

`target_grade` 가 계속 `0.00 ms` 로 찍혔습니다. 비용이 없는 것이 아니라
**계측 CLI 의 기본값이 그 단계를 건너뛰고 있었습니다.** 켜고 재니 **58,995 ms,
전체의 97.5%** 였습니다 — 엔진에서 가장 비싼 단계를 그 0.00 때문에 GPU 후보에
한 번도 안 올렸습니다([`06`](06-false-claims.md) 14절).

지금 `--develop-timing` 은 이런 켜기 스위치를 갖고 있습니다:

```
negaflow-cli --develop-timing <원본> [dmin r g b] [xN] [nocurve] [filmlook]
                                     [noritsu|sp3000|f135|hr]
```

**단계 표에서 0.00 인 줄이 보이면 그 단계를 켜는 스위치를 먼저 찾으십시오.**

### 규칙 4 — 커널보다 **살림**을 먼저 의심하십시오

`--gpu-transfer-bench` 로 재 보니 24MP 반전 커널의 **디스패치가 0.01 ms**,
같은 이미지의 **왕복이 145 ms** 였습니다. 그 145 ms 는 셋이 겹친 것이었고
셋 다 커널이 아니었습니다:

1. 다운로드마다 264 MB 스테이징 텍스처를 **만들고 지웠습니다**.
2. 회수 복사가 **한 스레드 `memcpy`** 였습니다.
3. 업로드가 `UpdateSubresource`(드라이버가 한 스레드로 복사)였습니다.

고친 뒤 **63.5 ms · 8.1 GB/s**. 그리고 진입점 여덟이 **작업 텍스처를 호출마다
만들고 있었습니다** — `GpuImagePool` 하나로 묶었습니다.

> **새 커널을 붙이기 전에 `--gpu-transfer-bench` 를 한 번 돌리십시오.**
> 커널이 0.01 ms 인데 왕복이 63 ms 라는 사실이 설계를 정합니다.

### 규칙 5 — 재료마다 올렸다 내리면 **집니다**

필름 룩 재료 다섯을 각자 GPU 로 돌렸을 때 `film_look` 이 **1,926 ms** 였고,
한 번 올려 한 번 내리는 오케스트레이터로 묶으니 **370 ms** 였습니다.
24MP 에서 왕복 다섯 번은 277 MB × 10 입니다.

**사슬이 두 단계 이상이면 오케스트레이터를 먼저 생각하십시오.**
본보기는 `gpu/gpu_film_look_stage.cpp` 입니다 — 게이트는 CPU 가 `DigitalFilmLookPlan`
에 담아 넘기고 GPU 는 **순서대로 돌리기만** 합니다.

### 규칙 6 — 병렬화는 **지문으로 증명**하십시오

`target_grade` 를 행 블록으로 쪼갠 뒤:

```powershell
# ① 지금 빌드의 지문
negaflow-cli --develop-timing <원본> noritsu     # pixel_fingerprint 를 읽는다
# ② core/include/negaflow/core/parallel_rows.h 의
#    minimum_parallel_row_work_units 를 1ULL << 62U 로 올려 다시 빌드 → 전부 인라인
# ③ 같은 명령으로 지문을 다시 읽어 ①과 비교
```

이번에는 둘 다 `cfe1f1b11f1cc9a3` 였습니다(직렬 58.9s / 병렬 9.6s).
**"타일이 겹치지 않는다" 는 이유이지 증거가 아닙니다.**

☠️ 그리고 `work_units` 에 **출력 행 수를 넘기지 마십시오.** 문턱(1M)을 못 넘으면
병렬화가 **경고도 없이 꺼지고**, 그 상태를 재면서 "병렬화해도 안 빨라진다" 는
거짓 결론을 냅니다([`13`](13-performance-playbook.md) 21절).
**실제로 읽고 쓰는 양**(화소 수 × 화소당 무게, 또는 바이트 수)을 넘기십시오.

### 규칙 7 — CPU 의 **조기 반환과 하드 게이트**를 그대로 옮기십시오

CPU 커널은 "변화 없음" 이면 커널을 안 돌리고 **원본을 복사**합니다. GPU 가 그 자리에서
커널을 돌리면 반올림이 붙습니다(`colorMixerHSL` 이 delta 0.1 로 깨졌던 함정).

그리고 **하드 게이트가 있는 커널은 오차의 성격이 다릅니다.** 노리츠 장치 질감의
`low < 0 || high > 1` 이 그렇습니다 — 경계에 앉은 화소는 1ulp 차이로 결과가 통째로
갈리고, 그때 최대 오차는 **누적 오차가 아니라 효과 자체의 크기**입니다.
그런 커널의 시험은 **최대 오차 + 이탈 화소 비율**을 같이 걸어야 계약이 됩니다
(`tests/Native.UnitTests/gpu_scanner_target_grade_tests.cpp` 가 본보기).

---

## 2. 지금 GPU 가 도는 자리 (전부 `ApproximateAcceleratorScope` 안 = 프리뷰·검출)

| 무엇 | 진입점 | 실측 오차 |
|---|---|---:|
| 톤 7단계 | `stages/look.cpp` → `GpuToneStage` | 6.0e-07 ~ 1.4e-06 |
| `film_scan_denoise` 사슬 | `stages/finish.cpp` | 2.1e-05 ~ 6.2e-05 |
| 네거티브 반전 | `manual_negative_developer.cpp` | 1.8e-07 |
| 디지털 필름 룩 **사슬 전체** | `working_film_look.cpp` → `GpuFilmLookStage` | 1.13e-06 |
| ↳ 헐레이션 · 색 큐브 · 아큐턴스 · 색 프리셋 · 그레인 | 각자 진입점도 남아 있음(흑백 룩이 씀) | 4.5e-06 이하 |
| 흐린 장면 vibrance · 컬러 모델 | `muted_scene_vibrance.cpp` · `color_model.cpp` | **WARP 0**, NVIDIA 1.2e-07 |
| 스캐너 타겟 그레이드 | `scanner_target_grade.cpp` | 1e-4 (노리츠 합성은 게이트 뒤집힘 5e-3) |
| NORITSU 장치 질감 | `apply_noritsu_texture` → `GpuNoritsuTexture` | NVIDIA **7.15e-07**, WARP **5.96e-07**. 게이트 화소는 원본과 비트 일치 |
| 형태학(검출) | `grain_mend_morphology.cpp` + RGB 오케스트레이터 | **0**(비트 일치). **기본 켬.** 자동 검출 18.1s → **5.3s** |
| TextureStage `filmGrain` | `apply_grain` → `GpuTextureGrain` | NVIDIA **5.96e-08**, WARP **0**. **기본 끔** — 프리뷰 texture 단계가 더 느림(아래 3.4) |
| 채널 클리핑 오버레이 | `apply_channel_clipping_overlay` + 프리뷰 합성 | **0**(비트 일치). 현상 화소는 안 바꿈 |
| 흑백 디지털 룩 **사슬** | `apply_digital_bw_film_look` → `GpuFilmLookStage::apply_bw` | NVIDIA **3.28e-07**. **기본 켬.** |
| `CIAreaAverage` 면적 평균 | `area_average` → `GpuAreaAverage` | NVIDIA **2.98e-08**. **기본 끔** — 업로드가 리덕션보다 큼(아래 3.5) |

계측기: `--develop-timing`(단계 표 + 프리뷰 지문) · `--gpu-transfer-bench`(전송) ·
`NEGA_TIMING=1`(어디서든 표 출력) · `NEGA_GPU=0`(GPU 끄기) ·
`NEGA_GPU_MORPHOLOGY=1`(형태학 켜기).

---

## 3. 남은 일 — 우선순위 순서

### 3.1 노리츠 장치 질감 GPU — **2026-08-19 붙임**

`GpuNoritsuTexture` + `shaders/noritsu_texture.hlsl`. 가중치·세기·플로어·루마 게이트는
`scanner_target_texture_setup()` 한 곳만 씁니다. 게이트 순서·hue 공통 축소는
CPU/`noritsuTexture` 와 같습니다.

**동치** (`native.gpu_noritsu_texture`, 97×53, 게이트 띠 포함):

| 경로 | 최대 오차 | >1e-4 화소 | 게이트 화소 |
|---|---:|---:|---|
| NVIDIA 제품 경로 | **7.15e-07** | 0 / 5,141 | 586개, 원본과 비트 일치 |
| WARP | **5.96e-07** | 0 / 5,141 | 〃 |

GPU 가 안 돌면 시험이 실패합니다(`apply_noritsu_texture` 가 `true` 여야 함).
`native.gpu_scanner_target_grade` · `native.scanner_target_grade` 도 통과.

**실측** (5088×3401, RTX 4060 Ti, `--develop-timing … x3 noritsu`):

| | 붙이기 전 | 지금 |
|---|---:|---:|
| `target_grade` | **887.44 ms** | **231.33 ms** |
| 전체 | **2,040.37 ms** | **1,287.55 ms** |

프리뷰 지문은 `198bfb1b29646af7` → `6ebfe937620bc6a` 로 바뀌었습니다.
질감이 프리뷰에서 GPU(float 누적)로 바뀌었기 때문입니다. 내보내기·골든은
`ApproximateAcceleratorScope` 밖이라 **CPU 그대로**입니다.
`NEGA_GPU=0` 지문은 `f4e15a5eff17d2a6` 입니다. 붙이기 전 CPU 전용 지문은
이 세션에서 **안 쟀습니다** — GPU 켠 상태만 기준선이었습니다.

### 3.2 검출 형태학 — **2026-08-19 재측정 후 기본 켬 + RGB 오케스트레이터**

사용자 맥 실측 목표(품질 타협 없음): **자동 < 5~10초(그보다 빠르게)**,
가이드·브러시·복제·IR **1초 미만**. 해상도를 깎거나 후보를 줄여 시간을
맞추지 않습니다. 자동 전체 프레임은 macOS `detectComponents` 와 같이
**다운스케일하지 않습니다**(1800 으로 줄이면 3~8px 먼지가 사라짐).

**재측정** (5088×3401, RTX 4060 Ti, 3회, 결과 성분 610 · 채택 9,331 고정):

| 경로 | 벽시계 중앙값 |
|---|---:|
| CPU (`NEGA_GPU=0`) | **18,052 ms** |
| GPU 형태학, 호출마다 왕복(`NEGA_GPU_MORPHOLOGY=1`, 옛 이음매) | **15,383 ms** |
| 풀 재사용 + RGB 톱햇(먼지) | **7,915 ms** |
| + RGB 열기/닫기(미세입자) | **5,323 ms** (4,671 / 5,323 / 5,567) |

타일 안에서 스크래치 행을 다시 병렬화하면 워커 4개와 겹쳐 **이득 없음**(5.2~5.6 s).
되돌렸습니다. 5초를 안정적으로 밑돌리려면 스크래치 각도 커널을 GPU 로 옮기는 쪽이 다음입니다.

제품 경로 동치: `native.gpu_morphology_product` — GPU 가 안 돌면 실패,
열기·닫기·톱햇·RGB 톱햇·RGB 열기 **비트 단위 일치**.

기본은 켭니다. 끄려면 `NEGA_GPU_MORPHOLOGY=0`.

남은 자동 병목은 **스크래치 각도**(벽시계에 ~4.5~5.0 s 기여).
5초를 안정적으로 밑돌려면 그다음이 여기입니다. 값을 바꾸지 말고 GPU 로 옮기십시오.

### 3.3 `ditherAdd` · `channelClippingOverlay` — **2026-08-19 호출부 확정**

**`ditherAdd` — CPU 가 이미 제품 경로에 있습니다. GPU 커널은 안 붙였습니다.**

살아 있는 호출부:
- macOS `OutputDither.apply` → `ExportRenderedImage` · `DevelopFrameRenderer+Developed` (8bit 직전, sRGB 인코딩 뒤 ±0.5/255)
- Windows 내보내기 8bit: `output/working_to_srgb16.cpp` `quantize_component_8`
- Windows 프리뷰 8bit: `preview.cpp` + `display_dither_offset`

둘 다 sRGB 도메인에서 한 스텝 안의 좌표 해시 잡음입니다. 프리뷰 `output` 단계(3600 상자 평균+인코딩+디더)는 GPU 켠 프리뷰에서 **120.86 ms**, CPU 전용에서 **116.64 ms** — 디더만의 비용이 아니라 축소·인코딩이 대부분입니다. 별도 GPU 패스를 넣으면 왕복이 이 해시 한 줄보다 큽니다. 16bit 내보내기는 macOS 와 같이 디더하지 않습니다.

**`channelClippingOverlay` — CPU 분류 + 설정 + 프리뷰 합성 + GPU 동치.**

- macOS: 설정 `clippingOverlayEnabled`, 커널 경계 `<=0` / `>=1`, opacity 0.62, 색 (0.055,0.24,0.82)/(0.90,0.07,0.055)/(0.64,0.10,0.70), 프리뷰 전용
- Windows 작업 이미지는 프리멀티가 아니라 `rgb/a` 를 **빼었습니다**
- 설정 토글을 켜고 `ShellPreferences.ClippingOverlayEnabled` 로 남깁니다
- `write_preview` 가 상자 평균 때 같은 분류를 얹습니다. 내보내기 요청에는 필드가 없습니다
- `native.gpu_channel_clipping_overlay`: GPU 가 안 돌면 실패, CPU 와 **비트 일치**

앱 설치본에서 토글을 눌러 화면을 확인하지는 **아직** 않았습니다.

### 3.4 `filmGrain`(TextureStage) — **2026-08-19 GPU 붙임, 기본 끔**

규칙 1: 살아 있는 호출부는 `ColorModel.apply` 가 아니라 **`TextureStage.apply`**
(`ColorModel.swift:106-114`, `params.grain > 1e-3`, `amount = grain * 0.055`).
Windows CPU 는 이미 `texture_stage_effects.cpp` `apply_grain` 입니다. `color_model.cpp` 에
없는 것은 맞지만, **빠진 기능이 아니었습니다.**

**동치** (`native.gpu_texture_grain`, 97×53, grain 0.40):

| 경로 | 최대 오차 |
|---|---:|
| NVIDIA 제품 경로 | **5.96e-08** |
| WARP | **0** |

GPU 가 안 돌면 시험이 실패합니다. 제품 경로 시험은 `NEGA_GPU_TEXTURE_GRAIN=1` 로 표를 엽니다.

**실측** (5088×3401, grain 0.40, 프리뷰 3600, x2 마지막 회차):

| | CPU (`NEGA_GPU=0`) | GPU texture 켬 |
|---|---:|---:|
| `texture` 단계 | **26.84 ms** | **69.52 ms** |
| 프리뷰 전체 | 969.55 ms | 662.89 ms |

전체 벽시계가 줄어든 것은 develop/tone GPU 덕분입니다. **texture 단계만 보면 GPU 가 졌습니다**
(왕복 > 커널). 그래서 기본은 끕니다. `NEGA_GPU_TEXTURE_GRAIN=1` 로만 켭니다.
사슬 안에 이미 올라가 있을 때만 이득이 날 수 있습니다 — 그때 다시 재십시오.

### 3.5 `CIAreaAverage` 대응 병렬 리덕션 — **2026-08-19 GPU 붙임, 기본 끔**

살아 있는 macOS 호출부는 `FilmBaseEstimator.averageRGB`(스트립 폴백)뿐입니다.
Windows `strip_fallback_base` 는 격자+제외 마스크를 직접 평균하므로 **이 함수로 바꾸지 않았습니다.**
AutoLevels 주석이 말하듯 히스토그램을 면적평균으로 대체할 수 없습니다.

원시연산 `area_average` + `shaders/area_average.hlsl`. `cs_5_0` `groupshared` 트리만 씁니다.
Wave 내장은 쓰지 않습니다. CPU 는 행 우선 `double`, GPU 는 float 트리 — 허용 오차 **1e-5**.

**동치** (`native.gpu_area_average`, 97×53 전체 + ROI 40×20):

| 경로 | 최대 오차 | 화소 수 |
|---|---:|---:|
| NVIDIA 직접 + 제품 경로 | **2.98e-08** | 5,141 / 800 |
| GPU 가 안 돌면 시험 실패 | | |

**실측** (5088×3401 전체 17,304,288 px, RTX 4060 Ti, `--develop-timing … x2 areaavg`):

| | CPU (`NEGA_GPU=0`) | GPU 허용 |
|---|---:|---:|
| `area_average` | **25.109 ms** | **33.397 ms** |
| 평균 RGB | 0.130627, 0.0616215, 0.0293909 | 같은 자릿수 |

업로드(약 264 MB)가 리덕션을 이깁니다. 규칙 4. 기본은 끕니다.
`NEGA_GPU_AREA_AVERAGE=1` 로만 켭니다. 이미 GPU 에 올라가 있는 사슬 안에서만 다시 재십시오.

### 3.6 `GpuMipHalve` 배선 — **2026-08-19 배선, 기본 끔**

`downsample_for_statistics` 한 곳이 세 호출부를 모두 탑니다. `GenerateMips` 는
필터가 규정되지 않고 미지원 포맷은 조용히 실패해서 **안 씁니다.**
이미 있는 `GpuMipHalve`(2x2 평균, 홀수 변 재사용)만 쓰고 마지막 이중선형은 CPU `double`.

**동치** (`native.gpu_mip_halve_product`): GPU 가 안 돌면 실패.
97×53→20×11, 61×37→12×8 제품 경로 **비트 일치**.
프리뷰 지문 `651295e35c738fca` 유지.

**실측** (5088×3401, RTX 4060 Ti, `--develop-timing … x2` 마지막 회차):

| | 배선 전 GPU | 배선 후 GPU |
|---|---:|---:|
| `develop` | 212.91 ms | 205.10 ms |
| `tone_adjust` | 177.28 ms | 204.12 ms |
| 전체 | **617.69 ms** | **629.15 ms** |
| 벽시계 | 625.74 ms | 637.30 ms |

전체·벽시계가 줄지 않았습니다. 규칙 4. 기본은 끕니다.
`NEGA_GPU_MIP_HALVE=1` 로만 켭니다. x6 한 번은 마지막 회차 `output` 486 ms 로
흔들려 대표값으로 안 씁니다.

### 3.7 흑백 디지털 룩 사슬 — **2026-08-19 오케스트레이터 붙임, 기본 켬**

순서(macOS/`apply_digital_bw_film_look` 와 같음): 헐레이션 → 유제 응답 → 아큐턴스 → 밀도 그레인.
게이트는 CPU 가 `DigitalBwFilmLookPlan` 에 담고, GPU 는 `GpuFilmLookStage::apply_bw` 가
한 번 올려 한 번 내립니다. `GenerateMips` 와 무관합니다.

**동치** (`native.gpu_bw_film_look`, 64×48, Tri-X 0.80):

| 경로 | 최대 오차 |
|---|---:|
| NVIDIA 직접 + 제품 경로 | **3.28e-07** |

GPU 가 안 돌면 시험이 실패합니다.

**실측** (5088×3401, RTX 4060 Ti, `--develop-timing … x2 bwlook` 마지막 회차):

| | CPU (`NEGA_GPU=0`) | GPU |
|---|---:|---:|
| `film_look` | **27,343.04 ms** | **215.11 ms** |
| 전체 | **29,412.69 ms** | **610.80 ms** |

프리뷰 지문 `6c6611b1deb86cb7` → `49aed1144126c81c` (근사 사슬). 내보내기·골든은
스코프 밖이라 CPU 그대로입니다.

### 3.8 남은 `double` 두 곳 — **재기 전에 손대지 마십시오**

| 어디 | 무엇 |
|---|---|
| `grain_mend_morphology.cpp:240` `box_mean` | 적분영상을 `double` 로 누적합니다. **CPU 를 float 로 내려도 골든이 안 바뀌는지 먼저 재십시오** |
| 밴드 측정의 `double` 면적평균 | D3D11 의 double 은 선택 기능이라 옮길 수 없습니다([`04`](04-gpu-plan.md) 0.4절) |

---

## 4. ☠️ 확인 못 한 것 (정직하게)

1. **내장 GPU 실기.** 이 기계에 Intel/AMD 내장이 없습니다. 범용성은 **코드 구조로만**
   보장돼 있습니다 — 벤더 ID 로 거르는 코드 0줄, FL 11_0 공통 하한, WARP 폴백.
   전송 실측(8.1 GB/s)도 외장 기준이라 **내장에는 그대로 적용되지 않습니다**
   (시스템 메모리를 공유합니다).
2. **`GpuImagePool` 여섯 장의 메모리.** 24MP 에서 1.6 GB 입니다. 못 잡으면
   처리하지 않았다고 돌려주고 CPU 로 가지만, **내장 GPU 에서 실제로 어떻게 되는지는
   확인 못 했습니다.**
3. **macOS 와의 알고리즘 차이 하나.** `ScannerTargetGrade` 를 macOS 는 64³ 큐브로,
   Windows 는 화소마다 풉니다(66배). 이번 작업은 Windows 의 셈을 옮긴 것이고,
   **큐브로 바꾸는 것은 값이 달라지는 별건**입니다 — 결정 전에 골든 영향을 재십시오.

---

## 5. 작업 절차 (매번 이대로)

```powershell
# 1) 기준선 — 고치기 전에 잰다
$src = "C:\Users\habin\OneDrive\바탕 화면\negaflow_test\OpticFilm8100_frame_1.tiff"
$env:NEGA_TIMING = "1"
negaflow-cli --develop-timing $src x3 [noritsu|filmlook]

# 2) 고친다. CPU 판을 먼저 읽고, 게이트·조기 반환·상수를 그대로 옮긴다.

# 3) 동치 시험을 **신설**한다 — 진짜 CPU 함수를 부르고 겨룬다.
#    참조를 옮겨 적으면 시험이 아무것도 증명하지 않는다.
cmake --build --preset x64-release --target <새 시험>
.\out\build\native\x64-release\Release\<새 시험>.exe

# 4) 전체 시험
ctest --preset x64-release          # 지금 90/90

# 5) 다시 잰다. 커밋 메시지에 **전후 숫자와 실측 오차**를 적는다.
```

**GPU 를 안 쓰고 재려면** `NEGA_GPU=0`. **켜고 끄며 재는 것**이 유일한 증거입니다.
