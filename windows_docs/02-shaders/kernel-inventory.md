# Metal 커널 인벤토리와 Windows 이식 분류

기준일: 2026-08-04  
macOS 기준 커밋: `9be909c`  
직접 조사 파일: `Sources/Chromabase/Engine/ChromabaseMetalKernels.swift`  
현재 파일 길이: 814줄  
현재 `[[stitchable]]` 함수: 31개

이 문서의 숫자 31은 전체 렌더 stage 수나 GPU dispatch 수가 아니다. 하나의 Core Image Metal
source string에 등록된 custom color kernel 수다. Core Image built-in filter, CPU 측정, LUT 생성,
defect detector, resampling, encoding은 이 숫자에 포함되지 않는다.

## 1. 조사 결과 요약

```text
custom stitchable color kernel                31
단일 image 입력                                18
다중 image 입력                                13
kernel 내부 임의 좌표/이웃 texel sampling       0
kernel 내부 texture/sampler 선언                0
공간 연산으로 만든 선행 image를 요구하는 kernel  9
독립 noise/source branch를 요구하는 kernel       3
```

핵심 해석은 다음과 같다.

- 31개 kernel 자체는 모두 현재 output coordinate의 input sample만 소비한다.
- 따라서 각 kernel의 HLSL 입력은 원칙적으로 Direct2D `SIMPLE` sampling 후보이다.
- 그러나 multi-input kernel의 일부 input은 Gaussian/box blur, median, LUT branch처럼 앞선 별도
  graph 결과다.
- “kernel이 pointwise”와 “전체 pipeline을 한 pass로 합칠 수 있다”는 다른 주장이다.
- Direct2D shader linking은 runtime이 graph와 hazard를 보고 선택하는 최적화다. 문서에서 고정
  dispatch 수를 보장하지 않는다.

## 2. 용어

### 2.1 unary point transform

현재 pixel 하나와 scalar/vector 상수만으로 output pixel 하나를 만든다.

```text
output(x,y) = f(input(x,y), parameters)
```

이 그룹은 연속 효과 graph에서 가장 강한 linking/fusion 후보다.

### 2.2 multi-input point combine

여러 image의 같은 coordinate를 읽어 하나의 output을 만든다.

```text
output(x,y) = f(a(x,y), b(x,y), ..., parameters)
```

kernel 자체는 simple sampling이지만, `b`가 `blur(a)`라면 blur를 먼저 materialize해야 한다.

### 2.3 spatial producer

이웃 sample, window, convolution, resampling 또는 reduction이 필요하다.

```text
blur(x,y) = g(input[x-r...x+r, y-r...y+r])
```

현재 31개 Metal color kernel 안에는 이 형태가 없다. Core Image built-in filter나 별도 CPU/GPU
stage가 이를 생산해 color kernel에 image input으로 넘긴다.

## 3. 전체 31개 목록

line은 기준 커밋의 함수 시작 line이다. 소스가 변하면 이름과 signature를 다시 추출하고 이 문서를
갱신한다.

### 3.1 색·톤·출력 보조: 10개

| line | kernel | image 입력 | domain/역할 | Windows 기본 후보 |
|---:|---|---:|---|---|
| 74 | `colorMixerHSL` | 1 | display-referred HSL 8-band mixer | linkable D2D pixel shader |
| 101 | `colorGrade` | 1 | shadow/midtone/highlight chroma·luma | linkable D2D pixel shader |
| 123 | `bwToning` | 1 | monochrome shadow/highlight tint | linkable D2D pixel shader |
| 151 | `calibrationPrimaries` | 1 | HSL primary hue/saturation calibration | linkable D2D pixel shader |
| 185 | `basicTone` | 1 | perceptual tone masks, linear delta output | linkable D2D pixel shader |
| 241 | `parametricToneCurve` | 1 | measured band boundary 기반 tone | linkable D2D pixel shader |
| 492 | `gamutSoftClip` | 1 | luma-preserving chroma compression | output/display-bound D2D shader |
| 579 | `highlightDesaturate` | 1 | low-chroma highlight neutralization | linkable D2D pixel shader |
| 595 | `ditherAdd` | 2 | sRGB 8-bit boundary dither | output-only shader, seeded noise |
| 603 | `channelClippingOverlay` | 1 | preview-only premultiplied overlay | canvas overlay shader |

