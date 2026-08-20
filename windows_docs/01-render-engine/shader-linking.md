# Direct2D effect shader linking 설계

상태: 1차 기준선 확정  
최종 공식 문서 확인: 2026-08-04  
대상: D3D11 + Direct2D custom pixel effect의 선택적 pass 융합

---

## 1. 한 줄 결정

Direct2D effect shader linking은 **정확성을 정의하는 기능이 아니라 중간 surface와 GPU pass를
줄일 수 있는 런타임 최적화**로 사용한다.

- 모든 custom point effect에 full shader를 제공한다.
- 링크 가치가 있는 pixel effect에는 export function을 함께 embed한다.
- Direct2D가 실제로 어떤 transform을 연결할지는 런타임에 결정한다.
- 링크 성공 여부와 무관하게 출력이 같아야 한다.
- 특정 커널 수나 고정 pass 수를 제품 계약으로 약속하지 않는다.
- FXC/SM5/DXBC 경로가 D3D11 + Direct2D 기준선이다.
- DXC/SM6/D3D12는 이 기능의 대체 기준선이 아니다.

---

## 2. 공식 동작

Microsoft가 설명하는 effect shader linking은 여러 Direct2D rendering transform의 precompiled
pixel shader function을 런타임에 연결해 하나의 pass로 만들 수 있는 최적화다.

공식 예시는 다음 차이를 보여 준다.

| 예시 graph | pass | intermediate surface |
|---|---:|---:|
| link하지 않은 4개 transform | 4 | 3 |
| 네 transform 전체가 link된 경우 | 1 | 0 |

이 숫자는 설명용 graph의 결과다. Negaflow graph의 보장값이 아니다.

Direct2D는 graph를 자동 분석하고, adjacent rendering transform을 연결하는 것이 유리할 때만
연결한다. 앱이 별도 “link now” API를 호출하는 구조가 아니다. effect author가 호환 shader
artifact와 올바른 transform/input 계약을 제공해야 한다.

공식 문서가 명시하는 핵심 조건:

- full pixel shader와 export function version을 모두 제공해야 한다.
- full blob만 `ID2D1EffectContext::LoadPixelShader`로 올리면 인접 transform과 link되지 않는다.
- pixel shader만 link 대상이다.
- compute shader와 vertex shader는 link되지 않는다.
- simple input만 앞 shader function의 출력으로 공급할 수 있다.
- complex input은 sample할 실제 texture가 필요하므로 predecessor와의 link 경계가 된다.
- hazard 주변은 끊기더라도 나머지 graph는 계속 link 후보가 될 수 있다.
- built-in effect도 linking을 지원하지만, 실제 graph 최적화 결과는 런타임 판단이다.

---

## 3. Negaflow에서 기대하는 이득

현상 파이프라인에는 인접한 point transform이 많다.

- negative inversion
- tone mapping
- color grading
- color mixer
- calibration
- B&W toning
- gamut soft clip
- highlight desaturation
- 디지털 film response의 일부

이 transform 사이의 materialization을 줄이면 다음 이득이 가능하다.

- GPU 메모리 read/write 감소
- transient surface 감소
- peak GPU memory 감소
- driver submission/pass overhead 감소
- 넓은 범위 중간값을 낮은 precision surface에 잘못 materialize할 위험 감소

마지막 항목도 “위험 감소”일 뿐 “정밀도 문제가 사라짐”이 아니다. link가 끊기는 모든
경계와 최종 output surface는 여전히 precision 계약이 필요하다.

---

## 4. linkability와 pointwise는 같은 말이 아니다

`ChromabaseMetalKernels.swift`에는 현재 31개 `[[stitchable]]` 함수가 있다. 이 숫자는 macOS
stitchable kernel inventory이며 Windows Direct2D linkability 개수가 아니다.

### 4.1 개별 함수 관점

현재 inventory는 함수의 image input 모양으로 다음처럼 분류된다.

- 단일 image input: 18개
- 둘 이상의 image input: 13개

