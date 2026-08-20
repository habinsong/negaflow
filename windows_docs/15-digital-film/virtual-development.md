# 디지털 소스 가상 현상 — Windows 이식 사양

기준일: 2026-08-04  
대상: WinUI 3 셸, C++20 네이티브 엔진, Direct3D 11/Direct2D, CPU scalar/SIMD fallback  
macOS 근거: `Sources/Chromabase/Digital/` 8개 파일, `DevelopParameters`, post pipeline,
10개 Metal kernel, `DigitalFilmLookTests`  
상태: 현재 의미·Windows graph·검증 계약 정리, macOS와 Windows 실기 pixel parity는 아직 미검증

관련 문서:

- [kernel inventory](../02-shaders/kernel-inventory.md)
- [수치 정밀도와 clipping](../01-render-engine/precision-and-clipping.md)
- [backend 선택](../12-performance/backend-selection.md)
- [GPU 범용성](../12-performance/gpu-vendor-portability.md)
- [large-image tiling](../06-large-images/image-source-tiling.md)
- [색 관리](../04-color-management/color-pipeline.md)
- [제품 불변식](../99-plan/product-invariants.md)
- [유지보수](../99-plan/maintenance.md)

## 1. 결론

이 기능은 “필름 LUT”가 아니다. 이미 카메라 렌더를 거친 디지털 이미지를 다음 순서의 물리적 근사로
통과시키는 별도 develop graph다.

```text
camera-rendered digital source
  → scene exposure reconstruction
  → emulsion scatter + halation
  → layer density characteristic curves
  → inter-image coupling
  → negative paper reflection 또는 reversal transmission
  → stock color signature
  → stock-specific display-domain color preset
  → density-dependent grain
  → acutance
  → original/result final mix
```

Windows판은 이 순서와 수치 의미를 C++ engine 안에 구현한다. WinUI 3은 recipe 편집과 preview 표시만 맡고
pixel math를 C#이나 XAML effect로 나누지 않는다.

기준 실행 구조:

```text
canonical recipe + immutable render snapshot
                 │
                 ▼
DigitalFilmGraph C++
  ├── Direct2D custom pixel effects + built-in spatial effects
  ├── D3D11 compute, 실제 병목에서만
  └── CPU scalar/SIMD complete fallback
                 │
                 ▼
working-linear extended float output
  ├── display color transform
  └── export/print color transform
```

중요한 결정:

- 필름 scan은 이 graph를 절대 지나지 않는다.
- `Digital Color`와 `Digital B&W`만 digital source process다.
- digital source 여부를 단순 UI boolean 추측으로 만들지 않고 persisted source-signal contract로 검증한다.
- GPU stage가 하나라도 필수 계약을 만족하지 못하면 부분 graph를 조용히 출력하지 않는다. 전체 CPU 경로로
  전환하거나 visible failure를 낸다.
- 모든 materialized working intermediate는 원칙적으로 32-bpc float 4채널이다.
- blur edge는 macOS의 `clampedToExtent`에 맞춰 edge-repeat이어야 한다. Direct2D Gaussian blur의 기본/`HARD`
  mirror behavior를 그대로 쓰지 않는다.
- noise는 tile과 재시도에 독립적인 deterministic absolute-coordinate field로 정의한다.
- 11개 stock의 물리/색 parameter는 한 versioned manifest에서 CPU/GPU 양쪽으로 공급한다.
- `CUDA`는 이 graph의 필수 경로가 아니다. NVIDIA 전용 별도 accelerator를 나중에 붙여도 같은 recipe와
  conformance를 통과해야 한다.

## 2. 이름과 범위

### 2.1 “가상 현상”과 “가상 복사본”은 다르다

이 문서의 virtual development는 디지털 이미지에 필름 노출·밀도·매체 응답을 계산하는 렌더 기능이다.
Library의 virtual copy는 하나의 source를 여러 recipe가 공유하는 catalog 기능이다.

두 기능은 함께 사용할 수 있지만 identity가 다르다.

```text
SourceAsset               immutable file identity
  ├── Frame/VirtualCopy A  recipe A: Digital Color + Portra 400
  ├── Frame/VirtualCopy B  recipe B: Digital Color + E100
  └── Frame/VirtualCopy C  recipe C: ordinary positive
```

가상 현상 결과를 source file이나 다른 copy의 recipe에 bake하지 않는다.

### 2.2 지원 input의 정확한 뜻

현재 macOS 설명은 “디지털 카메라가 이미 display render한 이미지”를 대상으로 한다. scene reconstruction은
클리핑으로 사라진 highlight를 복원하지 않고, 눌린 shoulder를 전역 단조 곡선으로 다시 펼치는 근사다.

Windows v1에서 안전하게 지원할 신호:

- embedded/assigned ICC가 검증된 JPEG, PNG, TIFF 등 rendered digital image
- WIC/codec decode 뒤 source profile을 거쳐 canonical working-linear로 변환된 image
- alpha와 orientation이 정규화된 image

별도 계약 없이 같은 경로에 넣지 않을 신호:

- camera mosaic/raw sensor values
- log/scene-linear EXR/HDR
- 이미 film emulation을 bake한 source
- negative/positive film scan
- profile이 없고 의미를 추정할 수 없는 wide-gamut numeric values

camera RAW를 LibRaw로 decode할 수 있다는 사실만으로 이 scene reconstruction이 맞는 것은 아니다. RAW가
camera-rendered state인지 scene-linear state인지 metadata로 구분하고, v1에 scene-linear RAW path가 없다면
visible unsupported/ordinary digital develop 선택을 제공한다.

### 2.3 source kind는 recipe와 asset metadata를 구분한다

권장 내부 모델:

```text
SourceSignalKind
  filmNegativeScan
  filmPositiveScan
  renderedDigital
  sceneLinearDigital       // future, current virtual develop과 다른 entrance
  unknown

DevelopmentProcess
  c41
  e6
  d76
  bwReversal
  digitalColor
  digitalBW
```

`SourceSignalKind`는 file/decode 의미이고 `DevelopmentProcess`는 사용자가 선택한 처리 의미다. 사용자가 잘못된
조합을 골랐을 때 source bytes를 다시 분류하지 않고 경고·확인·recipe 변경으로 처리한다.

## 3. 현재 macOS 코드에서 확인한 사실

### 3.1 파일과 규모

현재 `Sources/Chromabase/Digital/`에는 8개 Swift 파일, 총 1,184줄이 있다.