주의:

- `basicTone`은 input을 `toneSafeUnitRGB`로 제한하고 sRGB luma mask를 만든 뒤 linear luma delta를
  적용한다. 단순 slider math로 다시 만들면 안 된다.
- `parametricToneCurve` kernel은 pointwise지만 band boundary는 이미지 측정 결과다.
- `gamutSoftClip`은 working image에 무조건 넣는 단계가 아니다. 목적 gamut을 아는 display/export
  boundary가 소유한다.
- `ditherAdd`는 render look이 아니라 target bit depth에 맞춘 output stage다.
- clipping overlay는 export 산출물에 들어가면 안 된다.

### 3.2 필름 반전·측정 기반 grade: 교차 분류

| line | kernel | image 입력 | 역할 | Windows 기본 후보 |
|---:|---|---:|---|---|
| 530 | `boundedRelativeGrade` | 2 | source와 LUT-graded branch를 measured domain 안에서 결합 | D2D multi-input combine |
| 556 | `negativeInvert` | 1 | Dmin/Dmax와 고정 H&D response 기반 negative inversion | linkable D2D pixel shader + CPU oracle |
| 579 | `highlightDesaturate` | 1 | 명부 neutral 보정 | 위 색·톤 표와 동일 |

`highlightDesaturate`와 `boundedRelativeGrade`는 다른 표에도 있다. 이 절은 negative pipeline에서의
의미를 설명하기 위한 교차 참조이며 전체 count에는 중복하지 않는다.

`negativeInvert`는 가장 먼저 이식할 conformance kernel이다. `log10`, `pow`, `exp`, 음의 density
mirror, extended working value가 모두 있어 precision·domain·fast-math 차이를 한 번에 드러낸다.

### 3.3 scanner target·noise reduction: 9개

| line | kernel | image 입력 | 선행 producer | 역할 |
|---:|---|---:|---|---|
| 288 | `scannerLowSatChroma` | 2 | Gaussian blur | 저채도 chroma 안정화 |
| 305 | `scannerMidtoneChroma` | 3 | small/large chroma guide | 다중 scale chroma residual 제어 |
| 361 | `filmScanShrink` | 6 | median×2, Gaussian pyramid×3 | wavelet-style coring + impulse replacement |
| 465 | `gfProduct` | 2 | 없음 | guided filter product |
| 469 | `gfCoeffA` | 4 | box means | guided regression coefficient A |
| 481 | `gfCoeffB` | 3 | box means | guided regression coefficient B |
| 485 | `gfApply` | 4 | box means of A/B | guided result compose |
| 504 | `noritsuTexture` | 2 | Gaussian blur | bounded luminance USM texture |
| 530 | `boundedRelativeGrade` | 2 | 3D LUT branch | measured domain grade combine |

여기서 9개 모두 current-coordinate combine이다. 다만 이들을 계산하기 전에 blur/median/box mean/LUT
branch가 필요하다. 따라서 다음 표현을 구분한다.

- 올바른 표현: “9개 custom combine shader의 각 image input은 simple sampling이다.”
- 틀린 표현: “9개가 공간 pass 없이 앞 단계와 모두 한 pass로 합쳐진다.”

`gfProduct` 자체는 spatial producer가 아니지만 뒤의 box mean을 만들기 위한 intermediate를 만든다.
guided filter 전체는 여러 pass다.

### 3.4 texture/noise: 교차 분류 2개

| line | kernel | image 입력 | 역할 |
|---:|---|---:|---|
| 280 | `filmGrain` | source + noise | zero-mean, luma-weighted generic grain |
| 595 | `ditherAdd` | source + noise | ±0.5/255 sRGB dither |

`filmGrain`은 generic ColorModel 경로다. 아래 `digitalFilmGrainDensity`와 다른 수학이다.
`ditherAdd`는 출력 보조 표에도 있으며 전체 count에는 한 번만 포함한다.

noise source 이식 정책:

