# Direct2D effect 계층 설계

상태: 1차 기준선 확정  
최종 코드·공식 문서 대조: 2026-08-04  
대상: Core Image 기반 Negaflow 렌더를 D3D11 + Direct2D에 옮기는 기준

---

## 1. 결정

Direct2D Effects는 Windows Negaflow의 **2D GPU effect graph와 화면 합성의 기준 계층**으로
사용한다. 다만 Core Image와 “진짜 등가물”이라고 부르지는 않는다.

두 프레임워크는 composable image effects와 custom shader를 지원하지만 다음이 다르다.

- 그래프 평가와 캐시 정책
- ROI/invalid rect 계약
- 타일링 방식
- color-management 통합
- 지원 pixel format과 precision
- built-in filter 수학
- random generator
- CPU/software 실행 모델
- custom kernel ABI와 shader linking

따라서 구조는 대응시키되 각 stage의 수학, edge behavior, precision, ROI를 별도로 검증한다.

Windows 기준선:

- D3D11 device
- Direct2D device/device context
- Direct2D built-in effects
- Negaflow custom `ID2D1EffectImpl` + transform
- DirectCompute 또는 CPU 보조 경로
- WinUI 3 canvas와 DXGI surface 연동
- CPU scalar/SIMD correctness fallback

D3D12, D3D11On12, CUDA는 기준선이 아니다.

---

## 2. Direct2D가 맡는 범위

### 맡는다

- viewport용 2D image graph
- point color transforms
- blur, affine/perspective transform, blend 등 검증된 built-in effect
- HLSL custom pixel effects
- 일부 custom compute effect
- effect ROI/invalid rectangle propagation
- GPU surface composition
- 인접 pixel transform의 선택적 shader linking

### 단독으로 맡지 않는다

- RAW decode
- 전체 image source/virtual tile cache
- catalog와 recipe persistence
- scanner plugin IPC
- ICC profile parsing/validation 전체
- histogram/reduction의 유일 구현
- connected-component defect 분석
- batch job scheduling
- export format encoding 전체
- CPU fallback 선택과 scalar oracle

Direct2D는 렌더 backend의 중심이지만 제품 전체 image pipeline을 대신하지 않는다.

---

## 3. Core Image와의 대응은 번역표이지 동일성 증명이 아니다

| macOS 개념 | Windows 후보 | 주의점 |
|---|---|---|
| `CIImage` graph value | internal image node + `ID2D1Image` | lifetime/cache/extent 의미가 다름 |
| `CIFilter` | built-in/custom `ID2D1Effect` | 수학과 parameter range를 비교해야 함 |
| `CIKernel`/Metal stitchable | custom D2D effect HLSL | ABI와 sampling contract가 다름 |
| Core Image ROI | `ID2D1Transform` mapping methods | 직접 정확히 구현해야 함 |
| `CIContext` | D2D device context + D3D device resources | thread/device-loss 규칙을 별도 관리 |
| `CIRenderDestination` | DXGI/D2D target 또는 export staging | format/color context를 명시해야 함 |
| Core Image color context | D2D color context + LittleCMS/output layer | ICC 기능 범위가 같지 않음 |
| Core Image software render | C++ CPU backend 또는 explicit WARP device | 자동 per-effect CPU fallback이 아님 |

“API 이름이 대응된다”와 “Negaflow 결과가 동등하다”를 구분한다.

---

## 4. custom effect 구성요소

Microsoft의 custom effect 모델은 네 부분으로 나뉜다.

1. **effect interface**
   - 앱이 effect를 생성하고 property/input을 설정하는 표면
   - `ID2D1EffectImpl`
2. **transform graph**
   - effect 내부 연산 node와 edge
   - property에 따라 node를 추가·제거·재배치할 수 있음
3. **transform**
   - 실제 image operation
   - output bounds와 필요한 input rect를 계산
4. **shader**
   - HLSL bytecode
   - pixel/vertex/compute 실행

Negaflow custom effect는 “HLSL 한 파일”만으로 끝나지 않는다. 다음 artifact가 함께 있어야 한다.

```text
effect metadata/CLSID
effect implementation
transform implementation
ROI mapping
property schema
constant-buffer ABI
compiled shader artifact
shader manifest
CPU oracle
golden tests
diagnostics label
```

---

## 5. 인터페이스 선택

### 5.1 `ID2D1DrawTransform`

