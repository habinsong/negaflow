# 톤 조정 공식 근거와 권리 조사

기준일: 2026-08-04

## 구현 provenance

Windows 수식과 순서는 같은 저장소의 다음 macOS source를 기준으로 직접 옮겼습니다.

- `Sources/Chromabase/Adjustments/ToneMapper.swift`
- `Sources/Chromabase/Engine/ChromabaseMetalKernels.swift`
- `Sources/Chromabase/Develop/DevelopParameters.swift`
- `Sources/Chromabase/Develop/DevelopToneRange.swift`
- `Tests/ChromabaseTests/ToneMapperControlsTests.swift`
- `Tests/ChromabaseTests/ToneMapperNegativeContrastTests.swift`

Windows 코드는 C++20 image view와 명시적 소유권 계약에 맞춰 새로 작성했습니다. Darktable,
RawTherapee, OpenColorIO 또는 다른 외부 프로젝트의 tone code를 복사·번역하지 않았고 새 library를
링크하지 않았습니다. 합성 fixture도 이번 저장소에서 직접 만든 숫자만 사용합니다.

## 공식 기술 근거

- [Apple CIContext workingColorSpace](https://developer.apple.com/documentation/coreimage/cicontextoption/workingcolorspace):
  Core Image가 working space에서 입력과 출력을 color match하며 기본 working space가 linear-gamma
  extended sRGB임을 확인했습니다.
- [Apple CIContext highQualityDownsample](https://developer.apple.com/documentation/coreimage/cicontextoption/highqualitydownsample):
  macOS 기본 affine downsample이 고품질 다중 패스이고 다른 플랫폼 기본과 다를 수 있음을 확인했습니다.
  공개 문서에는 filter coefficient가 없으므로 이를 추정해 Windows 계약으로 만들지 않았습니다.
- [Apple CIImage](https://developer.apple.com/documentation/coreimage/ciimage): 명시적 nearest와 bilinear
  sampling API가 따로 존재하고 affine transform이 별도 image recipe임을 확인했습니다.
- [Apple CIColorMatrix](https://developer.apple.com/documentation/coreimage/cifilter/3228294-colormatrix):
  macOS 노출 단계가 RGB vector 곱과 alpha 항등으로 표현되는 API 경계를 확인했습니다.
- [W3C CSS Color 4](https://www.w3.org/TR/css-color-4/): sRGB의 0.04045/0.0031308 경계와
  sign-preserving extended transfer 수식을 대조했습니다.

Apple 문서의 sample code나 문구를 source에 복사하지 않았습니다. 구현 계수는 외부 문서가 아니라
저장소의 기존 macOS 제품 수식에서 왔습니다.

## 특허 engineering screen

기능 표현이 가까운 공개 문서를 claims 중심으로 비교했습니다.

- [US9369684B2](https://patents.google.com/patent/US9369684B2/en)는 image block과 이웃 block의
  luminance distribution을 target luminance에 맞추는 local tone curve computation입니다. 현재 구현은
  block·이웃·target distribution이나 local curve 최적화를 사용하지 않는 전역 pointwise 수식입니다.
- [WO2015105643A1](https://patents.google.com/patent/WO2015105643A1/en)는 이미지를 여러 zone으로
  나누고 zone별 histogram과 tone curve를 정하는 local tone mapping입니다. 현재 구현은 zone을 만들지
  않습니다.
- [WO2017009182A1](https://patents.google.com/patent/WO2017009182A1/en)는 HDR/SDR video와
  encode/decode 맥락에서 입력 brightness에 따라 multi-range parametric tone function parameter를
  modulation하는 방법을 설명합니다. 현재 네 커브 값은 사용자가 직접 주고 percentile은 band mask의
  위치만 정하며 HDR video bitstream, inverse tone mapping, nits modulation이나 temporal smoothing을
  사용하지 않습니다.

Google Patents는 WO 문서 상태를 `Ceased`, 일부 미국 문서를 `Active`로 표시하지만 사이트 자체가 법적
분석이나 정확한 상태를 보증하지 않는다고 명시합니다. WO 출원의 상태만으로 국가별 family 권리가
끝났다고 판단하지 않습니다. 이 기록은 알려진 local/HDR 자동 tone-mapping claim과 의도치 않게 같은
구성을 채택하지 않기 위한 초기 engineering screen이며 법률 의견이나 freedom-to-operate 보증이
아닙니다.

## 구현에 반영한 경계

- 사용자 지정 전역 조정과 작은 전역 percentile 측정만 사용합니다.
- block/local optimization, 목표 histogram fitting, video temporal smoothing, encode metadata를 구현하지
  않습니다.
- 외부 특허의 equation, code, figure, sample을 구현 근거로 사용하지 않습니다.
- 현재 native runtime dependency는 Windows 기본 API뿐입니다.
- 배포 지역과 전체 M6 graph가 확정되면 전문 검토가 여전히 필요합니다.
