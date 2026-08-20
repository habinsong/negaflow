# 대용량 이미지 소스·타일링·메모리 설계

조사 기준일: 2026-08-04  
대상: Windows 11, WinUI 3 셸, 네이티브 C++ 이미지 엔진  
macOS 근거: `Chromabase` 현상·결함 제거·통계·내보내기 구현과 대응 XCTest

## 결론

Windows판은 Direct2D의 큰 이미지 기능만 믿지 않고 **앱 소유의 타일 실행 계층**을 둡니다.

두 계층의 책임은 다릅니다.

1. `ID2D1ImageSourceFromWic`와 `CACHE_ON_DEMAND`
   - 캔버스에서 큰 WIC 이미지를 필요한 영역만 표시하는 가속 경로
   - Direct2D가 내부 sparse tile cache를 관리
   - 줌·스크롤·회전의 빠른 첫 화면에 유용
2. Negaflow `TilePlanner`·`TileCache`
   - decode, develop, 결함 검출·복원, 전역 통계, 내보내기의 기준 실행 계층
   - 정확한 좌표·halo·revision·메모리 예산·결정적 merge를 앱이 통제
   - WIC, libtiff, LibRaw, CPU SIMD, D3D11/DirectCompute 모두를 같은 계약에 연결

Direct2D의 image source는 “그릴 수 있는 큰 이미지”를 제공하지만, 임의 커널의 입력 halo,
전역 통계의 두 패스, 타일별 provenance, export writer의 순서, CPU fallback까지 정의하지 않습니다.
따라서 앱 타일 계층을 생략하면 화면 표시와 최종 결과가 서로 다른 경로로 갈라집니다.

v1의 원칙은 다음과 같습니다.

- 전체 float RGBA 프레임을 항상 메모리에 올리지 않습니다.
- 한 가지 고정 타일 크기를 모든 codec·kernel·장치에 강제하지 않습니다.
- 타일 경계는 제품 결과에 보이면 안 됩니다.
- 전역 측정은 타일별 부분 결과를 정해진 순서로 합칩니다.
- CPU RAM과 GPU budget을 동시에 보고 in-flight 작업 수를 제한합니다.
- Intel·AMD·NVIDIA·Qualcomm·WARP·CPU가 같은 기능과 좌표 계약을 따릅니다.
- 디바이스 제거·메모리 압박·취소 시 미완성 타일을 게시하지 않습니다.

---

## 1. 현재 macOS 구현에서 보존할 계약

Windows가 Core Image의 내부 구현을 복제할 필요는 없습니다. 그러나 현재 제품에서 이미
사용자가 의존하는 다음 의미는 보존해야 합니다.

### 1.1 원본과 현상 상태

- source 파일은 불변입니다.
- develop parameter와 결함 recipe는 source와 분리됩니다.
- 화면 preview와 export는 같은 frame·revision의 recipe를 사용합니다.
- 비동기 결과는 적용 직전에 frame identity와 revision을 다시 확인합니다.
- required non-destructive 결과를 재구성하지 못하면 원본으로 조용히 fallback하지 않습니다.

### 1.2 결함 제거의 기존 타일 의미

`SoftwareDefectRemoval.detectComponents`는 이미 처리 영역을 타일로 나누고 halo를 포함해
검출합니다. 테스트는 타일 경계에 놓인 먼지를 놓치지 않고, core에 중심이 있는 component만
소유하게 하여 중복을 막습니다.

Windows 일반 타일 계층도 이 원칙을 확장합니다.

```text
input/apron rect: kernel이 읽을 수 있는 halo 포함 영역
core rect:        이 작업이 소유하고 결과를 확정하는 영역
valid rect:       실제 source 경계와 교차한 읽기 가능 영역
output rect:      다음 stage에 게시되는 좌표 영역
```

### 1.3 통계와 자동 보정

현재 제품은 서로 다른 목적의 측정을 구분합니다.

- UI histogram: 표시용 축소 sample과 64 bins
- Auto Tone/WB: versioned proxy·histogram·neutral subset 규칙
- film base: median, MAD, percentile 기반 robust statistics
- 결함 검출: 공간 이웃과 component merge

Windows에서는 “모두 histogram이므로 한 함수”로 합치지 않습니다. 각 측정의 sample domain,
bin 수, 색공간, merge 순서와 version을 별도 계약으로 유지합니다.

### 1.4 내보내기

현재 내보내기는 source snapshot을 고정하고 현상·리사이즈·샤픈·ICC·양자화·encode·검증·게시를
거칩니다. 타일 스트리밍을 도입해도 이 순서와 artifact transaction은 바뀌지 않습니다.

특히 다음을 보존합니다.

- Raw TIFF는 일반 develop 타일 경로가 아니라 source pixel domain 경로
- MAIN flat 동시 출력은 별도 parameter snapshot
- primary·sidecar·XMP·original pair는 하나의 논리 transaction
- 결과 파일은 검증 전 최종 이름으로 게시하지 않음
- 취소된 export의 일부 strip을 성공 파일로 남기지 않음

---

## 2. 좌표계 계약

타일 버그의 대부분은 메모리보다 좌표계에서 시작합니다. 모든 backend가 다음 좌표를 명시적으로
전달해야 합니다.

### 2.1 canonical source coordinates

기준 좌표는 **orientation이 정규화된 source pixel 좌표**입니다.

- origin: `(0, 0)`
- pixel center: `(x + 0.5, y + 0.5)`
- bounds: `[0, width) × [0, height)`
- rectangle 끝점은 exclusive
- width·height·stride·offset 계산은 overflow checked
- 디스크 EXIF orientation은 decode provenance에 남기되, 처리 graph 입구에서 한 번만 정규화

