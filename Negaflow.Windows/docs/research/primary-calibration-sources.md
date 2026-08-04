# Primary Calibration 공식 근거와 권리 조사

기준일: 2026-08-04

## 구현 provenance

Windows 수치, UI 범위와 처리 순서는 같은 Apache-2.0 저장소의 다음 source를 기준으로 독립 이식했습니다.

- `Sources/Chromabase/Develop/DevelopAdjustments.swift`
- `Sources/Chromabase/Adjustments/ColorAdjustStages.swift`
- `Sources/Chromabase/Engine/ChromabaseMetalKernels.swift`
- `Sources/Chromabase/Engine/ChromabaseEngine+PostPipeline.swift`
- `Sources/negaflowApp/Features/Develop/Inspector/DevelopAdjustmentSections.swift`
- `Sources/negaflowApp/Features/Develop/Inspector/DevelopInspectorBindings.swift`
- `Tests/ChromabaseTests/ColorAdjustStagesTests.swift`
- `Tests/ChromabaseTests/DevelopSliderStressTests.swift`

외부 HSL code, calibration library, shader, LUT, UI asset 또는 test data를 복사하지 않았습니다. fixture는
저장소가 소유한 합성 control과 RGB 값으로 별도 계산했습니다.

## 공식 기술 근거

- [Apple CIContext workingColorSpace](https://developer.apple.com/documentation/coreimage/cicontextoption/workingcolorspace):
  Core Image kernel이 context의 working color space에서 실행되며 기본 working space가 linear-gamma
  extended sRGB임을 확인했습니다. macOS kernel에 없는 transfer를 Windows에 추가하지 않습니다.
- [Apple Core Image Kernel Language Reference](https://developer.apple.com/metal/CoreImageKernelLanguageReference11.pdf):
  `fract`, `clamp`, `smoothstep`의 공식 의미를 확인했습니다.
- [W3C CSS Color 4 HSL](https://www.w3.org/TR/css-color-4/#the-hsl-notation): HSL이 sRGB의 hue,
  saturation, lightness를 나타내고 0°/120°/240°가 red/green/blue이며 무채색에서 hue가 의미를 잃는다는
  점을 대조했습니다.

W3C sample code는 복사하지 않았습니다. Windows 상수와 연산 순서의 직접 근거는 외부 문서가 아니라
저장소 소유 Metal Float32 source입니다. 표준 HSL과 달리 macOS kernel이 clamped linear working RGB에
직접 적용된다는 차이를 보존합니다.

## 특허 engineering screen

- [US11301972B2](https://patents.google.com/patent/US11301972B2/en)는 Google Patents에서 active,
  2038-12-29 만료로 표시됩니다. claim 1은 enhanced-dynamic-range image의 YCbCr/IPT/ICtCp 같은 두 번째
  색 공간, 다른 첫 번째 색 공간에서 정의된 grading metadata, 두 색 공간 사이에 대응하는 hue region과
  pixel별 saturation adjustment를 함께 요구합니다. 현재 구현은 하나의 clamped working RGB/HSL
  공간만 사용하고 HDR metadata, 두 번째 비대칭 색 공간, 색 공간 간 region mapping과 intensity별 LUT가
  없습니다.
- [US20070285434A1](https://patents.google.com/patent/US20070285434A1/en)는 미국 출원이
  `Abandoned`로 표시됩니다. CORDIC, YCbCr chroma signal과 control로 생성한 선택 adjustment area를
  사용하지만 현재 구현은 이 구성을 사용하지 않습니다. 다른 국가 family 상태가 같다고 추정하지
  않습니다.
- [US7009733B2](https://patents.google.com/patent/US7009733B2/en)는 `Expired - Lifetime`,
  2023-09-21 만료로 표시됩니다. 사용자가 특정 color/range와 target replacement color를 정의하고
  LUT를 만드는 구성이지만 현재 구현은 고정 R/G/B 중심이며 image sampling, target replacement와 LUT가
  없습니다.
- [US7262780B2](https://patents.google.com/patent/US7262780B2/en)는 `Expired - Lifetime`,
  2025-04-20 만료로 표시됩니다. sensor RGB를 LMS로 바꾸고 white-point adaptation·equalization 뒤 L/S를
  M 기준으로 늘리는 claims와 달리 현재 구현은 HSL pointwise 조정이며 LMS, sensor model과 white point가
  없습니다.
- [US7453591B2](https://patents.google.com/patent/US7453591B2/en)는 `Expired - Fee Related`로
  표시됩니다. CMY printer data의 gray-balance와 saturation component를 결합하는 claims이며 현재
  RGB/HSL creative 단계에는 printer CMY, gray balance curve와 halftone이 없습니다.

Google의 legal status는 법적 결론이 아닙니다. 위 기록은 가까운 공개 claims와 같은 구성을 무심코
복제하지 않기 위한 제한적 engineering screen이며 법률 자문, 유효성 판단 또는 freedom-to-operate
보증이 아닙니다. 다른 색 공간 metadata, 자동 장치 calibration이나 배포 국가가 확정되면 전문 검토가
필요합니다.

## 라이선스·저작권 결론

- 이 변경에서 실행·링크되는 제3자 코드와 데이터는 0개입니다.
- Apple과 W3C 자료는 색 공간·함수 의미 확인에만 사용했습니다.
- 특허 문서는 claim 경계 비교에만 사용했고 식·code·figure를 구현 근거로 복사하지 않았습니다.
- Windows 코드는 같은 Apache-2.0 제품 source의 동작을 C++20 계약으로 독립 작성했습니다.