| 파일 | 현재 줄 수 | 책임 |
|---|---:|---|
| `DigitalFilmLook.swift` | 135 | graph orchestration, stock color, final mix |
| `DigitalSceneReconstruct.swift` | 62 | camera shoulder inverse-like reconstruction |
| `DigitalFilmDevelop.swift` | 191 | density, inter-image, paper/reversal branch |
| `DigitalFilmPhysics.swift` | 363 | 11 stock physical parameters |
| `DigitalHalation.swift` | 64 | three blur branches + energy redistribution |
| `DigitalFilmGrain.swift` | 55 | random field + density-dependent grain |
| `DigitalFilmColorPreset.swift` | 282 | stock-specific grading/mixer/calibration |
| `DigitalFilmColorPresetStage.swift` | 32 | linear↔display transfer and preset stages |

줄 수는 설계 contract가 아니며 source가 바뀌면 inventory를 다시 생성한다.

### 3.2 현재 10개 custom kernel

```text
digitalSceneReconstruct
digitalFilmDensity
digitalInterImage
digitalPrintPaper
digitalReversalTransmit
digitalHalation
digitalToDisplayGamma
digitalToLinearLight
digitalFilmColor
digitalFilmGrainDensity
```

`ToneMapperControlsTests`가 전체 registered kernel 목록에서 10개 이름을 모두 고정한다.
`DigitalFilmLookTests.testDigitalKernelsCompile`의 지역 목록은 gamma 변환 2개를 제외한 8개를 직접 확인한다.
Windows에서는 kernel manifest test 하나를 source of truth로 두어 중복 목록 drift를 줄인다.

### 3.3 현재 stock

`.none`을 제외한 11종이다.

```text
reversal
  ektachromeE100
  provia100F
  velvia50

negative
  portra160
  portra400
  portra800
  ektar100
  ultramax400
  colorPlus200
  fujicolorC200
  pro400H
```

`isReversal`이 paper/transmission branch를 정한다. UI 그룹은 source process와 독립이다. 즉 Digital Color 위에
negative-stock look 또는 reversal-stock look을 선택할 수 있다.

### 3.4 full engine 안의 위치

`applyPostPipeline`에서 확인되는 실제 순서:

```text
positive/negative base develop
  → user PointCurve
  → user ColorMixer
  → user ColorGrading
  → user Calibration
  → if digital source: DigitalFilmLook
     else: ordinary FilmEmulationStage
  → Software Defect Removal
  → Noise Reduction
  → Local Dodge/Burn
  → generic Texture
     digital + selected film이면 grain/halation만 0으로 비워 이중 적용 방지
  → B&W final neutralization + optional B&W toning
  → ImageTransform crop/rotate/straighten
```

따라서 가상 현상은 source decode 직후의 독립 필터가 아니다. 사용자의 기본 tone/color adjustment 뒤,
defect/denoise/local/geometry 앞에 있다. Windows가 순서를 “더 자연스럽다”는 이유로 바꾸면 같은 slider와
recipe가 다른 결과를 낸다.

### 3.5 preview와 export

현재 export snapshot은 `DevelopParameters`를 그대로 보유하고 `ExportDevelopedFrameRenderer`가 최종적으로
`ChromabaseEngine.developScanner`를 호출한다. 따라서 digital film look은 display-only가 아니라 다음 모두에
적용된다.

- fast/settled develop preview
- thumbnail, 호출 경로와 generation 정책에 따라
- normal export
- print composite용 developed input
- batch export

`rawScanTIFF`처럼 의도적으로 develop graph를 우회하는 artifact는 예외다.

### 3.6 persistence compatibility

현재 `DevelopParameters.isDigitalSource`는 optional `Bool`이다.

- `nil`: 기존 film recipe, key 자체를 encode하지 않아 old fingerprint 보존
- `true`: digital source
- `false`: decode 가능하지만 정상 저장은 `nil`을 사용

새 recipe의 `filmEmulationIntensity` 기본은 `0.5`다. 이 key가 없던 legacy recipe는 과거 출력 보존을 위해
decode 시 `1.0`을 쓴다. Windows migration이 struct default 하나만 적용하면 기존 결과가 바뀐다.

## 4. 현재 코드에서 발견한 경계와 위험

### 4.1 invalid negative + digital marker

UI의 `DevelopmentProcess`는 negative film type에 `isDigitalSource == true`가 남아 있으면 C-41/D-76으로
표시한다. 하지만 engine post pipeline의 분기는 현재 `params.isDigitalSource == true`만 확인한다.

즉 다음 두 사실은 다르다.

```text
UI process mapping: negative + true → film process로 표시
engine post graph:  true           → DigitalFilmLook 호출
```

현재 `testNegativeFilmNeverEntersDigitalPath`는 실제 render path를 검증하지 않고
`filmType.requiresInversion`만 확인한다. 따라서 invalid persisted combination이 실제로 digital graph를 피한다는
증거가 아니다.

Windows에서는 snapshot validation으로 다음을 강제한다.

```text
digitalColor → colorPositive + renderedDigital
digitalBW    → bwPositive + renderedDigital
negative film type + digital marker → migration/repair 또는 visible invalid recipe
```

조용히 UI만 film으로 보이게 한 채 engine은 digital path를 타게 하지 않는다.

### 4.2 stage failure가 현재는 identity로 숨을 수 있음

현재 여러 Swift stage는 Metal kernel이나 Core Image filter 생성이 실패하면 input image를 그대로 반환한다.
그 결과 일부 stage만 빠진 “부분 필름”이 성공처럼 표시될 수 있다.

Windows 목표 contract:

- graph compile/registration을 render 전에 검증
- required stage 하나가 없으면 hardware graph를 사용하지 않음
- complete CPU graph로 job 전체를 재계획
- CPU도 없으면 visible render/export error
- 실패한 partial result를 thumbnail/cache/export로 publish하지 않음

### 4.3 texture override의 0 의미가 겹침

현재 digital selected-film에서 grain/halation parameter가 `0`이면 “명시적 off”가 아니라 “stock default를
사용”한다. 0보다 큰 값만 override다. 반면 ordinary texture path에서는 0이 off다.

Windows canonical recipe는 의미를 명시하는 편이 안전하다.

```text
TextureOverride<T>
  stockDefault
  explicit(value: 0...1)   // explicit 0이면 진짜 off를 지원할지 product 결정 필요
```