- macOS `CIRandomGenerator`의 우연한 frame-to-frame 결과를 API 계약으로 보지 않는다.
- preview 안정성과 export 재현성을 위해 명시적 seed, frame ID, absolute pixel coordinate를 input으로
  하는 deterministic noise field를 정의한다.
- CPU와 GPU가 같은 hash/PRNG 정수 연산을 사용할 수 있어야 한다.
- tile origin이 달라도 같은 absolute pixel의 noise가 같아야 한다.
- generic grain, density grain, dither는 서로 다른 stream/domain ID를 사용한다.
- dither seed가 export 재시도마다 바뀌어 output hash가 달라지는 것을 금지한다.

### 3.5 digital source virtual development: 10개

이 10개는 `params.isDigitalSource == true` 경로에만 적용한다. 이미 필름 물성을 포함한 scan에 같은
물리를 다시 적용하지 않는다.

| line | kernel | image 입력 | domain/역할 | spatial dependency |
|---:|---|---:|---|---|
| 639 | `digitalSceneReconstruct` | 1 | display-rendered value → estimated scene exposure | 없음 |
| 652 | `digitalFilmDensity` | 1 | exposure → layer density characteristic curves | 없음 |
| 680 | `digitalInterImage` | 1 | inter-image layer coupling | 없음 |
| 691 | `digitalPrintPaper` | 1 | negative density → paper reflectance | 없음 |
| 701 | `digitalReversalTransmit` | 1 | reversal density → transmission | 없음 |
| 711 | `digitalHalation` | 4 | source + near/far/wide scatter combine | Gaussian blur 3종 |
| 737 | `digitalToDisplayGamma` | 1 | linear → sRGB transfer | 없음 |
| 741 | `digitalToLinearLight` | 1 | sRGB → linear transfer | 없음 |
| 773 | `digitalFilmColor` | 1 | film stock color signature | 없음 |
| 799 | `digitalFilmGrainDensity` | 2 | density-dependent grain | deterministic noise field |

중요한 계약:

1. `digitalSceneReconstruct`는 clipping으로 사라진 정보를 복원한다고 주장하지 않는다.
2. `digitalFilmDensity`의 characteristic-curve limit와 paper/transmission limit를 중복 적용하지 않는다.
3. `digitalPrintPaper`와 `digitalReversalTransmit`는 polarity별로 상호 배타적이다.
4. `digitalHalation`은 3개의 다른 blur radius 결과를 요구한다. 하나의 blur를 scale만 바꿔 재사용하지
   않는다.
5. `digitalToDisplayGamma`/`digitalToLinearLight` 사이의 preset adjustment domain을 생략하지 않는다.
6. `digitalFilmColor` 내부도 transfer function을 사용하므로 caller의 domain과 중복 변환하지 않는다.
7. density grain은 additive RGB overlay가 아니다.

## 4. 정확한 count 분류

### 4.1 단일 image 입력 18개

```text
colorMixerHSL
colorGrade
bwToning
calibrationPrimaries
basicTone
parametricToneCurve
gamutSoftClip
negativeInvert
highlightDesaturate
channelClippingOverlay
digitalSceneReconstruct
digitalFilmDensity
digitalInterImage
digitalPrintPaper
digitalReversalTransmit
digitalToDisplayGamma
digitalToLinearLight
digitalFilmColor
```

이 18개는 scalar/vector parameter만 더 받는다.

### 4.2 다중 image 입력 13개

```text
filmGrain                  source + noise
scannerLowSatChroma        source + blur
scannerMidtoneChroma       source + smallGuide + largeGuide
filmScanShrink             source + med3 + med5 + g1 + g2 + g3
gfProduct                  a + b
gfCoeffA                   mIP + mII + mI + mP
gfCoeffB                   a + mI + mP
gfApply                    mA + mB + guide + source
noritsuTexture             source + blurred
boundedRelativeGrade       source + graded
ditherAdd                  source + noise
digitalHalation            source + near + far + wide blur
digitalFilmGrainDensity    source + noise
```

### 4.3 spatial producer가 필요한 combine 9개

```text
scannerLowSatChroma
scannerMidtoneChroma
filmScanShrink
gfProduct / gfCoeffA / gfCoeffB / gfApply  # guided-filter subgraph 전체 기준
noritsuTexture
digitalHalation
```

