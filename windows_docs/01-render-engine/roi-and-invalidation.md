# ROI, 타일, 무효화 계약

상태: 1차 기준선 확정  
최종 코드·공식 문서 대조: 2026-08-04  
대상: Direct2D custom effects, 대형 이미지, local masks, defect 편집, render cache

---

## 1. 결정

Windows Negaflow는 ROI를 Direct2D가 자동 해결하는 최적화로 취급하지 않는다.

- 각 render node가 output ROI → input ROI mapping을 명시한다.
- Direct2D custom transform의 세 rect mapping method를 정확히 구현한다.
- app-level tile planner와 Direct2D 내부 rendering implementation을 구분한다.
- 고정 기본 tile size를 제품 계약으로 쓰지 않는다.
- spatial filter는 명시적인 apron/halo를 가진다.
- global measurement와 local render를 분리한다.
- source, recipe, measurement, mask, display profile의 invalidation을 별도 추적한다.
- 비동기 완료 직전에 frame/revision/session identity를 재검증한다.
- macOS의 기존 crop/ROI 상수는 코드 근거로 inventory하되 Windows에서 자동으로 영구 고정하지
  않는다.

Direct2D는 rect mapping을 호출하고 graph에 전파할 수 있지만, 올바른 rect·좌표계·cache key를
설계하는 책임은 Negaflow에 있다.

---

## 2. ROI가 필요한 이유

필름 스캔은 수천만~수억 pixel일 수 있고 working surface는 pixel당 16 bytes다. 작은 슬라이더
변경이나 defect brush 편집마다 full frame과 모든 intermediate를 다시 만들면 다음 문제가 생긴다.

- interactive latency 증가
- GPU/CPU memory peak 증가
- decode와 upload 반복
- batch export starvation
- 장시간 작업 중 stale result race

ROI는 다음 세 목적을 동시에 해결해야 한다.

1. **correctness**: filter가 필요한 이웃 pixel을 빠뜨리지 않음
2. **performance**: 실제 필요한 영역만 계산
3. **cache safety**: 바뀐 영역과 바뀐 의미만 정확히 무효화

ROI를 작게 만드는 것보다 결과가 full-frame reference와 같게 만드는 것이 먼저다.

---

## 3. 좌표 공간

Negaflow는 최소 다음 좌표 공간을 구분한다.

| 공간 | 단위/원점 | 용도 |
|---|---|---|
| encoded source | 파일 pixel, orientation 적용 전 | decoder/raw identity |
| oriented source | 정수 pixel, 정규 orientation | develop source |
| normalized recipe | 보통 0...1 | crop/mask persistence |
| working image | 정수 pixel rect | render graph |
| transformed output | crop/rotate/perspective 이후 pixel | 최종 작업 이미지 |
| preview proxy | 축소 pixel | viewport render/측정 |
| viewport | device-independent pixel | WinUI input/layout |
| swap-chain | physical pixel | 화면 target |
| print page | point/mm + raster pixel | print composition |
| scanner bed | 장치 physical/unit coordinates | scan ROI |

### 3.1 원점

현재 macOS defect code에는 bitmap label row가 y-down이고 Core Image ROI가 y-up인 변환 경계가
있다. Windows에서는 한쪽을 암묵적으로 뒤집지 않는다.

권장 내부 규칙:

- raster storage: top-left, x-right, y-down
- normalized persisted crop/mask: top-left, x-right, y-down
- D2D integer rect: 해당 image node의 pixel space
- HLSL texture coordinate: wrapper가 명시적으로 변환
- print layout: 문서 계약대로 별도 변환

macOS sidecar와의 호환을 위해 기존 persisted 의미를 먼저 확인하고 importer에서 한 번만
canonicalize한다.

### 3.2 정수 rect

`D2D1_RECT_L`은 정수 경계 rect다. 내부 공통 규칙:

```text
left/top inclusive
right/bottom exclusive
width  = right - left
height = bottom - top
```

- empty rect 허용 의미를 정의한다.
- negative origin이 가능한 effect extent를 처리한다.
- 32-bit rect 산술 전 overflow를 확인한다.
- float transform bounds를 정수로 바꿀 때 floor(min), ceil(max)를 사용한다.
- sampling footprint를 반올림 뒤 추가한다.

