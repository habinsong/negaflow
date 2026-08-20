# 수치 정밀도와 clipping 계약

상태: 1차 기준선 확정  
최종 코드·공식 문서 대조: 2026-08-04  
대상: CPU/D3D11/Direct2D 렌더의 작업 범위, 중간 surface, alpha, 출력 양자화

---

## 1. 결정

Negaflow의 현상 core는 **linear-sRGB primaries의 float32 계산 의미와 extended numeric range**를
보존한다.

- 작업 RGB는 음수와 1 초과 값을 가질 수 있다.
- GPU 작업 graph의 materialized intermediate는 원칙적으로 `32BPC_FLOAT` 4채널을 요구한다.
- shader register만 float32라는 사실로 충분하지 않다.
- 명시적인 알고리즘 clamp와 출력 clamp를 구분한다.
- GPU가 필요한 precision·연산을 검증하지 못하면 품질을 낮추지 않고 CPU로 간다.
- final export는 hardware GPU 우선이며, WARP 강제 정책은 채택하지 않는다.
- WARP는 compatibility/diagnostic 후보이고 CPU scalar/SIMD가 공식 fallback이다.
- 8-bit/16-bit encoding은 작업 graph가 끝난 뒤 output color transform, dither, quantization 순서로
  처리한다.
- link on/off, vendor, tile 계획에 따라 결과가 달라지지 않아야 한다.

이 계약은 “모든 pixel이 항상 [0,1] 밖에 있다”는 뜻이 아니다. 알고리즘이 특정 stage 안에서
의도적으로 범위를 제한할 수 있다. 중요한 것은 그 위치와 수학이 명시되어야 한다는 뜻이다.

---

## 2. 현재 macOS 기준

현재 코드에서 확인되는 기준:

- `ChromabaseEngine`은 모든 처리를 32-bit float linear 영역에서 한다고 명시한다.
- working color space는 `CGColorSpace.linearSRGB`를 사용한다.
- post pipeline은 작업 이미지에서 음수와 1 초과 값을 보존한다고 명시한다.
- display/file gamut mapping은 출력 경계에서 수행한다.
- 측정용 render는 `.RGBAf`를 사용하는 경로가 있다.
- `gamutSoftClip`, tone-safe 변환, denoise, grain 등 일부 알고리즘 내부에는 의도적 clamp가 있다.
- 8-bit output dither는 export 경계에서 적용한다.

따라서 Windows 문서에서 단순히 “전체 pipeline은 unclamped”라고 쓰면 틀리다. 정확한 계약은:

> graph edge의 기본 작업 범위는 extended float이며, 각 알고리즘 내부의 명시적 clamp만 허용한다.
> 숨은 surface clamp와 backend-dependent clamp는 금지한다.

---

## 3. 왜 Direct2D 기본값만 믿을 수 없는가

Microsoft 공식 문서에 따르면 Direct2D는 effect graph를 여러 section으로 나눠 렌더할 수 있고,
section output을 intermediate Direct3D texture에 저장할 수 있다. 기본 intermediate는 제한된
range와 precision을 가질 수 있다.

중요한 사실:

- intermediate가 생기는 위치는 앱에 보장되지 않는다.
- GPU capability와 Windows 구현에 따라 달라질 수 있다.
- shader linking이 가능한 graph는 intermediate 수가 달라질 수 있다.
- 따라서 같은 HLSL이라도 intermediate format이 잘못되면 환경별 결과가 달라질 수 있다.
- built-in effect도 unpremultiplied 기준 [0,1] 밖의 값을 만들 수 있다.

위험 예:

```text
A: highlight를 1.25로 올림
B: tone curve가 1.25를 0.96으로 압축
```

두 stage 사이가 8-bit UNORM surface에 materialize되면 B는 1.25를 받을 수 없다. A/B가
link된 장치에서는 정상이고 link되지 않은 장치에서는 highlight가 달라지는 식의 조용한 오류가
생긴다.

