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
| **노리츠 타겟** | **60,536.19 ms** | **2,037.53 ms** | **−96.6%** |

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
| 스캐너 타겟 그레이드 | `scanner_target_grade.cpp` | 1e-4 (노리츠는 2절 참고) |
| 형태학(검출) | `grain_mend_morphology.cpp` | **0**(비트 일치) — 다만 **기본 꺼짐**, 아래 3절 |

계측기: `--develop-timing`(단계 표 + 프리뷰 지문) · `--gpu-transfer-bench`(전송) ·
`NEGA_TIMING=1`(어디서든 표 출력) · `NEGA_GPU=0`(GPU 끄기) ·
`NEGA_GPU_MORPHOLOGY=1`(형태학 켜기).

---

## 3. 남은 일 — 우선순위 순서

### 3.1 노리츠 장치 질감 GPU (**바로 이어서 하기 좋음 — 절반 되어 있음**)

`apply_noritsu_texture` 는 아직 CPU 입니다. 준비는 끝나 있습니다:

- 상수가 이미 공개 한 곳에 있습니다 — `scanner_target_texture_setup()`
  (`imaging/include/negaflow/imaging/scanner_target_grade.h`).
  CPU 루프도 그것을 씁니다. **셰이더에 숫자를 다시 적지 마십시오.**
- 모양은 아큐턴스(`gpu_film_emulation_acutance.*`)와 **같습니다** —
  분리형 5탭 저역 두 패스 + 원본을 함께 읽는 언샤프.
- ☠️ 게이트 두 개를 **순서까지** 그대로 옮기십시오:
  `lo < 0 || hi > 1` → 원본 통과, `lumaO <= 1e-5` → 원본 통과.
  플로어 `max(yO*0.45, min(yO, 0.008))` 의 상수 둘도 그대로.
  마지막 `mx > 1` 공통 축소는 hue 보존입니다 — 채널별 클립으로 바꾸면 색이 틀어집니다.
- 시험은 위 규칙 7 대로 **최대 오차 + 이탈 화소 비율**을 같이 걸으십시오.

기대: `target_grade` 859 ms 중 질감 몫(CPU)이 빠지고 왕복도 하나 줄어듭니다.

### 3.2 검출 형태학 오케스트레이터

커널은 서 있고 **비트 단위로 일치**하는데 **기본에서 꺼져 있습니다** —
실측이 더 느렸기 때문입니다(CPU 9,104~9,312 ms vs GPU 11,462~12,146 ms).
원인은 커널이 아니라 **평면마다 왕복** + D3D11 자물쇠가 4중 병렬 CPU 를 직렬로 만드는 것.

☠️ **재기 전에 `NEGA_GPU_MORPHOLOGY` 를 켜지 마십시오.** 지금 켜면 느려집니다.
고치는 길은 검출 전체가 GPU 에 머무는 오케스트레이터입니다 —
`GpuFilmLookStage` 와 같은 모양으로, 평면 넷을 한 번 올리고 열기·닫기·톱햇을
연속 디스패치로 돌리고 마지막에 한 번 내립니다.
**전송이 이미 절반으로 줄었으므로(규칙 4) 다시 재는 것부터 하십시오** — 판정이
바뀌었을 수 있습니다.

### 3.3 아직 없는 기능 둘 (GPU 이전에 **기능부터**)

| 무엇 | macOS | 무엇을 만들어야 하나 |
|---|---|---|
| `ditherAdd` | `Adjustments/OutputDither.swift` → `ExportRenderedImage`·`DevelopFrameRenderer+Developed` 에서 **8bit 변환 직전** | ① 노이즈는 `digital_film_grain.cpp` 의 **좌표 해시를 재사용**(새로 만들지 마십시오) ② CPU 커널을 `output/` 에 ③ 배선은 **sRGB 인코딩 뒤, 8bit 양자화 직전** ④ 그 다음 GPU. ☠️ 선형광에서 `1/255` 를 더하면 암부에서 수십 배로 보입니다 |
| `channelClippingOverlay` | `Imaging/ChannelClippingOverlay.swift` — `AppModel+PresentationSettings.clippingOverlayEnabled` 로 켜는 **표시 옵션** | ① **UI 부터**([`11`](11-ui-verification-protocol.md) 절차로 macOS 위치 확인) ② 프리뷰 위에 얹는 오버레이 층(현상 결과를 **바꾸면 안 됩니다**) ③ 커널은 화소별이라 **마지막**. ☠️ 경계는 `<= 0.0` / `>= 1.0` 입니다 — `< 0` / `> 1` 로 바꾸면 정확히 0/1 인 화소가 경고에서 빠집니다. ☠️ 프리멀티 나눗셈은 Windows 작업 이미지가 프리멀티가 **아니면 빼야** 합니다 |

### 3.4 `filmGrain`(ColorModel 쪽)

macOS `ColorModel.swift:109`. Windows `color_model.cpp` 에는 그레인 항목이 **없습니다** —
먼저 macOS 호출부가 살아 있는지 규칙 1 대로 확인하고, 살아 있으면 **CPU 부터**입니다.

### 3.5 `CIAreaAverage` 대응 병렬 리덕션

히스토그램·자동 보정용 원시연산. `groupshared` 트리로 가십시오 —
SM 6.0 wave intrinsics 는 wave 크기가 하드웨어마다 달라 **내장/외장 범용 요구와
충돌**합니다([`04`](04-gpu-plan.md) 의 `cs_5_0` 하한).
☠️ 부동소수 덧셈은 결합법칙이 없습니다. **CPU 가 어떤 순서로 더하는지 먼저 읽고**
맞추거나, 못 맞추면 `1e-5` 동치로 선언하고 적으십시오.

### 3.6 `GpuMipHalve` 배선

비트 단위 일치까지 증명해 놓고 **아무도 안 씁니다.** 쓸 곳 셋:
`film_base_sampling.cpp` · `manual_negative_developer.cpp` · `muted_scene_vibrance.cpp`.
한 곳씩 배선 → `--develop-timing` 으로 전후 6회씩 → **이득 없으면 되돌리고 수치를 적으십시오.**

### 3.7 흑백 디지털 룩 사슬

`digital_bw_film_look.cpp` 는 아직 재료별 진입점만 씁니다(헐레이션·그레인).
컬러 쪽처럼 사슬 오케스트레이터로 묶을 수 있습니다.

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