pixel shader 또는 vertex + pixel shader 기반 연산에 사용한다.

적합 후보:

- negative inversion
- tone/color point transforms
- LUT sampling
- same-coordinate combine
- coordinate overlay
- custom resampling이 필요한 제한된 효과

### 5.2 `ID2D1ComputeTransform`

Direct2D graph 안에서 compute shader가 필요한 경우 사용한다.

후보:

- 특정 neighborhood operation
- guided filter의 일부
- morphology
- output이 일반 2D image로 이어지는 compute stage

하지만 histogram처럼 output이 scalar/buffer이고 control plane으로 나가는 reduction은 별도
D3D11 DirectCompute service가 더 단순할 수 있다. 모든 compute를 custom effect로 감싸지 않는다.

### 5.3 `ID2D1SourceTransform`

CPU memory/source data를 D2D graph에 공급하는 source transform 후보가 될 수 있다. 그러나 대형
image decode와 tile cache 전체를 한 effect에 숨기지 않는다. image source 계층에서 resource
lifetime, decode cancellation, cache budget을 통제한다.

### 5.4 built-in effect

수학과 edge behavior가 맞으면 custom effect보다 built-in을 우선한다.

- Gaussian Blur
- Color Matrix
- 2D Affine Transform
- Perspective Transform
- Composite/Blend
- Crop
- Scale
- Unpremultiply/Premultiply
- Color Management

단 “이름이 같다”는 이유만으로 선택하지 않는다. filter radius, sigma, sampling, border mode,
alpha, interpolation, precision, color domain을 corpus로 비교한다.

---

## 6. 현재 Core Image 사용 inventory와 Windows 후보

현재 `Sources/Chromabase`에서 반복 사용되는 Core Image 기능을 기준으로 한 1차 표다.

| 현재 사용 | Windows 1차 후보 | 검증 포인트 |
|---|---|---|
| `CIColorMatrix` | D2D Color Matrix 또는 custom point effect | bias, alpha, extended range |
| `CIColorControls` | custom point effect | saturation/brightness/contrast 수학 순서 |
| `CIColorClamp` | custom explicit clamp | clamp 위치와 alpha |
| `CIGaussianBlur` | D2D Gaussian Blur | sigma/radius, border, extent growth |
| `CIUnsharpMask` | blur + custom combine | radius/intensity 정의, edge |
| `CILanczosScaleTransform` | D2D Scale 또는 custom/CPU resampler | kernel, phase, alpha, sharpness |
| `CIRandomGenerator` | deterministic coordinate hash/texture source | seed, distribution, tile stability |
| `CIRadialGradient` | custom procedural effect | coordinate and extent |
| `CIScreenBlendMode` | D2D Blend 또는 custom | linear/gamma domain, alpha |
| local masks | source + blur + combine graph | coordinate, invalidation, resolution |
| custom Metal kernels | custom D2D effect HLSL | scalar parity, precision, linking |

각 mapping에는 상태를 둔다.

```text
unassessed
candidate
scalar-matched
GPU-matched
edge-matched
vendor-validated
production-approved
```

---

## 7. effect registration과 lifecycle

### 7.1 등록

custom effect는 stable CLSID와 registration metadata를 가진다.

- effect 이름
- author/category/description
- input count
- property 이름·type·default/range
- setter/getter binding

CLSID는 algorithm version마다 무조건 새로 만들지 않는다. public effect identity와 shader/
algorithm version을 분리하고, ABI/semantic compatibility가 깨질 때 migration 전략을 정한다.

### 7.2 `Initialize`

`ID2D1EffectImpl::Initialize`에서 필요한 transform과 초기 graph를 만든다.

- shader bytecode load
- transform object 생성
- graph node 연결
- capability-dependent 경로 선택

실패 시 부분 초기화 object를 남기지 않는다.

### 7.3 `PrepareForRender`

property 또는 context 상태 변경에 대응한다.

- normalized property 검증
- constant buffer 갱신
- optional graph topology 갱신
- DPI-dependent 값 재계산

렌더마다 동일 constant buffer를 다시 생성하거나 shader를 reload하지 않는다.

### 7.4 `SetGraph`

variable input effect만 필요한 graph 재구성을 한다. 고정 input effect는 계약에 맞게 처리하고,
불필요한 dynamic topology를 만들지 않는다.

### 7.5 device lifetime

