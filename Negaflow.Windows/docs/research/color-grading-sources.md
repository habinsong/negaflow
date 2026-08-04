# Color Grading 공식 근거와 권리 조사

기준일: 2026-08-04

## 구현 provenance

Windows 수치, UI 범위와 처리 순서는 같은 Apache-2.0 저장소의 다음 source를 기준으로 독립 이식했습니다.

- `Sources/Chromabase/Develop/DevelopAdjustments.swift`
- `Sources/Chromabase/Adjustments/ColorAdjustStages.swift`
- `Sources/Chromabase/Engine/ChromabaseMetalKernels.swift`
- `Sources/Chromabase/Engine/ChromabaseEngine+PostPipeline.swift`
- `Sources/negaflowApp/Features/Develop/Inspector/ColorGradingSection.swift`
- `Sources/negaflowApp/Shared/UI/ColorWheelView.swift`
- `Tests/ChromabaseTests/ColorAdjustStagesTests.swift`
- `Tests/ChromabaseTests/DevelopSliderStressTests.swift`

외부 grading code, shader, LUT, UI asset 또는 test data를 복사하지 않았습니다. fixture는 저장소가 소유한
합성 control과 RGB 값으로 별도 계산했습니다.

## 공식 기술 근거

- [Apple CIContext workingColorSpace](https://developer.apple.com/documentation/coreimage/cicontextoption/workingcolorspace):
  Core Image kernel이 context의 working color space에서 실행되며 기본 working space가 linear-gamma
  extended sRGB임을 확인했습니다.
- [Apple extended linear sRGB](https://developer.apple.com/documentation/coregraphics/cgcolorspace/extendedlinearsrgb):
  macOS 단계의 입력 색 공간 이름과 extended 범위를 대조했습니다.
- [Apple Core Image Kernel Language Reference](https://developer.apple.com/metal/CoreImageKernelLanguageReference11.pdf):
  `clamp`, `mix`, `smoothstep`의 공식 의미를 확인했습니다.
- [W3C WCAG 2.2 relative luminance](https://www.w3.org/TR/WCAG22/#dfn-relative-luminance):
  linearized sRGB의 relative-luminance 계수 `0.2126, 0.7152, 0.0722`를 확인했습니다.
- [ITU-R BT.709-6](https://www.itu.int/dms_pubrec/itu-r/rec/bt/R-REC-BT.709-6-201506-I%21%21PDF-E.pdf):
  같은 기본 primaries의 luma 계수를 교차 확인했습니다. 방송용 비선형 신호 정의를 Windows linear
  수식으로 그대로 가져오지는 않았습니다.
- [Alvy Ray Smith, Color Gamut Transform Pairs](https://alvyray.com/Papers/CG/color78.pdf): HSV 모델의
  역사와 hue/saturation/value 의미만 확인했습니다. 논문의 식, code와 figure는 복사하지 않았습니다.

Windows 구현 상수와 연산 순서의 직접 근거는 외부 문서가 아니라 저장소 소유 Swift/Metal source입니다.
공식 문서는 색 공간과 표준 함수 의미의 교차 검증에만 사용했습니다.

## 특허 engineering screen

- [US7693341B2](https://patents.google.com/patent/US7693341B2/en)는 Google Patents에서 active,
  2029-02-04 만료로 표시됩니다. claims는 선택된 sample range를 받고 그 범위에 따라 interface를 골라
  image 위에 overlay하는 구성을 포함합니다. 현재 구현은 고정 세 구간과 별도 inspector를 사용하며
  image sample 선택, 자동 interface 선택과 on-image overlay가 없습니다.
- [US8958640B1](https://patents.google.com/patent/US8958640B1/en)은 active, anticipated expiration
  2033-07-01로 표시됩니다. 입력 pixel group에서 neutral color나 correction을 결정하는 claims와 달리
  현재 구현은 image content를 분석하지 않고 사용자가 준 고정 상수만 pointwise 적용합니다.
- [US7684096B2](https://patents.google.com/patent/US7684096B2/en)는 미국 문서가 active이고
  2026-11-18 만료로 표시됩니다. 대표 이미지, 2D histogram과 장면별 offset을 도출하는 claims를
  포함하지만 현재 구현은 단일 이미지의 histogram, scene analysis와 자동 offset이 없습니다.
- [US12394128B2](https://patents.google.com/patent/US12394128B2/)는 active, anticipated expiration
  2044-11-06으로 표시됩니다. on-image 영역 선택, 지능형 tonal classification, on-image wheel과 curve
  연동을 포함하는 claims와 달리 현재 구현은 별도 inspector의 고정 세 구간이며 선택·분류가 없습니다.
- [US7412105B2](https://patents.google.com/patent/US7412105B2/en)는 `Expired - Lifetime`, adjusted
  expiration 2025-09-19로 표시됩니다. local neighborhood intensity와 크기를 이용하는 tone-selective
  adjustment를 다루지만 현재 구현은 주변 pixel을 읽지 않는 source-luma pointwise 수식입니다.

Google의 legal status는 법적 결론이 아닙니다. 위 기록은 가까운 공개 claims와 같은 구성을 무심코
복제하지 않기 위한 제한적 engineering screen이며 법률 자문, 유효성 판단 또는 freedom-to-operate
보증이 아닙니다. UI interaction과 자동 분석 범위가 넓어지거나 배포 국가가 확정되면 전문 검토가
필요합니다.

## 라이선스·저작권 결론

- 이 변경에서 실행·링크되는 제3자 코드와 데이터는 0개입니다.
- Apple, W3C, ITU와 논문은 색 공간·함수·모델 의미 확인에만 사용했습니다.
- 특허 문서는 claim 경계 비교에만 사용했고 식·code·figure를 구현 근거로 복사하지 않았습니다.
- Windows 코드는 같은 Apache-2.0 제품 source의 동작을 C++20 계약으로 독립 작성했습니다.