macOS recipe migration에서는 기존 `0`을 `stockDefault`로 읽어 결과를 보존한다. 새로운 “완전 끄기” UI를
제공할지는 별도 제품 결정이며 기존 numeric field 의미를 조용히 바꾸지 않는다.

### 4.4 noise seed가 recipe에 없음

현재 grain은 `CIRandomGenerator`를 사용하고 explicit seed를 저장하지 않는다. 이는 다음을 보장하지 못한다.

- 같은 frame의 반복 render byte identity
- tile 순서 독립성
- preview/export 같은 grain placement
- retry한 export의 같은 hash
- macOS/Windows pixel-for-pixel noise

Windows는 deterministic noise contract를 가져야 한다. cross-platform exact grain까지 요구하면 macOS에도 같은
integer hash/seed contract를 도입해야 하므로 현재 Windows 문서에서는 다음처럼 등급을 나눈다.

- deterministic stages: macOS/Windows numeric parity
- stochastic grain disabled: exact/epsilon image parity
- grain enabled: 우선 통계·스펙트럼 parity
- shared seeded algorithm 도입 뒤: pixel parity 승격

### 4.5 grain size가 pixel 단위

현재 stock grain size는 약 1.1–1.6 pixel이고 noise image를 그 배율로 scale한다. halation radius는 frame
크기 비율이므로 proxy/full resolution에서 상대 모양이 유지되지만 grain size는 그렇지 않다.

print composite는 develop 전에 proxy downscale할 수 있으므로 현재 의미상 다음 위험이 있다.

- full export와 small-cell print의 grain scale 불일치
- preview proxy와 full output의 grain placement/크기 불일치
- source megapixel 수가 다른 사진의 시각적 grain 크기 불일치

초기 parity build는 current pixel rule을 `digital-film-v1`로 명시해 옮긴다. 새로운 resolution-independent
grain은 `v2` recipe/algorithm migration 없이 기존 결과에 적용하지 않는다.

## 5. canonical recipe와 algorithm identity

권장 snapshot 필드:

```text
DigitalFilmRecipe
  schemaVersion
  algorithmVersion
  sourceSignalKind
  developmentProcess
  stockId
  intensity
  grainOverrideMode/value
  halationOverrideMode/value
  noiseSeed
  stockManifestVersion
  workingColorContractVersion
  renderGraphVersion
```

일반 develop recipe의 film/type/tone/color/local/geometry 필드와 합쳐 immutable snapshot을 만든다.

### 5.1 algorithm version

parameter 값이 같아도 다음이 바뀌면 output이 바뀔 수 있다.

- scene reconstruction formula
- soft-limit formula 또는 constants
- transfer function threshold
- color preset coefficients
- blur kernel/radius mapping
- random field/hash
- grain resolution semantics
- acutance kernel
- final mix domain

따라서 cache key와 export manifest에는 단순 app version이 아니라 `algorithmVersion`과 component hashes를
넣는다. old catalog를 열었다고 recipe를 최신 math로 암묵 재해석하지 않는다.

### 5.2 stock manifest

Swift와 C++에 같은 숫자를 손으로 복제하지 않는 것이 목표다.

```text
StockManifest
  id, displayKey, kind
  gamma[3]
  latitudeStops
  toeSoftness, shoulderSoftness
  layerSpeed[3], layerDmax[3]
  interImage[3]
  scatterStrength[3], halationStrength[3]
  halationRadiusRatio
  grain { amplitude, chromaRatio, size, provenance }
  colorSignature
  qualitativeColorPreset
  acutance reference
  per-field provenance/source IDs
```

manifest는 bundled read-only resource이고 hash/version을 검증한다. 손상되거나 unknown version이면 stock을
`.none`으로 조용히 바꾸지 않는다.

### 5.3 provenance 등급

현재 `DigitalFilmDataProvenance` enum은 grain에 대해서만 `datasheet`/`inferred`를 표현한다. paper Dmax,
negative base, reversal limits 등 모든 상수의 provenance를 type으로 소유하는 것은 아니다.

Windows manifest는 최소 다음을 구분한다.

| 등급 | 뜻 | 제품 표현 |
|---|---|---|
| `manufacturerNumeric` | 제조사 수치를 직접 옮김 | source 문서/페이지/단위 필요 |
| `manufacturerQualitative` | 제조사 정성 설명을 방향으로 모델링 | 실측값처럼 표기 금지 |
| `secondaryLiterature` | 공개 사진과학 문헌 | exact citation 필요 |
| `inferredWithinFamily` | 같은 계열/감도에서 유추 | 추정임을 명시 |
| `renderingDecision` | 결과 품질·범위용 제품 결정 | device-accurate 주장 금지 |
| `measuredNegaflow` | 허가된 fixture/target으로 측정 | 장비·조건·raw data 필요 |

ColorPlus/C200 같은 정성 preset을 “제조사 분광 측정값”으로 표현하지 않는다.

## 6. 전체 파이프라인과 숫자 도메인

### 6.1 entrance

DigitalFilmLook entrance의 canonical domain:

```text
primaries      linear-sRGB working primaries, 현행 기준
transfer       linear working values
range          extended float, 음수/1 초과 가능
alpha          straight/premultiplied contract를 graph edge에 명시; 사진 본체는 통상 1
extent         full logical image extent before final ImageTransform
orientation    decode normalization 완료
```

“camera-rendered”는 tone characteristics를 뜻하며 input texture가 sRGB transfer 그대로라는 뜻이 아니다.
source ICC decode와 working color transform 뒤의 linear numeric domain에서 현재 식을 재현한다.

### 6.2 graph domain map

| stage | input domain | output domain | 의도적 제한 |
|---|---|---|---|
| scene reconstruct | working linear camera render | estimated exposure-like linear | `maxGain` 곡선 |
| halation | exposure-like linear | exposure-like linear | keep/scatter weights |
| film density | positive exposure | signed relative density | input floor `1e-5`, soft limits |
| inter-image | signed density | signed density | denominator floor |
| paper/reversal | signed density | linear reflectance/transmittance | medium soft limits |
| film color | linear reflectance | linear reflectance | 내부 sRGB transfer, 하한 clamp |
| preset entrance | linear reflectance | sRGB-display numeric | standard transfer |
| mixer/grading/calibration | display 0…1 assumption | display-domain adjusted | 각 기존 stage 내부 clamp |
| preset exit | display numeric | linear reflectance | standard inverse transfer |
| grain | linear reflectance | perturbed linear reflectance | density conversion/input floor |
| acutance | linear working | linear working | Core Image semantics 측정 필요 |
| mix | original/rendered 같은 working domain | working linear | amount clamp |