이 목록은 “9개의 kernel”과 “9번 dispatch”를 뜻하지 않는다. guided filter는 product, mean, coefficient,
mean, apply로 더 많은 graph node를 갖고, 여러 built-in effect가 runtime에 합쳐질 수도 있다.
`boundedRelativeGrade`의 두 번째 input은 3D LUT branch이지만 LUT 자체는 point transform이다. 그 branch를
실제 intermediate로 materialize할지는 Direct2D graph prototype 결과로 결정한다.

## 5. 31개 밖의 필수 렌더 연산

Windows 이식 범위를 31개 HLSL 파일로 축소하면 제품이 완성되지 않는다.

### 5.1 Core Image built-in 등가

현재 `Chromabase`에서 확인되는 주요 연산:

- color matrix
- color controls, vibrance
- color clamp
- color cube with color space
- tone curve
- gamma adjust
- linear↔sRGB tone curve
- exposure adjust
- Gaussian blur
- box blur
- median filter
- unsharp mask
- blend with mask
- Lanczos scale
- random generator
- area average
- crop/affine transform

Windows에서는 먼저 Direct2D built-in effect의 의미를 비교하고, 의미/precision/domain이 다르면 custom
effect 또는 DirectCompute/CPU 구현을 쓴다. 이름이 비슷하다는 이유로 등가라고 판정하지 않는다.

### 5.2 CPU 또는 compute 작업

- film-base sampling/estimation
- histogram, percentile, median, mean, variance
- auto levels/neutral/rescue parameter derivation
- defect candidate detection and morphology
- mask rasterization/feathering
- source decode/metadata/ICC
- tile scheduling
- image encode

이 연산은 custom color kernel count에 포함되지 않는다.

## 6. Windows backend 매핑

| 연산 형태 | v1 우선 backend | CPU fallback | 비고 |
|---|---|---|---|
| unary point transform | Direct2D linkable pixel shader | scalar/SIMD | 같은 math source/spec |
| multi-input point combine | Direct2D custom draw transform | scalar/SIMD | 모든 input rect mapping 명시 |
| built-in color matrix/transfer | Direct2D built-in 또는 custom | scalar/SIMD | domain conformance 우선 |
| Gaussian/box blur | Direct2D built-in 우선 | separable CPU | border/ROI 확인 |
| median/morphology | DirectCompute 또는 CPU | CPU baseline | D2D name-equivalence 가정 금지 |
| histogram/reduction | DirectCompute 또는 CPU | deterministic CPU | GPU 결과가 불안정하면 CPU 고정 |
| 3D LUT | D2D LookupTable3D 후보 | scalar/SIMD trilinear | interpolation/domain 검증 |
| resampling | D2D/WIC/custom | CPU | filter kernel와 phase 고정 |
| deterministic noise | HLSL integer hash | same CPU hash | tile-independent coordinate |

D3D12와 CUDA는 이 표의 v1 필수 backend가 아니다.

## 7. Direct2D shader-linking 해석

공식 Direct2D 문서상 effect shader linking은 인접 transform을 runtime에 한 pass로 결합할 수 있다.
하지만 다음 조건이 있다.

- full pixel shader와 export function을 함께 제공해야 한다.
- `d2d1effecthelpers.hlsli` 규약을 지켜야 한다.
- input 수와 `SIMPLE`/`COMPLEX`를 올바르게 선언해야 한다.
- compute 또는 vertex shader가 끼면 그 hazard 양옆은 link되지 않는다.
- complex-sampled input은 predecessor function output으로 연결할 수 없다.
- Direct2D가 실제로 linking이 이득이라고 판단해야 한다.

따라서 31개 각각을 `SIMPLE` 후보로 authoring하더라도 다음을 측정해야 한다.

- 실제 linked pass 수
- intermediate surface 수와 peak bytes
- graph construction/JIT cost
- parameter 변화 시 graph rebuild cost
- driver/vendor별 linking 결과
- WARP 결과

full shader blob만 `LoadPixelShader`에 전달하면 adjacent transform과 link되지 않는다.

