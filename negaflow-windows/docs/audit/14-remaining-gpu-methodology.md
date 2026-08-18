> # ☠️ 하드코딩 · 가짜 구현 · 창작 · 병신 백엔드 · 병신 프론트엔드 = 죽음 ☠️
>
> **🔬 추측·가설 금지.** 재현하고, 계측해서 원인을 **확정**한 뒤에 고칩니다.
> 원인을 못 잡았으면 **"못 잡았다" 고 적으십시오.**
>
> **백엔드**: macOS Swift 파일을 **먼저 열고** 코드를 1:1 로 그대로 옮깁니다.
> 이름이 같다고 "있음" 으로 적지 마십시오 — **함수 안을 읽고** 판정하십시오.
>
> **저장소**: 본체 `C:\Users\habin\negaflow\`(Apache 2.0) · 스캐너 `C:\Users\habin\negaflow-scanner-sane\`(GPL).
> **두 저장소의 `negaflow-mac\` 은 절대 고치지 마십시오.**
>
> 규칙 [`00-index.md`](00-index.md) · 무엇을 옮기나 [`04`](04-gpu-plan.md) · 어떻게 빠르게 [`13`](13-performance-playbook.md)

---

# 14 — 남은 GPU 작업의 방법론 (커널별 절차서)

**작성 2026-08-18.** [`04`](04-gpu-plan.md) 0.3절이 *"무엇이 남았고 왜 막혔나"* 라면,
이 문서는 **"그래서 어떻게 하나"** 입니다. 커널마다 ① macOS 원문 근거 ② Windows 현재 상태
③ 진짜 장애물 ④ 절차 ⑤ 검증 기준을 답니다.

☠️ **이 문서를 쓰면서 제 앞 판정 세 개가 틀린 것을 찾았습니다.** 0절에 먼저 적습니다.

---

## 0. ☠️ 먼저 — [`04`](04-gpu-plan.md) 0.3절의 오류 세 개

전부 **macOS 원문과 Windows 소스를 열어서** 확인했습니다. 이름과 문서만 보고 적었던 것입니다.

### 0.1 `digitalFilmColor` 은 **3D LUT 가 필요 없습니다**

04 문서는 *"**3D LUT**(`Texture3D`) 필요"* 라고 적었습니다. **틀렸습니다.**
`ChromabaseMetalKernels.swift:774` 를 열면 텍스처 샘플링이 **한 줄도 없습니다** —
행렬 3행 + 리프트 + 그림자/명부 틴트 + **hue 앵커 6개 원형 선형보간** + 채도 변조입니다.
**완전한 화소별 커널**입니다.

3D LUT 는 `ScannerTargetGrade` 의 `CIColorCube` 이고, 그것은 `boundedRelativeGrade`
쪽 이야기입니다. **두 개를 섞어서 적었습니다.**

### 0.2 `noritsuTexture` 의 "이웃 접근" 은 **이미 해결돼 있습니다**

04 문서는 *"이웃 접근"* 을 선행 조건으로 적었습니다. `:505` 를 열면 입력이
`src` 와 **`blurred`** 두 장이고, 커널 자체는 **화소별**입니다. 이웃 연산은 가우시안 저역인데
**`GpuGaussianBlur` 는 이미 있고 CPU 와 delta 0 입니다**([`04`](04-gpu-plan.md) 0.1절).

이미 이식한 `digitalHalation`(입력 4장: `src` + 블러 3장)과 **구조가 같습니다.**
`noritsuTexture` 는 막혀 있지 않습니다.

### 0.3 `digitalFilmGrainDensity` 의 "노이즈 씨앗 규칙" 은 **이미 정해져 있습니다**

04 문서는 *"macOS 와 대조해야 함"* 이라고 적었습니다.
`imaging/digital_film_grain.h:41-44` 가 이미 답을 적어 두었습니다:

> "The random field is a deterministic absolute-coordinate CPU field so retries and tiles
> cannot drift; macOS/Windows grain is therefore **statistical, not pixel-exact**, until a
> shared seed contract exists in the product recipe."

Windows CPU 는 이미 **좌표 해시 필드**를 씁니다(`digital_film_grain.cpp:25-36`) —
`x*0x9e3779b9 ^ y*0x85ebca6b ^ ch*0xc2b2ae35 ^ 0x27d4eb2f` 뒤 xorshift-multiply 3단.
**전부 uint32 정수 연산**이라 HLSL 에서 **비트 단위로 같게 낼 수 있습니다.**

즉 GPU 가 맞춰야 할 상대는 **Apple 의 `CIRandomGenerator` 가 아니라 Windows CPU 필드**입니다.
그리고 그것은 다른 커널과 똑같이 **정해진 작업**입니다.

---

## 1. 노이즈 — 웹 조사 결론: **Apple 과 화소 단위로 맞출 수 없습니다**

`filmGrain`·`digitalFilmGrainDensity`·`ditherAdd` 셋 다 `CIRandomGenerator` 출력을 받습니다.

### 조사한 것

| 무엇 | 결과 |
|---|---|
| Apple 공식 문서 | 필터의 **존재와 파라미터**만 있습니다. **알고리즘·수열 미공개** ([CIRandomGenerator](https://developer.apple.com/documentation/coreimage/cirandomgenerator) · [CI Filter Reference](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/)) |
| 역공학 공개 자료 | **없습니다.** 찾지 못했습니다 |
| GPU 노이즈 일반론 | 좌표 해시가 표준 접근입니다 — 같은 좌표 + 같은 씨앗 → 항상 같은 값 ([GPU 암호 해시 백색잡음](https://www.microsoft.com/en-us/research/wp-content/uploads/2007/10/tr-2007-141.pdf) · [셰이더 해시 노이즈](https://danilw.github.io/blog/Hash_Noise_in_GPU_Shaders/)) |

### 그래서 정한 계약 (이미 코드에 있고, 이 문서가 확정합니다)

> **그레인·디더의 macOS 대조는 "화소 일치" 가 아니라 "통계 일치" 입니다.**
> 대조 항목: **평균 0**(DC 바이어스 없음) · 진폭 분포 · 휘도 가중 곡선.
> **화소 단위 골든은 Windows CPU 필드를 기준으로 삼습니다.**

☠️ **이것은 창작이 아니라 한계의 기록입니다.** Apple 의 수열을 알 수 없으므로
"맞췄다" 고 적을 수 없고, 적으면 거짓말입니다. 대신 **Windows 안에서는 결정적**이며
CPU/GPU/타일/재시도가 전부 같은 값을 냅니다 — 그것이 검증 가능한 계약입니다.

### GPU 이식 절차 (`digitalFilmGrainDensity`)

1. `coordinate_hash` 를 HLSL `uint` 로 그대로 옮깁니다. **`uint` 연산은 정확**하므로
   CPU 와 **비트 단위로 같아야 합니다** — 안 같으면 옮겨 적은 것이 틀린 것입니다.
2. `unit_noise` 의 `>> 8` 과 `/ 0x00ffffff` 도 그대로. float 나눗셈 한 번이라 delta 0 이어야 합니다.
3. ☠️ **`scaled_noise` 의 `size > 1.01` 경로에 `double` 이 있습니다**(`:53-56`).
   제품 경로가 그 경로를 타는지 **먼저 확인하십시오.** 안 타면 문제없고,
   타면 [`13`](13-performance-playbook.md) 18절의 double 제약이 그대로 적용됩니다.
4. 밀도 도메인 응답(`apply_channel`)은 `log10`·`sqrt`·`exp`·`pow` 입니다 —
   [`04`](04-gpu-plan.md) 0.6절의 초월함수 규칙대로 **`1e-5` 동치**가 목표이지 delta 0 이 아닙니다.

**검증**: 해시 단독 시험(delta 0 요구) + 전체 사슬 동치 시험(`1e-5`) + 평균 0 통계 시험.

---

## 2. `digitalFilmColor` — 화소별, 지금 붙일 수 있습니다 (다만 **Windows 가 다른 알고리즘입니다**)

### ☠️ 먼저 확인된 발산 — 이것부터 판단이 필요합니다

| | 무엇을 하나 |
|---|---|
| **macOS** `:774` | 행렬 3행 + 채널 리프트 → 그림자/명부 틴트 → **hue 6앵커 보간 채도 변조**. `FilmEmulationProfile` 의 `mR/mG/mB`·`iieHue[6]`·`iie` 로 구동 |
| **Windows** `digital_film_color_preset.cpp` | **`apply_color_mixer` + `apply_color_grading` + `apply_primary_calibration`** 을 프리셋 값으로 순서대로 태웁니다 |

**같은 커널의 이식이 아닙니다.** Windows 는 다른 커널 3개를 조합해 비슷한 결과를 노린 것이고,
`hue` 라는 단어가 그 파일에 **한 번도 안 나옵니다**(`grep` 확인).

> ☠️ **이것은 GPU 문제가 아니라 이식 정확성 문제입니다.** GPU 로 옮기기 전에
> **어느 쪽이 맞는지 먼저 정해야 합니다.** 지금 GPU 로 옮기면 **틀린 것을 빠르게 만들 뿐**입니다.
> [`06-false-claims.md`](06-false-claims.md) 에 올릴 항목입니다.

### macOS 를 그대로 옮기기로 정한다면 — 절차

1. `FilmEmulationProfile` 의 `mR/mG/mB`·`toneR/G/B.lift`·`shadowTint`·`highlightTint`·
   `iieHue[6]`·`iie` 를 **먼저 CPU 로** 옮깁니다. 상수 하나도 지어내지 마십시오.
2. CPU 골든을 세운 뒤에 GPU.
3. ☠️ **`digitalHueBand` 의 `float anchors[6]` 은 HLSL 에서 그대로 쓰지 마십시오.**
   지역 배열 동적 인덱싱은 **indexable temp register** 로 내려가고, 레지스터 압박이
   커지면 fxc 가 `X4714`(과도한 임시 레지스터)를 냅니다 — 점유율이 떨어집니다
   ([DXC 동적 인덱싱](https://github.com/microsoft/DirectXShaderCompiler/issues/2817) ·
   [X4714](https://gamedev.net/forums/topic/623071-warning-x4714-excessive-temp-registers/)).
   앵커 6개는 이미 `float4` 두 개(`iieHueA`, `iieHueB.xy`)로 들어옵니다.
   **`[unroll]` 한 6분기 선택**이나 이미 쓰고 있는 `[i>>2][i&3]` 방식으로 푸십시오
   ([`13`](13-performance-playbook.md) 13절의 상수 버퍼 규칙과 같은 자리).
4. `digitalLinearToSRGB`/`digitalSRGBToLinear` 의 `pow` — 0.6절 규칙, `1e-5` 목표.

---

## 3. `noritsuTexture` — 막혀 있지 않습니다. `digitalHalation` 과 같은 모양입니다

### 근거

`:505`. 입력 `src` + `blurred` + `amount`. 커널 본문에 **텍스처 좌표 접근이 없습니다.**
`GpuGaussianBlur` 는 이미 있고 **CPU 와 delta 0** 입니다.

### 절차

1. Windows CPU 판이 **없습니다**(`grep noritsuTexture` → win=0). **CPU 부터**입니다.
2. `srgbEncodeLuma`/`srgbDecodeLuma` 를 Windows 의 기존 sRGB 전달함수와 **같은 것인지 확인**하십시오.
   다르면 그 자리에서 값이 갈립니다.
3. ☠️ 조기 반환 두 개를 **순서까지** 그대로 옮기십시오 —
   `lo < 0 || hi > 1` → 원본 통과, `lumaO <= 1e-5` → 원본 통과.
   **이 두 게이트가 "확장값 보존 계약" 입니다.** 빠뜨리면 측정 큐브 밖 화소가 망가집니다.
4. 플로어 `max(yO*0.45, min(yO, 0.008))` — 주석이 *"1~2 코드 픽셀이 0 으로 반올림"* 을 막는
   것이라고 명시합니다. **상수 두 개 다 그대로.**
5. 마지막 `mx > 1` 공통 축소 — hue 보존입니다. 채널별 클립으로 바꾸면 색이 틀어집니다.

**검증**: CPU 골든 → GPU 동치 `1e-5`. 가우시안이 delta 0 이므로 오차는 `pow` 에서만 나옵니다.

---

## 4. `boundedRelativeGrade` — 진짜 장애물은 `double` 하나입니다

### 근거

`:531`. `srgbEncodeLuma` 3회 + min/max + `smoothstep` 2회 + `mix`. **화소별, 입력 2장.**
Windows 대응은 `scanner_target_grade.cpp:62-64` 이고 **그 안이 전부 `double`** 입니다.

### 절차 — 순서를 지키십시오

1. **먼저 재십시오.** CPU 쪽을 `double` → `float` 로 내렸을 때 **골든이 움직이는지**.
   움직이지 않으면 GPU 이식은 다른 커널과 같아집니다.
2. 움직이면 **거기서 멈추고 적으십시오.** D3D11 의 double 은 선택 기능이고
   `DoublePrecisionFloatShaderOps` 가 TRUE 여도 **나눗셈은 보장되지 않습니다**
   ([D3D11_FEATURE_DATA_DOUBLES](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/ns-d3d11-d3d11_feature_data_doubles)).
   내장 GPU 범용성 요구와 정면으로 충돌합니다.
3. ☠️ **`domainWeight` 는 sRGB 코드 좌표에서 계산합니다**(주석이 명시). working-linear 에서
   계산하면 linear 0.01(sRGB ≈ 0.10)이 잘못 반감됩니다. 도메인 변환을 빠뜨리지 마십시오.

---

## 5. Windows 기능 자체가 없는 둘 — 무엇을 만들어야 하나

### 5.1 `ditherAdd` — 8bit 밴딩 디더

**macOS** `:596`: `(noise.rgb - 0.5) / 255` 를 **sRGB 인코딩된** 값에 더합니다. 알파는 보존.
주석이 *"LinearDodge 의 알파 합성 버그 회피"* 라고 그 이유를 답니다.

**만들 것** (순서대로):

| # | 무엇 | 어디 |
|---|---|---|
| 1 | 노이즈 필드 | 1절의 좌표 해시를 **재사용**합니다. 새로 만들지 마십시오 |
| 2 | CPU 커널 | `output/` — **sRGB 인코딩 뒤, 8bit 양자화 직전**에 들어가야 합니다 |
| 3 | 배선 | 내보내기 8bit 경로. 16bit/부동소수 출력에는 **넣지 마십시오** — 양자화가 없으면 디더는 잡음일 뿐입니다 |
| 4 | GPU | 화소별 2입력. 다른 커널과 같습니다 |

☠️ **적용 도메인을 틀리면 안 됩니다.** 선형 광에서 `1/255` 를 더하면 암부에서 수십 배로 보입니다.
macOS 가 sRGB 도메인에서 더하는 이유가 그것입니다.

### 5.2 `channelClippingOverlay` — 프리뷰 전용 클리핑 경고

**macOS** `:604`: **프리멀티플라이드 알파**를 풀고(`rgb / a`) `<= 0` / `>= 1` 을 검사해
파랑(암부)·빨강(명부)·보라(둘 다)를 **불투명도 0.62 로 프리멀티플라이해** 반환합니다.

**만들 것**:

| # | 무엇 |
|---|---|
| 1 | **UI 부터.** 이것은 사용자가 켜고 끄는 **표시 옵션**입니다. macOS 어느 메뉴/단축키에 있는지 [`11`](11-ui-verification-protocol.md) 절차로 확인한 뒤에 만드십시오 |
| 2 | 오버레이 합성 경로 — 프리뷰 위에 얹는 층. 현상 결과를 **바꾸면 안 됩니다** |
| 3 | 커널 자체는 화소별이고 가장 쉽습니다. **마지막에** 하십시오 |

☠️ **경계값 정의를 그대로 옮기십시오.** `<= 0.0` 과 `>= 1.0` 입니다 — 주석이
*"경계에 정확히 있는 채널은 정의상 클리핑"* 이라고 못박습니다. `< 0` / `> 1` 로 바꾸면
정확히 0/1 인 화소가 경고에서 빠집니다.

☠️ **프리멀티플라이드 나눗셈을 빠뜨리지 마십시오.** Windows 작업 이미지가 프리멀티가
아니라면 그 단계는 **빼야** 합니다 — 옮기기 전에 어느 쪽인지 확인하십시오.

---

## 6. CPU 판부터 없는 일곱 — **가상 현상 사슬**입니다. 하나씩 떼지 마십시오

`digitalSceneReconstruct` → `digitalFilmDensity` → `digitalInterImage` →
`digitalPrintPaper` **또는** `digitalReversalTransmit` → (`digitalHalation` **이식됨**) →
`digitalFilmColor` → `digitalFilmGrainDensity` → `digitalToDisplayGamma`/`digitalToLinearLight`.

**호출부는 `Digital/DigitalFilmDevelop.swift` 와 `Digital/DigitalSceneReconstruct.swift`** 입니다.
`isDigitalSource` 경로에서만 돕니다 — 필름 스캔은 이 물리를 이미 화소에 담고 있어서
같은 응답을 두 번 얹지 않습니다(`:632` 주석).

### 순서 — 사슬 순서 그대로

| 순 | 커널 | macOS | 어려운 점 |
|---|---|---|---|
| 1 | `digitalToDisplayGamma` · `digitalToLinearLight` | `:738`·`:742` | **없습니다.** sRGB 전달함수 왕복. 여기부터 하십시오 |
| 2 | `digitalSceneReconstruct` | `:640` | `sqrt` 한 번. 4줄 |
| 3 | `digitalFilmDensity` | `:653` | `softLimit`(`pow` 2회) × 6. **층별 감도/Dmax 가 파라미터**라 상수를 지어내면 즉시 틀립니다 |
| 4 | `digitalInterImage` | `:681` | 나눗셈 하나. `max(1-kk, 1e-3)` 하한 그대로 |
| 5 | `digitalPrintPaper` · `digitalReversalTransmit` | `:692`·`:702` | `pow(10, ·)`. 둘은 **배타 선택**입니다 |
| 6 | `digitalFilmColor` | `:774` | **2절 — 먼저 발산부터 정리** |
| 7 | `digitalFilmGrainDensity` | `:800` | **1절 — 해시부터** |

### 규칙

> **① CPU 를 먼저 만들고 골든을 세운 뒤에만 GPU 로 갑니다.**
> GPU 부터 만들면 **비교할 상대가 없습니다.** 그러면 "맞다" 를 증명할 방법이 없습니다.
>
> **② `softLimit` 은 공통 함수입니다.** 세 커널이 씁니다(`:628`). **한 번만 만드십시오** —
> 세 벌 복사하면 세 벌이 어긋납니다([`04`](04-gpu-plan.md) 0.2절의 `gpu_pointwise` 와 같은 이유).
>
> **③ 파라미터는 `FilmEmulationProfile` 에서 옵니다.** 프로파일 테이블이 Windows 에 없으면
> **그것부터**입니다. 값을 지어내면 그 순간 이 문서의 첫 줄을 어기는 것입니다.

### GPU 로 넘길 때 — 사슬이라 **한 번에 올리고 한 번에 내립니다**

☠️ 7단계를 **단계마다 업로드·다운로드하면 집니다.** GPU 형태학이 그래서 CPU 보다 느렸습니다
([`13`](13-performance-playbook.md) 15절: 9.1s CPU vs 11.5s GPU).

중간 결과는 **`D3D11_USAGE_DEFAULT` 텍스처에 남겨** 다음 디스패치의 SRV 로 바로 묶고,
**마지막에 한 번만** 스테이징으로 회수합니다
([D3D11 리소스 커밋](https://diligentgraphics.com/diligent-engine/architecture/d3d11/committing-shader-resources-to-the-gpu-pipeline/) ·
[읽기 회수](https://learn.microsoft.com/en-us/windows/win32/direct3d12/readback-data-using-heaps)).
`GpuStagingRing` 이 이미 그 회수용 더블 버퍼입니다.

---

## 7. 오케스트레이터 둘 — 커널이 아니라 **구조**가 문제입니다

### 7.1 검출 형태학 — 이미 이식했는데 **더 느립니다**

실측: CPU **9,104~9,312 ms** vs GPU **11,462~12,146 ms**, 결과는 **비트 단위 일치**.
원인은 커널이 아니라 **평면마다 왕복** + D3D11 자물쇠가 4중 병렬 CPU 를 직렬로 만드는 것.

**고치는 절차**:

1. 검출 전체가 **GPU 에 머무는** 오케스트레이터를 만듭니다 — 평면 4장을 한 번 올리고,
   열기·닫기·톱햇을 **연속 디스패치**로 돌리고, 마지막에 한 번 내립니다.
2. ☠️ **재기 전에는 `NEGA_GPU_MORPHOLOGY` 를 켜지 마십시오.** 지금 켜면 느려집니다.
3. 재는 법은 [`13`](13-performance-playbook.md) **21절 규칙 ①~⑤** 그대로 —
   **특히 ①: 바꾼 것이 실제로 돌았는지부터 확인.**

### 7.2 `film_scan_denoise` — 타일 루프가 **시험 안에만** 있습니다

`tests/Native.UnitTests/GpuFilmScan/` 에 있고 제품 경로에 없습니다.

☠️ **[`04`](04-gpu-plan.md) 0.5절의 타일 규칙을 그대로 옮겨야 합니다.**
CPU 와 **같은 512/18 타일**로 나누지 않으면 박스 블러의 누적 이력이 달라져
**delta 4.3e-05** 가 납니다. 이것은 성능 선택이 아니라 **값의 조건**입니다.
부수적으로 메모리도 풀립니다 — 전체 한 번에 = 중간 텍스처 **5 GB**, 타일 = **58 MB**.

### 7.3 `CIAreaAverage` 대응 — 병렬 리덕션

히스토그램·자동 보정용 원시연산입니다. 아직 없습니다.

**방법**: `groupshared` 트리 리덕션 → 그룹당 부분합 → 2단계로 합산.
SM 6.0 의 wave intrinsics(`WaveActiveSum`)가 더 빠르지만 **wave 크기가 하드웨어마다
다르고 DirectX 가 보장하지 않습니다**(8/16/32/64) — **내장/외장 범용 요구와 충돌합니다.**
[`04`](04-gpu-plan.md) 의 **`cs_5_0` 하한**을 지키려면 `groupshared` 트리로 가십시오.
([Wave Intrinsics](https://github.com/microsoft/directxshadercompiler/wiki/wave-intrinsics) ·
[D3D11 병렬 리덕션 사례](https://github.com/wolfgangfengel/graphicsdemoskeleton/blob/master/DirectX%2011/04_DirectCompute%20Parallel%20Reduction%20Case%20Study/05_ParallelReduction/ParallelReduction.hlsl))

☠️ **부동소수 덧셈은 결합법칙이 성립하지 않습니다.** 리덕션 순서가 CPU 와 다르면 값이 다릅니다 —
[`13`](13-performance-playbook.md) 14절(러닝 섬)과 **같은 함정**입니다.
CPU 가 어떤 순서로 더하는지 **먼저 읽고** 맞추거나, 못 맞추면 `1e-5` 동치로 선언하고 적으십시오.

### 7.4 `GpuMipHalve` — 만들어 놓고 **안 쓰고 있습니다**

비트 단위 일치까지 증명했는데 배선이 없습니다. 쓸 곳 셋:
`film_base_sampling.cpp`(자동 베이스 표본 격자) · `manual_negative_developer.cpp`
(`scene_density_range`, 자동 Dmax) · `muted_scene_vibrance.cpp`.

**절차**: 한 곳씩 배선 → `--develop-timing` 으로 **전후 6회씩** → 이득 없으면 되돌리고 수치를 적습니다.

---

## 8. 이 문서를 쓰며 지킨 절차 (다음 사람도 이대로)

1. **macOS 원문을 열었습니다.** `sed -n` 으로 커널 본문을 직접 읽었습니다.
   문서·파일 이름으로 판정한 것은 **0절에서 세 개가 틀렸습니다.**
2. **Windows 소스를 열었습니다.** `grep -ril` 로 존재를 세고, 존재하면 **안을 읽었습니다** —
   `digital_film_color_preset.cpp` 는 이름만 보면 이식된 것처럼 보이지만 **다른 알고리즘**입니다.
3. **모르는 것은 웹으로 찾고 출처를 남겼습니다.** 찾아서 **없다는 것을 확인한 것**
   (`CIRandomGenerator` 알고리즘)도 결과로 적었습니다.
4. **확인 못 한 것은 "확인 못 함" 으로 적었습니다.** 내장 GPU 실기, `scaled_noise` 의
   `double` 경로가 제품에서 도는지 — 둘 다 이 기계에서 확정할 수 없습니다.