### 3.3 pixel center

- integer pixel index와 sample center `(x + 0.5, y + 0.5)`를 구분한다.
- normalized coordinate는 image dimension과 center phase를 포함한다.
- resize/rotate/crop에서 half-pixel drift를 corpus로 검증한다.
- mask stroke와 image transform이 동일 matrix chain을 사용한다.

---

## 4. Direct2D의 세 mapping method

### 4.1 `MapInputRectsToOutputRect`

input bounds와 opaque sub-rects를 받아 output bounds와 opaque sub-rect를 계산한다.

공식 contract의 중요한 부분:

- input rect는 input bounds다.
- input count는 transform input 수와 같다.
- transform의 shader/software callback은 이 계산을 지켜야 한다.
- renderer가 정해진 rendering algorithm 위치에서 명시적으로 호출한다.
- `MapInvalidRect`와 `MapOutputRectToInputRects`보다 먼저 호출된다.
- 이 method는 input bounds를 바탕으로 필요한 state를 갱신할 수 있다.

용도:

- scale/transform 후 output extent
- crop
- border/blur extent growth
- 여러 input의 union/intersection
- opaque output의 conservative 계산

### 4.2 `MapOutputRectToInputRects`

요청된 output rect를 올바르게 계산하는 데 필요한 각 input sample rect를 반환한다.

공식 contract:

- input rect array는 transform input 순서와 일치한다.
- method는 pure function처럼 동작해야 한다.
- 현재 effect property/state를 읽을 수 있다.
- 호출 때문에 state를 바꾸면 안 된다.
- Direct2D가 임의의 시점·순서로 호출할 수 있다.

예:

```text
point effect: input = output
radius-r convolution: input = inflate(output, footprint(r))
affine transform: input = inverseMap(output) + interpolation footprint
source + mask: image input = output, mask input = mapMask(output)
```

### 4.3 `MapInvalidRect`

한 input의 invalid rect가 output에서 어떤 rect를 무효화하는지 계산한다.

공식 contract:

- input index와 invalid input rect를 받는다.
- 해당 output invalid rect를 반환한다.
- `MapInputRectsToOutputRect` 이후 임의 시점·순서로 호출될 수 있다.
- pure function이어야 하며 state를 변경하면 안 된다.

예:

```text
point effect: output invalid = input invalid
blur: output invalid = inflate(input invalid, radius)
scale: output invalid = forwardMap(input invalid) + footprint
mask combine: mask invalid을 image output 공간으로 변환
```

### 4.4 세 method의 대칭성

forward bounds, backward sample ROI, forward invalidation은 같은 geometry contract에서 파생해야
한다. 서로 다른 상수와 반올림 코드를 세 곳에 복사하지 않는다.

```text
GeometryModel
  ├─ outputBounds(inputs)
  ├─ requiredInputs(outputRequest)
  └─ affectedOutput(inputChange)
```

공통 모델이 있더라도 Direct2D interface별 순수성·호출 순서 contract는 지킨다.

---

## 5. node별 ROI 규칙

### 5.1 point transform

```text
required input rect = output rect
invalid output rect = invalid input rect
```

tone, grade, calibration, per-pixel LUT combine 등이 해당한다. scene position만 사용하는 procedural
effect는 source input ROI는 같아도 tile origin/state가 결과에 영향을 주지 않게 해야 한다.

### 5.2 fixed-radius filter

```text
required input = inflate(output, apron)
affected output = inflate(changed input, apron)
```

`apron`은 UI radius 값을 그대로 정수화한 숫자가 아니라 실제 discrete kernel footprint다.

- Gaussian truncate factor
- separable pass
- interpolation tap
- morphology radius
- repeated blur

를 포함한다.

### 5.3 multi-stage spatial graph

연속된 공간 stage는 apron이 누적된다.

```text
output ROI
← combine
← blur r2
← blur r1
← source
```

최종 required source rect는 단순히 `max(r1, r2)`가 아니라 graph dependency와 합성에 따라
`r1 + r2`가 될 수 있다. branch별 required rect를 따로 계산한 뒤 union한다.

### 5.4 affine/perspective transform

- output corner를 inverse map
- nonlinear/perspective edge 극값 확인
- interpolation footprint 추가
- source bounds와 intersect
- transparent/border extend mode 반영