회전·반전·crop을 stage마다 암묵 적용하면 halo 계산과 dither 좌표가 어긋납니다. geometry는
versioned affine transform으로 한 곳에서 계산하고, 각 tile request에 source↔stage 변환을 넣습니다.

### 2.2 정수 범위

공개 image descriptor는 `uint64_t` 또는 검증된 양수 크기를 받되, 각 API 호출 직전에 해당 API의
정수 범위를 확인합니다.

- `width * channels * bytesPerChannel`
- `stride * height`
- `offset + byteCount`
- `x + width`, `y + height`
- halo 확장과 clamp
- mip 차원 반올림

이 계산을 unchecked `UINT`나 `size_t` 곱으로 바로 수행하지 않습니다. decode된 dimensions가
비정상적으로 크거나 allocation budget을 넘으면 파일 손상/지원 불가 오류로 종료합니다.

### 2.3 core·apron·valid

예를 들어 512×512 core와 32px halo가 필요한 내부 타일은 최대 576×576을 읽습니다.

```text
┌──────────── input/apron rect ────────────┐
│ halo                                     │
│     ┌──────── core rect ────────┐        │
│     │ 이 타일이 게시할 픽셀      │        │
│     └───────────────────────────┘        │
│                                     halo │
└──────────────────────────────────────────┘
```

source 가장자리에서는 apron이 bounds 밖으로 나갈 수 있습니다. 그때 `validRect`와 border mode를
분리합니다.

- clamp-to-edge
- mirror
- transparent/zero
- kernel-specific constant

border mode는 kernel package의 일부입니다. backend마다 다른 기본 sampler를 쓰지 않습니다.

### 2.4 tile ownership

픽셀 출력은 core를 소유한 정확히 한 tile만 게시합니다. component나 feature가 경계를 가로지를 때는
다음처럼 처리합니다.

1. 각 tile이 apron에서 후보를 검출
2. 후보 좌표를 absolute source coordinates로 변환
3. 경계 equivalence를 deterministic union/merge
4. centroid 또는 명시된 ownership rule로 한 core에 귀속
5. stable sort key로 component ID 부여

thread 완료 순서로 ID를 부여하면 같은 이미지가 실행마다 다른 sidecar를 만들 수 있습니다.

---

## 3. 하나가 아닌 네 종류의 타일

타일 크기는 저장, 연산, 표시, encode에서 병목이 다릅니다. 다음을 분리합니다.

| 종류 | 책임 | 크기 결정 요인 |
|---|---|---|
| decode/storage tile | codec에서 source sample 읽기 | TIFF strip/tile, WIC/RAW decoder 특성, disk I/O |
| processing tile | develop·결함·resize kernel 실행 | halo, intermediate 수, CPU cache, GPU thread layout |
| display tile/mip | 현재 viewport 표시 | zoom, viewport, Direct2D cache, latency |
| export strip/tile | encoder로 순서 있게 전달 | encoder scanline/strip 계약, output bit depth, backpressure |

서로 다른 크기 사이에는 복사 없는 view 또는 bounded reblocking을 우선합니다. 모든 stage를 1024×1024로
고정하는 것은 v1 결정이 아닙니다.

### 3.1 초기 후보와 결정 방식

초기 spike 후보는 다음처럼 넓게 둡니다.

- processing core: 256, 512, 1024 pixels square
- export strip: 64, 128, 256 scanlines
- display mip tile: 256 또는 512 pixels square

이는 제품 상수가 아니라 benchmark 입력입니다. 최종 선택은 다음 조합별로 기록합니다.

- x64 Intel/AMD CPU
- ARM64 Qualcomm CPU
- Intel integrated GPU
- AMD integrated/discrete GPU
- NVIDIA discrete GPU
- Qualcomm GPU
- WARP
- 8/16-bit standard image, RAW, compressed/uncompressed TIFF

### 3.2 메모리 산정 예

RGBA float32는 pixel당 16 bytes입니다.

| core | core 한 장 | input+output 두 장 | intermediate 4장 |
|---:|---:|---:|---:|
| 256² | 1 MiB | 2 MiB | 4 MiB |
| 512² | 4 MiB | 8 MiB | 16 MiB |
| 1024² | 16 MiB | 32 MiB | 64 MiB |

여기에 halo, staging upload/readback, codec buffer, mask, histogram, command queue가 더해집니다.
1024² tile을 작업자 8개가 intermediate 4장씩 잡으면 단순 계산만 512 MiB입니다. source·output과
GPU 복제까지 포함하면 훨씬 커집니다.

100 megapixel 전체 RGBA float32는 약 1.49 GiB입니다. full-frame intermediate가 네 장이면 약
5.96 GiB이므로 16 GB PC에서도 OS·UI·codec·VRAM 공유를 고려하면 안전한 기본이 아닙니다.

FP16 RGBA는 pixel당 8 bytes지만, 메모리를 절반으로 줄이기 위해 임의로 선택하지 않습니다.
[정밀도 문서](../01-render-engine/precision-and-clipping.md)의 corpus·clipping·round-trip gate를 통과한
stage에서만 사용합니다.

---

## 4. Direct2D 큰 이미지 경로의 정확한 범위

### 4.1 `ID2D1ImageSourceFromWic`

`ID2D1DeviceContext2::CreateImageSourceFromWic`은 WIC source를 Direct2D image source로 만들며,
일반 최대 texture 크기보다 큰 이미지도 지원합니다. Direct2D는 내부적으로 sparse tile cache를
사용합니다.

```cpp
ComPtr<ID2D1ImageSourceFromWic> imageSource;
check_hresult(deviceContext2->CreateImageSourceFromWic(
    wicSource.Get(),
    D2D1_IMAGE_SOURCE_LOADING_OPTIONS_CACHE_ON_DEMAND,
    &imageSource));
```

공식 계약에서 주의할 점:

