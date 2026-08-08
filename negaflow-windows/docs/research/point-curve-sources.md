# 포인트 커브 공식 근거와 권리 조사

기준일: 2026-08-04

## 구현 provenance

Windows 처리 순서와 수식은 같은 Apache-2.0 저장소의 다음 macOS source를 기준으로 독립 이식했습니다.

- `Sources/Chromabase/Adjustments/ColorAdjustStages.swift`
- `Sources/Chromabase/Develop/DevelopAdjustments.swift`
- `Sources/Chromabase/Engine/ChromabaseEngine+PostPipeline.swift`
- `Tests/ChromabaseTests/ColorAdjustStagesTests.swift`

Windows 구현은 C++20 checked image view와 고정 배열 계약에 맞춰 새로 작성했습니다. 외부 편집기,
라이브러리, 논문 또는 특허의 코드와 표를 복사하지 않았고 새 runtime dependency도 추가하지 않았습니다.

## 공식 기술 근거

- [Apple Core Image Filter Reference](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/):
  `CIColorCube`가 RGB를 table index로 사용하고 cube data가 Float32 RGBA이며 R index가 가장 빠르게
  변한다는 공개 의미를 확인했습니다. 색상 filter는 working space에서 unpremultiplied 값으로 동작한다고
  설명합니다.
- [Apple CIContext workingColorSpace](https://developer.apple.com/documentation/coreimage/cicontextoption/workingcolorspace):
  Core Image가 working space로 자동 변환하고 기본값이 extended-linear sRGB라는 경계를 확인했습니다.
- [Apple CIColorCubeWithColorSpace](https://developer.apple.com/documentation/coreimage/cicolorcubewithcolorspace):
  명시한 color space와 함께 cube lookup을 사용하는 현재 API 경계를 확인했습니다.
- [Fritsch–Carlson, Monotone Piecewise Cubic Interpolation](https://epubs.siam.org/doi/abs/10.1137/0717021):
  단조 piecewise cubic interpolation의 공개 학술 배경을 확인했습니다. Windows 코드는 논문 구현을
  복사한 것이 아니라 저장소의 macOS `CurveLUT` 수식을 C++로 독립 이식했습니다.

Apple 문서는 cube domain의 의미를 제공하지만 1차원 curve를 cube로 펼친 실제 macOS 구현의 끝점,
채널 합성, lookup 보간과 Float32 반올림을 모두 규정하지 않습니다. Windows의 64표본 선형 픽셀 lookup은
공개 cube 의미와 저장소 source를 함께 따른 구현 판단이며 실제 Core Image runtime golden으로 아직
증명하지 않았습니다.

## 특허 engineering screen

공개 claims가 현재 범위와 겹치는지 기능 단위로 제한적으로 비교했습니다.

- [US9997196B2](https://patents.google.com/patent/US9997196B2/en)는 Google Patents에서 active로 표시되며
  media item의 playback·transition retiming curve를 다룹니다. 현재 구현은 이미지 RGB lookup이고
  재생 시간, media transition 또는 timeline을 처리하지 않습니다.
- [US9460236B2](https://patents.google.com/patent/US9460236B2/en)는 cluster에서 variable을 선택하는
  curve 분석을 다루며 Google Patents에는 fee-related expiration이 표시됩니다. 현재 구현은 cluster,
  variable selection 또는 data analysis를 하지 않습니다.
- [US10542269B2](https://patents.google.com/patent/US10542269B2/en)는 Google Patents에서 active로 표시되며
  video decoder가 SDR에서 HDR을 예측하기 위한 LUT node를 구성·수정하는 claims를 포함합니다. 현재
  구현은 bitstream decoder, HDR prediction, 이전 node와 slope를 이용한 node 수정, weight parameter,
  video 처리를 사용하지 않습니다.

국제 출원의 ceased 표시는 같은 family의 미국 특허까지 소멸했다는 뜻으로 사용하지 않았습니다. 위
비교는 알려진 공개 claims와 같은 구성을 무심코 채택하지 않기 위한 제한적 engineering screen이며,
법률 자문, 특허 유효성 판단 또는 freedom-to-operate 보증이 아닙니다. 배포 범위와 전체 M6 graph가
확정되면 전문 검토가 별도로 필요합니다.

## 라이선스·저작권 결론

- 이 변경에서 실행·링크되는 제3자 코드나 데이터는 0개입니다.
- 수치 fixture는 저장소가 소유한 합성 제어점과 pixel로 만들었으며 사용자 TIFF를 포함하지 않습니다.
- Apple 문서는 API 의미 확인에만, 논문과 특허는 선행 기술·claim 경계 확인에만 사용했습니다.
- 구현은 같은 Apache-2.0 제품 source의 동작을 Windows 계약에 맞게 독립 작성했습니다.