90° 회전처럼 exact integer mapping 가능한 경우와 arbitrary angle을 분리한다.

### 5.5 resize

한 output pixel이 읽는 source support를 resampler kernel에 따라 계산한다.

- downscale에서 kernel footprint가 scale에 따라 넓어질 수 있음
- x/y anisotropic scale
- phase
- edge mode
- source tile decode granularity

### 5.6 local mask

- stroke bbox만으로 충분하지 않다.
- brush radius와 feather를 포함한다.
- downstream blur/repair radius를 누적한다.
- normalized mask coordinate를 current oriented/transformed pixel space로 변환한다.
- edit 중 preview quality와 commit quality의 차이를 명시한다.

### 5.7 LUT

point LUT는 input ROI=output ROI다. 하지만 3D texture resource는 graph-global immutable data이며
ROI cache key에 LUT version/hash가 포함되어야 한다.

### 5.8 procedural noise

source ROI는 output과 같을 수 있다. 결과는 다음에만 의존해야 한다.

- absolute image coordinate
- deterministic seed
- algorithm version

tile origin, execution order, thread index만으로 seed를 만들지 않는다.

---

## 6. global dependency

모든 stage가 local ROI로 끝나지는 않는다.

### 6.1 global measurement

- histogram
- percentile
- film base statistics
- neutral balance
- scanner target signature

는 정의된 measurement ROI 전체에 의존한다. viewport tile마다 숨겨진 full-frame 측정을 하지
않는다.

```text
measurement source/proxy
→ global/scoped statistics
→ immutable parameters
→ local render graph
```

measurement가 바뀌면 그 parameter를 소비하는 이후 render prefix 전체가 무효다.

### 6.2 global structure

defect scratch/connected component처럼 멀리 연결된 구조를 분석하는 알고리즘은 작은 output ROI만
보고 동일 결과를 만들 수 없을 수 있다.

후보 구조:

1. coarse/global detection pass
2. stable component/repair recipe
3. local repair render

global detection을 local D2D effect의 숨은 full-frame dependency로 넣지 않는다.

### 6.3 full-image output

export와 print composition은 최종 파일 전체를 요구한다. 그래도 tile execution은 가능하지만:

- global measurement 완료
- deterministic tile order-independent output
- encoder scanline/tile contract
- output sharpening apron
- ICC transform consistency

가 필요하다.

---

## 7. 현재 defect 코드에서 가져올 근거

현재 macOS 코드에는 다음 검증된 개념이 있다.

### 7.1 repair context

`SoftwareDefectRemoval.repairContextRadius = 264`는 현재 repair 구조에서:

- 최대 128 step 구조 탐색
- texture transfer displacement
- 이웃 sample
- context ring
- grain sigma 범위

를 포함하도록 설명되어 있다. Windows 포트에서 이 값은 다음처럼 다룬다.

- 현재 algorithm version의 코드 근거 baseline
- scalar/full-frame corpus로 재검증
- 알고리즘이 바뀌면 manifest version과 함께 변경
- 모든 defect 종류의 범용 상수로 오용하지 않음

### 7.2 detection tile

현재 region detection에는 별도 값이 있다.

- 기본 `tileMax = 1400`
- 기본 `halo = 48`
- 큰 ROI에서 overlap tile
- 결과는 non-overlap core에서 취함
- 최대 동시 tile 수 4

이는 repair context 264와 목적이 다르다.

| 값 | 목적 |
|---|---|
| detection halo | tile 경계에서 detector context 확보 |
| repair context | 지정 mask/defect를 full-frame과 동일하게 복원 |
| render tile apron | 전체 downstream effect graph의 sample footprint |

세 값을 하나로 합치지 않는다.

### 7.3 좌표 변환

현재 코드 주석은 detector label row y-down과 image ROI y-up 변환을 명시한다. Windows corpus에
위·아래 비대칭 defect pattern을 넣어 accidental flip을 잡는다.

---

## 8. app-level tile planner

Direct2D가 내부에서 언제 어떤 intermediate를 타일로 처리하는지는 opaque할 수 있다. Negaflow는
대형 source decode, cache, CPU/compute stage, export memory를 통제하기 위한 자체 tile plan을
가진다.

### 8.1 tile 크기 입력

