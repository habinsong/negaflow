# ADR-0014: Color Grading은 고정 3구간 extended-linear scalar로 시작한다

- 상태: 채택
- 날짜: 2026-08-04

## 문제

macOS Chroma Engine은 Color Mixer 뒤에서 shadows, midtones, highlights의 hue, saturation, luminance와
전역 blending, balance를 사용하는 `colorGrade`를 실행합니다. 일반 색상환이나 서드파티 grading
라이브러리로 바꾸면 구간 가중치, pivot, 색차 보존 방식과 clamp 경계가 달라집니다. 전체 Develop graph나
UI 상태를 한꺼번에 옮기면 아직 검증되지 않은 stage와 I/O가 섞입니다.

## 결정

1. 같은 Apache-2.0 저장소의 macOS `ColorGrading`, `ColorGradingStage`, `colorGrade`와 post-pipeline
   순서를 기준으로 C++20 scalar를 독립 작성합니다. 외부 grading code, LUT나 특허 문서의 수식을
   복사하지 않습니다.
2. 구간은 shadows, midtones, highlights 세 개로 고정합니다. 각 hue 범위는 `[0, 360]`, saturation은
   `[0, 1]`, luminance는 `[-1, 1]`입니다. blending은 `[0, 1]`, balance는 `[-1, 1]`입니다.
3. 모든 구간에서 `saturation <= 1e-4`이고 `abs(luminance) <= 1e-4`이면 identity입니다. hue,
   blending과 balance만 바뀐 경우도 identity이며 extended RGB와 alpha를 bit-exact로 보존합니다.
4. 활성 단계는 extended-linear sRGB를 입력으로 받고 입력을 먼저 clamp하지 않습니다. 구간 hue를
   HSV 값 1의 tint로 바꾼 뒤 Rec.709/sRGB relative-luminance 계수로 무채색 성분을 빼고 saturation과
   고정 계수 `0.75`를 적용합니다. luminance offset 계수는 `0.22`입니다.
5. `pivot = clamp(0.5 + balance × 0.30, 0.15, 0.85)`,
   `width = mix(0.10, 0.50, blending)`으로 고정합니다. source luma로 shadow/highlight smoothstep과
   삼각형 midtone weight를 계산하고 세 offset을 더한 뒤 최종 RGB만 `[0, 1]`로 clamp합니다. alpha는
   보존합니다.
6. 처리 순서는 `포인트 커브 → Color Mixer → Color Grading`입니다. 수학은 `color_grading.cpp`에,
   순서와 실패 시 owned pixel 폐기는 작은 working orchestration에 둡니다. 파일 I/O, TIFF, CLI parsing,
   UI 상태는 kernel이 소유하지 않습니다.
7. 파라미터, image view 또는 입력 pixel이 유효하지 않으면 명시적으로 실패합니다. 준비된 세 구간
   offset, pivot과 width는 image call마다 한 번만 계산하며 pixel loop에는 heap allocation이나 추가
   full-frame buffer가 없습니다.
8. 이번 체크포인트는 native recipe 경계와 conformance를 추가합니다. CLI와 WinUI는 아직 활성 값을
   입력·저장하지 않으며 report에는 알고리즘 버전과 적용 여부만 기록합니다.
9. 일반 이미지 SHA-256 기본값은 계속 `끔`입니다. Color Grading은 hash를 요구하지 않습니다.

## 결과

작은 3구간 scalar reference가 생겨 이후 AVX2, NEON, Direct2D/WARP 구현이 같은 수치 계약을 공유할 수
있습니다. 수학, orchestration, CLI 보고와 UI가 분리되어 한 타입에 독립적인 변경 이유를 모으지 않습니다.

## 검증 한계

현재 fixture는 저장소 소유 macOS 수식을 별도 Float32 계산으로 재현한 합성 기준이며 실제 macOS Core
Image render golden은 아닙니다. compiler 연산 결합과 GPU runtime 차이를 확인하기 전에는 bit-exact
동등성을 주장하지 않습니다.

## 공식 근거와 권리

- [Apple Core Image workingColorSpace](https://developer.apple.com/documentation/coreimage/cicontextoption/workingcolorspace)
- [Apple extended linear sRGB](https://developer.apple.com/documentation/coregraphics/cgcolorspace/extendedlinearsrgb)
- [Apple Core Image Kernel Language Reference](https://developer.apple.com/metal/CoreImageKernelLanguageReference11.pdf)
- [W3C WCAG 2.2 relative luminance](https://www.w3.org/TR/WCAG22/#dfn-relative-luminance)

새 runtime dependency, 외부 코드, 이미지, ICC profile 또는 sample payload는 추가하지 않습니다. 관련
공개 claims와 구현 차이, 법적 한계는 `research/color-grading-sources.md`에 기록합니다.