단일 image input이고 같은 logical coordinate의 한 pixel만 소비하는 함수는 가장 단순한
link 후보다. 그러나 다음 조건이 추가로 맞아야 한다.

- Windows HLSL port가 D2D helper contract를 사용함
- input을 `SIMPLE`로 정확히 선언함
- full + export artifact가 정상임
- scene position 제약이 충돌하지 않음
- 앞뒤 transform에 compute/vertex/complex hazard가 없음
- effect graph 분기와 resource precision이 허용함
- Direct2D runtime이 실제로 이득이 있다고 판단함

### 4.2 다중 입력 함수 관점

다중 입력이라고 무조건 complex sampling인 것은 아니다. 예를 들어 같은 좌표의 source와 mask를
읽는 combine은 각 input 자체를 `SIMPLE`로 표현할 수 있다. 하지만 입력이 서로 다른 upstream
branch에서 오기 때문에 graph fan-out/fan-in과 materialization 요구를 별도로 확인해야 한다.

### 4.3 spatial-derived input 관점

다음과 같은 함수는 최종 combine 자체가 pointwise일 수 있다.

```text
combine(source(x, y), blurredSource(x, y))
```

그러나 `blurredSource`를 만들기 위해 이웃 pixel을 sample하는 blur transform이 먼저 필요하다.
blur output이 texture로 materialize되거나 별도 pass가 되는 경계가 생길 수 있다.

예:

- scanner low/midtone chroma graph
- film scan shrink/guided filter graph
- digital halation graph
- TextureStage halation/clarity
- Noritsu texture graph

따라서 “combine shader는 pointwise이므로 전체 스테이지가 link된다”는 결론을 금지한다.

---

## 5. `SIMPLE`과 `COMPLEX` 선언

`d2d1effecthelpers.hlsli`는 각 input의 sampling contract를 preprocessor directive로 받는다.

```hlsl
#define D2D_INPUT_COUNT 1
#define D2D_INPUT0_SIMPLE
#include <d2d1effecthelpers.hlsli>

D2D_PS_ENTRY(NegaflowPointTransform)
{
    float4 source = D2DGetInput(0);
    return ApplyTransform(source);
}
```

### 5.1 `SIMPLE`

`SIMPLE`은 output pixel을 계산할 때 해당 input의 대응되는 단일 sample value만 필요하다는
계약이다. Direct2D는 이 input을 texture sample로 공급하거나 앞 shader function의 반환값으로
공급할 수 있다.

후보:

- per-pixel matrix
- per-pixel curve
- per-pixel grade
- 같은 좌표의 mask/composite
- 명시적인 scene position을 사용하지 않는 단순 LUT transform

### 5.2 `COMPLEX`

다음은 `COMPLEX`다.

- offset sample
- arbitrary position sample
- convolution/blur
- resampling/warp
- neighborhood morphology
- 주변 pixel을 읽는 defect repair
- custom vertex input에 의존하는 sample

input type을 선언하지 않으면 helper contract상 complex가 기본이다. 잘못 `SIMPLE`로 표시해
link를 유도하는 것은 최적화가 아니라 correctness bug다.

### 5.3 scene position

`D2D_REQUIRES_SCENE_POSITION`은 실제로 필요한 shader에만 둔다. 공식 contract상 linked shader
하나에서 scene position을 사용하는 function 수에 제약이 있으므로, 단순히 편리하다는 이유로
모든 shader가 scene position을 요청하면 link opportunity를 줄인다.

absolute pixel coordinate가 필요한 grain/dither는 다음을 먼저 비교한다.

- scene position 사용
- 별도 origin uniform + input coordinate
- compute/CPU 독립 경로

결정성, 타일 origin, viewport 이동, transform 뒤 좌표를 모두 검증한 뒤 선택한다.

---

## 6. full shader와 export function

linkable custom pixel shader blob은 두 형태를 함께 담아야 한다.

1. **full shader**
   - 독립 rendering pass로 실행 가능
   - 일반 D2D effect input signature 포함