## 8. HLSL source 구조

31개를 무조건 31개의 중복 파일로 만들지 않는다. 그러나 거대한 한 파일의 runtime registry도 그대로
복제하지 않는다.

권장 구조:

```text
native/shaders/
├── include/
│   ├── color_math.hlsli
│   ├── transfer.hlsli
│   ├── tone_safe.hlsli
│   ├── noise.hlsli
│   └── d2d_effect_contract.hlsli
├── point/
│   ├── negative_invert.hlsl
│   ├── basic_tone.hlsl
│   ├── parametric_tone_curve.hlsl
│   └── ...
├── combine/
│   ├── guided_filter.hlsl
│   ├── scanner_chroma.hlsl
│   └── digital_halation.hlsl
└── generated/
    ├── shader_manifest.json
    └── embedded_shader_blobs.*
```

한 source file에 관련 entry point 여러 개를 둘 수 있지만 manifest는 entry별로 다음을 기록한다.

- stable logical name
- source path와 entry point
- input count와 sampling type
- constant-buffer schema version/size/alignment
- full/export bytecode hash
- target profile
- minimum feature level
- source commit/hash

runtime 이름 문자열을 흩뿌리지 않는다.

## 9. constant-buffer ABI

Metal 함수 인자 순서를 C# property 순서와 직접 연결하지 않는다.

각 effect는 C++ 쪽 POD parameter struct를 소유하고 다음을 고정한다.

- 16-byte register packing
- `float`/`float2`/`float3`/`float4` offset
- bool은 32-bit integer 또는 float flag로 명시
- matrix row/column convention
- enum wire value
- struct size/alignment static assertion
- NaN/Inf/denormal handling
- default value
- ABI version

C#은 opaque effect handle과 setter/request snapshot을 통해 값을 넘긴다. XAML view model이 raw HLSL
constant buffer layout을 소유하지 않는다.

## 10. precision·domain 계약

각 kernel manifest/test에는 다음을 붙인다.

- input color space
- input transfer function
- premultiplied/unpremultiplied alpha
- expected finite range
- extended negative/>1 value 허용 여부
- explicit clamp 위치
- output domain
- math precision (`float32` baseline)
- fast-math 허용 여부

공통 규칙:

- HLSL `saturate`를 Metal `clamp`가 있는 모든 곳에 기계적으로 넣지 않는다.
- 반대로 source에 있는 clamp를 “HDR에 좋다”는 이유로 제거하지 않는다.
- `pow(0, noninteger)`, negative base, log lower bound를 source와 동일하게 처리한다.
- alpha premultiplication은 clipping overlay, mask blend, export boundary에서 별도 검증한다.
- display-referred HSL/LUT와 scene-linear stage를 섞지 않는다.
- CPU oracle과 GPU shader가 같은 transfer constants를 사용한다.

## 11. kernel별 conformance fixture

### 11.1 공통 input vector

- `0`, `1`, `-0.1`, `1.1`
- `0.18` linear mid gray
- sRGB encoded mid gray 근처
- neutral ramp
- saturated R/G/B/C/M/Y
- near-neutral warm/cool gray
- alpha 0, fractional, 1
- NaN/Inf는 public boundary에서 reject 또는 canonicalize

### 11.2 `negativeInvert`

- Dmin보다 큰/같은/작은 transmission
- preset/measured Dmax
- negative density mirror continuity
- channel-specific base
- very low positive input lower bound
- monotonicity per channel
- CPU reference ULP/absolute/relative error

### 11.3 tone kernel

- each slider min/zero/max
- absolute black anchoring
- 0.18 linear mid preservation/expected delta
- highlight/white boundary
- hue preservation under luma-only changes

### 11.4 multi-input kernel

- mismatched input extent
- ROI boundary and apron
- transparent edge
- each secondary input independently perturbed
- tile split versus full-frame equality
- source branch and derived branch revision mismatch rejection

### 11.5 noise kernel

- same seed/frame/pixel reproducibility
- different stream/domain separation
- tile-origin independence
- mean near zero for generic grain/dither
- density response for digital grain
- CPU/GPU bitwise hash field before float conversion