- output image dimensions
- working format bytes/pixel
- 활성 graph의 peak live surfaces
- 최대 apron
- GPU dedicated/shared memory budget
- process working-set budget
- decoder tile/strip geometry
- encoder scanline/tile preference
- device maximum texture dimension
- concurrent jobs
- interactive/export priority

### 8.2 고정 1024 금지

이전 문서의 “Direct2D 기본 타일은 1024×1024”를 제품 설계값으로 사용하지 않는다.

- public contract로 신뢰할 근거가 아님
- internal optimizer/driver/graph에 따라 달라질 수 있음
- large apron에서는 1024가 비효율적일 수 있음
- shared-memory ARM64와 discrete GPU의 최적점이 다름

초기 후보군을 benchmark할 수는 있다.

```text
256, 512, 768, 1024, 1536, 2048
```

하지만 선택은 scenario/device capability class별 실측 결과로 한다.

### 8.3 memory 추정

```text
tileWidthWithApron  = coreWidth  + left + right
tileHeightWithApron = coreHeight + top  + bottom

bytesPerSurface = width × height × bytesPerPixel
peakBytes ≈ Σ live surfaces + staging + decoder + driver reserve
```

overflow-safe 64-bit 산술을 사용한다.

### 8.4 core와 apron

각 tile은:

- **sample region**: apron 포함
- **core output**: 이 tile이 최종적으로 소유하는 non-overlap 영역

을 가진다. 인접 tile은 sample region이 겹쳐도 core output은 겹치지 않는다.

### 8.5 edge

image boundary에서 algorithm별 extend mode를 고정한다.

- clamp
- mirror
- wrap
- transparent/zero
- reduced kernel normalization

Core Image의 `clampedToExtent()`와 crop 조합을 Windows border mode 하나로 단순 추정하지 않는다.

---

## 9. invalidation 계층

### 9.1 source invalidation

원본 내용이나 identity가 바뀌면:

- decode cache
- measurements
- render plan
- intermediates
- thumbnails
- display cache

를 무효화한다.

mtime만으로 판단하지 않는다. catalog의 source identity, size/time, 필요 시 hash/fingerprint,
Windows file ID를 조합한다.

### 9.2 recipe invalidation

stage order 기준 prefix/suffix invalidation을 사용한다.

예:

- exposure 변경: exposure 이전 cache는 유지, 이후 무효
- vignette 변경: TextureStage 이전 유지
- crop 변경: transform 이후 무효; measurement/mask coordinate 영향 별도 검사
- film base 변경: negative inversion 이후 무효
- output JPEG quality: working render 유지, encoder만 무효
- output ICC: working render 유지, output transform 이후 무효

### 9.3 measurement invalidation

measurement key에는 다음이 포함된다.

- source content revision
- measurement kind/version
- measurement input parameters
- ROI
- proxy specification

UI slider 전체를 무조건 넣지도, source만 넣고 recipe 영향을 무시하지도 않는다.

### 9.4 mask/defect invalidation

한 stroke/defect가 바뀌면:

```text
edit bbox
→ brush/feather expand
→ repair context expand
→ downstream spatial apron expand
→ image bounds intersect
```

을 무효 영역으로 삼는다. 다만 component/global detection이 바뀌면 전체 detection result revision을
갱신하고 관련 repair를 다시 계획한다.

### 9.5 display invalidation

작업 image는 유지하면서 display cache만 무효화하는 사건:

- monitor 이동
- monitor ICC 변경
- HDR/SDR mode 변경
- window swap-chain resize
- OS color setting 변경
- softproof toggle/output profile 변경

### 9.6 algorithm invalidation

app update로 algorithm/shader/ICC engine version이 바뀌면 해당 version을 key로 갖지 않은 cache는
재사용하지 않는다.

---

## 10. interactive edit lifecycle

### 10.1 slider

```text
pointer update
→ recipe draft revision 증가
→ previous interactive request 취소 표시
→ affected graph suffix/ROI 계획
→ low-latency viewport render
→ revision 확인
→ frame present
→ idle 시 full-quality refinement
```

low-latency tier가 수학을 바꾸는 경우 정확한 차이를 명시해야 한다. 기본은 resolution/scheduling만
달라지고 color math는 같다.

### 10.2 brush stroke

stroke 동안:

- incremental mask bbox
- preview feather/repair plan
- current viewport intersection
- previous committed base reuse

를 사용할 수 있다.

stroke commit 시:

- normalized recipe에 원자적으로 추가
- committed revision 증가
- exact repair ROI 재계산
- final-quality viewport refinement
- sidecar/catalog persistence

### 10.3 undo/redo

- recipe revision은 단조 증가시킨다.
- 과거 state로 돌아가도 예전 numeric revision을 재사용하지 않는다.
- recipe content hash가 같으면 safe intermediate reuse를 검토할 수 있다.
- in-flight old revision 결과는 UI에 적용하지 않는다.

---

## 11. 비동기와 stale result

render task는 시작 시 다음을 capture한다.

```text
frameID
sourceRevision
recipeRevision
measurementRevision
renderSessionID
viewportRequestID
deviceGeneration
outputPurpose
```

결과 적용 직전에 모두 확인한다.

### 11.1 취소

- CPU loop는 tile/row/stage boundary에 cooperative cancellation
- 이미 제출된 GPU work는 완료될 수 있음
- 완료돼도 revision mismatch면 폐기
- export temp file은 final rename 전에 다시 확인
- canceled task가 cache index를 latest로 갱신하지 않음

### 11.2 priority inversion

- old full-quality refinement가 new interactive frame을 막지 않게 한다.
- export가 GPU memory를 독점하지 않게 budget을 분리한다.
- 현재 viewport tile이 background thumbnail보다 우선한다.
- starvation 방지를 위해 export queue fairness를 둔다.

---

## 12. cache key와 entry

### 12.1 최소 key

```text
source identity/content revision
recipe prefix hash
measurement hashes
algorithm versions
image orientation/geometry
resolution level
ROI/tile core
apron/edge mode
precision/color context
backend compatibility class
device generation if GPU-owned
```

### 12.2 entry metadata

- produced rect
- valid core rect
- sampled input rects
- format/domain/alpha
- byte size
- last access
- creation revision
- checksums for disk cache where applicable
- GPU/device ownership

### 12.3 partial validity

큰 intermediate 전체를 하나의 valid boolean로 관리하지 않는다. tile별 validity가 가능하지만
복잡성이 이득을 넘는 stage에는 full-entry invalidation을 선택한다.

### 12.4 cache poisoning 방지

- failed/canceled task는 complete entry로 publish하지 않음
- temp entry → 검증 → atomic publish
- output rect/format/hash validation
- device loss 뒤 GPU entry 폐기
- corrupt disk cache는 source/recipe 손상으로 오인하지 않음

---

## 13. transform별 상세 예

### 13.1 point grade

```text
output bounds = input bounds
required input = requested output
invalid output = invalid input
opaque output = input opaque, alpha-preserving이 증명될 때만
```

### 13.2 Gaussian blur 후 crop

```text
blur internal bounds = input bounds expanded 또는 border policy 의존
final output bounds = original extent
required input = inflate(requested output, kernel footprint) ∩ source/border domain
invalid output = inflate(invalid input, footprint) ∩ output extent
```

### 13.3 unsharp mask

```text
source branch: requested output
blur branch: inflate(requested output, footprint)
combine output: requested output
```

source가 fan-out되므로 branch별 ROI와 lifetime을 계산한다.

### 13.4 halation

```text
source → luma/highlight mask → blur → warm transform
source ───────────────────────────────→ screen/blend
```

- mask threshold는 point
- blur는 apron
- original source branch는 core ROI
- combine은 두 branch union dependency

### 13.5 guided filter

여러 mean/coeff pass의 radius가 누적된다. 최종 output tile에 필요한 guide/source rect를 graph를
거슬러 정확히 계산한다. 각 intermediate만 보고 radius 하나를 적용하면 seam이 생길 수 있다.

### 13.6 image transform

- crop은 source normalized coordinate에서 시작
- rotate/flip/perspective 순서를 고정
- output bounds 계산과 inverse ROI가 같은 matrix chain을 사용
- mask/defect coordinate도 동일 chain 또는 명시된 pre-transform space 사용

---

## 14. 타일 seam 검증

### 14.1 full-frame oracle

가능한 크기의 fixture는 full-frame 결과를 oracle로 사용한다.

### 14.2 tile variants