---

## 4. 숫자 도메인 표

모든 graph node는 다음 중 하나의 domain을 선언한다.

| domain | RGB 범위 | 전달함수 | 대표 용도 |
|---|---|---|---|
| source encoded | format/profile 의존 | source 의존 | decode 직후 |
| working linear extended | 음수 및 1 초과 허용 | linear | core develop |
| normalized algorithm-local | 알고리즘 정의, 보통 [0,1] | 명시 | LUT/마스크/일부 denoise 내부 |
| mask | 보통 [0,1] | scalar linear | local/defect mask |
| display encoded | display mode/profile 의존 | SDR/HDR 명시 | 화면 출력 |
| output encoded | format/profile/bit depth 의존 | output profile | 파일/PRINT |

“float texture”만 표시해서는 부족하다. primaries, transfer, numeric range, alpha가 모두 edge
metadata에 있어야 한다.

---

## 5. 작업 surface 정책

### 5.1 core working graph

기준 format:

```text
R32G32B32A32_FLOAT
D2D1_BUFFER_PRECISION_32BPC_FLOAT
D2D1_CHANNEL_DEPTH_4
```

이는 channel당 32-bit float, pixel당 128-bit다.

적용 대상:

- inversion 이후 작업 이미지
- color/tone stage 사이 intermediate
- extended highlight/negative가 통과하는 spatial intermediate
- film look/emulation output
- output color transform 직전 working master

### 5.2 예외 후보

다음은 증거가 있을 때 낮은 precision을 쓸 수 있다.

- binary/low-range mask
- thumbnail-only display cache
- UI overlay
- 일부 analysis proxy
- final SDR swap-chain buffer

예외마다 다음을 기록한다.

- 허용 format
- 값 범위
- error budget
- downstream 영향
- corpus 결과
- memory/latency 이득

단순히 VRAM을 줄이기 위해 working master를 `16BPC_FLOAT`로 강등하지 않는다. 16-bit float는
범위는 넓지만 mantissa precision이 달라 현재 수학과 동일하다고 가정할 수 없다.

### 5.3 display target

작업 surface와 화면 swap-chain format은 같을 필요가 없다.

- SDR: 최종 display transform 뒤 지원되는 8/10-bit surface 후보
- HDR: OS/monitor/output contract에 맞는 10-bit 또는 16-bit float 후보
- XAML overlay: UI framework의 색 처리와 별도 검증

화면 target이 8-bit여도 working graph intermediate까지 8-bit로 낮추면 안 된다.

### 5.4 export target

export 계산은 32-bit float working graph에서 끝낸 후 encoder가 요구하는 staging format으로
변환한다.

- JPEG: output transform → dither → 8-bit encode
- PNG 8-bit: output transform → dither → 8-bit encode
- PNG 16-bit: output transform → 16-bit quantization/encoder 계약
- TIFF 16-bit: output transform → 16-bit quantization
- TIFF float 후보: format/reader compatibility와 metadata를 별도 결정
- rawScanTIFF: develop graph 우회, source contract 보존

---

## 6. Direct2D precision 제어

### 6.1 capability probe

device/context 생성 후 최소 다음을 확인한다.

```cpp
const bool supports32BpcFloat =
    context->IsBufferPrecisionSupported(
        D2D1_BUFFER_PRECISION_32BPC_FLOAT);
```

boolean 하나만으로 production approval을 내리지 않는다. capability report에는 다음도 포함한다.

- adapter vendor/device/subsystem/revision
- driver version
- D3D feature level
- 32bpc float texture/render-target 지원
- required sampling/filter support
- DirectCompute requirements
- maximum texture dimensions
- shared/system memory class
- actual precision corpus result

API가 지원을 보고해도 shader arithmetic, sampling, driver correctness는 corpus로 확인한다.

### 6.2 context rendering controls

