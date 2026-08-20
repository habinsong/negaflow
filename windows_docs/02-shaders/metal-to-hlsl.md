# Core Image Metal → Direct2D HLSL 이식 규약

기준일: 2026-08-04  
macOS 기준 커밋: `9be909c`  
대상: `ChromabaseMetalKernels.swift`의 `[[stitchable]]` 31개  
Windows v1 target: D3D11, Direct2D 1.1+, SM5/DXBC, offline FXC

이 작업은 문법 변환이 아니라 수치·색공간·graph 계약 이식이다. `float3`를 `float3`로 복사해
컴파일되는 것과 같은 사진을 만드는 것은 다르다.

## 1. source와 target의 차이

### 1.1 현재 macOS 형태

```metal
#include <CoreImage/CoreImage.h>
using namespace metal;

inline float3 helper(float3 v) { /* ... */ }

[[stitchable]] float4 basicTone(
    coreimage::sample_t src,
    float contrastAmount,
    float densityAmount,
    float highlightAmount,
    float shadowAmount,
    float whitesAmount,
    float blacksAmount
) {
    /* ... */
}
```

Swift는 하나의 Metal source string을 `CIKernel.kernels(withMetalString:)`로 runtime compile하고 name별
`CIColorKernel`로 보관한다. image argument는 Core Image graph node이며 scalar/vector argument는
kernel parameter다.

### 1.2 Windows v1 형태

```hlsl
#define D2D_INPUT_COUNT 1
#define D2D_INPUT0_SIMPLE
#include <d2d1effecthelpers.hlsli>
#include "tone_safe.hlsli"

cbuffer BasicToneConstants : register(b0)
{
    float contrastAmount;
    float densityAmount;
    float highlightAmount;
    float shadowAmount;
    float whitesAmount;
    float blacksAmount;
    float2 _padding;
};

D2D_PS_ENTRY(BasicTone)
{
    float4 src = D2DGetInput(0);
    /* ported math */
}
```

build가 full shader와 linkable export function을 만들고 하나의 blob contract로 묶는다. runtime은 raw
HLSL을 compile하지 않는다.

## 2. 이식 단위

kernel마다 다음 5개 artifact를 함께 만든다.

1. C++ scalar reference function
2. HLSL source/entry point
3. Direct2D effect/transform wrapper
4. parameter-layout manifest와 compile manifest
5. macOS/CPU/GPU golden conformance test

HLSL만 먼저 대량 변환하고 나중에 맞추는 방식은 금지한다. 한 kernel을 reference→shader→wrapper→test
까지 닫은 뒤 다음으로 간다.

## 3. 문법 대응표

| Metal/Core Image | HLSL/Direct2D | 주의 |
|---|---|---|
| `coreimage::sample_t src` | `float4 src = D2DGetInput(n)` | premultiplied alpha 계약 확인 |
| image argument 수 | `D2D_INPUT_COUNT` | manifest와 wrapper input count 일치 |
| current-coordinate image | `D2D_INPUTn_SIMPLE` | ROI mapping도 same-coordinate여야 함 |
| arbitrary sample | `D2DSampleInput*` + complex input | 현재 31 kernel에는 없음 |
| scalar/vector argument | `cbuffer` field | 16-byte packing 검증 |
| `float2/3/4` | `float2/3/4` | `float3` padding에 주의 |
| `mix(a,b,t)` | `lerp(a,b,t)` | extrapolation semantics 동일 확인 |
| `fract(x)` | `frac(x)` | negative input fixture 필요 |
| `select(a,b,cond)` | `cond ? b : a` 또는 component select helper | argument 순서 반전 주의 |
| `constexpr` | `static const` | compile-time constant 확인 |
| `int(arrayIndex)` | explicit cast | dynamic index capability/optimization 확인 |
| `log2/log10/exp/pow/sqrt` | 같은 intrinsic | precision/undefined domain 검증 |
| `any(bool3)` | `any(bool3)` | 동일 |
| `clamp` | `clamp` | source에 없는 clamp 추가 금지 |
| `smoothstep` | `smoothstep` | edge order와 NaN fixture |
| return `float4` | return `float4` | alpha와 premultiplication 유지 |

### 3.1 `select`는 특히 위험하다