effect object와 resource는 device generation에 귀속시킨다.

- D3D device removed/reset 감지
- 이전 generation의 effect/cache 폐기
- 새 D2D device/context에서 registration/resource 재생성
- 진행 중 결과는 revision gate에서 폐기
- source/recipe는 보존

---

## 8. property와 constant-buffer ABI

### 8.1 공개 property와 내부 ABI 분리

UI/C# property를 HLSL cbuffer memory에 그대로 직렬화하지 않는다.

```text
C# UI value
→ validated native command/recipe
→ normalized C++ parameter object
→ explicit HLSL constant-buffer packer
→ reflected byte layout
```

### 8.2 HLSL packing

- 16-byte register packing을 명시한다.
- `bool`을 언어 간 ABI에 직접 노출하지 않는다.
- vector/matrix row/column-major를 고정한다.
- padding byte를 초기화한다.
- enum을 fixed-width integer로 정규화한다.
- NaN/Inf/range를 GPU 제출 전에 검증한다.

### 8.3 버전

manifest에 다음을 남긴다.

- property schema version
- algorithm version
- cbuffer byte size
- field offset/type
- reflection hash
- shader bytecode hash

CI에서 C++ packer offset과 shader reflection을 대조한다.

---

## 9. HLSL 규칙

### 9.1 D2D helper

link 후보 custom pixel effect는 Windows SDK의 `d2d1effecthelpers.hlsli`를 사용한다.

```hlsl
#define D2D_INPUT_COUNT 3
#define D2D_INPUT0_SIMPLE
#define D2D_INPUT1_SIMPLE
#define D2D_INPUT2_COMPLEX
#include <d2d1effecthelpers.hlsli>
```

- input count 선언은 필수다.
- 선언하지 않은 input sampling은 complex가 기본이다.
- `SIMPLE`은 같은 logical location의 한 input value 계약이다.
- offset/arbitrary sampling은 `COMPLEX`다.
- scene position은 실제 필요한 경우만 선언한다.

세부 내용은 [shader-linking.md](shader-linking.md)에 둔다.

### 9.2 좌표계

shader마다 다음을 문서화한다.

- output pixel coordinate
- input image coordinate
- scene position
- normalized coordinate 사용 여부
- tile origin
- crop/rotate 전후 coordinate
- mask coordinate

Core Image의 `dest.coord()`를 기계적으로 HLSL UV로 바꾸면 half-pixel, origin, transform 오류가
생길 수 있다. identity, 1-pixel edge, odd dimension, rotated crop corpus로 검증한다.

### 9.3 alpha

각 input/output에 다음 중 하나를 선언한다.

- opaque RGB
- straight alpha
- premultiplied alpha

현상 core가 사실상 opaque 사진을 다루더라도 PNG/overlay/mask 경로의 alpha를 암묵적으로
버리면 안 된다. D2D built-in effect가 기대하는 alpha mode와 custom math를 맞춘다.

### 9.4 색 도메인

각 effect는 다음을 갖는다.

- input primaries/white point
- transfer function 상태
- linear/nonlinear domain
- numeric range
- output domain

Direct2D가 알아서 Negaflow working space를 추론한다고 가정하지 않는다.

---

## 10. ROI와 invalid rectangle

custom transform은 다음 mapping을 정확히 구현해야 한다.

- output rect → 필요한 input rects
- input rects → output rect + opaque rect
- invalid input rect → invalid output rect

예:

| effect | output→input |
|---|---|
| point transform | 동일 rect |
| radius `r` blur | 각 방향 `r` 이상 확장; 실제 kernel footprint 기준 |
| affine transform | output rect inverse map + interpolation footprint |
| displacement/warp | 변위 한계 포함 |
| global histogram-dependent effect | measurement plane 분리; 숨은 full-frame read 금지 |
| connected defect structure | 별도 global/coarse pass 또는 full-image dependency 명시 |

Direct2D가 ROI를 호출해 준다는 사실이 올바른 ROI를 자동 생성해 주는 것은 아니다. 잘못된
mapping은 seam, stale pixel, out-of-bounds read, 불필요한 full-frame render를 만든다.

자세한 기준은 [roi-and-invalidation.md](roi-and-invalidation.md)에 둔다.

---

## 11. output rect와 opaque rect

`MapInputRectsToOutputRect`는 output bounds뿐 아니라 opaque sub-rectangle을 보고할 수 있다.