중간 surface가 UNORM이면 signed density와 >1 highlight가 사라진다. 모든 graph 분할 지점에서
`D2D1_BUFFER_PRECISION_32BPC_FLOAT`/`R32G32B32A32_FLOAT`을 요청·검증한다.

## 7. stage별 이식 계약

### 7.1 scene reconstruction

현재 상수:

```text
midGray = 0.18
maxGain = 3.5
```

CPU oracle과 HLSL은 같은 계수 생성과 식을 사용한다.

```text
a      = 1 - midGray
dmin   = a / maxGain
om     = 1 - v
denom  = 0.5 * (om + sqrt(om² + 4*dmin²))
scale  = denom(midGray) / a
out    = a * v / denom * scale
```

불변식:

- `v = 0.18`은 약 0.18
- finite input 범위에서 단조 증가
- highlight gain이 shadow gain보다 큼
- clipped white에서 새 detail을 만들었다고 주장하지 않음
- negative channel이 들어올 때 sqrt domain과 output policy를 test

Windows HLSL과 CPU에서 fast-math 재결합으로 anchor가 움직이지 않게 tolerance를 고정한다.

### 7.2 halation/scatter

radius는 `min(fullExtent.width, fullExtent.height)` 기준이다.

```text
farRadius  = max(1.0, reference * halationRadiusRatio)
nearRadius = max(0.6, farRadius * 0.28)
wideRadius = farRadius * sqrt(2)
```

세 blur는 같은 image의 서로 다른 kernel footprint다. 하나의 blur texture를 단순 확대해 대체하지 않는다.

combine:

```text
far  = farBlur * 0.68 + wideBlur * 0.32
keep = max(1 - scatter - halation, 0)
out  = source*keep + nearBlur*scatter + far*halation
```

edge contract가 특히 중요하다. macOS는 `clampedToExtent()` 뒤 Gaussian blur하고 original extent로 crop한다.
Direct2D built-in Gaussian blur의 `HARD` border는 mirror-type이다. 동일하지 않다.

Windows 후보 graph:

```text
source
  → D2D Border effect, X/Y = CLAMP(edge repeat), infinite logical extension
  → Gaussian blur, calibrated radius/standard-deviation mapping
  → crop to requested expanded ROI
```

Core Image `inputRadius`와 Direct2D `StandardDeviation` 숫자를 1:1이라고 가정하지 않는다. impulse image의
kernel profile, half-energy radius, edge response로 mapping을 측정한다.

검증:

- uniform field energy 보존
- bright impulse 주변 R contribution > B contribution
- full-frame edge에서 dark seam 없음
- tile boundary가 full-frame reference와 같음
- preview/full resolution에서 normalized radius가 같음

### 7.3 film density

핵심 순서:

```text
e = max(rgb, 1e-5)
stops = (log2(e/0.18) + layerSpeed) * exposureScale
density = gamma * 0.30103 * stops * polarity
positive/negative lobes를 각 softLimit
layerDmax로 channel별 limit 조정
```

`polarity`:

- negative stock: `+1`
- reversal stock: `-1`

주의:

- signed density가 정상이다.
- `0.30103`은 현재 source constant다. `log10(2)`를 backend별로 다시 계산해 미세 drift를 만들지 않는다.
- input floor는 알고리즘 clamp다. surface clamp와 다르다.
- `layerSpeed`와 `layerDmax`를 RGB display primary 의미로 임의 재해석하지 않는다. 현재 모델 parameter
  ordering을 그대로 옮긴다.

### 7.4 soft limit 중복 방지

density characteristic curve와 final paper/transmission 모두 끝단을 제한한다. 같은 physical limit를 두 번
강하게 적용하면 tone range가 안쪽으로 수축한다.

현재 reversal transmission은 density limit 뒤에 다음 headroom을 쓴다.

```text
Dmax = reversalDmax * 1.2
Dmin = reversalDmin * 1.15
knee = 3.0
```

이 숫자를 “정리”해 density stage와 똑같이 만들지 않는다. Windows test는 linear output만이 아니라 실제 SDR
display transform 뒤 black/white/highlight steps도 측정한다.

### 7.5 inter-image coupling

현재 식:

```text
others = (sum(density) - densityChannel) * 0.5
out = (density - k*others) / max(1-k, 1e-3)
```

불변식:

- equal RGB density는 보존
- chromatic channel spread는 parameter 방향대로 증가
- k가 invalid range면 snapshot validation에서 거부/clamp policy 명시
- NaN/Inf가 다음 paper stage로 조용히 전파되지 않음

### 7.6 negative paper branch

현재 공통 RA-4 render constants:

```text
paperGamma = 1.70
paperDmax  = 1.52
paperDmin  = 0.790
paperKnee  = 2.4
```

식의 핵심은 negative density 부호를 뒤집어 paper exposure로 읽고, paper density를 다시 reflectance로
바꾸는 2단 구조다.

```text
stops = -negativeDensity / 0.30103
paperDensity = paperGamma * 0.30103 * stops
soft-limit positive/negative lobes
reflectance = 0.18 * 10^(-limitedDensity)
```

이 상수는 특정 실제 인화지/profile을 측정한 device-accurate 값으로 홍보하지 않는다. 현재 source comment상
일부는 rendering decision이다.

### 7.7 reversal transmission branch

반전 stock은 paper 단계를 지나지 않는다.

```text
limitedDensity = softLimit signed density with headroom
transmittance = 0.18 * 10^(-limitedDensity)
```

negative와 reversal branch는 동시에 실행하거나 나중에 mix하지 않는다. stock manifest의 kind가 하나를
선택하고 unknown kind는 error다.

### 7.8 stock color signature

`DigitalFilmColor`은 기존 `FilmEmulationProfile`에서 다음을 읽는다.

- 3×3 color matrix와 channel lift
- shadow/highlight tint
- six hue anchors
- exposure/chroma-weighted inter-image saturation

대비/특성곡선 전체를 다시 적용하지 않는다. 가상 현상에서 tone을 이미 만들었기 때문이다.

kernel 내부에서 linear→sRGB transfer, color math, sRGB→linear를 수행한다. caller가 이 stage 앞뒤에 다시 같은
transfer를 추가하지 않는다.