Metal의 `select(falseValue, trueValue, condition)`를 HLSL `lerp`로 기계적으로 바꾸면 bool vector와
NaN에서 의미가 달라질 수 있다.

예:

```metal
float3 outY = select(mirrored, y, d >= float3(0.0));
```

의도는 channel별로 다음과 같다.

```hlsl
float3 outY = float3(
    d.x >= 0.0 ? y.x : mirrored.x,
    d.y >= 0.0 ? y.y : mirrored.y,
    d.z >= 0.0 ? y.z : mirrored.z
);
```

반드시 음수/0/양수 경계 fixture로 검증한다.

### 3.2 array와 loop

`colorMixerHSL`, `calibrationPrimaries`, `digitalHueBand`는 작은 local array와 dynamic index를 쓴다.
초기 port는 수학을 유지한다. FXC/driver 결과가 성능 병목으로 확인되면 다음 순서로 최적화한다.

1. compiler unroll 확인
2. `[unroll]` hint 비교
3. fixed branch/vectorized 표현 비교
4. 결과와 register pressure 측정

수동 unroll로 수학 순서가 달라질 경우 conformance tolerance를 다시 평가해야 한다.

## 4. Direct2D input 선언

현재 31개 image argument는 모두 current-coordinate sample이다. HLSL authoring은 각 input을 simple로
선언하는 것이 기본 후보다.

```hlsl
#define D2D_INPUT_COUNT 3
#define D2D_INPUT0_SIMPLE
#define D2D_INPUT1_SIMPLE
#define D2D_INPUT2_SIMPLE
#include <d2d1effecthelpers.hlsli>
```

그러나 다음 세 조건이 모두 맞아야 한다.

- HLSL이 `D2DGetInput(n)`만 사용한다.
- transform의 rect mapping이 같은 coordinate를 요구한다고 보고한다.
- caller가 input image를 동일한 logical coordinate space로 정렬한다.

두 번째 image가 blur 결과라는 이유만으로 combine shader input을 `COMPLEX`로 선언하지 않는다.
blur transform이 complex/spatial producer이고 그 출력의 같은 coordinate를 읽는 combine input은 simple다.

## 5. multi-input port

예: `scannerLowSatChroma(src, blur)`

```hlsl
#define D2D_INPUT_COUNT 2
#define D2D_INPUT0_SIMPLE
#define D2D_INPUT1_SIMPLE
#include <d2d1effecthelpers.hlsli>

D2D_PS_ENTRY(ScannerLowSatChroma)
{
    float4 src = D2DGetInput(0);
    float4 blur = D2DGetInput(1);
    /* point combine */
}
```

effect wrapper가 보장할 것:

- 두 input의 transform/extent가 같은 logical pixel grid인지
- secondary input이 어느 source revision에서 만들어졌는지
- output rect에 필요한 두 input rect
- crop/border 처리
- device loss 뒤 두 input을 같은 generation으로 재생성하는지

`filmScanShrink`처럼 6개 image input이 있는 shader는 Direct2D input limit와 wrapper complexity를 첫
spike에서 확인한다. 제한 또는 driver 문제가 있으면 수학을 임의로 줄이지 않고 D3D11 compute 또는
두 단계 combine으로 옮긴다.

## 6. constant-buffer layout

HLSL constant buffer는 C++ struct와 byte-for-byte 맞아야 한다.

### 6.1 규칙

- 16-byte register boundary를 명시한다.
- `float3` 다음 field offset을 C++ natural layout에 맡기지 않는다.
- bool을 C++ `bool`과 직접 공유하지 않는다.
- enum은 고정폭 integer wire value로 보낸다.
- padding field도 manifest와 static assertion에 포함한다.
- shader constant buffer 전체를 초기화하고 padding에 미정 값을 남기지 않는다.
- effect setter는 finite/range validation 후 snapshot 전체를 한 번에 교체한다.

### 6.2 생성 검증

build가 다음을 비교한다.

```text
C++ sizeof/alignof/offsetof
↔ manifest byte offsets
↔ HLSL reflection 결과
```

reflection을 production runtime dependency로 만들 필요는 없지만 build/test에서 ABI drift를 막는 데
사용한다.

### 6.3 C# 경계

C# shell은 raw constant-buffer pointer를 만들지 않는다. C ABI request struct 또는 typed setter를
통해 C++ renderer에 immutable parameter snapshot을 전달한다. renderer가 validation, packing,
upload를 소유한다.