일반 working graph context에는 다음 방향을 사용한다.

```cpp
D2D1_RENDERING_CONTROLS controls{};
context->GetRenderingControls(&controls);
controls.bufferPrecision = D2D1_BUFFER_PRECISION_32BPC_FLOAT;
context->SetRenderingControls(&controls);
```

공식 contract상 이는 effect/transform에 별도 precision이 설정되지 않은 intermediate의 minimum
precision을 제어한다.

주의:

- “요청한 precision”은 minimum이다.
- graph가 intermediate를 만들지 않으면 다른 방식으로 실행될 수 있다.
- Direct2D는 같은/다른 graph의 intermediate를 공유할 수 있고 관련 요청 중 최대 precision을
  선택할 수 있다.
- context setting만 했다고 모든 source/target/compute resource가 자동 32bpc가 되는 것은 아니다.

### 6.3 effect property

특정 effect boundary에 minimum precision을 명시할 수 있다.

```cpp
effect->SetValue(
    D2D1_PROPERTY_PRECISION,
    D2D1_BUFFER_PRECISION_32BPC_FLOAT);
```

공식 contract상 effect에 설정한 precision은 다른 값이 지정되지 않는 한 같은 graph의 downstream
effect로 전파된다.

### 6.4 custom transform output

custom effect 내부에서는 render info에 output buffer를 명시할 수 있다.

```cpp
renderInfo->SetOutputBuffer(
    D2D1_BUFFER_PRECISION_32BPC_FLOAT,
    D2D1_CHANNEL_DEPTH_4);
```

transform-level 설정은 effect-level 설정과 propagation 의미가 다르다. 공식 문서상 transform
output precision은 downstream transform node precision을 자동 결정하지 않는다. 따라서 graph
edge 계약과 실제 intermediate capture가 필요하다.

### 6.5 source/target 기반 추론에 의존하지 않기

precision을 수동 지정하지 않으면 Direct2D는 input bitmap/WIC image source와 render target에서
minimum precision을 추론할 수 있다. branch가 합쳐지면 input 중 높은 precision이 사용될 수
있다.

하지만 다음 문제가 있다.

- command list처럼 자체 precision이 없는 input
- input 없는 effect
- 낮은 precision WIC source
- target-dependent 결과
- graph topology 변경

Negaflow core는 source/target 추론만으로 precision을 정의하지 않는다.

---

## 7. GPU, CPU, WARP 선택

### 7.1 hardware GPU 우선

다음 조건을 모두 만족하면 프리뷰와 export에 hardware GPU를 우선한다.

- required 32bpc float resource/precision 지원
- 필수 HLSL/DirectCompute capability 지원
- extended-range corpus 통과
- ICC/output path 통과
- device/driver quarantine 대상 아님
- end-to-end로 CPU보다 이득

이 정책은 Intel, AMD, NVIDIA, Qualcomm에 동일하게 적용한다.

### 7.2 CPU fallback

공식 fallback은 C++ scalar/SIMD backend다.

- x64 Intel/AMD
- ARM64
- 같은 algorithm version
- 같은 stage order
- 같은 precision 의미
- 같은 output bit depth/ICC/metadata

GPU fallback을 이유로 기능이나 export 품질을 낮추지 않는다.

### 7.3 WARP

Microsoft 공식 문서는 WARP가 실제 GPU와 무관하게 모든 Direct2D buffer precision을 지원하도록
할 수 있고, photo effect를 disk에 저장하는 시나리오 및 feature level 9.x에서 고려할 수 있다고
설명한다.

그러나 Windows Negaflow의 결정은 다음과 같다.

- 모든 export를 WARP로 강제하지 않는다.
- 최소 OS/장치 기준선은 현대 Windows 11 장치군을 대상으로 한다.
- C++ CPU backend가 이미 correctness fallback이다.
- WARP는 CI, diagnostic, 특정 driver compatibility spike에서 평가한다.
- WARP가 hardware GPU와 CPU SIMD보다 실제로 유리한 workload가 입증되면 제한적으로 선택한다.

