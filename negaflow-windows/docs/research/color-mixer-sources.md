# Color Mixer 공식 근거와 권리 조사

기준일: 2026-08-04

## 구현 provenance

Windows 수치와 처리 순서는 같은 Apache-2.0 저장소의 다음 source를 기준으로 독립 이식했습니다.

- `Sources/Chromabase/Develop/DevelopAdjustments.swift`
- `Sources/Chromabase/Adjustments/ColorAdjustStages.swift`
- `Sources/Chromabase/Engine/ChromabaseMetalKernels.swift`
- `Sources/Chromabase/Engine/ChromabaseEngine+PostPipeline.swift`
- `Sources/negaflowApp/Features/Develop/Inspector/ColorMixerSection.swift`
- `Tests/ChromabaseTests/ColorAdjustStagesTests.swift`
- `Tests/ChromabaseTests/DevelopSliderStressTests.swift`

외부 HSL code, 편집기 구현, shader, LUT 또는 test data를 복사하지 않았습니다. fixture는 저장소가 소유한
합성 control과 RGB 값으로 별도 계산했습니다.

## 공식 기술 근거

- [Apple CIContext workingColorSpace](https://developer.apple.com/documentation/coreimage/cicontextoption/workingcolorspace):
  Core Image가 filter kernel을 working color space에서 실행하고 기본값이 linear-gamma extended sRGB임을
  확인했습니다. 이 때문에 macOS kernel에 없는 sRGB transfer를 Windows에 추가하지 않습니다.
- [Apple Core Image Kernel Language Reference](https://developer.apple.com/metal/CoreImageKernelLanguageReference11.pdf):
  `fract(x)=x-floor(x)`, clamp와 `smoothstep`의 경계·Hermite 의미를 확인했습니다.
- [Apple Metal resources](https://developer.apple.com/metal/resources/): 현재 Metal Shading Language
  specification의 공식 배포 위치를 확인했습니다.
- [W3C CSS Color 4 HSL](https://www.w3.org/TR/css-color-4/#the-hsl-notation): HSL의 hue 원, saturation,
  lightness와 RGB 왕복 의미를 대조했습니다. W3C HSL은 sRGB 색으로 정의되고 hue가 무채색에서 의미를
  잃는다고 설명합니다.

W3C sample code는 복사하지 않았습니다. Windows는 같은 저장소의 Metal Float32 분기와 상수를 그대로
독립 작성하며, 표준 HSL과 달리 macOS kernel이 clamped linear working RGB에 직접 적용된다는 차이를
보존합니다.

## 특허 engineering screen

- [US6724435B2](https://patents.google.com/patent/US6724435B2/en)는 실시간 digital video에서 개별색의
  hue 또는 saturation을 독립 조절하는 claims를 포함합니다. Google Patents는 미국 문서를
  `Expired - Lifetime`과 2022-10-24 만료로 표시합니다. 문서의 색별 RGB 함수는 사용하지 않았습니다.
- [US20070285434A1](https://patents.google.com/patent/US20070285434A1/en)는 기준 색축 주변 영역을 고르고
  선형·고차 보간으로 hue angle을 바꾸는 내용을 공개합니다. Google Patents는 미국 출원을
  `Abandoned`로 표시합니다. 다른 국가 family 상태까지 같다고 추정하지 않습니다.
- [US9626774B2](https://patents.google.com/patent/US9626774B2/en)는 Google Patents에서 active이며
  anticipated expiration이 2028-03-07로 표시됩니다. claims는 luminance로 결정한 mapping과 사용자
  curve의 minimum·midpoint·exponent를 이용해 saturation을 바꾸는 구성을 포함합니다. 현재 구현은
  luminance-keyed 지수 curve가 없고 고정 hue 중심의 원형 삼각 가중 평균만 사용합니다.
- [US7262780B2](https://patents.google.com/patent/US7262780B2/en)는 image sensor 색 성분의 saturation
  변환을 다루며 Google Patents에서 `Expired - Lifetime`과 2025-04-20 만료로 표시됩니다. 해당 수식과
  sensor component model을 사용하지 않았습니다.

Google의 legal status는 사이트 자체가 법적 결론이 아니라고 명시합니다. 위 기록은 가까운 공개 claims와
같은 구성을 무심코 복제하지 않기 위한 제한적 engineering screen이며 법률 자문, 유효성 판단 또는
freedom-to-operate 보증이 아닙니다. 전체 M6 graph와 배포 국가가 확정되면 전문 검토가 필요합니다.

## 라이선스·저작권 결론

- 이 변경에서 실행·링크되는 제3자 코드와 데이터는 0개입니다.
- Apple/W3C 자료는 공개 API·색 공간 의미 확인에만 사용했습니다.
- 특허 문서는 claim 경계 비교에만 사용했고 식·code·figure를 구현 근거로 복사하지 않았습니다.
- Windows 코드는 같은 Apache-2.0 제품 source의 동작을 C++20 계약으로 독립 작성했습니다.