- 지원 pixel format은 `CreateBitmapFromWicBitmap` 계열과 연결됩니다.
- GPU가 포맷을 지원하지 않으면 `D2DERR_UNSUPPORTED_PIXEL_FORMAT`이 가능합니다.
- API가 gamma conversion이나 alpha premultiplication을 대신해 주지 않습니다.
- image source format은 생성한 WIC source format에서 결정됩니다.
- 이 경로는 화면에 image를 draw하는 source이지, 앱 전체 processing graph의 cache API가 아닙니다.

따라서 캔버스 source가 16-bit/float 의미를 필요로 하면 WIC converter가 먼저 저정밀도로 내리지
않았는지 확인합니다. 실패 시 8-bit로 조용히 바꾸지 않습니다.

### 4.2 `CACHE_ON_DEMAND`

`D2D1_IMAGE_SOURCE_LOADING_OPTIONS_CACHE_ON_DEMAND`는 필요한 subregion을 지연 채웁니다.
`EnsureCached`와 `TrimCache`로 힌트를 줄 수 있습니다.

하지만 다음 수명 계약이 있습니다.

- on-demand decode를 위해 원래 `IWICBitmapSource`를 살아 있게 유지
- `CACHE_ON_DEMAND`와 `RELEASE_SOURCE`를 함께 쓰는 설계 금지
- frame·decoder·stream·COM apartment 수명을 image source보다 짧게 두지 않음
- source 파일이 교체되거나 revision이 바뀌면 이전 image source cache를 재사용하지 않음

viewport가 빠르게 이동할 때는 현재 viewport와 가까운 다음 영역만 `EnsureCached`하고, 멀어진 영역은
pressure 상태에서 `TrimCache`합니다. 전체 이미지를 미리 cache하면 on-demand의 의미가 사라집니다.

### 4.3 `ID2D1TransformedImageSource`

회전·flip·scale을 표현하고 원래 image source와 resources를 공유할 수 있어 표시 경로에 유용합니다.
다만 이는 최종 develop geometry의 source of truth가 아닙니다.

- 화면 transform과 export transform은 같은 canonical geometry parameters에서 계산
- Direct2D transform이 지원하는 interpolation/scale 결과를 product resampler와 자동 동등시하지 않음
- display mip 선택은 화면 품질 최적화이고 export pixel 계약을 바꾸지 않음

### 4.4 texture 한계

D3D11 feature level 11.x의 Texture2D 최대 width와 height는 각각 16,384입니다. 이는 “16 megapixels”가
아니라 **축별 차원 한계**입니다. 20,000×2,000 image는 40 MP여도 한 축이 한계를 넘습니다.

장치의 실제 feature level과 `GetMaximumBitmapSize`를 기록하지만, app tile planner는 한계를 넘을 때만
켜는 예외 경로가 아닙니다. 메모리 budget·halo·streaming 때문에 지원되는 작은 이미지에도 동일한
타일 계약을 사용할 수 있습니다.

### 4.5 `D2D1_RENDERING_CONTROLS.tileSize`

`tileSize`는 앱의 processing tile 크기를 지정하는 API가 아닙니다. 공식 설명상 렌더러가 할당하는 tile의
최소 pixel extent이고, Direct2D가 더 큰 power-of-two tile을 선택할 수 있습니다. feature-level texture
한계까지 커질 수도 있습니다.

따라서 다음을 하지 않습니다.

- `tileSize = 1024`이므로 항상 정확히 1024×1024라고 가정
- shader dispatch·halo·cache key를 Direct2D 내부 tile에 맞춤
- Direct2D tile 경계를 export strip 경계로 사용
- undocumented 기본값을 제품 계약으로 기록

---

## 5. 앱 소유 `TilePlanner`

### 5.1 입력

planner는 최소 다음을 받습니다.

```text
ImageDescriptor
  sourceIdentity
  width, height
  orientation-normalized geometry
  pixel interpretation + ICC digest

StageDescriptor
  stageID + implementationVersion
  input/output format
  halo function
  border mode
  global-pass dependency
  backend capabilities

ExecutionBudget
  CPU available commit/RAM signal
  GPU local/non-local budget and current usage
  max in-flight bytes
  interactive priority
```

### 5.2 출력

각 `TileRequest`는 다음을 명시합니다.

- mip/scale level
- absolute core rect
- requested apron rect
- clamped valid rect
- border fill rule
- output destination rect
- expected input revision
- memory reservation bytes
- deterministic sequence number
- cancellation token/job ID

### 5.3 tile key

cache key에 최소 다음이 들어갑니다.

```text
source content identity or immutable generation
decoder ID + decoder version
decode interpretation/profile digest
frame ID + source generation
develop recipe digest
defect recipe digest
stage ID + kernel package version
mip level
tile core coordinates
pixel format + color domain
```

파일 경로와 수정 시각만 cache identity로 쓰지 않습니다. 동일 path의 파일이 교체되거나 network/cloud
provider가 timestamp를 보존할 수 있습니다.

### 5.4 stage fusion

여러 pointwise stage는 중간 메모리를 줄이기 위해 하나의 CPU loop 또는 shader로 fuse할 수 있습니다.
그러나 fusion은 다음 조건을 통과해야 합니다.

- scalar reference와 수치 동등
- ICC transform 순서를 바꾸지 않음
- clamp를 앞당기거나 제거하지 않음
- global measurement boundary를 넘지 않음
- debug provenance에서 fused stage version 식별 가능
- CPU/GPU 결과 tolerance gate 통과

단순히 dispatch 수가 줄어든다는 이유로 제품 수학을 재배열하지 않습니다.

---

## 6. codec별 region decode 현실

타일 요청을 codec에 전달한다고 해서 항상 디스크·CPU가 그 영역만 처리하는 것은 아닙니다.

### 6.1 WIC JPEG·PNG