즉 공식 권고를 무시하는 것이 아니라 제품의 최소 장치·CPU backend·성능 목표를 함께 반영한다.

### 7.4 선택 기록

매 render/export job에 다음을 기록한다.

```text
requested quality
required precision
selected backend
adapter/driver
capability class
fallback reason
precision policy version
shader/CPU algorithm version
```

---

## 8. float 계산 의미

### 8.1 scalar oracle

reference는 C++ float32 계산 의미를 기준으로 하되, 장기 golden 생성에는 필요할 때 double
reference를 함께 사용한다.

- float32는 production target
- double은 error 분석용
- CPU와 GPU 모두 같은 상수 bit pattern 사용
- decimal literal drift를 manifest/test로 방지

### 8.2 FMA와 contraction

GPU는 multiply-add를 융합할 수 있고 CPU compiler도 target에 따라 다르게 최적화할 수 있다.

- bit-identical이 필요한 stage와 tolerance 기반 stage를 분류한다.
- FMA on/off가 branch threshold를 바꾸는지 검사한다.
- histogram/decision logic은 tie-break와 quantization을 명시한다.
- deterministic manifest/hash에 raw float output hash만 무조건 요구하지 않는다.

### 8.3 transcendental

negative inversion과 digital film math는 다음을 사용할 수 있다.

- `log10`
- `exp`
- `pow`
- transfer-function piecewise math

HLSL intrinsic과 CPU standard library는 완전히 같은 비트를 보장하지 않는다.

- domain guard를 동일하게 둔다.
- scalar range corpus를 촘촘히 만든다.
- perceptual/output error와 decision threshold error를 분리한다.
- vendor-specific fast-math로 결과 의미를 바꾸지 않는다.

### 8.4 denormal과 zero

- `+0`/`-0`
- very small positive transmission
- subnormal flush behavior

를 stress한다. negative inversion의 log domain guard처럼 알고리즘에 이미 있는 epsilon을 정확히
이식하고 backend마다 다른 임의 epsilon을 추가하지 않는다.

---

## 9. NaN과 Inf

작업 graph에 NaN/Inf가 들어오면 단순 clamp만으로 안전해지지 않는다.

### 9.1 경계 검증

- decode 직후 dimensions/format/profile 검증
- parameter normalization 시 finite 검증
- film base와 density denominator 검증
- LUT data 검증
- ICC transform 결과 sanity check
- shader constant buffer finite 검증

### 9.2 정책

| 발생 위치 | 정책 |
|---|---|
| 사용자/recipe parameter | 요청 거부 또는 마지막 유효값 유지 |
| corrupt source sample | decoder failure 또는 명시된 sanitize policy |
| measurement result | 해당 자동 측정 실패, manual 경로 제공 |
| shader output | diagnostic counter/capture, release correctness 실패 |
| export staging | export 실패; corrupt 파일을 성공으로 표시하지 않음 |

NaN을 0으로 바꾸는 범용 shader를 graph 끝에 넣어 bug를 숨기지 않는다.

---

## 10. clamp 분류

### 10.1 알고리즘 내부 clamp

현재 kernel에는 수학의 일부로 clamp가 존재한다.

예:

- log domain의 최소 transmission
- tone-safe RGB 변환
- HSL/tonal mask 범위
- guided-filter variance lower bound
- grain/output 제한
- denoise reconstruction 제한
- LUT domain taper
- gamut soft clip

이 clamp는 포팅 시 그대로 검증해야 한다. “extended working이므로 모든 clamp 제거”는 잘못이다.

### 10.2 안전 guard

0으로 나눔, log 음수, invalid exponent를 막는 guard다.

- threshold와 epsilon을 algorithm version에 포함
- CPU/HLSL 동일 상수
- guard 전후 derivative/discontinuity 검사

