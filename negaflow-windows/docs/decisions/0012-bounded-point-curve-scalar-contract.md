# ADR-0012: 포인트 커브는 고정 64표본 scalar 계약으로 시작한다

- 상태: 채택
- 날짜: 2026-08-04

## 문제

macOS Chroma Engine의 첫 post-pipeline 단계는 전체 RGB와 R/G/B 채널별 포인트 커브를 하나의 색상
큐브로 합성합니다. Windows에서 비슷해 보이는 임의 곡선을 만들면 기존 recipe 의미와 처리 순서를
잃습니다. 반대로 Core Image의 공개되지 않은 세부 수치를 추정해 무제한 자료구조로 복제하면 아직
검증하지 못한 동작을 제품 계약으로 굳히고 렌더 경로의 비용도 제한할 수 없습니다.

## 결정

1. 같은 Apache-2.0 저장소의 macOS `CurveLUT`, `PointCurveStage`와 post-pipeline 순서를 기준으로
   독립적인 C++20 scalar 구현을 작성합니다. 외부 편집기, 논문 또는 특허의 코드를 복사하지 않습니다.
2. DR/R/G/B 각 커브는 최대 64개 제어점을 받으며 LUT 크기도 64표본으로 고정합니다. 제어점과
   정규화 버퍼는 고정 배열이므로 LUT 생성과 픽셀 적용 중 동적 할당이 없습니다.
3. 제어점은 유한한 `[0, 1]` 좌표여야 합니다. 입력 순서와 무관하게 x로 정렬하고, x 간격이
   `1e-9`보다 작으면 거부합니다. 끝점이 없으면 가장 가까운 y를 x=0 또는 x=1까지 연장합니다.
4. 빈 커브와 두 점 미만의 단독 커브, 모든 점의 `abs(y-x) < 1e-4`인 커브는 macOS 기준과 같이
   무연산으로 봅니다. 전체가 무연산이면 extended RGB를 clamp하지 않고 bit-exact로 복사합니다.
5. 각 커브의 단조 cubic LUT를 만든 뒤 전체 RGB LUT 결과를 가장 가까운 64표본 index로 채널 LUT에
   합성합니다. 픽셀 적용 시에는 extended-linear sRGB를 sRGB로 인코딩하고 `[0, 1]` cube domain에
   제한한 다음 채널 LUT를 선형 보간하고 다시 extended-linear sRGB로 되돌립니다. alpha는 보존합니다.
6. 처리 순서는 `노출 → 기본 톤 → 동적 측정 → 파라메트릭 커브 → 포인트 커브`입니다. 포인트 커브는
   macOS post-pipeline의 첫 단계이며 기존 tone orchestration 뒤에 실행합니다.
7. 잘못된 제어점, image view 또는 유한하지 않은 입력은 명시적 상태로 실패합니다. orchestration은
   실패한 결과 pixel을 게시하지 않습니다.
8. 이번 체크포인트는 native recipe 경계와 conformance만 추가합니다. CLI와 WinUI는 아직 임의 제어점
   입력을 노출하지 않으며 report에는 알고리즘 버전과 실제 적용 여부만 기록합니다.
9. 일반 이미지 SHA-256 기본값은 계속 `끔`입니다. 포인트 커브는 hash를 요구하지 않습니다.

## 결과

포인트 커브 수학, tone orchestration, CLI 보고와 fixture가 분리되어 다음 SIMD/GPU 구현이 UI나 파일
I/O를 소유하지 않습니다. 고정 배열과 64표본 LUT로 한 프레임의 추가 full-frame buffer 없이 기존
`WorkingImage`에 제자리 적용할 수 있습니다.

64개 제어점 상한은 현재 Windows의 명시적 방어 경계입니다. macOS 편집기의 실질 상한과 recipe
serialization을 확인한 뒤 더 큰 값이 실제로 필요하다는 증거가 생기면 별도 결정으로 바꿉니다.

## 검증 한계

Apple 문서는 색상 큐브의 domain과 working color space는 설명하지만 Core Image 런타임의 모든
끝점·보간·Float32 반올림을 보증하지 않습니다. 현재 fixture는 저장소 소유 수식을 독립 계산한
합성 기준이며 실제 macOS Core Image render golden은 아닙니다. 따라서 현재 구현을 macOS runtime과
bit-exact하다고 주장하지 않습니다.

## 공식 근거와 권리

- [Apple Core Image Filter Reference](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/)
- [Apple CIContext workingColorSpace](https://developer.apple.com/documentation/coreimage/cicontextoption/workingcolorspace)
- [Apple CIColorCubeWithColorSpace](https://developer.apple.com/documentation/coreimage/cicolorcubewithcolorspace)
- [Fritsch–Carlson monotone interpolation paper](https://epubs.siam.org/doi/abs/10.1137/0717021)

새 runtime dependency, 외부 코드, 이미지, ICC profile 또는 sample payload는 추가하지 않습니다. 공개
특허와 구현 경계 비교 및 법적 한계는 `research/point-curve-sources.md`에 기록합니다.