- 64, 127, 128, 255, 256
- radius보다 작은 core
- non-square
- odd sizes
- very large practical sizes
- image보다 큰 tile
- 1-pixel remainder tile

### 14.3 비교 구역

- 전체 image
- tile boundary ± 최대 apron
- image outer edge
- crop boundary
- mask bbox boundary
- rotated edge
- transparent border

### 14.4 패턴

- impulse가 seam 위에 위치
- diagonal line
- high-frequency checkerboard
- flat field
- gradient
- dust/scratch가 seam을 가로지름
- asymmetric top/bottom marker
- random grain with fixed seed

### 14.5 지표

- exact match가 가능한 integer/mask stage
- max/RMS error
- seam band vs interior error ratio
- component count/shape difference
- mask occupancy
- histogram/percentile difference

---

## 15. bounds와 overflow 검증

fuzz/property tests:

- empty rect
- inverted invalid rect
- negative origin
- `INT32_MIN/MAX` 근처
- huge radius
- zero/negative scale
- near-singular perspective
- NaN/Inf transform parameters
- 1×N/N×1
- input count mismatch
- output outside source
- fully clipped output

요구 input rect를 계산할 때 signed overflow가 발생하면 넓은 잘못된 rect를 반환하지 말고 effect/
render plan을 명시적으로 실패시킨다.

---

## 16. diagnostics

debug capture에 다음을 남긴다.

```text
scenario/node
output request rect
input required rects
input invalid rect
output invalid rect
apron per edge
coordinate transform hash
tile core/sample rect
cache hit/miss/invalidation reason
recipe/source/session revision
backend/device generation
render duration/bytes
```

개발용 overlay 후보:

- tile core 경계
- sample/apron 경계
- invalidated region
- mask bbox
- source/output mapped rect
- cache hit/miss 색상

이 overlay는 제품 사진에 bake하지 않고 diagnostic surface로만 표시한다.

---

## 17. 성능 gate

### 지표

- full-frame 대비 ROI 계산 pixel 비율
- apron overhead ratio
- cache hit ratio
- brush-to-preview latency p50/p95
- slider-to-preview latency p50/p95
- pan/zoom tile latency
- peak CPU/GPU memory
- duplicate tile computation
- canceled work bytes/time
- export throughput

### 대표 시나리오

- 24 MP 사진의 point slider
- 45 MP film scan의 clarity/halation
- 100 MP scan의 local brush
- repair context 264 defect near tile edge
- denoise maximum radius
- rapid crop/rotate edits
- monitor 전환 중 render
- export와 interactive preview 동시 실행

### 판정

- quality/precision/DPI/ICC를 낮추지 않음
- full-frame reference와 정한 오차 내 동일
- ROI bookkeeping overhead가 작은 image에서 이득을 역전하면 full-frame CPU/GPU 선택 가능
- 장치별 tile size는 evidence로 선택

---

## 18. 실패 정책

| 실패 | 처리 |
|---|---|
| ROI mapping overflow | render 실패, diagnostics |
| apron 계산 불명확 | conservative full input rect |
| global dependency 발견 | measurement/global pass로 분리 |
| tile seam 초과 | apron/edge/tile algorithm 수정; full-frame fallback 가능 |
| cache key 불충분 | cache version 폐기, key 확장 |
| stale result | 폐기, 최신 요청 유지 |
| GPU OOM | tile 축소 또는 CPU fallback |
| corrupt disk tile | 해당 cache 폐기 후 source에서 재생성 |
| coordinate transform invalid | 해당 편집/render 실패; 원본/recipe 보존 |

correctness가 불확실하면 ROI를 넓히는 것이 좁히는 것보다 안전하다.

---

## 19. 구현 순서

### Phase 0 — coordinate contract

- persisted crop/mask 의미 inventory
- top-left canonical model
- orientation/transform matrix
- rect utility와 overflow tests

### Phase 1 — point/transform effects

- 세 Direct2D mapping method
- identity/crop/rotate/scale corpus
- opaque rect conservative policy

### Phase 2 — spatial apron

- blur/unsharp/halation
- guided filter
- tile seam harness

### Phase 3 — invalidation/cache

- recipe prefix
- measurement key
- mask bbox
- display/device generation
- stale result gate

### Phase 4 — defect