### 10.3 출력 경계 clamp

다음에서 output encoding range로 정리할 수 있다.

- monitor encoding
- selected ICC output encoding
- JPEG/PNG/TIFF integer quantization
- mask encoding
- diagnostic overlay

clamp 전에 gamut mapping/soft clip이 필요한지 output intent별로 결정한다.

### 10.4 금지하는 숨은 clamp

- 낮은 precision intermediate의 UNORM saturation
- sampler/resource format 때문에 생기는 saturation
- built-in effect의 default `ClampOutput` 미확인
- alpha premultiply/unpremultiply 과정의 정보 손실
- encoder가 profile transform 전에 수행하는 implicit conversion

---

## 11. Direct2D built-in effect와 clamp

Microsoft 문서가 `ClampOutput` property를 제공한다고 명시한 예:

- Color Matrix
- Arithmetic Composite
- Convolve
- Transfer 계열

`ClampOutput = TRUE`이면 unpremultiplied space에서 clamp되어 shader linking 여부와 무관한 일관된
clamp를 만들 수 있다.

범위 밖 출력을 만들 수 있지만 같은 property가 없는 built-in 예:

- cubic/high-quality cubic transforming/scaling
- lighting
- overlay edge detection
- exposure
- plus composite
- temperature/tint
- sepia
- saturation

명시적으로 clamp가 필요하면 pass-through Color Matrix + `ClampOutput = TRUE` 같은 boundary를
사용할 수 있다. 다만 Negaflow core에서는 대체로 clamp가 필요 없으므로 다음을 따른다.

1. built-in effect output 범위를 먼저 측정
2. working stage이면 extended precision 유지
3. algorithm/output contract가 clamp를 요구할 때만 명시적 boundary 추가
4. link on/off 결과 비교

---

## 12. alpha 계약

### 12.1 기본 사진

스캔/RAW 사진 core는 일반적으로 opaque RGB로 다룬다. 그러나 effect graph의 실제 resource는
4채널일 수 있다.

- opaque path의 alpha는 정확히 1로 유지
- RGB math가 alpha를 임의 수정하지 않음
- source alpha가 의미 있는 raster import는 별도 policy

### 12.2 premultiplied와 straight

Direct2D built-in effect는 premultiplied alpha를 사용하는 경우가 많다. 공식 precision 문서는
범위 판단을 unpremultiplied 기준으로 해야 한다고 강조한다.

각 node edge에 다음을 기록한다.

- alpha mode
- premultiply/unpremultiply node
- alpha 0에서 RGB 처리
- blend math domain
- export alpha support

### 12.3 mask

mask는 사진 alpha와 동일하지 않다.

- single-channel scalar 의미
- [0,1] contract
- feathering precision
- coordinate identity
- combine strength

mask를 premultiplied color image처럼 처리해 값이 변하지 않도록 한다.

### 12.4 alpha 테스트

- alpha 0 + nonzero RGB
- alpha near zero
- alpha 0.5
- alpha 1
- repeated pre/unpremultiply
- blur edge
- transform transparent border
- PNG roundtrip

---

## 13. LUT precision

### 13.1 1D/3D LUT

- LUT storage format
- interpolation mode
- domain min/max
- edge clamp/taper
- texture coordinate phase
- alpha bypass

를 명시한다.

### 13.2 extended input

현재 bounded LUT 경로는 LUT domain 밖의 working value를 무조건 endpoint로 붙이지 않도록 원본과
graded branch를 결합하는 수학이 있다. Windows에서도:

- LUT lookup domain
- input code↔linear 변환
- 0.02/0.98 같은 boundary 의미
- original/graded blend

를 scalar oracle로 고정한다.

### 13.3 storage 후보

- `R32G32B32A32_FLOAT`: 기준 정확성
- `R16G16B16A16_FLOAT`: memory 후보, corpus 통과 필요
- integer LUT: output-specific 목적이 아니면 기준선 아님

