# macOS 커널 수식 대조

기준일: 2026-08-10

## 왜 이걸 했나

macOS pixel golden 은 macOS 호스트가 있어야 만들 수 있고, 그것 없이는 "수치가 같다"를 증명할
방법이 없다고 적어 왔습니다. 하지만 **기준 자료가 저장소 안에 있습니다** —
`negaflow-mac/Sources/Chromabase/Engine/ChromabaseMetalKernels.swift` 에 Core Image 가 실제로
실행하는 Metal 커널 소스가 상수까지 그대로 들어 있습니다.

golden 이미지 비교는 아니지만, **수식과 상수의 1:1 대조**는 지금 여기서 할 수 있고 실제로
차이를 찾아냅니다. 이 문서는 무엇을 대조했고 결과가 무엇이었는지 기록해, 다음 사람이 이미
확인된 곳에 시간을 쓰지 않게 합니다.

## 결과 요약

| 단계 | macOS 기준 | 결과 |
|---|---|---|
| Basic Tone | `basicTone` | **일치** |
| Parametric Tone Curve | `parametricToneCurve` | **일치** |
| Negative Inversion | `negativeInvert` | **일치** |
| Color Mixer (HSL 8밴드) | `colorMixerHSL` | **일치** |
| Color Grading | `colorGrade` + `ColorGradingStage.swift` | **일치** |
| Primary Calibration | `calibrationPrimaries` | **일치** |
| B&W Toning | `bwToning` | **일치** |
| Texture (전체) | `TextureStage.apply` (ColorModel.swift) | **일치** |
| Film Grain | `filmGrain` | 수식 일치, 잡음원만 다름 |
| **표시 경계** | `DisplayGamutMap` + `OutputDither` | **누락 — 이번에 구현** |

## 확인한 것들

**Basic Tone.** 대비 피벗 `0.46`, 지수 `2^(c·0.9 / c·0.7)`, 음수 대비의 `smoothstep(0.12,0.30)`
저역 가드, Density `0.10`·mid mask `0.18~0.36 × 0.58~0.76`, Highlights `0.10`·`0.55~0.80`,
Shadows `0.10`·`0.02~0.08 × 0.32~0.46`, Whites `0.12`·`0.68~0.92`, Blacks `0.06`·`0.0~0.03 ×
0.14~0.30`. sRGB 감마 도메인에서 마스크를 정의하고 luma 차이를 linear 로 되돌려 additive 로
적용하는 구조까지 같습니다.

**Negative Inversion.** `t = max(rgb, 1e-5)`, `d = log10(dmin/t) / max(dmaxNorm, 1e-6)`,
`arg = pow(max(rate·|d|, 1e-12), shape)`, `y = yCeil − amplitude·exp(−arg)`,
`toeY = yCeil − amplitude`, `d < 0` 일 때 `2·toeY − y` 로 미러, `pow(10, outY)`.
`1e-12` 하한(fast-math NaN 방지)까지 같습니다.

**Color Mixer.** 8밴드 중심, `bw = 0.14`, hue `±0.0833`, luminance `0.16`,
gate `smoothstep(0.04, 0.18)`, `wsum > 1e-4` 정규화.

**Color Grading.** pivot `clamp(0.5 + balance·0.30, 0.15, 0.85)`, width `mix(0.10, 0.50,
blending)`, chroma `×0.75`, luminance `×0.22`, 그리고 tint 가 "완전 채도 hue 색 × saturation"
이라는 Swift 쪽 유도까지 같습니다.

**Primary Calibration.** 중심 `{0, 1/3, 2/3}`, `bw = 0.22`, hue `0.08`,
gate `smoothstep(0.03, 0.16)`.

**B&W Toning.** `shadowReach mix(0.68,0.92)`, `highlightReach mix(0.38,0.76)`,
crossover `smoothstep(0.22,0.86)`, toneMask `mix(0.95,0.68)`/`mix(0.30,0.72)`,
amount `mix(0.18,0.36)`, density `0.060`/`0.026`.

**Texture.** 하위 효과 순서(sharpness → grain → clarity → halation → vignette)와 모든 상수 —
unsharp `1.0 + s·1.2` / `0.18 + s·0.42`, clarity `6.0 + c·5.0` / `0.10 + c·0.18`,
negative clarity `min(0.9, −c·0.8)`, vignette `1 − v·0.42` / `−v·0.16` 와
반경 `min·0.34`~`min·0.72`.