### 7.9 stock color preset stage

기존 문서의 미해결 항목은 코드로 해소됐다. 이 stage는 `DigitalFilmColor` 중복 호출이 아니다. stock별
정성적 color direction을 기존 세 adjustment stage로 추가한다.

정확한 순서:

```text
linear reflectance
  → digitalToDisplayGamma
  → ColorMixerStage(stock preset)
  → ColorGradingStage(stock preset)
  → CalibrationStage(stock preset)
  → digitalToLinearLight
```

사용자의 mixer/grading/calibration은 full post pipeline 앞부분에서 이미 적용됐다. 여기서는 stock preset의
별도 parameter를 사용한다. 두 parameter set을 합쳐 순서를 바꾸면 nonlinear stage 때문에 결과가 달라진다.

### 7.10 density-dependent grain

현재 implementation은 final reflectance를 다시 optical-density-like 값으로 읽고 noise를 더한 뒤 reflectance로
되돌린다.

```text
v          = max(rgb, 1e-5)
density    = -log10(v / 0.18)
physical   = sqrt(max(density, 0) + 0.02)
t          = (density - 1.0) / 1.15
perceptual = exp(-t²)
amplitude  = stockAmplitude * strength * physical * perceptual
noise      = luma/chroma mixture of centered RGB noise
out        = 0.18 * 10^(-(density + noise*amplitude))
```

generic Texture grain과 수학이 다르다. digital selected-film에서는 generic grain/halation을 post texture stage에서
0으로 만들어 이중 적용을 막는다. sharpness/clarity/vignette는 그대로 남긴다.

### 7.11 acutance

현재는 `FilmEmulationProfile.acutance`의 radius/intensity를 `CIUnsharpMask`에 전달하고 intensity에 film strength를
곱한다.

Direct2D built-in 효과 이름이 비슷하다고 동일하다고 가정하지 않는다. Windows 기준 구현 후보:

```text
blur = calibratedGaussian(source, radius)
detail = source - blur
out = source + intensity * detail
```

하지만 Core Image가 channel/luma, edge mode, premultiplication, radius에 적용하는 정확한 semantics를 impulse,
step-edge, saturated edge fixture로 측정한 뒤 식을 확정한다. 이 stage는 sharpness slider의 generic texture와
별개다.

### 7.12 final mix

물리 chain 중간에 intensity를 분산하지 않고 완성된 rendered result와 original을 마지막에 섞는다.

```text
amount = clamp(intensity, 0, 1)
amount <= 1e-3 → original
amount >= 0.999 → rendered
그 사이 → CIMix reference와 같은 domain/alpha semantics
```

Windows 기본 의도는 같은 working-linear domain의 `lerp(original, rendered, amount)`다. 그러나 Core Image
`CIMix`의 현재 working/output color-space, alpha, extended-range semantics를 macOS float fixture로 먼저
측정한다. 0과 1만 비교하면 domain 차이를 잡지 못하므로 0.25/0.5/0.75를 포함한다.

## 8. Windows effect graph 배치

### 8.1 pointwise path

다음은 Direct2D custom pixel effect 후보이다.

- scene reconstruction
- film density
- inter-image coupling
- paper 또는 reversal
- stock color signature
- transfer functions
- stock color preset의 custom color stages
- grain combine
- final mix

공통 effect ABI:

- input count와 domain 명시
- plain constant buffer layout, packing static assert
- absolute/output/input rectangle mapping
- output precision 32-bpc float
- shader bytecode hash/version
- CPU oracle function ID

### 8.2 spatial path

- halation: Border(CLAMP) + Gaussian blur 3종 + custom combine
- acutance: calibrated blur + custom combine
- grain source: deterministic procedural texture/effect

Direct2D custom effects는 pixel/vertex/compute transform을 구성할 수 있지만, v1은 pointwise pixel effect와
built-in spatial effect로 시작한다. D3D11 compute는 blur나 noise generation이 실제 critical path이고 같은
resource/ROI contract가 더 단순해질 때만 채택한다.

### 8.3 shader linking

Direct2D는 adjacent compatible pixel transforms를 runtime에 link할 수 있다. 다음을 보장하지 않는다.

- 고정 pass 수
- 모든 vendor에서 같은 fusion
- multi-input/spatial/compute boundary 통과
- linking on/off의 같은 intermediate allocation

Negaflow contract는 linking on/off에서 결과가 같다는 것이다. 32-bpc intermediate가 없으면 extended value가
clamp될 수 있으므로 graph precision과 intermediate capture를 검증한다.

### 8.4 graph atomicity

다음 두 plan 중 하나만 publish한다.

```text
Plan A: complete validated GPU graph
Plan B: complete CPU graph
```

stage별로 실패할 때 input을 반환해 A/B가 섞인 partial output을 만들지 않는다. CPU와 GPU를 섞는 것은 명시적
transfer plan과 cost/precision test가 있을 때만 허용한다.

## 9. tile, ROI, halo

### 9.1 full logical extent가 parameter다

halation radius를 tile 크기로 계산하면 tile마다 물리가 달라진다. snapshot은 다음을 가진다.

```text
fullLogicalExtent
requestedOutputROI
tileCoreRect
expandedInputRect
absolutePixelOrigin
proxyScale
```

### 9.2 halo

tile input halo는 다음 최대 footprint를 포함한다.

- wide halation blur
- far/near halation blur
- acutance blur
- downstream spatial stage가 같은 tile plan에 있으면 그 footprint

Gaussian의 실효 support는 구현별 무한하지만 실제 kernel truncation/error budget으로 bounded halo를 정한다.
Direct2D 공식 문서의 `standard deviation × 3` radius 설명은 Windows built-in blur의 시작 근거이며, Core Image
parity mapping 뒤 실제 halo를 고정한다.

### 9.3 edge와 crop

- halo가 image 밖으로 나가면 full image edge pixel을 repeat
- tile edge를 image edge로 clamp하지 않음
- crop/rotate/straighten은 현재 순서상 DigitalFilmLook 뒤
- crop된 최종 화면만 보고 halation reference size를 다시 계산하지 않음
- proxy가 먼저 적용된 경로에서는 proxy full extent를 쓰되 normalized radius parity를 test

### 9.4 grain coordinate

noise 함수 입력:

```text
noise(frameSeed, streamId, absoluteX, absoluteY, channel)
```