## 7. 색공간과 alpha

### 7.1 Core Image context를 명시적으로 복원한다

Metal source만 보면 input 색공간이 드러나지 않는다. caller가 다음을 결정한다.

- source decode color space
- working linear space
- `CIColorCubeWithColorSpace`의 domain
- display/output transform
- premultiplication
- crop/extent

Windows HLSL manifest에는 caller-side domain을 포함해야 한다.

### 7.2 working baseline

- GPU/CPU working arithmetic: linear float32 RGBA
- extended negative/>1 values: stage contract에 따라 유지
- alpha: source와 mask 종류별 premultiplied contract 명시
- display HSL/LUT stage: 명시적 transfer boundary
- export/print: destination ICC transform 뒤 format quantization

### 7.3 alpha test

다음을 별도 fixture로 둔다.

- opaque photo
- alpha 0 RGB nonzero input
- fractional premultiplied edge
- unpremultiplied conversion round trip
- clipping overlay의 premultiplied warning color
- blend-with-mask edge

사진 source가 보통 opaque라는 이유로 alpha bug를 무시하지 않는다. crop, mask, overlay, print
composition은 alpha를 사용한다.

## 8. clamp와 extended value

source에 clamp가 있는 위치만 port한다.

### clamp를 유지해야 하는 예

- HSL 변환 전 display-domain unit clamp
- `basicTone`의 mask input과 final unit output
- `filmScanShrink`의 denoise output
- clipping overlay boundary test

### clamp를 추가하면 안 되는 예

- `negativeInvert` output
- working-linear intermediate
- measured-domain identity outside LUT range
- digital scene reconstruction headroom
- pre-output color transform

Direct2D intermediate precision/format이 조용히 clamp하지 않는지 별도 spike한다. HLSL이 clamp하지
않았다는 사실만으로 extended value가 보존되는 것은 아니다.

## 9. transcendental math

다음 kernel은 특히 compiler/backend 차이에 민감하다.

- `negativeInvert`: `log10`, `pow`, `exp`
- `digitalSceneReconstruct`: `sqrt`, division
- `digitalFilmDensity`: `log2`, `pow`
- `digitalPrintPaper`/`digitalReversalTransmit`: `pow(10, x)`
- `digitalFilmColor`: transfer `pow`
- `digitalFilmGrainDensity`: `log10`, `sqrt`, `exp`, `pow`

### 9.1 baseline

- scalar C++ double 또는 carefully-defined float reference를 만든다.
- shipping contract는 float32 GPU/CPU 결과의 허용 오차로 고정한다.
- compiler flags와 driver identity를 golden metadata에 기록한다.
- `precise`/IEEE strict flag는 kernel별 필요성과 성능을 비교한다.
- fast-math는 default가 아니다.
- denormal flush, signed zero, NaN propagation을 public behavior로 노출하지 않도록 valid input을
  boundary에서 제한한다.

### 9.2 error metric

단일 max absolute error만 쓰지 않는다.

- absolute error near black
- relative error in mid/high values
- ULP sample
- per-channel delta
- neutral hue/chroma error
- monotonicity
- output range
- full-image perceptual comparison은 보조 증거

허용 오차는 kernel과 domain별로 정하고 모든 kernel에 같은 숫자를 억지로 쓰지 않는다.

## 10. full shader와 export function

Direct2D shader linking을 쓰려면 한 HLSL entry에서 다음 두 산출물을 만든다.

1. export function
2. full pixel shader 안에 export function을 private data로 embed한 final blob

개념적 build:

```text
FXC D2D_FUNCTION
→ .fxlib

FXC D2D_FULL_SHADER + entry + embedded .fxlib
→ .cso
```

정확한 target profile과 FXC option은 shader-linking spike에서 현재 Windows SDK로 검증하고 manifest에
고정한다. 공식 문서의 두 단계 명령을 source of truth로 삼는다.

규칙:

- full blob만 load하고 linking이 된다고 주장하지 않는다.
- `LoadPixelShader`에는 compiled bytecode만 전달한다.
- shader GUID는 logical effect ID와 안정적으로 매핑한다.
- 같은 GUID에 다른 blob을 runtime에서 재등록하지 않는다.
- debug/release blob hash를 구분한다.
- compile warning을 release artifact에서 허용하지 않는다.