`IWICBitmapSource::CopyPixels`는 rectangle을 받을 수 있지만, decoder가 compressed stream을 어떻게
materialize하는지는 codec 구현의 영역입니다.

- JPEG는 entropy stream과 MCU/DCT 구조 때문에 임의 영역 접근 비용이 full sequential decode에 가까울 수 있음
- PNG는 scanline filter와 DEFLATE 때문에 아래쪽 작은 영역도 앞 데이터를 처리할 수 있음
- 동일 source에 반복적인 임의 `CopyPixels` 호출이 재디코드를 유발하는지 ETW/benchmark로 확인

대책:

- 첫 full decode가 unavoidable하면 bounded decoded-tile cache로 재사용
- 화면 첫 표시에는 decoder-native downscale/thumbnail을 우선 검토
- final export에는 품질 gate 없이 proxy를 대신 사용하지 않음
- codec별 access cost를 `random-region`, `sequential-strip`, `full-decode-once`로 분류

### 6.2 TIFF

TIFF는 파일이 strip 또는 tile organization을 갖습니다. libtiff로 source layout을 읽고 decode 계획을
그에 맞춥니다.

- tiled input: 필요한 encoded tile만 읽을 수 있는지 검증
- stripped input: strip 순서를 존중하고 동일 strip 중복 decode 방지
- orientation·planar configuration·predictor·compression 검증
- malformed offset/byte count는 allocation/index 전에 거부

앱 processing tile과 파일 tile을 동일 크기로 강제하지 않습니다. source tile/strip을 decode cache에 넣고
필요한 processing apron을 assemble합니다.

### 6.3 LibRaw

많은 camera RAW는 full sensor decode/demosaic 성격이 강합니다. 임의 512×512 region을 요청했다고 실제로
그 부분만 싸게 decode된다고 가정하지 않습니다.

- metadata/thumbnail path와 full-quality path 분리
- full RAW decode 결과를 bounded storage tiles로 나눠 소비
- 한 `LibRaw` object를 여러 thread가 동시에 사용하지 않음
- embedded preview를 final develop source로 승격하지 않음
- decode profile과 LibRaw version을 cache key/provenance에 포함

### 6.4 scanner plugin output

scanner plugin은 최종 artifact path와 capability/progress를 외부 JSON 계약으로 전달합니다. 앱이 plugin
process의 메모리나 native handle을 타일 cache로 직접 공유하지 않습니다.

- plugin이 완결·flush한 파일만 source로 등록
- dimensions·format·ICC·ROI manifest를 검증한 뒤 decode
- scan 진행 중인 부분 파일을 image source로 열지 않음
- IR/RGB pair는 identity와 geometry를 검증하고 각 plane을 별도 source로 취급

---

## 7. halo와 공간 연산

### 7.1 halo 계산

각 kernel은 input pixel domain에서 필요한 radius를 함수로 보고합니다.

```text
halo = ceil(filterRadius × transformScale) + interpolationFootprint + safetyTerm
```

정확한 식은 kernel별로 versioning합니다. 모든 연산에 고정 48px을 쓰지 않습니다.

- blur/morphology: structuring element 반경
- resample: filter support와 inverse transform
- sharpen: blur radius
- defect repair: search window·patch footprint
- local mask feather: feather radius
- geometric warp: destination core를 source로 역변환한 bounding region

여러 stage를 fuse할 때는 단순 최대값이 아니라 dependency를 따라 required input region을 역전파합니다.

### 7.2 seam 방지

각 tile은 apron 전체를 계산할 수 있지만 core만 다음 stage에 게시합니다. 다음은 금지합니다.

- tile마다 noise seed 재시작
- tile-local auto exposure/WB
- tile마다 histogram percentile을 독립 적용
- tile마다 edge normalization이 달라지는 convolution
- crop 전 좌표와 crop 후 좌표를 섞은 mask sampling
- CPU와 GPU의 서로 다른 border mode

### 7.3 component merge

결함 검출처럼 connected component가 타일 경계를 넘는 경우에는 overlap label을 merge합니다.

deterministic key 예:

```text
(minimumY, minimumX, area, sourceTileSequence, localLabel)
```

merge 뒤 canonical root와 global ID를 stable sort로 부여합니다. thread scheduling이나 hash-map iteration
순서가 sidecar 결과에 영향을 주지 않아야 합니다.

---

## 8. 전역 통계: 두 패스 계약

histogram, percentile, film base, 일부 defect threshold는 한 타일만 보고 결정할 수 없습니다.

### 8.1 기본 흐름

```text
Pass A
  source/proxy tiles
    → tile partial statistics
    → deterministic merge
    → versioned global parameters

Pass B
  source tiles 다시 순회
    → global parameters를 고정해 develop/render
    → output tiles
```

### 8.2 partial result

가능한 partial은 다음처럼 명시적으로 merge 가능한 형태를 사용합니다.

- integer histogram bins
- pixel/sample count
- finite min/max와 invalid count
- compensated sum 또는 fixed-order float accumulator
- candidate reservoir with deterministic ranking
- component boundary equivalence pairs

모든 pixel sample을 RAM에 모은 뒤 sort하는 방식은 100MP 확장성이 없습니다. 정확한 percentile이 반드시
필요한 stage인지, fixed bins/selection pass로 같은 계약을 만족할 수 있는지 따로 결정합니다.

### 8.3 merge 결정성

worker가 끝난 순서로 floating-point partial을 더하지 않습니다.

1. tile sequence를 canonical raster order로 부여
2. partial을 sequence slot에 저장
3. 정해진 pairwise tree 또는 순차 순서로 merge
4. NaN/Inf·empty tile 정책을 동일 적용
5. backend와 worker count를 provenance/test parameter로 기록

필요하다면 integer bins와 64-bit counts를 우선해 GPU atomic 실행 순서의 영향을 줄입니다.