tile origin, worker ID, dispatch order, preview invalidation count를 seed에 넣지 않는다. generic grain, digital grain,
dither는 서로 다른 `streamId`를 쓴다.

## 10. CPU reference와 SIMD

CPU backend는 모든 stage를 완성해야 한다.

- scalar/reference pointwise math
- separable Gaussian 또는 승인된 정확도 kernel
- deterministic noise
- color mixer/grading/calibration equivalent
- acutance
- final mix

x64 Intel/AMD와 ARM64는 같은 C++ algorithm을 쓴다. SIMD는 [SIMD 문서](../16-cpu/simd-and-dispatch.md)의
runtime dispatch를 따르며 다음 decision kernel은 exact/strict contract를 우선한다.

수동 SIMD 우선 후보:

- pointwise density/paper/transfer chain
- color matrix와 final mix
- noise combine

먼저 보지 않을 것:

- 큰 Gaussian blur를 단순 lane widening만으로 해결
- tile scheduler와 memory bandwidth를 무시한 full-frame temporary
- global fast-math

CPU/GPU `pow`, `log2`, `log10`, `exp` 결과는 bit-identical하지 않을 수 있다. stage별 numeric tolerance와 최종
decision/visual contract를 정의한다. film stock 선택이나 branch 같은 control decision은 float 결과로 바꾸지
않는다.

## 11. UI/UX parity — WinUI 3

### 11.1 process picker

macOS와 같은 6개 항목:

```text
C-41
E-6
D-76
B&W Reversal
Digital Color
Digital B&W
```

표시 문자열과 localization key는 별도지만 recipe ID는 안정적이다. Digital Color/B&W는 내부적으로 positive
film type에 매핑된다.

### 11.2 Film surface

- slide section 3종
- color-negative section 8종
- 같은 row를 다시 누르면 선택 해제
- 별도의 “None” row 없음
- 선택 상태 checkmark
- 한 번에 한 stock
- 선택된 stock이 있을 때만 intensity slider
- 새로 켤 때 intensity 0.5
- stock끼리 바꿀 때 기존 intensity 유지
- slider double-click reset과 keyboard/accessibility equivalent

WinUI에서는 native `ListView`/`ItemsRepeater`/`Slider`와 적절한 automation properties를 사용한다. macOS의
SF Symbol 이름을 그대로 흉내낸 custom raster icon을 만들지 않고 Windows native iconography로 같은 의미만
맞춘다.

### 11.3 before/after와 status

- drag 중 fast preview와 settled preview의 recipe/revision을 구분
- old render가 새 stock 선택 위에 적용되지 않음
- missing GPU capability는 사용자에게 필름 이름이 사라지는 방식으로 나타나지 않음
- CPU fallback 중에도 같은 control/state 유지
- output pending/failed를 last good preview와 구분

### 11.4 copy/paste, preset, virtual copy

다음이 함께 이동해야 한다.

- digital process/source marker
- stock ID
- intensity
- grain/halation override semantics
- algorithm/manifest version
- deterministic seed 정책

film scan에 digital process를 붙이는 paste는 scope validation이 필요하다. virtual copy는 source를 공유하지만
seed를 copy ID에서 파생할지 source ID에서 공유할지 제품 결정을 고정해야 한다. 같은 source의 두 copy가 같은
stock/recipe면 같은 grain을 원한다면 source family seed가 적합하고, 각 copy를 독립 render로 보려면 recipe seed가
적합하다. 추측으로 구현하지 않는다.

## 12. preview, export, print 동등성

### 12.1 동일 graph

preview와 export는 quality/ROI/scale만 다르고 stage order와 constants가 같아야 한다.

```text
same canonical recipe
same stock manifest
same algorithm version
same color-domain transitions
same normalized spatial parameters
same seed contract
```

### 12.2 proxy 허용 범위

proxy에서 허용되는 차이:

- output pixel count
- blur implementation의 scale-adjusted sampling error
- preview display quantization

허용되지 않는 차이:

- 다른 stock parameter
- paper/reversal branch 변경
- grain/halation 이중 적용
- color preset 생략
- 8-bit intermediate
- different ICC interpretation
- crop 때문에 radius 기준 변경

### 12.3 export snapshot

render 시작 전에 source identity, recipe, algorithm/manifest/shader hashes, output color recipe를 고정한다. render
완료 뒤 source identity와 job revision을 재확인하고 그 뒤에만 artifact를 publish한다.

필수 stage를 재구성하지 못하면 original image를 대신 export하지 않는다.

### 12.4 print composite

small cell을 위해 develop 전 proxy decode/scale을 허용할 수 있지만 다음을 따로 검증한다.

- requested cell resolution 충족
- normalized halation radius
- acutance radius scaling
- grain size/version semantics
- output ICC가 page composer 단계에서 한 번만 적용
- 여러 cell이 같은 shared render target을 동시에 mutate하지 않음

## 13. 색 관리

### 13.1 source

- embedded ICC 우선
- profile이 없을 때 format/source policy를 명시
- WIC가 decoder convenience conversion으로 어떤 color space를 만들었는지 기록
- source-encoded value에 scene reconstruction을 바로 적용하지 않음

### 13.2 working

현재 cross-platform reference는 linear-sRGB primaries다. sRGB transfer function을 shader에서 명시적으로
사용하는 두 구간은 stock color/preset algorithm의 일부다. Windows Color Management가 자동으로 이 transfer를
대신한다고 생각해 제거하지 않는다.

### 13.3 display/export

DigitalFilmLook output은 아직 working image다. 다음을 내부에서 하지 않는다.

- monitor ICC transform
- soft proof printer transform
- output gamut mapping
- JPEG/TIFF quantization

이는 공통 output boundary가 담당한다. 같은 working output에서 display와 export가 갈라진다.

## 14. 테스트 계약

### 14.1 current macOS property tests를 이식

- film source path `nil`/false marker 동등성
- digital path와 ordinary film LUT path 분리
- 10개 kernel manifest
- scene mid-gray anchor
- scene monotonic highlight expansion
- 모든 stock develop mid-gray 보존
- inter-image neutral 보존/chroma separation
- negative highlight latitude > reversal
- uniform halation energy conservation
- red-biased highlight halo
- density-dependent grain
- fine/coarse stock grain ordering
- intensity zero identity
- `.none` identity
- highlight step preservation
- generic texture grain double-application 방지
- stock color direction/order/distinguishability
- neutral cast bound
- saturated patch bound
- tonal crossover
- no true black/white product range
- negative/reversal black ordering
- contrast ordering