2. **export function**
   - HLSL function linking에 사용
   - 앞 shader function의 반환값을 function input으로 받을 수 있음

Direct2D는 runtime graph에 맞춰 둘 중 알맞은 형태를 선택한다. 그러므로 export function만
제공하거나 full shader를 제거할 수 없다.

### 6.1 helper 사용 원칙

Windows SDK의 `d2d1effecthelpers.hlsli`를 사용한다.

- `D2D_INPUT_COUNT`
- `D2D_INPUTn_SIMPLE` 또는 `D2D_INPUTn_COMPLEX`
- 필요할 때만 `D2D_REQUIRES_SCENE_POSITION`
- `D2D_PS_ENTRY`
- `D2DGetInput`, `D2DSampleInput*` 계열

preprocessor input 선언은 include보다 앞에 있어야 한다.

### 6.2 공식 2단계 FXC 흐름

개념적인 build 흐름은 다음과 같다.

```text
HLSL source
  ├─ FXC: D2D_FUNCTION → export function library
  └─ FXC: D2D_FULL_SHADER + /setprivate export library
                          → combined .cso
```

공식 문서 형태의 command template:

```bat
fxc /T <linking-profile> Effect.hlsl ^
    /D D2D_FUNCTION /D D2D_ENTRY=<entry> ^
    /Fl Effect.fxlib

fxc /T ps_<shader-model> Effect.hlsl ^
    /D D2D_FULL_SHADER /D D2D_ENTRY=<entry> ^
    /E <entry> /setprivate Effect.fxlib ^
    /Fo Effect.cso /Fh Effect.generated.h
```

정확한 shader/linking profile은 최소 feature-level matrix와 실제 Windows SDK FXC 검증 뒤
build manifest에 고정한다. 문서 예시의 placeholder를 그대로 실행하지 않는다.

### 6.3 왜 FXC인가

이 경로는 Direct2D 공식 helper와 `D3D_BLOB_PRIVATE_DATA` embedding 절차가 FXC 기준으로
문서화되어 있다. 기준선 결정은 다음과 같다.

- D3D11 + Direct2D custom effects: FXC, SM5 계열, DXBC
- compile은 build time/offline
- runtime HLSL compile 금지
- `.cso`와 reflection/manifest를 signed app artifact에 포함
- DXC는 D3D12/SM6 실험 경로에서만 별도 검토

DXC로 컴파일된 다른 artifact가 존재해도 Direct2D linking blob을 자동 대체한다고 가정하지
않는다.

---

## 7. build artifact 계약

각 custom effect entry는 manifest에 다음을 남긴다.

```text
semanticEffectName
algorithmVersion
hlslSourceSHA256
entryPoint
shaderProfile
fxcVersion
windowsSdkVersion
compileFlags
inputCount
input0..N sampling type
requiresScenePosition
fullShaderPresent
embeddedExportPresent
constantBufferSize
constantBufferLayoutHash
bytecodeSHA256
```

### 7.1 재현 가능한 build

- shader source와 generated artifact의 hash를 CI에서 비교한다.
- developer machine의 임의 SDK에서 조용히 다시 생성하지 않는다.
- pinned Windows SDK/FXC 버전을 기록한다.
- debug flag, optimization flag, strictness flag를 build type별로 고정한다.
- generated header와 `.cso` 중 하나를 단일 진실로 선택하고 중복 drift를 검사한다.

### 7.2 CI 실패 조건

- full shader 누락
- private data의 export function 누락
- manifest와 실제 input count 불일치
- `SIMPLE/COMPLEX` 선언 drift
- constant buffer reflection drift
- 예상하지 않은 shader profile 변경
- source 변경 후 bytecode 미갱신
- 동일 pinned toolchain에서 hash 비결정성

### 7.3 runtime 검증

앱 시작 시 모든 effect를 무조건 생성해 startup을 느리게 하지 않는다. 대신 다음 계층으로
검증한다.

- 설치/CI: 전체 artifact 정적 검증
- 최초 device 생성: registry/effect class 등록 검증
- 최초 effect 사용: bytecode load와 property binding 검증
- failure: 해당 effect/backend를 capability matrix에서 제외하고 진단 기록