### 8.4 preview와 final

interactive preview용 proxy 통계와 final export 통계를 혼동하지 않습니다.

- Auto Tone/WB가 현재 제품상 versioned proxy를 기준으로 한다면 그 proxy 계약을 보존
- export pixel 결과에 필요한 global stage는 final source domain에서 다시 측정
- preview가 먼저 계산됐다고 final이 그 cache를 무조건 재사용하지 않음
- 재사용하려면 source·recipe·scale·color domain·algorithm version key가 완전히 같아야 함

---

## 9. CPU 메모리 예산

### 9.1 관측

`GlobalMemoryStatusEx`는 호출 시점의 physical/virtual memory 상태를 제공합니다. 값은 휘발성이므로
한 번 읽은 총 RAM으로 고정 cache 크기를 정하지 않습니다.

`CreateMemoryResourceNotification(LowMemoryResourceNotification)`은 system-wide low-memory 상태를
알리는 waitable object입니다. 이는 정확한 byte budget이 아니라 pressure 신호입니다.

함께 기록할 값:

- process private/working set
- system available physical memory
- available commit
- tile cache resident/compressed/on-disk bytes
- in-flight decode/process/encode reservations
- allocation failure count

### 9.2 reservation 방식

작업을 queue에 넣을 때가 아니라 큰 buffer를 만들기 **전에** 예상 peak bytes를 예약합니다.

```text
decode buffer
+ processing input apron
+ processing output core
+ stage intermediates
+ upload/readback staging
+ encoder row/strip buffer
+ safety margin
```

reservation을 얻지 못하면 무제한 대기 worker를 늘리지 않고 다음 중 하나를 합니다.

1. cache eviction
2. 낮은 우선순위 prefetch 취소
3. 동시 file 수 감소
4. 더 작은 processing tile로 재계획
5. 사용자 작업을 보존한 채 명시적 메모리 부족 오류

### 9.3 pressure 상태

고정 percentage 하나 대신 상태 기계를 둡니다.

| 상태 | 동작 |
|---|---|
| normal | viewport prefetch와 bounded export concurrency 허용 |
| pressure | 먼 display mip·prefetch 제거, 새 background 작업 억제 |
| critical | 비필수 cache 전부 trim, file concurrency 1, 새 큰 작업 거부 가능 |
| recovery | 즉시 원래 크기로 튀지 않고 점진적으로 budget 회복 |

임계치는 8/16/32/64 GB, x64/ARM64 장치에서 측정해 정합니다. 문서 단계에서 임의 수치를 제품 상수로
확정하지 않습니다.

---

## 10. GPU 메모리 예산

### 10.1 DXGI budget

`IDXGIAdapter3::QueryVideoMemoryInfo`에서 segment group별 다음을 봅니다.

- `Budget`
- `CurrentUsage`
- `AvailableForReservation`
- `CurrentReservation`

adapter가 discrete인지 UMA인지에 따라 local/non-local 의미와 CPU RAM 중복 계산이 달라집니다. dedicated
VRAM 숫자만 보고 cache 크기를 정하지 않습니다.

### 10.2 budget 변화

DXGI budget은 다른 process·화면 구성·전원 상태에 따라 변할 수 있습니다.
`RegisterVideoMemoryBudgetChangeNotificationEvent`로 변화를 받아 다음을 수행합니다.

- 새 GPU tile submission 잠시 제한
- 현재 usage가 새 budget을 넘으면 unpinned cache eviction
- visible·in-flight resource는 fence 완료 전 해제하지 않음
- repeated thrash면 CPU 또는 WARP 후보로 새 job을 재계획

Microsoft 문서는 budget을 넘으면 paging 때문에 process 또는 system 성능이 악화될 수 있다고 경고합니다.
“할당이 성공했다”는 것이 안전한 resident working set이라는 뜻은 아닙니다.

### 10.3 UMA

Qualcomm·Intel/AMD integrated GPU에서는 GPU local memory와 system RAM이 물리적으로 공유될 수 있습니다.

- CPU decode tile과 GPU texture를 별도 예산으로 단순 합산하면 과대 계산 가능
- 반대로 shared memory 숫자를 공짜 VRAM으로 보면 system pressure를 놓침
- adapter architecture와 budget telemetry로 분류
- upload 복사 제거 최적화는 측정 후 도입

### 10.4 eviction 우선순위

보호 순서:

1. 현재 화면에 보이는 tile
2. GPU command가 참조 중인 in-flight tile
3. 현재 export가 다음 encode 순서로 요구하는 tile
4. 인접 viewport prefetch
5. 이전 revision display mip
6. 재생성 가능한 intermediate

source 원본과 recipe가 있으므로 대부분의 derived tile은 재생성 가능합니다. 그러나 dirty manual defect edit처럼
아직 durable recipe로 저장되지 않은 상태를 cache eviction과 함께 잃어서는 안 됩니다.

---

## 11. cache 계층

### 11.1 L0: 작업 scratch

- 한 tile invocation 동안만 유지
- thread/queue local reuse 가능
- contents를 다음 job에 노출하지 않음
- 민감한 source data를 debug dump하지 않음

### 11.2 L1: CPU decoded/processed cache

- immutable buffers
- source/revision/stage key
- bounded bytes와 pin count
- visible/in-flight pin 해제 후 eviction
- allocation failure 전에 trim callback

### 11.3 L2: GPU resource cache

- device generation 포함
- fence/query completion 전 재사용 금지
- device lost면 generation 전체 무효화
- CPU cache와 별도 residency accounting

### 11.4 L3: disk derived cache

v1에서 꼭 필요할 때만 둡니다. OS page file을 대신하는 임의 virtual memory system을 먼저 만들지 않습니다.

가능한 대상:

- display mip pyramid
- expensive stable cleaned-raw tiles
- RAW full decode의 재사용 tile container