## 11. FXC와 DXC

### v1

- Direct2D linkable effects: FXC/DXBC
- D3D11 compute: FXC `cs_5_0`
- runtime compiler DLL: 배포하지 않음
- HLSL source: product package에 필수 포함하지 않음

### 선택 tier

DXC/DXIL은 D3D12/SM6 backend가 별도 gate를 통과할 때 추가한다. D2D linking artifact와 D3D12
artifact를 같은 blob이라고 취급하지 않는다.

DXC가 더 최신이라는 이유로 Direct2D FXC pipeline을 교체하지 않는다. 반대로 FXC를 쓴다는 이유로
전체 renderer를 오래된 설계로 간주하지 않는다. compiler는 target ABI 선택이다.

## 12. build integration

각 shader build rule의 input:

- `.hlsl`
- transitive `.hlsli`
- entry name
- target/profile
- define set
- FXC version/path hash
- optimization/debug/strictness flags
- expected constant-buffer schema

output:

- `.cso`
- optional generated C/C++ byte array
- source hash
- blob SHA-256
- reflection/layout report
- warning/error log
- manifest entry

CMake/Ninja가 FXC include dependency를 자동으로 정확히 추적한다고 가정하지 않는다. wrapper 또는
명시적 dependency list로 `.hlsli` 변경 시 필요한 shader가 모두 rebuild되는 test를 둔다.

### 12.1 reproducibility

동일 pinned toolchain/build input에서 blob hash가 같은지 CI에서 확인한다. hash가 다르면 먼저 compiler
version, absolute path embedding, debug metadata, timestamp를 조사한다. 재현 불가능한데 hash를
release allowlist에 수동 추가하지 않는다.

## 13. manual port 절차

### Step 1 — contract extraction

- caller 파일과 graph 위치 읽기
- input domain/extent/alpha 기록
- default/off condition 기록
- scalar/vector range 기록
- source clamp와 transfer boundary 표시

### Step 2 — scalar oracle

- helper math port
- edge vector test
- source Metal fixture와 비교
- undefined input 처리 고정

### Step 3 — HLSL port

- source statement order 보존
- intrinsic 변환
- `select` component semantics 보존
- constant layout 생성
- full/export offline compile

### Step 4 — one-pixel/readback conformance

- WARP
- Intel/AMD/NVIDIA
- ARM64 device
- scalar CPU reference

### Step 5 — image/graph conformance

- gradient/color chart/negative fixture
- full-frame vs tile
- neighboring linked/unlinked graph
- device lost/recreation

### Step 6 — performance

- pass count/intermediate bytes
- shader JIT/first-use cost
- steady-state GPU duration
- graph rebuild cost
- parameter upload cost

수치 conformance가 먼저이며 performance 때문에 statement order나 precision을 바꾸는 일은 별도
optimization change로 다룬다.

## 14. 자동 변환 도구 정책

일반 shader transpiler는 이 방향의 source-of-truth가 아니다.

- 현재 source는 일반 MSL compute/pixel entry가 아니라 Core Image `[[stitchable]]` dialect다.
- caller-side Core Image color management와 ROI는 source에 없다.
- Direct2D helper/export-function 규약을 자동으로 만들지 않는다.
- parameter ABI와 effect registration은 별도다.

작은 script로 name/signature/manifest skeleton을 생성하는 것은 가능하다. 그러나 수학 본문, domain,
clamp, alpha 의미를 자동 변환 결과로 승인하지 않는다.

## 15. 대표 port 위험

### 15.1 좌표와 texel center

current-coordinate kernel도 source/secondary input이 다른 transform을 거치면 alignment가 깨질 수 있다.
checkerboard, 1-pixel impulse, odd-size crop, rotated/mirrored image로 검증한다.

### 15.2 border

blur/median/resample producer의 border mode가 Core Image와 다르면 combine kernel은 정확해도 최종 결과가
다르다. clamp, mirror, transparent, crop semantics를 stage별로 고정한다.

### 15.3 transfer 중복

`digitalFilmColor`와 digital preset stage는 내부/외부 transfer boundary가 있다. HLSL helper를 공용화할
때 caller가 이미 변환했다는 이유로 내부 transfer를 삭제하지 않는다.

