# Film Emulation acutance 공식 근거와 권리 조사

기준일: 2026-08-04

## 구현 provenance

profile별 radius와 base intensity, 사용자 강도 적용 순서는 같은 Apache-2.0 저장소의 다음 source를
기준으로 C++20으로 독립 이식했습니다.

- `Sources/Chromabase/Adjustments/FilmEmulation.swift`
- `Sources/Chromabase/Adjustments/FilmEmulationProfile.swift`
- `Sources/Chromabase/Adjustments/FilmEmulationProfile+Slide.swift`
- `Sources/Chromabase/Adjustments/FilmEmulationProfile+Negative.swift`
- `Sources/Chromabase/Engine/ChromabaseEngine+PostPipeline.swift`

Gaussian sigma와 허용오차는 같은 저장소의 test-only emitter가 canonical macOS runner에서 만든 합성
impulse/step Float32 관측값에 맞췄습니다. 외부 사진, LUT, ICC profile, sharpening code, kernel table이나
특허 수식을 복사하지 않았습니다.

## Apple 공식 기술 근거

- [CIUnsharpMask](https://developer.apple.com/documentation/coreimage/ciunsharpmask): 입력 영상에서 edge
  contrast를 높이는 필터이며 radius와 intensity 입력을 갖는다는 공개 계약을 확인했습니다.
- [CIUnsharpMask radius](https://developer.apple.com/documentation/coreimage/ciunsharpmask/radius): 영향
  반경 parameter의 존재를 확인했습니다.
- [CIUnsharpMask intensity](https://developer.apple.com/documentation/coreimage/ciunsharpmask/3228820-intensity):
  sharpening 강도 parameter의 존재를 확인했습니다.
- [CIContext](https://developer.apple.com/documentation/coreimage/cicontext): working/output color space와
  render context가 결과에 관여하므로 emitter가 extended-linear sRGB와 `RGBAf`를 명시하도록 했습니다.

공식 문서는 exact kernel taps, radius→sigma 변환, border mode와 backend별 Float32 결과를 보장하지
않습니다. 따라서 Windows가 Apple 내부 구현을 복제했다고 주장하지 않고, 고정 OS·fixture에서 관측한
응답과 허용오차를 versioned compatibility contract로 사용합니다.

## 제한적 특허 engineering screen

- [US6046821A](https://patents.google.com/patent/US6046821A/en)는 Google Patents에서
  `Expired - Lifetime`으로 표시되고 예상 만료일은 2017-11-17입니다. standard unsharp 식과 separable
  filtering을 설명하지만 claims는 draft printing mode와 동적 control을 결합합니다. 현재 component는
  고정 profile amount의 desktop 후처리이며 print draft mode나 동적 control이 없습니다.
- [US8750639B2](https://patents.google.com/patent/US8750639B2/en)는 `Active`, 예상 만료일
  2032-07-17로 표시됩니다. 여러 해상도의 histogram/statistical deviation에서 sharpening amount와
  threshold를 자동 산출하는 구성이 중심입니다. 현재 component는 histogram, multi-resolution 분석,
  자동 amount와 threshold를 사용하지 않습니다.
- [US8724919B2](https://patents.google.com/patent/US8724919B2/en)는 Google Patents에서
  `Expired - Fee Related`, 예상 만료일 2032-09-21로 표시됩니다. subject/background segmentation,
  aim sharpness와 위치별 gain을 다루지만 현재 component에는 segmentation, scene/edge histogram이나
  위치별 gain이 없습니다.

Google Patents의 상태와 예상 만료일은 법적 결론이 아닙니다. 위 검토는 가까운 공개 claims와 같은 복합
구성을 무심코 넣지 않기 위한 제한적 engineering screen이며 법률 자문, 유효성 판단 또는
freedom-to-operate 보증이 아닙니다. 자동 선명도, subject-aware 처리나 print mode가 추가되면 전문 검토가
필요합니다.

## 라이선스·저작권 결론

- Windows 구현은 저장소와 같은 Apache-2.0이며 새 제3자 runtime payload는 없습니다.
- Apple 문서는 API 의미 확인에만 사용했고 sample code를 복사하지 않았습니다.
- Gaussian 코드는 공개된 표준 수학을 독립 작성했고, 계수는 저장소 소유 합성 fixture의 실행 관측으로
  정했습니다.
- 특허 문서는 claim 경계 비교에만 사용했으며 식, code, 표와 figure를 구현 자산으로 복사하지 않았습니다.