필수 조건:

- app-owned cache directory
- versioned header와 checksum
- atomic file publication
- bounded total size와 startup reconciliation
- 원본/recipe가 없으면 cache만으로 source를 복구했다고 주장하지 않음
- catalog 손상을 empty catalog로 해석해 orphan을 삭제하지 않음

### 11.5 cache invalidation

다음 중 하나가 바뀌면 관련 stage 이후를 무효화합니다.

- source generation/content identity
- decode profile 또는 codec version
- input ICC/profile digest
- orientation/crop geometry
- develop parameters
- defect recipe
- local adjustment mask
- kernel package/version
- output profile·resize·sharpen options

전체 cache를 매 slider 변경마다 비우지 않습니다. dependency graph에서 영향받는 stage부터 새 revision을 만들고
이전 revision은 in-flight reader가 끝난 뒤 제거합니다.

---

## 12. progressive preview와 우선순위

### 12.1 화면 정책

사용자가 사진을 열면 다음 순서로 보입니다.

1. catalog thumbnail 또는 embedded preview
2. viewport를 덮는 낮은 mip develop 결과
3. 현재 zoom에 필요한 tile
4. 화면 주변 작은 prefetch ring
5. 정지 시 고품질 refinement

“전체 100MP 현상이 끝날 때까지 빈 캔버스”는 금지합니다.

### 12.2 우선순위

권장 logical class:

```text
P0 interaction: 현재 viewport, brush feedback, active slider result
P1 foreground:  사용자가 시작한 export/scan 후 첫 결과
P2 maintenance: thumbnail, mip, cleaned-raw persist
P3 prefetch:    인접 사진/viewport 예상 영역
```

P0가 P2/P3를 취소하거나 앞지를 수 있어야 하지만, P1 export가 영원히 굶지 않도록 weighted fairness를 둡니다.
OS thread priority를 매 tile마다 바꾸는 대신 queue admission과 concurrency로 우선순위를 제어합니다.

### 12.3 coalescing

slider가 빠르게 바뀌면 이전 revision의 아직 시작하지 않은 tile을 제거합니다. 이미 실행 중이면 cooperative
cancellation point에서 멈추고 결과 적용 직전에 revision을 다시 확인합니다.

thumbnail/persist도 동일 frame·recipe의 최신 요청 하나만 남기는 coalescing key를 가집니다.

---

## 13. 내보내기 스트리밍

### 13.1 기본 흐름

```text
source tiles
  → optional global measurement pass
  → bounded processing tiles
  → ordered output reblocker
  → ICC/quantize/dither
  → codec strip/scanlines
  → staged file
  → readback validation
  → journaled publish
```

### 13.2 순서와 backpressure

processing tile은 병렬일 수 있지만 encoder가 요구하는 output 순서는 지킵니다.

- writer마다 next expected sequence 유지
- out-of-order 완료 tile은 bounded reorder buffer에 보관
- reorder buffer가 차면 producer를 멈춤
- 한 느린 tile 때문에 무제한 후속 tile을 메모리에 쌓지 않음
- codec handle은 한 output writer가 소유

### 13.3 absolute-coordinate dither

8-bit output dither는 tile-local seed가 아니라 최종 output absolute coordinates와 algorithm version에서
결정합니다. tile 크기·worker 수·완료 순서를 바꿔도 같은 위치의 분포가 바뀌지 않아야 합니다.

### 13.4 실패와 취소

- staged file만 쓰고 최종 path에는 접근하지 않음
- tile 실패 시 writer 종료, incomplete staging을 journal 규칙으로 정리
- cancellation 뒤 encoder finalize가 성공해도 artifact를 publish하지 않음
- source generation과 export snapshot을 commit 직전에 재확인
- 재시도는 새 transaction ID와 깨끗한 staging에서 시작

---

## 14. device lost와 backend 전환

D3D11 작업이 `DXGI_ERROR_DEVICE_REMOVED` 또는 `DXGI_ERROR_DEVICE_RESET`을 만나면 해당 device와 모든
device-dependent cache를 폐기해야 합니다. `ID3D11Device::GetDeviceRemovedReason`을 진단에 기록하되
사용자 파일 경로·pixel 내용은 telemetry에 넣지 않습니다.

### 14.1 화면

1. GPU submission 중지
2. device generation 증가
3. D2D/D3D resource 폐기
4. hardware device 재생성 시도
5. 실패하면 WARP 또는 CPU 표시 fallback
6. 동일 frame/revision의 viewport tile 재요청

### 14.2 내보내기

한 artifact 중간에 backend를 바꿔 이미 쓴 strip과 다른 수학을 섞지 않습니다.

- publish 전 device lost: staging artifact 폐기 후 job 전체를 CPU/WARP로 재시작 가능
- publish 후: 성공 artifact를 자동 덮어쓰지 않음
- retry backend와 kernel version을 provenance에 기록
- hardware→CPU 결과가 tolerance gate를 통과하더라도 byte identity를 자동 약속하지 않음

---

## 15. 오류 모델

최소 오류 category:

| category | 예 |
|---|---|
| invalid descriptor | 0 dimension, overflow, impossible stride |
| unsupported format | decoder/GPU가 required precision 미지원 |
| corrupt source | truncated stream, invalid TIFF offsets |
| memory pressure | reservation 불가, commit 부족 |
| GPU removed | device reset/hung/driver update |
| stale result | frame/revision/source generation 불일치 |
| cancelled | user cancel 또는 superseded preview |
| encode/publish | codec 실패, disk full, verification mismatch |

`E_OUTOFMEMORY`를 모두 “이미지가 너무 큽니다”로 표시하지 않습니다. CPU allocation, DXGI budget, malformed
dimensions, address overflow를 구분해 내부 진단하고 사용자에게는 복구 가능한 조치를 안내합니다.