### 14.2 현재 coverage gap도 그대로 기록

- invalid negative + digital marker가 실제 engine graph를 피하는지 render test 없음
- `CIMix` 0.25/0.5/0.75 domain/alpha fixture 없음
- display transform 뒤 tone-range guard 부족
- deterministic grain seed/tile parity 없음
- proxy/full-resolution grain-scale parity 없음
- export/preview 동일 snapshot pixel comparison 부족
- Core Image blur와 Direct2D blur impulse equivalence 미측정
- missing kernel에서 partial identity output이 publish되지 않는 failure test 부족

Windows acceptance는 이 gap을 포함해 보완한다.

### 14.3 stage fixtures

```text
uniform gray: 0, 1e-5, 0.003, 0.18, 0.5, 0.98, 1, 3.5
signed RGB: negative/positive channel mixtures
ramp: 0…1 and extended -0.25…4
step edge: vertical/horizontal/diagonal
impulse: center, edge, corner
color patches: neutral, skin, red, green, blue, cyan, magenta, yellow
dimensions: 1, odd, vector-width±1, tile-boundary±1
stride/alignment: packed, padded, unaligned ROI
```

### 14.4 comparison levels

| level | 비교 |
|---|---|
| stage scalar vs HLSL | float numeric tolerance, monotonic/property |
| CPU x64 vs ARM64 | strict decision + numeric tolerance |
| D3D hardware vendors | WARP/reference + corpus error |
| macOS vs Windows no grain | working float + display encoded output |
| grain statistical | mean, variance, channel covariance, radial spectrum, density response |
| UI preview/export | same recipe/scale-normalized visual and metadata |

single average RGB만으로 spatial/color preset을 승인하지 않는다.

### 14.5 device matrix

- WARP
- Intel x64 iGPU
- AMD x64 iGPU/dGPU
- NVIDIA x64 dGPU
- Qualcomm Windows ARM64
- CPU scalar/SIMD x64 Intel/AMD
- CPU ARM64

Debug layer와 32-bpc support query 통과만으로 image parity를 대신하지 않는다.

## 15. 성능과 메모리

### 15.1 먼저 측정할 항목

- three Gaussian branches의 pixels/bytes/time
- stock color/preset pointwise chain pass 수
- 32-bpc intermediate peak VRAM
- tile halo duplication
- grain generation/materialization
- preview first result와 settled result
- 55MP full export
- multi-file batch throughput

### 15.2 최적화 순서

1. graph lifetime과 unnecessary materialization 제거
2. ROI/tiling과 blur cache
3. Direct2D shader linking 실제 결과 확인
4. shared blur producer 재사용 가능성 확인
5. CPU/GPU residency 유지
6. pointwise fusion, 조합 폭발 없이 제한
7. compute blur/noise 후보
8. CUDA는 공통 path가 충분히 검증된 뒤 NVIDIA에서만 비교

### 15.3 blur reuse 주의

near/far/wide는 다른 radius라 texture 하나를 재사용할 수 없지만, 같은 source/stock/scale/revision에서 다른
consumer가 정확히 같은 radius와 edge contract를 요청한다면 graph cache가 결과를 공유할 수 있다. float radius
근사값만 같다고 cache key를 합치지 않는다.

### 15.4 memory budget

55MP `R32G32B32A32_FLOAT` 한 장은 약 880MB다. source와 blur 3종, density, color, output을 full-frame으로
동시에 materialize하면 수 GB가 된다. 따라서:

- tile + halo
- lifetime analysis
- sequential blur combine 또는 bounded cache
- byte-based admission
- foreground preview/export priority
- device budget pressure fallback

이 필요하다. 메모리를 줄이려고 16-bit/UNORM으로 조용히 강등하지 않는다.

## 16. 오류·fallback·진단

### 16.1 validation error

- unknown stock ID
- invalid stock kind
- missing/corrupt manifest
- non-finite parameters
- invalid source/process combination
- unsupported input signal kind
- dimensions/stride/ROI overflow

이 경우 recipe를 `.none`으로 바꾸지 않는다. catalog에는 원래 값을 보존하고 해당 render를 visible failure로
표시한다.

### 16.2 backend fallback

```text
GPU graph capability/compile/runtime validation 실패
  → 같은 immutable snapshot으로 complete CPU graph
  → CPU 성공 시 fallback reason과 backend를 manifest에 기록
  → CPU 실패 시 job 실패, last good preview와 구분
```

GPU partial image를 CPU chain 중간 입력으로 쓰지 않는다. 명시적으로 승인된 hybrid plan이 있을 때만 예외다.

### 16.3 diagnostics

```text
operationId
frameId/revision
sourceSignalKind
stockId, stockManifestVersion
algorithm/renderGraph/shader versions
backend + adapter/driver 또는 CPU tier
working precision
tile geometry/halo
noise seed/stream version, 원본 seed 노출 정책에 따라 hash 가능
stage timings
fallback/failure reason
```

사용자 source path나 파일 내용을 ETW에 기록하지 않는다.

## 17. 구현 단계

### 단계 0 — oracle과 manifest

- 11 stock constants/provenance inventory
- versioned canonical manifest
- C++ scalar pointwise oracle
- macOS float fixture export 절차
- recipe migration: `nil/true`, legacy intensity 1.0

완료 조건: GPU 없이 deterministic stage 결과를 재생할 수 있음.

### 단계 1 — pointwise graph

- scene/density/inter-image/paper/reversal
- stock color
- transfer + stock preset stages
- final mix
- 32-bpc precision enforcement

완료 조건: grain/halation/acutance를 끈 11 stock cross-platform corpus 통과.

### 단계 2 — spatial graph

- CLAMP border
- calibrated Gaussian mapping
- three-radius halation
- acutance
- tile/halo equivalence

완료 조건: full-frame/tile, edge/interior, WARP/vendor/CPU parity.

### 단계 3 — deterministic grain

- seed ownership 결정
- integer noise spec
- absolute-coordinate CPU/HLSL implementation
- statistical and tile parity
- proxy/full-resolution v1 behavior 고정

완료 조건: retry/tile order/backend가 결과를 바꾸지 않음.

### 단계 4 — app integration

- WinUI process picker/Film surface
- immutable revisioned preview
- copy/paste/preset/virtual copy
- export/print snapshots
- failure/fallback status

완료 조건: macOS와 같은 user flow, stale render 방지, preview/export recipe 동일.