**Film Grain.** luma 가중 `smoothstep(0.02,0.16) × (1 − smoothstep(0.82,1.0))`, 진폭
`strength·0.055`, zero-mean 노이즈, clamp 까지 같습니다. 다른 것은 잡음원뿐입니다 — macOS 는
`CIRandomGenerator`(공유 seed 없음), Windows 는 좌표 해시(재현 가능). 분포는 같습니다.

## 찾은 차이 하나

**표시 경계.** macOS 표시 경로는 8비트로 내리기 전에 `DisplayGamutMap`(hue 보존 soft clip)과
`OutputDither`(±0.5/255)를 겁니다. Windows 미리보기에는 둘 다 없었고 채널별 하드 클립과
`>> 8` 뿐이었습니다. 구현과 근거는 `../implementation/display-boundary.md`.

**게시 경로는 오히려 Windows 가 맞았습니다.** macOS 의 `appliesDither` 는 `bitDepth == .eight`
일 때만 참이고 Windows 는 16비트만 게시합니다. "macOS 에 있으니 옮긴다"로 갔으면 게시 결과를
잘못 바꿨을 것입니다. **어느 조건에서 걸리는지까지 봐야 합니다.**

## 도달 가능성 확인 — 없어서 맞는 것들

macOS 소스에 있다고 다 살아 있는 코드는 아닙니다. 옮기기 전에 **실제로 불리는지** 확인했습니다.

| macOS 심볼 | 호출부 | Windows |
|---|---|---|
| `ChromabaseEngine.gamutSoftClip(_:)` | **없음** | 없어서 맞음 |
| `ChromabaseEngine.applyHighlightDesaturation(...)` | **없음** | 없어서 맞음 |
| `ScannerNoiseReduction` (`scannerLowSatChroma`, `scannerMidtoneChroma`) | **없음** | 없어서 맞음 |
| `SoftProof.apply` | 표시 경로에서 호출됨 | **미구현 — 기능 공백** |

앞의 셋은 정의만 남아 있고 활성 파이프라인이 부르지 않습니다. PostPipeline 주석의
"타겟 프로파일 밖의 고정 NR·명부 탈채도·추가 gamut 압축은 적용하지 않는다"와 일치합니다.
**소스에 있다는 이유로 옮겼다면 없는 효과를 만들어 냈을 것입니다.**

`SoftProof` 는 표시 경로에서 실제로 걸리며 Windows 에는 없습니다. 다만 사용자가 켜는 기능이지
조용한 차이가 아니므로 기능 백로그입니다.

## 아직 못 정한 수치 위험 — Core Image 내장 blur 반경

macOS 는 `CIUnsharpMask`/`CIGaussianBlur` 에 `inputRadius` 를 넘기고, Windows 는 그 값을
**Gaussian sigma 로** 해석합니다(`gaussian_transform(image, sigma)` → 커널 반경
`ceil(3σ)`, 가중치 `exp(−offset²/2σ²)`).

`inputRadius` 가 실제로 sigma 인지 커널 반경인지는 Apple 문서가 명시하지 않고, 웹에서도
권위 있는 답을 찾지 못했습니다. 두 해석의 차이는 작지 않습니다 — 선예도 0.6 이면 macOS
`inputRadius = 1.72` 이고, sigma 해석이면 σ=1.72, 반경 해석이면 σ≈0.57 로 **3배 좁은 블러**가
됩니다. 선예도·명료도·헐레이션의 성격이 통째로 달라집니다.

**추측으로 바꾸지 않았습니다.** 잘못 바꾸면 모든 선예도 설정이 조용히 달라집니다.

**정하는 방법(macOS 세션에서 몇 분):** 중앙 1픽셀만 흰 검은 이미지에
`CIGaussianBlur(inputRadius: 4.0)` 를 걸고 중심에서의 감쇠를 읽습니다. 중심값 대비
`exp(−0.5) ≈ 0.607` 이 되는 거리가 sigma 입니다. 그 거리가 4 이면 `inputRadius == sigma`
(현재 Windows 가 맞음), 약 1.33 이면 `inputRadius == 3σ` 입니다.

## 이 대조가 증명하지 않는 것

- **부동소수점 결과의 동일성.** 같은 수식이어도 Core Image 의 GPU 연산 순서·정밀도와 Windows
  CPU 결과는 마지막 자리에서 다를 수 있습니다. 그건 여전히 macOS 호스트의 golden 이 필요합니다.