원칙:

- 확실히 불투명하다고 증명할 수 있는 범위만 opaque로 보고한다.
- blur, transform, alpha combine 뒤의 opaque 범위를 과장하지 않는다.
- 사진 source가 opaque여도 transparent border를 만드는 transform은 output 전체를 opaque로
  보고하면 안 된다.
- 불확실하면 conservative empty/smaller opaque rect가 correctness 면에서 안전하다.

잘못된 opaque rect는 단순 성능 손실이 아니라 잘못된 composition 결과를 만들 수 있다.

---

## 12. built-in effect 사용 기준

### 12.1 채택 순서

1. current macOS stage의 수학/extent/edge 계약 추출
2. D2D built-in effect candidate 구성
3. CPU oracle 및 macOS golden과 비교
4. precision과 vendor matrix 확인
5. 맞지 않으면 custom HLSL/CPU 구현

### 12.2 Gaussian blur

확인할 항목:

- standard deviation과 macOS radius mapping
- optimization mode가 결과에 미치는 영향
- border mode
- output extent growth
- alpha premultiplication
- 16/32bpc behavior
- tile apron

### 12.3 scale/Lanczos

export resize는 품질 민감하다.

- downscale/upscale kernel
- pixel-center phase
- anisotropic scale
- aspect ratio
- sharpness/ringing
- alpha
- large-image tile seam

D2D built-in scale이 현재 `CILanczosScaleTransform`과 충분히 맞지 않으면 C++ resampler 또는
custom compute를 선택한다. 속도를 위해 export 품질을 낮추지 않는다.

### 12.4 color matrix/controls

matrix 자체뿐 아니라 bias와 alpha handling을 확인한다. `CIColorControls`는 D2D의 유사 이름
effect로 추정하지 않고 현재 수식을 C++/HLSL로 명시하는 쪽을 우선한다.

### 12.5 random generator

Core Image random output의 bit-identical 복제를 목표로 삼지 않는다. 대신 Windows의 제품 계약을
정한다.

- recipe 기반 seed
- absolute pixel coordinate
- tile-order 독립
- repeatable export
- grain distribution과 spectrum 검증
- dither amplitude/quantization 검증

---

## 13. compute 사용 결정

### 13.1 feature 확인

custom compute effect 또는 DirectCompute job은 device capability를 먼저 확인한다.

- D3D feature level
- compute shader 지원
- required typed UAV/load/store
- resource format
- maximum dimensions/thread groups
- shared memory 요구

지원하지 않는 경우 effect 생성 단계에서 명시적으로 capability failure를 반환하고 CPU 경로로
재계획한다.

### 13.2 후보

- histogram/reduction
- guided filter
- morphology
- large-kernel neighborhood operation
- structured defect prepass

### 13.3 pixel effect를 유지할 조건

- 단순 point math
- built-in D2D graph와 자연스럽게 연결
- compute 전환의 UAV/resource barrier 비용이 큼
- linking 이득 가능
- ROI가 pixel transform에서 더 단순

### 13.4 CPU를 유지할 조건

- 작은 proxy
- sparse data
- branching이 많음
- component/graph traversal
- GPU readback이 필수라 이득이 사라짐
- ARM64/x64 SIMD로 충분히 빠름

---

## 14. software 실행과 WARP

이전 문서의 “Direct2D가 CPU fallback을 자동 제공한다”는 표현은 폐기한다.

WARP는 Microsoft의 software rasterizer로 D3D device를 명시적으로 만들 수 있는 선택지다.
Negaflow가 개별 effect 실패 시 자동으로 같은 graph를 CPU로 바꿔 주는 기능으로 해석하면 안 된다.

Windows fallback 계층:

1. hardware D3D11 + Direct2D
2. 동일 기능의 C++ scalar/SIMD CPU backend
3. WARP는 진단, CI, 제한된 compatibility spike

WARP를 모든 final export의 강제 기본값으로 쓰지 않는다. 대형 32bpc image workload에서 CPU
전용 구현보다 빠르거나 안정적이라는 실측이 없기 때문이다.

fallback은 해상도, bit depth, ICC, 품질을 낮추지 않는다.

---

## 15. device/context 구조

### 15.1 device 생성

하나의 graphics device domain 안에서 다음을 공유한다.