LUT texture를 half로 줄이는 최적화는 결과 오차와 성능 이득을 장치군 전체에서 측정한 뒤에만
허용한다.

---

## 14. 측정 precision

렌더가 float32라고 histogram/통계가 자동으로 같은 결정을 내리는 것은 아니다.

### 14.1 histogram

- input domain
- bin mapping
- under/overflow bin
- alpha/mask 제외
- accumulator width
- sample count overflow
- reduction order

를 고정한다.

### 14.2 평균/분산

- accumulation은 float64 CPU reference 후보
- GPU는 충분한 accumulator precision과 안정된 reduction scheme 사용
- tile merge order 차이의 tolerance 정의
- decision threshold 근처 corpus 제공

### 14.3 percentile

- exact/approximate 정의
- interpolation/tie-break
- proxy sampling grid
- empty ROI
- NaN/Inf

CPU/GPU가 다른 auto parameter를 만들면 최종 pixel tolerance만으로 문제를 찾기 어렵다. 측정
결과 자체를 별도 비교한다.

---

## 15. output color와 양자화

### 15.1 순서

```text
working linear extended
→ output gamut mapping/ICC transform
→ output transfer encoding
→ bit-depth-specific dither
→ quantization
→ encoder
```

실제 LittleCMS/WIC 경로에서 transform과 quantization이 결합될 수 있어도 논리적 계약은 이
순서를 유지한다.

### 15.2 8-bit

- dither amplitude를 1 LSB 기준으로 정의
- absolute pixel coordinate와 deterministic seed
- channel correlation 정책
- alpha dither 여부
- clamping과 rounding 순서
- full-range/code-range

### 15.3 16-bit

- 현재 8-bit dither를 그대로 확대 적용하지 않는다.
- 필요성/진폭을 banding corpus로 결정한다.
- endian/channel order를 encoder와 대조한다.
- ICC transform output precision을 확인한다.

### 15.4 JPEG

8-bit sample 외에도 chroma subsampling과 encoder quality가 결과를 바꾼다. 현재 macOS 구현의
고품질 threshold 보정은 ImageIO 동작에 근거한 것이므로 Windows encoder에 숫자만 복사하지
않는다. WIC/선택 encoder의 실제 subsampling을 측정해 별도 정책을 만든다.

---

## 16. preview와 export

### 공유

- algorithm math
- precision requirement
- measurements
- recipe
- stage order
- clamp 위치
- random seed contract

### 명시적으로 다를 수 있음

- spatial resolution
- viewport ROI
- display transform
- final target format
- scheduling priority

프리뷰만 half precision으로 돌려 색이나 tone이 달라지는 것을 기본 최적화로 두지 않는다.
half-preview 후보가 필요하면 UI 확대/전환/softproof corpus와 strict error budget을 통과해야 한다.

export는 프리뷰 cache의 8-bit display bitmap을 재사용하지 않는다.

---

## 17. memory 비용

32bpc RGBA는 pixel당 16 bytes다.

대략적인 raw surface 크기:

| 해상도 | 한 surface |
|---|---:|
| 24 MP | 약 384 MB |
| 45 MP | 약 720 MB |
| 100 MP | 약 1.6 GB |

이는 alignment, mip, staging, driver overhead, 여러 intermediate를 제외한 값이다.

따라서 precision을 낮추는 대신 다음을 먼저 한다.

- shader linking
- ROI rendering
- tile + apron
- transient lifetime aliasing
- graph prefix cache budget
- CPU/GPU stage partition
- full-frame intermediate 수 감소
- source decode tile

peak budget을 넘으면 tile을 줄이거나 CPU로 전환한다. OOM 직전에 품질을 조용히 낮추지 않는다.

---

## 18. 검증 corpus

### 18.1 scalar ramp

채널별 다음 값을 포함한다.