## 12. 이식 순서

### K0 — inventory lock

- 31 name/signature manifest 생성
- Core Image built-in operation inventory 고정
- macOS canonical input/output fixture 생성

### K1 — render skeleton

- source decode → float working surface
- one D2D custom effect → readback
- WARP/Intel/AMD/NVIDIA/ARM64 conformance

### K2 — `negativeInvert`

- scalar C++ oracle
- HLSL port
- extended values와 error budget
- full/export shader loading

### K3 — core tone/color

- `basicTone`
- `parametricToneCurve`
- point curve/LUT
- color mixer/grading/calibration
- B&W toning

### K4 — measurement coupling

- film-base/percentile/histogram parameter derivation
- immutable parameter snapshot
- stale result rejection

### K5 — spatial graph

- blur/median/box mean
- scanner chroma
- guided filter
- film scan shrink
- texture

### K6 — defect/local adjustment

- defect detector/repair/mask
- local dodge/burn
- ROI/apron/tile equivalence

### K7 — digital virtual development

- scene reconstruction/density/media response
- halation
- color signature
- density grain
- digital-only routing guard

### K8 — output-only effects

- display gamut mapping
- clipping overlay
- output sharpening
- seeded dither

## 13. 완료 gate

- [ ] manifest가 source의 31 entry와 정확히 일치한다.
- [ ] 31개 외 Core Image built-in operation이 누락되지 않는다.
- [ ] 각 kernel의 CPU oracle 또는 independent reference가 있다.
- [ ] full shader와 export function이 build artifact에 함께 있다.
- [ ] runtime이 실제 shader hash/profile을 진단할 수 있다.
- [ ] WARP, Intel, AMD, NVIDIA, Qualcomm ARM64 결과가 허용 오차를 만족한다.
- [ ] simple/complex input 선언이 ROI mapping과 일치한다.
- [ ] full-frame과 tiled render가 seam 없이 일치한다.
- [ ] preview와 export가 같은 parameter/domain contract를 사용한다.
- [ ] digital kernel이 film scan path에 적용되지 않는다.
- [ ] output overlay/dither가 working master에 섞이지 않는다.
- [ ] actual linked pass/intermediate 수를 GPU capture로 확인한다.

## 14. drift 점검 명령

```bash
rg -n '\[\[stitchable\]\]\s+float4\s+[A-Za-z0-9_]+' \
  Sources/Chromabase/Engine/ChromabaseMetalKernels.swift

rg -o 'colorKernel\(named: "[A-Za-z0-9_]+"\)' \
  Sources/Chromabase -g '*.swift' | sort

rg -n 'applyingFilter\("CI[A-Za-z0-9_]+' \
  Sources/Chromabase -g '*.swift' | sort
```

숫자만 수정하지 않는다. kernel 추가·삭제 시 다음을 함께 갱신한다.

- name/signature/input count
- domain/alpha/clamp contract
- graph 위치
- CPU oracle
- HLSL manifest
- fixture/golden hash
- compatibility matrix

## 15. 공식 자료

- [Direct2D custom effects](https://learn.microsoft.com/en-us/windows/win32/direct2d/custom-effects)
- [Direct2D effect shader linking](https://learn.microsoft.com/en-us/windows/win32/direct2d/effect-shader-linking)
- [Direct2D HLSL helpers](https://learn.microsoft.com/en-us/windows/win32/direct2d/hlsl-helpers)
- [ID2D1EffectContext::LoadPixelShader](https://learn.microsoft.com/en-us/windows/win32/api/d2d1effectauthor/nf-d2d1effectauthor-id2d1effectcontext-loadpixelshader)
- [Direct2D effects overview](https://learn.microsoft.com/en-us/windows/win32/direct2d/effects-overview)

관련 문서:

- [Metal→HLSL](metal-to-hlsl.md)
- [pipeline shape](../01-render-engine/pipeline-shape.md)
- [shader linking](../01-render-engine/shader-linking.md)
- [precision and clipping](../01-render-engine/precision-and-clipping.md)
- [histogram and statistics](../03-measurement/histogram-and-statistics.md)
- [virtual development](../15-digital-film/virtual-development.md)