- DXGI adapter 선택
- D3D11 device/context
- Direct2D factory/device
- D2D device contexts
- display swap-chain resources
- compute/shared textures

UI와 export가 무조건 하나의 immediate context를 동시에 두드리지 않게 scheduling ownership을
정한다.

### 15.2 multithreading

- Direct2D factory threading mode를 설계와 맞춘다.
- device context를 여러 thread에서 동시에 사용하지 않는다.
- worker별 context 또는 단일 render scheduler 중 하나를 명확히 선택한다.
- resource creation과 draw submission lock 범위를 측정한다.
- C# UI thread는 native GPU work 완료를 동기 대기하지 않는다.

### 15.3 device loss

다음 HRESULT와 device-removed reason을 처리한다.

- target recreation 요구
- DXGI device removed/reset/hung
- out-of-memory

처리 순서:

1. 현재 GPU result를 실패/stale 처리
2. UI에 잘못된 이전 frame을 새 revision 결과로 적용하지 않음
3. device-owned cache와 effect 해제
4. adapter/capability 재탐색
5. device generation 증가
6. graph 재계획
7. 필요하면 CPU fallback

---

## 16. WinUI 3 canvas 연동

Direct2D output을 일반 XAML `Image` bitmap으로 매 슬라이더 변경마다 복사하지 않는다.

1차 방향:

- `SwapChainPanel` 또는 검증된 composition surface
- DXGI swap chain
- D3D11/Direct2D interop surface
- XAML은 toolbar/inspector/overlay interaction 담당
- native render service는 frame와 synchronization 담당

확인할 항목:

- logical DPI와 physical pixel size
- resize race
- occlusion/minimize
- monitor 전환과 ICC
- HDR/SDR surface format
- device loss
- overlay coordinate
- screen reader와 keyboard focus는 XAML layer에서 유지

세부 UI 연결은 [../08-ui/swapchainpanel-canvas.md](../08-ui/swapchainpanel-canvas.md)에 둔다.

---

## 17. 캐시

### 17.1 장기 캐시 금지 대상

- device context에 종속된 임시 target
- 이전 device generation resource
- stale recipe revision intermediate
- monitor profile이 바뀐 display bitmap

### 17.2 재사용 후보

- compiled shader bytecode
- effect registration
- immutable LUT texture
- validated ICC transform object
- decode tile
- 동일 recipe prefix의 expensive intermediate

### 17.3 key

```text
device generation
source content revision
recipe prefix hash
algorithm/shader version
resolution
ROI/tile
precision
color context
output intent
```

---

## 18. diagnostics

각 render capture에서 다음을 볼 수 있어야 한다.

- effect semantic name
- algorithm version
- property snapshot hash
- backend: built-in D2D/custom pixel/custom compute/CPU
- input/output format
- input/output rect
- requested apron
- observed pass/intermediate
- shader hash
- device/driver
- duration
- fallback reason
- device generation

사용자 로그에는 사진 pixel이나 전체 경로 같은 개인정보를 기본 포함하지 않는다. source는
salted/ephemeral identifier로 표시한다.

---

## 19. 검증 matrix

### 19.1 effect 단위

- scalar oracle
- D2D built-in candidate
- custom full shader
- link candidate graph
- CPU SIMD

### 19.2 입력

- black/white/gray
- saturated color patches
- negative and >1 values
- NaN/Inf 정책
- alpha 0/partial/1
- 1×1, odd dimension, very large
- high-frequency pattern
- edge impulse
- color ramp

### 19.3 장치

- Intel x64 iGPU
- AMD x64 iGPU/dGPU
- NVIDIA x64 dGPU
- Qualcomm ARM64 GPU
- x64 CPU fallback
- ARM64 CPU fallback
- WARP diagnostic

### 19.4 판정

- numeric error distribution
- maximum/outlier error
- extent/ROI exactness
- tile seam
- alpha correctness
- ICC/display boundary
- device-loss recovery
- memory peak
- preview/export performance

---

## 20. 구현 순서

### Phase 1 — infrastructure

- D3D11/D2D device domain
- custom effect registration
- shader artifact manifest
- scalar oracle harness
- WinUI surface proof

### Phase 2 — point effects

- inversion
- tone
- grading/mixer/calibration
- LUT
- full shader path
- optional linking artifact

### Phase 3 — built-in graph

- color matrix
- blur
- transform
- blend/composite
- precision/ROI tests