---

## 8. Negaflow effect 분류 절차

31개 Metal 함수 각각에 다음 질문을 적용한다.

1. Windows HLSL 함수가 같은 좌표의 input만 소비하는가?
2. input이 몇 개인가?
3. 각 input은 `SIMPLE`인가 `COMPLEX`인가?
4. scene position이 필요한가?
5. upstream에 blur/transform/compute가 있는가?
6. output이 여러 downstream으로 fan-out하는가?
7. precision/alpha/color-domain 경계가 있는가?
8. custom vertex shader가 필요한가?
9. full shader 독립 실행 결과가 scalar oracle과 맞는가?
10. export function이 포함된 graph 결과도 같은가?

결과는 다음 상태 중 하나로 기록한다.

| 상태 | 의미 |
|---|---|
| `not-ported` | HLSL 구현 전 |
| `full-only` | 독립 shader만 검증됨 |
| `link-candidate` | export artifact와 입력 계약 준비됨 |
| `link-observed` | 대표 graph capture에서 실제 link 확인 |
| `link-rejected` | runtime이 link하지 않음; correctness 문제 아님 |
| `link-disabled` | precision/driver/correctness 이유로 의도적으로 금지 |

`link-candidate`를 `link-observed`로 표시하지 않는다.

---

## 9. 예상 hazard 목록

### 9.1 compute/vertex transform

Direct2D는 compute/vertex shader 자체를 link하지 않는다. 해당 transform은 graph의 hazard가 될
수 있다. pixel output이 이후 transform과 일부 link될 여지는 공식 문서에 있지만, 실제 graph를
캡처해야 한다.

### 9.2 complex sampling

- Gaussian blur
- Lanczos/resize
- guided filter neighborhood
- morphology
- defect texture search
- warp/perspective

는 predecessor와 직접 function link할 수 없는 입력을 만든다.

### 9.3 fan-out/fan-in

source가 원본 branch와 graded/blurred branch로 나뉘었다가 합쳐지는 graph는 intermediate가
필요할 수 있다. Direct2D optimizer가 어떤 branch를 유지/재계산/materialize할지는 추측하지
않는다.

### 9.4 precision boundary

effect output precision 요구가 달라지는 경계는 link 계획과 결과에 영향을 줄 수 있다.

- 8bpc unorm
- 16bpc float
- 32bpc float

작업 범위가 필요한 Negaflow core에 낮은 precision을 허용해 link 수를 늘리지 않는다.

### 9.5 alpha boundary

premultiplied와 straight alpha 변환을 shader 사이 숨은 관례로 두면 link/non-link 결과가
달라질 수 있다. effect edge마다 alpha contract를 고정한다.

### 9.6 color-space boundary

linear working transform, display transform, ICC output transform의 경계는 성능을 위해 이동하지
않는다. color context가 다른 effect를 하나로 합친다고 수학적으로 동등해지는 것이 아니다.

### 9.7 scene position 경쟁

공식 export contract상 linked shader에서 scene position을 사용하는 function 수에 제약이 있다.
grain, vignette, overlays 등 coordinate-dependent 함수가 연속될 때 실제 link group이 분리될 수
있다.

---

## 10. 정밀도와 clipping

Microsoft는 effect graph에서 linking 여부가 intermediate precision과 clipping 동작에 영향을
줄 수 있음을 별도로 문서화한다.

### 10.1 위험 시나리오

```text
effect A: 0...1 밖의 값을 생성
effect B: 그 값을 다시 유효 범위로 가져옴
```

두 effect가 link되면 값이 register에 남을 수 있지만, link되지 않아 낮은 precision/clamping
surface에 materialize되면 정보가 사라질 수 있다. 이런 graph가 runtime 환경에 따라 다르게
보이면 안 된다.

### 10.2 결정