---

## 16. 관측성

각 job과 tile에 다음을 구조화해 기록합니다.

- job/frame/revision ID의 비식별 internal token
- source dimensions·format·bit depth, 파일명 제외 가능
- stage/backend/device generation
- core/apron dimensions와 halo
- decode/process/upload/readback/encode 시간
- queue wait와 memory reservation wait
- CPU/GPU reserved·resident bytes
- DXGI Budget/CurrentUsage snapshot
- cache hit/miss/eviction 이유
- cancellation/stale/device-lost/error category

pixel data, 전체 사용자 path, ICC contents, scanner serial은 기본 telemetry에 넣지 않습니다.

성능 분석에서 평균만 보지 않고 p50/p95/p99, first-visible latency, peak bytes, page faults, GPU budget
oversubscription을 봅니다.

---

## 17. 테스트 계약

### 17.1 geometry/property tests

- 임의 dimensions와 tile sizes에서 core가 전체 image를 겹침·구멍 없이 정확히 덮음
- apron clamp 후 valid rect가 source bounds 안
- crop/rotate/flip 왕복 좌표
- overflow 직전 dimensions 거부
- 1×N, N×1, 홀수 dimensions, tile보다 작은 image
- 한 축이 16,384를 넘는 virtual image

### 17.2 seam tests

동일 synthetic image를 다음 방식으로 실행해 비교합니다.

- full-frame scalar reference
- 256/512/1024 core
- raster/reverse/random scheduling
- worker 1/2/N
- CPU SIMD/D3D11/WARP
- crop이 tile boundary를 가르는 경우

검사:

- boundary band와 interior error distribution
- dither continuity
- morphology/blur/sharpen halo
- connected component 누락·중복
- resample phase

### 17.3 global statistics

- tile order·worker count가 histogram integer bins를 바꾸지 않음
- floating merge tolerance와 canonical order
- NaN/Inf/transparent pixel 정책
- empty/solid/gradient/high-dynamic-range inputs
- preview algorithm과 final algorithm을 잘못 교차 재사용하지 않음

### 17.4 memory/fault injection

- 작은 artificial budget에서 bounded in-flight bytes
- low-memory notification 시 prefetch/cache 축소
- allocation failure 뒤 partial publish 없음
- DXGI budget 감소와 eviction
- forced device removal 뒤 stale GPU tile 적용 없음
- decoder가 잘못된 stride/dimensions를 보고할 때 index 전 거부
- cancellation이 decode, compute, reorder, encode 각 단계에 도착

### 17.5 대용량 virtual corpus

실제 거대 파일만으로 테스트하지 않습니다. lazy synthetic source로 다음을 만듭니다.

- 100 MP, 250 MP, 1 GP logical dimensions
- 한 축 16,385 이상
- tile 경계에 impulse·line·component
- deterministic coordinate gradient/checker/noise
- strip/tile 순서가 뒤섞이는 scheduler

peak resident memory가 설정한 budget 안인지 자동 측정합니다. 실제 scanner/RAW/TIFF corpus는 별도 라이선스와
개인정보 검토를 거친 integration gate로 둡니다.

---

## 18. 성능 측정표

각 장치에서 다음을 같은 source와 동일 output 품질로 측정합니다.

| 시나리오 | 핵심 지표 |
|---|---|
| 첫 사진 열기 | thumbnail→첫 viewport tile latency |
| 100% zoom pan | missing tile rate, p95 frame time |
| slider drag | stale cancellation, latest revision latency |
| Auto Tone/WB | measurement pass와 merge 시간 |
| 결함 검출 | tile seam accuracy, CPU/GPU time, peak memory |
| 100 MP JPEG export | decode/ICC/encode breakdown |
| 100 MP TIFF16 export | strip throughput, peak RAM/VRAM |
| 39장 batch | time-to-first-file, total time, fairness |
| low-memory injection | recovery, thrash, failure clarity |

성능 향상을 위해 DPI, pixel dimensions, JPEG quality, bit depth, ICC transform, defect quality를 낮추지 않습니다.

---

## 19. 구현 경계 제안

코드 작성 단계의 최소 모듈 경계입니다. 지금 문서 단계에서 class hierarchy를 확정하는 뜻은 아닙니다.

```text
ImageDescriptor / PixelFormat / ColorDomain
        │
        ├── ImageSource
        │     ├── WicSource
        │     ├── TiffSource
        │     ├── LibRawSource
        │     └── SyntheticTestSource
        │
        ├── TilePlanner
        ├── MemoryBudgetBroker
        ├── CpuTileCache
        ├── GpuTileCache
        ├── StageGraph / KernelPackage
        └── OrderedExportSink
```

규칙:

- decoder별 세부 API를 UI에 노출하지 않음
- `ImageSource`는 immutable source samples와 provenance만 제공
- planner는 codec handle을 공유하지 않음
- cache는 catalog/source ownership을 결정하지 않음
- export sink만 writer 순서와 staging publication을 소유
- scanner plugin은 이 process 내부 interface를 구현하지 않고 파일·JSON 경계에 머묾

---

## 20. 단계별 도입

### Phase A — 계약과 scalar reference

- coordinate/core/apron property tests
- checked size/stride utilities
- synthetic image source
- CPU scalar tiled identity/convolution/resample
- deterministic statistics merge

완료 gate: tile 크기와 순서를 바꿔도 full-frame reference와 합의된 tolerance 내 일치.

### Phase B — codec sources

- WIC JPEG/PNG source
- libtiff strip/tile source
- LibRaw full-decode→bounded tile bridge
- malformed input limits

완료 gate: standard/RAW/TIFF corpus에서 dimensions·ICC·orientation·pixel checksum 검증.

### Phase C — display path

- `ID2D1ImageSourceFromWic` on-demand path
- viewport priority와 mip cache
- unsupported format fallback
- device loss 복구