### 15.4 LUT

3D LUT size, address mode, interpolation, color-space conversion, endpoint handling이 달라질 수 있다.
Direct2D LookupTable3D의 이름만 보고 Core Image cube와 동일하다고 판정하지 않는다.

### 15.5 noise

API random generator를 그대로 바꾸면 preview flicker와 export non-determinism이 생긴다. deterministic
absolute-coordinate noise contract를 먼저 만든다.

### 15.6 shader linking

linking on/off가 수치 결과를 바꿀 수 있다. linked path와 deliberately unlinked path를 모두 golden과
비교하고, intermediate precision/clamp 차이가 허용 오차 밖이면 graph precision을 명시적으로
설정한다.

## 16. kernel port manifest 예시

```json
{
  "name": "negativeInvert",
  "version": 1,
  "source": "point/negative_invert.hlsl",
  "entry": "NegativeInvert",
  "inputs": [
    { "index": 0, "sampling": "simple", "domain": "linear-rgba-f32" }
  ],
  "constants": {
    "schema": "NegativeInvertConstantsV1",
    "size": 48
  },
  "artifacts": {
    "kind": "d2d-full-plus-export",
    "profile": "pinned-after-spike",
    "sha256": "..."
  },
  "math": {
    "extendedOutput": true,
    "fastMath": false
  }
}
```

profile/size 값은 구현 spike와 reflection이 확정하기 전 placeholder를 production manifest에 넣지 않는다.
위 JSON은 필드 구조 예시다.

## 17. 완료 gate

- [ ] 31개 source name과 31개 manifest entry가 일치한다.
- [ ] 각 entry의 input count와 caller input count가 일치한다.
- [ ] C++/HLSL constant layout reflection test가 통과한다.
- [ ] 모든 shader가 offline compile되고 runtime source compile이 없다.
- [ ] Direct2D effect registration/load 실패가 fallback 또는 명시적 오류로 처리된다.
- [ ] full/export artifact 둘 다 존재하고 실제 linking capture가 있다.
- [ ] CPU/WARP/Intel/AMD/NVIDIA/ARM64 conformance가 허용 오차를 만족한다.
- [ ] extended value, alpha, border, tile fixture가 통과한다.
- [ ] linked/unlinked graph 결과가 계약 안에 있다.
- [ ] digital-only routing과 output-only routing이 test로 고정된다.
- [ ] shader source/compiler/flags/blob hash가 release manifest에 기록된다.

## 18. 금지 목록

- 31개를 “전체 renderer”라고 표현
- Metal compile 성공을 HLSL 수치 동등성 증거로 사용
- `mix`, `select`, transfer function을 무검증 기계 치환
- HLSL source를 production runtime에서 compile
- C#이 constant-buffer packing 소유
- source에 없는 clamp 추가
- source의 clamp를 임의 제거
- full pixel shader만 load하고 shader linking 완료 주장
- FXC/DXBC와 DXC/DXIL artifact 혼용
- vendor 하나의 screenshot으로 GPU portability 승인
- tile 좌표를 noise seed로 사용

## 19. 공식 자료

- [Direct2D HLSL helpers](https://learn.microsoft.com/en-us/windows/win32/direct2d/hlsl-helpers)
- [Direct2D effect shader linking](https://learn.microsoft.com/en-us/windows/win32/direct2d/effect-shader-linking)
- [Direct2D custom effects](https://learn.microsoft.com/en-us/windows/win32/direct2d/custom-effects)
- [ID2D1EffectContext::LoadPixelShader](https://learn.microsoft.com/en-us/windows/win32/api/d2d1effectauthor/nf-d2d1effectauthor-id2d1effectcontext-loadpixelshader)
- [Compiling shaders with FXC](https://learn.microsoft.com/en-us/windows/win32/direct3dhlsl/dx-graphics-hlsl-part1)
- [FXC syntax](https://learn.microsoft.com/en-us/windows/win32/direct3dtools/dx-graphics-tools-fxc-syntax)

관련 문서:

- [kernel inventory](kernel-inventory.md)
- [shader linking](../01-render-engine/shader-linking.md)
- [precision and clipping](../01-render-engine/precision-and-clipping.md)
- [pipeline shape](../01-render-engine/pipeline-shape.md)
- [build environment](../13-build-and-deps/development-environment.md)
