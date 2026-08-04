# ADR-0009: 첫 톤 조정은 macOS 수식과 순서를 보존하고 동적 측정 차이를 명시한다

- 상태: 채택
- 날짜: 2026-08-04

## 문제

M4 한 장 수직 경로에는 네거티브 반전 뒤 최소 노출·대비·커브가 필요합니다. 단순히 비슷하게 보이는
Windows 필터를 고르면 macOS의 선형 노출, 지각 도메인 대비, 검정 앵커, 적응형 커브 대역과 처리 순서를
잃습니다. 반대로 Core Image의 내부 축소 필터를 추정해 복제하면 검증할 수 없는 플랫폼 종속 수치를
제품 계약처럼 굳히게 됩니다.

## 결정

1. 같은 저장소의 macOS `ToneMapper`와 `ChromabaseMetalKernels`에 있는 Float32 수식을 Windows C++20
   scalar 기준 구현으로 직접 옮깁니다. 외부 이미지 편집기나 특허 문서의 코드를 복사하지 않습니다.
2. 처리 순서는 `노출 → 기본 톤 → 커브 대역 측정 → 파라메트릭 커브`로 고정합니다. 노출은
   extended-linear RGB에서 `2^stops`를 곱하고 tone stage가 시작될 때만 hue/luma 보존 방식으로
   `[0, 1]` 표시 영역에 넣습니다.
3. macOS와 같은 적용 임계값 `abs(value) > 1e-3`을 사용합니다. 제품 입력 범위는 노출 `[-5, 5]`,
   기본 톤과 커브 `[-1, 1]`로 제한하고 범위를 벗어나면 source를 읽기 전에 CLI가 거부합니다.
4. 기본 톤은 sRGB 인코딩 luma의 0.46 피벗 대비와 density/highlights/shadows/whites/blacks mask를 모두
   구현합니다. 첫 CLI는 최소 계약에 필요한 contrast만 노출하지만 나머지 수식도 같은 응집된 kernel에
   보존합니다.
5. 커브는 highlights/lights/darks/shadows 네 값을 구현하고, 작은 이미지에는 macOS의 고정 fallback
   band를 그대로 사용합니다.
6. 동적 band는 macOS와 같은 target width 64~256, 4% border 제외, p10/p35/p65/p90 index와 최소
   0.025 간격을 사용합니다. Apple 문서는 macOS 기본 affine downsample을 고품질 다중 패스로만 설명하고
   filter coefficient는 공개하지 않으므로 Windows raster는 결정적인 면적 평균 `portable_area_v1`을
   사용합니다. 이 mode와 target·sample 수·임시 byte를 결과 JSON에 기록합니다.
7. 측정용 luma는 최대 1,048,576개로 제한합니다. 실패하면 조정된 pixel을 폐기하고 출력 단계로
   진행하지 않습니다.
8. 기존 8개 인수 export 명령은 완전한 no-op tone stage로 유지합니다. 여섯 선택 인수를 모두 줄 때만
   노출·대비·네 커브를 적용합니다.
9. 일반 이미지 source/artifact SHA-256은 계속 기본 `off`입니다. 톤 stage는 hash를 요구하지 않습니다.

## 결과

픽셀 수식, 동적 측정, 소유 이미지 orchestration이 서로 다른 파일에 있어 향후 AVX2/NEON/D3D 경로가
측정 정책이나 CLI와 얽히지 않습니다. 합성 3×2 fixture는 고정 fallback을 선택해 Windows에서 macOS
Float32 수식을 독립 기준값으로 검증할 수 있습니다. 실제 631×403 저장소 TIFF에서는 동적 측정과
검증된 TIFF16/PNG16 게시까지 연결됩니다.

macOS Core Image와 Windows 면적 평균의 동적 band가 bit-exact하다는 주장은 하지 않습니다. 실제 macOS
runtime golden이 생기면 같은 입력의 percentile과 최종 pixel diff를 보고하고, 허용 범위를 벗어날 때만
명시적 공통 resampler로 두 플랫폼 계약을 바꾸는 결정을 별도로 내립니다.

## 현재 범위 밖

- macOS runtime tone golden, 실제 사진 pixel diff, cross-platform 허용오차 manifest와 recipe serialization
- AVX2/NEON, DirectCompute/WARP와 tile 처리
- point curve, local contrast, clarity, channel/color grading 등 M6 전체 graph
- UI slider와 실제 catalog 상태 연결

stage process CPU와 진단 전용 versioned fingerprint는 후속 ADR-0010에서 구현했습니다.

## 공식 근거와 권리

- [Apple Core Image working color space](https://developer.apple.com/documentation/coreimage/cicontextoption/workingcolorspace)
- [Apple Core Image high-quality downsample option](https://developer.apple.com/documentation/coreimage/cicontextoption/highqualitydownsample)
- [Apple CIImage sampling modes](https://developer.apple.com/documentation/coreimage/ciimage)
- [Apple CIColorMatrix](https://developer.apple.com/documentation/coreimage/cifilter/3228294-colormatrix)
- [W3C CSS Color 4 sRGB transfer](https://www.w3.org/TR/css-color-4/)

이번 구현은 같은 Apache-2.0 저장소의 macOS 제품 수식을 독립적으로 이식한 것이며 새 runtime dependency,
외부 코드, 사진, ICC profile 또는 sample payload를 추가하지 않습니다. 특허 비교와 한계는
`research/tone-adjustment-sources.md`에 기록합니다.