```text
-16, -4, -1, -0.1, -0.0,
0, smallest guarded positive, 1e-5,
0.001, 0.018, 0.02, 0.18, 0.5,
0.98, 1, 1.001, 1.25, 4, 16,
NaN, +Inf, -Inf
```

알고리즘 domain상 허용되지 않는 값은 실패/sanitize 정책을 검사한다.

### 18.2 image patterns

- linear ramp
- logarithmic ramp
- impulse
- checkerboard
- saturated primaries/secondaries
- neutral near-black gradient
- highlight gradient >1
- negative RGB stress
- alpha ramp
- wide-gamut patch set
- film density patches
- random/grain statistics

### 18.3 graph variants

- link 후보 연속 graph
- 강제 intermediate graph
- branch/fan-in graph
- built-in blur/scale 경계
- command list input
- 32bpc source + 낮은 target
- 낮은 source + 32bpc working target
- GPU vs CPU
- tile sizes 여러 개

### 18.4 판정 지표

- max/mean/RMS channel error
- percentile error
- threshold-crossing count
- hue/luma error
- out-of-range preservation count
- NaN/Inf count
- alpha error
- seam-band error
- output code-value difference
- ICC patch difference

---

## 19. 장치 matrix

| 장치군 | 확인 |
|---|---|
| Intel x64 iGPU | 32bpc surface, sampling, driver, memory pressure |
| AMD x64 iGPU/dGPU | 동일 |
| NVIDIA x64 dGPU | 동일, CUDA 없이 기준 기능 확인 |
| Qualcomm ARM64 GPU | D3D11/D2D precision, shared memory, driver |
| x64 CPU | scalar/SIMD parity |
| ARM64 CPU | scalar/NEON parity |
| WARP | diagnostic/CI parity와 성능 |

각 결과에 Windows build와 driver version을 포함한다.

---

## 20. failure policy

| 실패 | 동작 |
|---|---|
| 32bpc float 미지원 | CPU fallback |
| 32bpc 보고하지만 corpus 실패 | device/driver quarantine + CPU fallback |
| GPU OOM | 작은 tile 또는 CPU fallback |
| shader link on/off 차이 초과 | linking 비활성화 또는 release 차단 |
| built-in effect clamp 불명확 | custom effect 또는 CPU로 대체 |
| ICC/output precision 부족 | export 실패 또는 검증된 higher-precision 경로 |
| NaN/Inf 생성 | 해당 render/export 실패, diagnostics |
| CPU/GPU 차이 초과 | fastest 결과가 아니라 oracle에 맞는 backend 선택 |

fallback은 사용자 원본이나 recipe를 변경하지 않는다.

---

## 21. 구현 순서

### Phase 0 — 계약 추출

- current stage별 domain/clamp inventory
- scalar oracle
- extended-range golden corpus
- alpha policy

### Phase 1 — D2D spike

- 32bpc input/intermediate/target
- link on/off graph
- built-in effect clamp
- Intel/AMD/NVIDIA/Qualcomm 최소 장치

### Phase 2 — CPU parity

- x64 scalar/SIMD
- ARM64 scalar/NEON
- transcendental tolerance
- tile parity

### Phase 3 — output

- monitor transform
- ICC/softproof/PRINT
- 8/16-bit quantization
- WIC/encoder roundtrip

### Phase 4 — hardening

- device loss/OOM
- driver quarantine
- large-image memory budget
- WARP comparative spike

---

## 22. 금지 사항

- GPU register가 float32라는 이유로 intermediate precision 검증을 생략하지 않는다.
- 모든 export를 WARP로 강제하지 않는다.
- WARP를 automatic per-effect CPU fallback이라고 부르지 않는다.
- 16bpc float를 32bpc float와 동등하다고 가정하지 않는다.
- shader linking이 항상 extended range를 보존한다고 가정하지 않는다.
- current code의 의도적 clamp를 일괄 제거하지 않는다.
- 낮은 precision으로 성능 수치를 만든 뒤 같은 품질이라고 보고하지 않는다.
- invalid ICC나 NaN을 silent sRGB/0으로 덮지 않는다.
- display bitmap을 export master로 재사용하지 않는다.
- alpha mode를 암묵적으로 바꾸지 않는다.