- `CIVibrance`, `CIUnsharpMask`, `CIGaussianBlur` 같은 **Apple 내장 필터**. 이들은 소스가 없어
  대조 대상이 아니며 Windows 는 독립 구현입니다.
- ScannerTargetGrade 의 측정 기반 3D LUT 와 GrainMend 검출기. 커널이 아니라 데이터·알고리즘이
  기준이라 별도 작업입니다.

## 부수 정리

`tone_safe_unit_rgb` 가 `tone_mapping.cpp` 안에도 따로 구현돼 있었습니다. 표시 경계 작업으로
공용 헤더가 생겼으므로 중복을 지우고 한 곳만 남겼습니다. 수치 계약이 두 벌 있으면 언젠가
갈라집니다. 실촬영 export SHA-256 `1A4EB1A7…` 가 그대로임을 확인했습니다.

## 2026-08-13 추가 조사 — blur 반경의 의미 (아직 미결, 다만 한쪽으로 기울었습니다)

macOS 호스트 없이 이 질문을 닫을 수 있는지 다시 확인했습니다. 닫지 못했지만 근거는 모였고,
**Windows 의 현재 해석(`inputRadius` 를 sigma 로 읽음)을 바꾸지 않는 편이 맞다**는 결론입니다.

확인한 것:

- macOS 의 blur 는 전부 Apple 내장 필터입니다. `ChromabaseMetalKernels.swift` 에는 Gaussian 이
  없고, `ColorModel`(clarity·halation), `FilmEmulation`(acutance), `FilmScanDenoise`,
  `LocalDodgeBurnStage` 가 `CIGaussianBlur`/`CIUnsharpMask` 에 `inputRadius` 를 넘깁니다.
  그러므로 이 저장소 안에서는 답이 나오지 않습니다.
- Apple 문서는 서로 다르게 씁니다. `CIGaussianBlur.radius` 는 "The radius of the blur, in
  pixels" 이고, 편의 API 는 이름부터 `applyingGaussianBlur(sigma:)` 이며 "sigma 가 0.16 보다
  작으면 원본을 그대로 돌려준다"고 합니다. 두 API 가 같은 필터를 가리킨다면 그 파라미터는
  sigma 입니다.
- 웹의 통설도 `inputRadius == sigma` 쪽입니다. 다만 1차 출처를 확보하지 못했으므로
  **증명으로 취급하지 않습니다.**

그래서 코드는 그대로 둡니다. 근거가 약한 채로 바꾸면 지금 맞을 수도 있는 것을 틀리게 만듭니다.

**macOS 세션에서 여전히 할 일은 위의 1픽셀 측정 하나입니다.** 추가로 `applyingGaussianBlur`
의 0.16 문턱이 `CIGaussianBlur(inputRadius:)` 에도 같게 나타나는지 보면, 두 API 가 같은
파라미터를 쓴다는 것이 바로 확인됩니다.

---

## 후속 (2026-08-18) — 이 문서가 GPU 이식의 전제입니다

[`../audit/04-gpu-plan.md`](../audit/04-gpu-plan.md) 가 같은 파일(`ChromabaseMetalKernels.swift`)에서
`[[stitchable]]` 커널 **32개**를 세어 GPU 이식 대상 목록으로 삼았습니다.

**이 문서의 두 결과가 그 목록을 거르는 필터입니다:**

1. **위 "일치" 9개**(`basicTone`·`parametricToneCurve`·`negativeInvert`·`colorMixerHSL`·
   `colorGrade`·`calibrationPrimaries`·`bwToning`·텍스처·`filmGrain`)는 수식이 이미 대조돼 있어
   **CPU 코드를 그대로 HLSL 로 옮기면 됩니다.**
2. **"없어서 맞는 것들" 3개**(`ScannerNoiseReduction`의 `scannerLowSatChroma`/`scannerMidtoneChroma`,
   `gamutSoftClip`, `highlightDesaturate`)는 macOS 활성 파이프라인이 **부르지 않습니다.**
   **GPU 로 옮기면 macOS 에 없는 효과를 만듭니다. 옮기지 마십시오.**

또 하나 이 문서가 확인한 원칙 — *"macOS 에 있으니 옮긴다"로 갔으면 게시 결과를 잘못 바꿨을
것입니다. 어느 조건에서 걸리는지까지 봐야 합니다."* — **GPU 이식에도 그대로 적용됩니다.**

> ⚠️ 위 대조는 **2026-08-10 기준**입니다. 그 뒤 바뀐 커널은 다시 대야 합니다.