완료 gate: 100 MP급 이미지에서 bounded memory와 responsive zoom/pan.

### Phase D — processing/export

- CPU SIMD와 D3D11 tile executors
- global two-pass stages
- ordered export sink와 backpressure
- WARP/CPU retry

완료 gate: 전체 포맷·bit-depth·ICC·artifact transaction parity와 39장 batch 시나리오.

### Phase E — 튜닝

- 장치별 tile 후보 benchmark
- stage fusion
- disk derived cache 필요성 판단
- optional CUDA 후보 측정

완료 gate: 기능·정밀도 gate를 먼저 통과하고 실제 병목 근거가 있는 최적화만 채택.

---

## 21. 금지 사항

- Direct2D sparse cache가 있으므로 앱 타일 계층이 필요 없다고 결론 내리지 않음
- `D2D1_RENDERING_CONTROLS.tileSize`를 정확한 processing tile 크기로 해석하지 않음
- WARP 한계를 “16 megapixels”로 기록하지 않음
- full float frame 여러 장을 RAM에 상시 유지하지 않음
- codec region API가 실제 partial decode라고 가정하지 않음
- tile마다 auto parameters나 noise seed를 새로 계산하지 않음
- worker 완료 순서로 통계·component ID·artifact 순서를 결정하지 않음
- GPU allocation 성공을 budget 준수로 해석하지 않음
- device lost 뒤 이전 generation resource를 재사용하지 않음
- 메모리 부족 때 품질·해상도·ICC를 몰래 낮추지 않음
- scanner plugin process와 raw memory/COM/GPU object를 공유하지 않음

---

## 22. 미결정 항목

다음은 구현 spike와 corpus 측정 전 확정하지 않습니다.

- codec·stage·장치별 최종 tile/strip 크기
- CPU cache와 GPU cache의 기본 byte budget/비율
- RAW full decode 결과의 RAM-only 또는 disk cache 여부
- hardware GPU export의 손익분기 image size
- deferred context가 tile command recording에 실제 이득인지
- FP16을 허용할 stage
- viewport prefetch ring 크기
- cache eviction algorithm의 정확한 weighting
- CUDA가 어느 단일 stage에서 end-to-end 이득을 주는지

---

## 공식 출처

- [ID2D1DeviceContext2::CreateImageSourceFromWic](https://learn.microsoft.com/en-us/windows/win32/api/d2d1_3/nf-d2d1_3-id2d1_3-id2d1devicecontext2-createimagesourcefromwic%28iwicbitmapsource_d2d1_image_source_loading_options_id2d1imagesourcefromwic%29)
- [D2D1_IMAGE_SOURCE_LOADING_OPTIONS](https://learn.microsoft.com/en-us/windows/win32/api/d2d1_3/ne-d2d1_3-d2d1_image_source_loading_options)
- [ID2D1ImageSource::EnsureCached](https://learn.microsoft.com/en-us/windows/win32/api/d2d1_3/nf-d2d1_3-id2d1imagesource-ensurecached)
- [ID2D1ImageSource::TrimCache](https://learn.microsoft.com/en-us/windows/win32/api/d2d1_3/nf-d2d1_3-id2d1imagesource-trimcache)
- [ID2D1DeviceContext2::CreateTransformedImageSource](https://learn.microsoft.com/en-us/windows/win32/api/d2d1_3/nf-d2d1_3-id2d1devicecontext2-createtransformedimagesource)
- [D2D1_RENDERING_CONTROLS](https://learn.microsoft.com/en-us/windows/win32/api/d2d1_1/ns-d2d1_1-d2d1_rendering_controls)
- [Direct3D 11 resource limits](https://learn.microsoft.com/en-us/windows/win32/direct3d11/overviews-direct3d-11-resources-limits)
- [D3D11_TEXTURE2D_DESC](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/ns-d3d11-d3d11_texture2d_desc)
- [IDXGIAdapter3::QueryVideoMemoryInfo](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_4/nf-dxgi1_4-idxgiadapter3-queryvideomemoryinfo)
- [DXGI 1.4 video memory budget improvements](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/dxgi-1-4-improvements)
- [GlobalMemoryStatusEx](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/nf-sysinfoapi-globalmemorystatusex)
- [MEMORYSTATUSEX](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/ns-sysinfoapi-memorystatusex)
- [CreateMemoryResourceNotification](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-creatememoryresourcenotification)
- [Handling device-lost scenarios in Direct3D 11](https://learn.microsoft.com/en-us/windows/uwp/gaming/handling-device-lost-scenarios)
- [ID3D11Device::GetDeviceRemovedReason](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/nf-d3d11-id3d11device-getdeviceremovedreason)
- [IWICBitmapSource::CopyPixels](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nf-wincodec-iwicbitmapsource-copypixels)
- [libtiff TIFFReadEncodedTile](https://libtiff.gitlab.io/libtiff/functions/TIFFReadEncodedTile.html)
- [libtiff TIFFReadEncodedStrip](https://libtiff.gitlab.io/libtiff/functions/TIFFReadEncodedStrip.html)
- [LibRaw API notes](https://www.libraw.org/docs/API-notes.html)

## 연결 문서

- [실행 백엔드 선택](../12-performance/backend-selection.md)
- [GPU 벤더 범용성](../12-performance/gpu-vendor-portability.md)
- [정밀도와 clipping](../01-render-engine/precision-and-clipping.md)
- [히스토그램과 통계](../03-measurement/histogram-and-statistics.md)
- [WIC](../05-image-io/wic.md)
- [libtiff](../05-image-io/libtiff.md)
- [LibRaw](../05-image-io/libraw.md)
- [내보내기 포맷](../05-image-io/export-formats.md)
- [멀티스레드 내보내기](../07-threading/multithreading-export.md)