### Phase 4 — complex effects

- denoise
- halation
- local masks
- defect stages
- DirectCompute/CPU selector

### Phase 5 — production hardening

- device matrix
- device loss/OOM
- render capture
- performance budgets
- driver quarantine

---

## 21. 금지 사항

- Direct2D를 Core Image와 자동 동등하다고 선언하지 않는다.
- Direct2D가 타일·ROI·CPU fallback을 모두 알아서 처리한다고 쓰지 않는다.
- 비공식 제3자 앱의 구현 설명을 Negaflow 아키텍처 근거로 삼지 않는다.
- built-in effect의 이름만 보고 current macOS 수학과 같다고 가정하지 않는다.
- D2D graph 안에 catalog, scanner IPC, batch scheduler를 넣지 않는다.
- unsupported GPU에서 silent low-precision fallback을 하지 않는다.
- WARP를 자동 per-effect fallback 또는 모든 export 기본으로 쓰지 않는다.
- UI thread에서 GPU completion을 동기 대기하지 않는다.
- device generation이 다른 resource를 재사용하지 않는다.
- HLSL constant buffer에 C# object memory를 직접 복사하지 않는다.

---

## 22. 공식 자료

- [Custom effects](https://learn.microsoft.com/en-us/windows/win32/direct2d/custom-effects)
- [Effects overview](https://learn.microsoft.com/en-us/windows/win32/direct2d/effects-overview)
- [Built-in effects](https://learn.microsoft.com/en-us/windows/win32/direct2d/built-in-effects)
- [HLSL Helpers](https://learn.microsoft.com/en-us/windows/win32/direct2d/hlsl-helpers)
- [Effect Shader Linking](https://learn.microsoft.com/en-us/windows/win32/direct2d/effect-shader-linking)
- [Precision and numerical clipping in effect graphs](https://learn.microsoft.com/en-us/windows/win32/direct2d/precision-and-clipping-in-effect-graphs)
- [Supported pixel formats and alpha modes](https://learn.microsoft.com/en-us/windows/win32/direct2d/supported-pixel-formats-and-alpha-modes)
- [Direct2D custom image effects sample](https://github.com/microsoft/Windows-universal-samples/tree/main/Samples/D2DCustomEffects)
- [Direct3D WARP guide](https://learn.microsoft.com/en-us/windows/win32/direct3darticles/directx-warp)

공식 자료는 API 계약의 근거다. Negaflow 결과 동등성은 repository-derived scalar/golden tests로
별도 입증한다.

---

## 23. 관련 문서

- [pipeline-shape.md](pipeline-shape.md)
- [shader-linking.md](shader-linking.md)
- [precision-and-clipping.md](precision-and-clipping.md)
- [roi-and-invalidation.md](roi-and-invalidation.md)
- [../02-shaders/kernel-inventory.md](../02-shaders/kernel-inventory.md)
- [../02-shaders/metal-to-hlsl.md](../02-shaders/metal-to-hlsl.md)
- [../03-measurement/histogram-and-statistics.md](../03-measurement/histogram-and-statistics.md)
- [../06-large-images/image-source-tiling.md](../06-large-images/image-source-tiling.md)
- [../08-ui/swapchainpanel-canvas.md](../08-ui/swapchainpanel-canvas.md)
- [../12-performance/backend-selection.md](../12-performance/backend-selection.md)

---

## 24. 완료 조건

- [ ] Core Image 사용 inventory가 전부 mapping 상태를 가짐
- [ ] custom effect lifecycle과 ABI가 spike로 검증됨
- [ ] built-in effect 후보가 scalar/macOS golden과 비교됨
- [ ] ROI/opaque/invalid rect corpus가 통과함
- [ ] 32bpc float working graph capability가 장치별 확인됨
- [ ] alpha/color-domain contract가 모든 edge에 있음
- [ ] full/link custom shader가 CPU oracle과 일치함
- [ ] WinUI surface에서 resize/DPI/monitor/device-loss가 검증됨
- [ ] x64/ARM64 CPU fallback이 기능과 품질을 보존함
- [ ] Intel/AMD/NVIDIA/Qualcomm GPU matrix가 통과함
- [ ] 성능 capture가 실제 loaded photo와 large virtual batch를 포함함

이 조건 전에는 “Core Image 대응 계층 완료”라고 선언하지 않는다.