- detection halo
- repair context 264 parity
- component/global pass
- brush/undo/redo stress

### Phase 5 — large image

- dynamic tile planner
- decoder/encoder integration
- memory/OOM/device matrix

---

## 20. 금지 사항

- Direct2D가 macOS의 국소 재평가를 자동으로 완성한다고 쓰지 않는다.
- 고정 1024×1024를 Direct2D/Negaflow 기본 계약으로 쓰지 않는다.
- Microsoft Q&A나 제3자 앱 구현을 제품 보장의 근거로 쓰지 않는다.
- `MapOutputRectToInputRects`나 `MapInvalidRect`에서 state를 변경하지 않는다.
- filter radius와 실제 discrete apron을 같은 값으로 추정하지 않는다.
- detection halo와 repair context와 render apron을 합치지 않는다.
- y-up/y-down 변환을 shader마다 따로 구현하지 않는다.
- stale GPU completion을 최신 frame에 적용하지 않는다.
- cancel된 partial tile을 valid cache로 publish하지 않는다.
- ROI 성능 때문에 full-frame과 다른 defect/denoise 결과를 허용하지 않는다.

---

## 21. 공식 자료

- [Custom effects](https://learn.microsoft.com/en-us/windows/win32/direct2d/custom-effects)
- [`ID2D1Transform::MapInputRectsToOutputRect`](https://learn.microsoft.com/en-us/windows/win32/api/d2d1effectauthor/nf-d2d1effectauthor-id2d1transform-mapinputrectstooutputrect)
- [`ID2D1Transform::MapOutputRectToInputRects`](https://learn.microsoft.com/en-us/windows/win32/api/d2d1effectauthor/nf-d2d1effectauthor-id2d1transform-mapoutputrecttoinputrects)
- [`ID2D1Transform::MapInvalidRect`](https://learn.microsoft.com/en-us/windows/win32/api/d2d1effectauthor/nf-d2d1effectauthor-id2d1transform-mapinvalidrect)
- [`D2D1_RENDERING_CONTROLS`](https://learn.microsoft.com/en-us/windows/win32/api/d2d1_1/ns-d2d1_1-d2d1_rendering_controls)
- [Direct2D image sources](https://learn.microsoft.com/en-us/windows/win32/direct2d/image-sources)

공식 자료는 rect callback의 API contract를 제공한다. tile 크기, defect context, cache 무효화,
full-frame 동등성은 Negaflow 코드와 corpus가 근거다.

---

## 22. 관련 문서

- [pipeline-shape.md](pipeline-shape.md)
- [direct2d-effects.md](direct2d-effects.md)
- [precision-and-clipping.md](precision-and-clipping.md)
- [shader-linking.md](shader-linking.md)
- [../03-measurement/histogram-and-statistics.md](../03-measurement/histogram-and-statistics.md)
- [../06-large-images/image-source-tiling.md](../06-large-images/image-source-tiling.md)
- [../07-threading/multithreading-export.md](../07-threading/multithreading-export.md)
- [../08-ui/surfaces/defects.md](../08-ui/surfaces/defects.md)
- [../12-performance/backend-selection.md](../12-performance/backend-selection.md)
- [../14-persistence/catalog-and-storage.md](../14-persistence/catalog-and-storage.md)

---

## 23. 완료 조건

- [ ] 모든 render node가 forward/backward/invalid rect 계약을 가짐
- [ ] mapping method 순수성과 호출 순서가 unit test로 검증됨
- [ ] 좌표 공간과 y-axis 변환이 한 곳에 고정됨
- [ ] filter별 실제 apron inventory가 있음
- [ ] global measurement/structure가 local graph와 분리됨
- [ ] defect detection halo와 repair context가 별도 검증됨
- [ ] 여러 tile size가 full-frame oracle과 일치함
- [ ] cache key가 source/recipe/measurement/precision/version을 포함함
- [ ] rapid edit/undo/redo에서 stale result가 적용되지 않음
- [ ] GPU OOM/device loss 뒤 cache가 오염되지 않음
- [ ] Intel/AMD/NVIDIA/Qualcomm 및 x64/ARM64에서 성능·seam corpus 통과

이 조건이 충족되기 전에는 “대형 이미지와 local edit가 ROI로 안전하게 최적화됐다”고 선언하지
않는다.