---

## 23. 공식 자료

- [Precision and numerical clipping in effect graphs](https://learn.microsoft.com/en-us/windows/win32/direct2d/precision-and-clipping-in-effect-graphs)
- [`ID2D1DeviceContext::IsBufferPrecisionSupported`](https://learn.microsoft.com/en-us/windows/win32/api/d2d1_1/nf-d2d1_1-id2d1devicecontext-isbufferprecisionsupported)
- [`ID2D1DeviceContext::SetRenderingControls`](https://learn.microsoft.com/en-us/windows/win32/api/d2d1_1/nf-d2d1_1-id2d1devicecontext-setrenderingcontrols)
- [`ID2D1RenderInfo::SetOutputBuffer`](https://learn.microsoft.com/en-us/windows/win32/api/d2d1effectauthor/nf-d2d1effectauthor-id2d1renderinfo-setoutputbuffer)
- [Supported pixel formats and alpha modes](https://learn.microsoft.com/en-us/windows/win32/direct2d/supported-pixel-formats-and-alpha-modes)
- [Direct3D WARP guide](https://learn.microsoft.com/en-us/windows/win32/direct3darticles/directx-warp)
- [DXGI formats](https://learn.microsoft.com/en-us/windows/win32/api/dxgiformat/ne-dxgiformat-dxgi_format)

Microsoft의 WARP 설명은 API 선택지의 근거다. Negaflow의 hardware-GPU-first/CPU-fallback 결정은
현대 Windows 11 장치 기준선, 범용 CPU backend, 실제 성능·정확성 검증 요구를 함께 반영한다.

---

## 24. 관련 문서

- [pipeline-shape.md](pipeline-shape.md)
- [direct2d-effects.md](direct2d-effects.md)
- [shader-linking.md](shader-linking.md)
- [roi-and-invalidation.md](roi-and-invalidation.md)
- [../02-shaders/metal-to-hlsl.md](../02-shaders/metal-to-hlsl.md)
- [../03-measurement/histogram-and-statistics.md](../03-measurement/histogram-and-statistics.md)
- [../04-color-management/color-pipeline.md](../04-color-management/color-pipeline.md)
- [../05-image-io/export-formats.md](../05-image-io/export-formats.md)
- [../06-large-images/image-source-tiling.md](../06-large-images/image-source-tiling.md)
- [../12-performance/backend-selection.md](../12-performance/backend-selection.md)
- [../16-cpu/simd-and-dispatch.md](../16-cpu/simd-and-dispatch.md)

---

## 25. 완료 조건

- [ ] 모든 render node edge에 domain/precision/alpha가 정의됨
- [ ] core working graph가 실제 32bpc intermediate를 사용함
- [ ] link on/off extended-range corpus가 통과함
- [ ] built-in effect clamp/extent 동작이 측정됨
- [ ] GPU capability report와 runtime corpus가 일치함
- [ ] Intel/AMD/NVIDIA/Qualcomm 장치군이 검증됨
- [ ] x64/ARM64 CPU fallback이 같은 결과를 냄
- [ ] WARP는 별도 comparative evidence가 있음
- [ ] NaN/Inf failure가 숨겨지지 않음
- [ ] 8/16-bit output 순서와 rounding/dither가 고정됨
- [ ] softproof/PRINT ICC 경계가 precision corpus를 통과함
- [ ] 대형 이미지 peak memory와 OOM fallback이 검증됨

이 조건이 충족되기 전에는 “Windows 렌더가 32-bit float를 보장한다”거나 “macOS와 색이
동등하다”고 선언하지 않는다.
