# ADR-0015: Calibration은 고정 R/G/B HSL 대역 scalar로 시작한다

- 상태: 채택
- 날짜: 2026-08-04

## 문제

macOS Chroma Engine의 `Calibration`은 scanner·monitor·printer의 장치 calibration이 아니라 Develop
recipe의 마지막 고급 색상 단계입니다. R/G/B 기본색 주변의 hue와 saturation을 조절합니다. 이름만 보고
ICC 장치 보정과 섞거나 일반 primary matrix로 대체하면 제품 동작과 처리 순서가 달라집니다. 반대로
전체 Develop graph나 UI 저장을 한 번에 옮기면 검증되지 않은 책임이 orchestration에 모입니다.

## 결정

1. 같은 Apache-2.0 저장소의 macOS `CalibrationAdjust`, `CalibrationStage`,
   `calibrationPrimaries`와 post-pipeline 순서를 기준으로 C++20 scalar를 독립 작성합니다. 외부 색상
   보정 code, LUT나 특허 문서의 수식을 복사하지 않습니다.
2. 내부 이름은 장치 calibration과 구분되는 `PrimaryCalibrationParameters`로 정합니다. 사용자 계약은
   red/green/blue 각각 hue와 saturation 두 값이며 모두 UI와 같은 `[-1, 1]`입니다.
3. 여섯 값 모두 `abs(value) < 1e-4`이면 identity입니다. 정확히 `±1e-4`인 값은 활성입니다.
   identity는 변환과 clamp를 건너뛰어 extended RGB와 alpha를 bit-exact로 보존합니다.
4. 활성 단계는 extended-linear sRGB 입력을 먼저 `[0, 1]`로 clamp하고 macOS kernel과 같은 Float32
   RGB↔HSL 수식을 적용합니다. 표준 HSL이 gamma-encoded sRGB를 전제로 한다는 이유로 임의의 transfer
   function을 추가하지 않습니다.
5. hue 중심은 red `0`, green `0.333333`, blue `0.666667` turn이며 원형 삼각 가중치 폭은 `0.22`입니다.
   겹친 대역은 가중 평균합니다. saturation `0.03~0.16` smoothstep gate로 무채색을 보호하고 hue는
   `weightedHue × 0.08`, saturation은 `s × (1 + weightedSaturation × gate)`로 조절합니다. 최종 RGB는
   `[0, 1]`로 clamp하며 lightness와 alpha는 보존합니다.
6. 처리 순서는 `포인트 커브 → Color Mixer → Color Grading → Calibration`입니다. 수학은
   `primary_calibration.cpp`에, 단계 순서와 실패 시 owned pixel 폐기는 작은 working orchestration에
   둡니다. 파일 I/O, TIFF, CLI parsing과 UI 상태는 kernel이 소유하지 않습니다.
7. 파라미터, image view 또는 입력 pixel이 유효하지 않으면 명시적으로 실패합니다. 여섯 control은
   image call마다 고정 배열로 한 번 준비하며 pixel loop에는 heap allocation이나 추가 full-frame
   buffer가 없습니다.
8. 이번 체크포인트는 native recipe 경계와 conformance를 추가합니다. CLI와 WinUI는 아직 활성 값을
   입력·저장하지 않으며 report에는 알고리즘 버전과 적용 여부만 기록합니다.
9. 일반 이미지 SHA-256 기본값은 계속 `끔`입니다. Calibration은 hash를 요구하지 않습니다.

## 결과

고정 3대역 scalar reference가 생겨 이후 AVX2, NEON, Direct2D/WARP 구현이 같은 수치 계약을 공유할 수
있습니다. 이름과 문서가 creative primary adjustment를 scanner/display ICC calibration과 분리합니다.

## 검증 한계

현재 fixture는 저장소 소유 macOS 수식을 별도 Float32 계산으로 재현한 합성 기준이며 실제 macOS Core
Image render golden은 아닙니다. compiler 연산 결합과 GPU runtime 차이를 확인하기 전에는 bit-exact
동등성을 주장하지 않습니다.

## 공식 근거와 권리

- [Apple Core Image workingColorSpace](https://developer.apple.com/documentation/coreimage/cicontextoption/workingcolorspace)
- [Apple Core Image Kernel Language Reference](https://developer.apple.com/metal/CoreImageKernelLanguageReference11.pdf)
- [W3C CSS Color 4 HSL](https://www.w3.org/TR/css-color-4/#the-hsl-notation)

새 runtime dependency, 외부 코드, 이미지, ICC profile 또는 sample payload는 추가하지 않습니다. 관련
공개 claims와 구현 차이, 법적 한계는 `research/primary-calibration-sources.md`에 기록합니다.