- core working graph에 필요한 effect output precision을 명시한다.
- link on/off 결과를 모두 golden corpus와 비교한다.
- link가 없어도 extended range를 보존해야 한다.
- “항상 link되므로 중간 precision은 중요하지 않다”는 설계를 금지한다.
- precision 지원이 부족하면 품질을 낮추지 않고 CPU fallback을 선택한다.

세부 기준은 [precision-and-clipping.md](precision-and-clipping.md)에 둔다.

---

## 11. 검증 전략

### 11.1 단위 검증

각 effect에 대해 다음을 비교한다.

- C++ scalar oracle
- CPU SIMD
- D2D full shader 독립 실행
- D2D export/link graph 실행

입력 corpus:

- 0, 1, 음수, 1 초과
- NaN, +Inf, -Inf의 정의된 처리
- grayscale, saturated primaries, near-black, highlight
- alpha 0, fractional alpha, alpha 1
- odd dimensions와 1×1

### 11.2 graph pair 검증

같은 수학을 다음 두 graph로 실행한다.

1. link를 막는 identity/hazard boundary를 둔 graph
2. link 후보가 인접한 graph

출력뿐 아니라 intermediate precision, alpha, edge ROI까지 비교한다.

### 11.3 실제 link 관찰

공개 API 수준에서 “이 transform들이 정확히 한 shader로 link됐다”는 단순 boolean에 의존하지
않는다. 다음 증거를 조합한다.

- PIX GPU capture
- Direct2D debug layer 메시지
- pass/intermediate instrumentation
- GPU event label
- transient resource count
- shader invocation/pass timing

captured artifact에는 다음을 남긴다.

```text
scenario ID
GPU vendor/device/driver
Windows build
Windows App SDK version
D3D feature level
effect graph hash
shader manifest hashes
observed pass count
observed intermediate formats
linked group observation
output metric
```

### 11.4 벤더 matrix

- Intel integrated GPU
- AMD integrated/discrete GPU
- NVIDIA discrete GPU
- Qualcomm ARM64 GPU
- WARP diagnostic path

WARP 결과는 소프트웨어 reference/diagnostic일 수 있지만 일반 export의 강제 기본값으로 삼지
않는다.

---

## 12. 성능 판정

linking의 가치는 다음으로 측정한다.

- GPU pass 감소
- intermediate bytes 감소
- peak GPU memory 감소
- preview p50/p95 latency
- export throughput
- shader/link preparation overhead
- driver별 hitch/regression

### 12.1 비교 시나리오

- 긴 point transform chain
- point → blur → point
- fan-out/fan-in halation
- guided filter
- multiple local masks
- display ICC를 포함한 viewport
- 16-bit TIFF full export
- 8-bit JPEG batch export

### 12.2 채택 기준

- correctness 결과가 link off와 동등함
- 적어도 주요 장치군에서 end-to-end 이득이 있음
- 특정 driver에서 심한 hitch/crash가 없음
- artifact/build 복잡성이 유지 가능함
- fallback이 항상 존재함

한 vendor에서만 빨라지고 다른 vendor에서 regression이면 graph별 또는 capability-class별로
link 후보를 제한할 수 있다. 이 제한은 vendor 이름 하드코딩보다 재현 가능한 driver/capability
quarantine 데이터에 근거해야 한다.

---

## 13. 실패와 fallback

| 실패 | 처리 |
|---|---|
| export function 누락 | full shader로 실행; CI는 실패 |
| combined blob load 실패 | 해당 GPU effect 비활성화, CPU fallback |
| effect registration 실패 | capability에서 제외, 사용자 작업은 유지 |
| runtime link 미선택 | 정상; full shader pass로 실행 |
| link 결과 correctness 불일치 | 해당 graph/effect linking 비활성화, release 차단 |
| 특정 driver crash | 최소 재현 확보, driver range quarantine, CPU/D2D 대체 |
| precision 미지원 | 낮은 품질 surface 대신 CPU fallback |
| device loss | graph 결과 폐기, device 재생성 후 재계획 |

“link되지 않음” 자체는 오류가 아니다. “link 여부에 따라 결과가 달라짐”은 오류다.