### 단계 5 — optimization

- physical vendor profiling
- linking/materialization/VRAM audit
- CPU SIMD
- optional compute
- CUDA는 별도 gate

완료 조건: 품질/정확성/출력 설정을 낮추지 않은 end-to-end 개선.

## 18. 금지 목록

- 가상 현상을 3D LUT 하나로 축소
- film scan에 digital graph 이중 적용
- camera RAW와 rendered JPEG를 같은 signal kind로 추정
- source ICC 이전 numeric values에 scene reconstruction 적용
- stage 순서 변경
- density/paper soft limit를 같은 값으로 합침
- display-domain stock preset 전후 transfer 삭제
- generic grain/halation과 digital stock texture 이중 적용
- Direct2D Gaussian `HARD` mirror edge를 macOS clamp와 같다고 간주
- Core Image radius와 Direct2D standard deviation을 숫자 1:1로 복사
- 중간 surface를 UNORM/8-bit로 생성
- missing shader를 identity로 숨긴 partial result publish
- random seed에 tile/worker/render order 사용
- preview와 export에 다른 stock constants 사용
- 정성 preset을 실측 spectral profile로 표현
- NVIDIA CUDA만으로 기능 구현
- 사용자-visible 이름만 같고 export graph가 다른 가짜 UI parity

## 19. 미해결 결정

### 출하 전에 반드시 닫기

- [ ] `CIMix`의 현재 working-space/alpha/extended-range 수치 fixture
- [ ] Core Image Gaussian radius ↔ Direct2D standard-deviation mapping
- [ ] `CIUnsharpMask` ↔ Windows acutance mapping
- [ ] deterministic seed ownership: source family, virtual copy, recipe 중 무엇인가
- [ ] explicit grain/halation off를 새 schema에서 제공할지
- [ ] pixel-based grain v1을 언제 resolution-independent v2로 전환할지
- [ ] rendered digital과 scene-linear RAW UX를 어떻게 구분할지
- [ ] invalid negative+digital legacy record migration
- [ ] stock field별 source/provenance ledger

### 구현 후 측정으로 닫기

- [ ] pointwise graph의 실제 Direct2D linking/pass 수
- [ ] three-blur VRAM과 tile halo crossover
- [ ] R32 float support/performance vendor matrix
- [ ] CPU vs D2D vs compute blur
- [ ] 55MP preview/export/batch budget

## 20. 완료 체크리스트

### 의미

- [ ] digital source와 film scan이 명시적으로 분리됨
- [ ] 11 stock과 paper/reversal branch가 고정됨
- [ ] full post-pipeline 순서가 macOS와 같음
- [ ] source signal kind가 decode semantics를 가짐
- [ ] legacy intensity와 optional marker가 migration됨

### 수치

- [ ] 32-bpc working intermediate가 검증됨
- [ ] negative/over-range values가 materialization을 통과함
- [ ] display-domain preset round trip이 유지됨
- [ ] soft-limit 이중 수축 회귀가 없음
- [ ] blur/acutance mapping이 impulse/edge fixture로 고정됨

### 안정성

- [ ] complete GPU 또는 complete CPU plan만 publish됨
- [ ] invalid recipe가 visible failure임
- [ ] source/revision ownership을 publish 직전에 재검증함
- [ ] tile/full-frame 결과가 같음
- [ ] deterministic noise가 backend/order에 독립적임

### 제품

- [ ] WinUI 3 process/Film UX가 native로 동작함
- [ ] selection/intensity/reset/copy-paste/virtual-copy가 보존됨
- [ ] preview/export/print가 같은 recipe/graph version을 사용함
- [ ] physical Intel/AMD/NVIDIA/Qualcomm와 CPU x64/ARM64에서 검증됨
- [ ] device-accurate/film-accurate 주장이 provenance 수준을 넘지 않음

## 21. 공식·직접 근거

Windows rendering:

- [Direct2D custom effects](https://learn.microsoft.com/en-us/windows/win32/direct2d/custom-effects) — HLSL pixel/vertex/compute effect와 transform graph
- [Direct2D effect shader linking](https://learn.microsoft.com/en-us/windows/win32/direct2d/effect-shader-linking) — runtime linking 조건과 hazard
- [Precision and numerical clipping in effect graphs](https://learn.microsoft.com/en-us/windows/win32/direct2d/precision-and-clipping-in-effect-graphs) — 32-bpc intermediate 요청과 graph precision
- [Direct2D Gaussian blur](https://learn.microsoft.com/en-us/windows/win32/direct2d/gaussian-blur) — standard deviation, output growth, soft/hard border
- [Direct2D Border effect](https://learn.microsoft.com/en-us/windows/win32/direct2d/border) — clamp/wrap/mirror edge behavior
- [Direct3D 11 compute shader overview](https://learn.microsoft.com/en-us/windows/win32/direct3d11/direct3d-11-advanced-stages-compute-shader) — optional compute path

macOS reference behavior:

- [Apple `CIGaussianBlur`](https://developer.apple.com/documentation/coreimage/cigaussianblur) — pixel radius parameter
- [Apple `CIUnsharpMask`](https://developer.apple.com/documentation/coreimage/ciunsharpmask) — radius/intensity interface
- [Apple `CIMix`](https://developer.apple.com/documentation/coreimage/cimix) — final mix filter interface
- [Apple `CIRandomGenerator`](https://developer.apple.com/documentation/coreimage/cirandomgenerator) — current noise source interface

manufacturer material examples:

- [Kodak EKTACHROME E100 technical data E-4000](https://kodakprofessional.com/sites/default/files/wysiwyg/pro/resources/e4000_ektachrome_100.pdf)
- [Kodak PORTRA 400 technical data E-4050](https://www.kodakprofessional.com/sites/default/files/2025-07/e4050.pdf)
- [Fujifilm PROVIA 100F official overview](https://www.fujifilm.com/us/en/business/professional-photography/film/provia-100f)
- [Fujifilm PROVIA 100F data sheet](https://asset.fujifilm.com/www/us/files/2020-03/6325e0d91ad8f74448c5968b5a954199/Provia100f.pdf)

manufacturer 자료가 film 성격과 일부 grain/curve/MTF 정보를 제공해도 Windows render constant 전체를 직접
증명하지는 않는다. 각 숫자의 provenance는 별도 ledger로 추적하고 rendering decision을 측정값처럼 표현하지
않는다.