---

## 14. 구현 체크리스트

### artifact

- [ ] pinned Windows SDK와 FXC 버전
- [ ] 모든 D2D custom effect에 full shader
- [ ] 가치 있는 pixel effect에 embedded export function
- [ ] manifest에 sampling/scene-position/reflection 정보
- [ ] source/artifact hash drift CI
- [ ] runtime HLSL compile 없음

### correctness

- [ ] scalar/full/export 비교
- [ ] link 후보 graph와 forced-boundary graph 비교
- [ ] extended-range/alpha/NaN corpus
- [ ] ROI와 tile seam 비교
- [ ] Intel/AMD/NVIDIA/Qualcomm matrix
- [ ] CPU fallback 동등성

### performance

- [ ] PIX capture
- [ ] observed pass/intermediate 기록
- [ ] preview/export end-to-end 비교
- [ ] cold/warm shader load 구분
- [ ] peak GPU memory 비교
- [ ] driver quarantine 근거와 expiry/retest 정책

---

## 15. 금지 사항

- Metal `[[stitchable]]`이라는 이유만으로 D2D linkable로 표시하지 않는다.
- 현재 31개 함수 중 고정 N개가 link된다고 문서화하지 않는다.
- `SIMPLE`을 성능 목적으로 거짓 선언하지 않는다.
- export function만 제공하고 full shader fallback을 제거하지 않는다.
- runtime에서 HLSL을 임의 컴파일하지 않는다.
- link 수를 늘리려고 working precision을 낮추지 않는다.
- link on/off에 따라 제품 결과가 달라지는 상태로 출시하지 않는다.
- D3D12/DXC/CUDA를 Direct2D linking 필수 의존성으로 만들지 않는다.
- WARP를 모든 최종 export의 강제 기본값으로 만들지 않는다.

---

## 16. 공식 자료

- [Effect Shader Linking](https://learn.microsoft.com/en-us/windows/win32/direct2d/effect-shader-linking)
- [HLSL Helpers](https://learn.microsoft.com/en-us/windows/win32/direct2d/hlsl-helpers)
- [Custom effects](https://learn.microsoft.com/en-us/windows/win32/direct2d/custom-effects)
- [`ID2D1EffectContext::LoadPixelShader`](https://learn.microsoft.com/en-us/windows/win32/api/d2d1effectauthor/nf-d2d1effectauthor-id2d1effectcontext-loadpixelshader)
- [Precision and numerical clipping in effect graphs](https://learn.microsoft.com/en-us/windows/win32/direct2d/precision-and-clipping-in-effect-graphs)
- [FXC syntax](https://learn.microsoft.com/en-us/windows/win32/direct3dtools/fxc-syntax)

공식 문서는 기능과 build contract의 근거다. Negaflow의 특정 graph가 실제로 link되는지와 성능
이득은 이 문서의 capture gate로 별도 입증한다.

---

## 17. 관련 문서

- [pipeline-shape.md](pipeline-shape.md)
- [direct2d-effects.md](direct2d-effects.md)
- [precision-and-clipping.md](precision-and-clipping.md)
- [roi-and-invalidation.md](roi-and-invalidation.md)
- [../02-shaders/kernel-inventory.md](../02-shaders/kernel-inventory.md)
- [../02-shaders/metal-to-hlsl.md](../02-shaders/metal-to-hlsl.md)
- [../12-performance/backend-selection.md](../12-performance/backend-selection.md)
- [../12-performance/gpu-vendor-portability.md](../12-performance/gpu-vendor-portability.md)

---

## 18. 완료 판정

이 문서는 export function이 생성됐다는 사실만으로 완료되지 않는다. 다음 세 가지가 모두 있어야
한다.

1. **artifact 증거**: full + export blob, manifest, pinned toolchain
2. **correctness 증거**: full/link/CPU 결과 비교
3. **runtime 증거**: 대표 장치의 실제 graph capture와 pass/intermediate 측정

세 증거가 없으면 상태는 `link-candidate`이며 `link-observed`가 아니다.
