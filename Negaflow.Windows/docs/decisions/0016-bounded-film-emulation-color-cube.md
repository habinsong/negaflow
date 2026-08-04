# ADR-0016: Film Emulation 색상 단계는 고정 RGB33 cube로 격리한다

- 상태: 채택
- 날짜: 2026-08-04

## 문제

macOS Chroma Engine은 Primary Calibration 다음에 입력 종류를 나눕니다. 디지털 입력은
`DigitalFilmLook`, 필름 스캔은 `FilmEmulationStage`로 들어가며 후자는 절차형 색상 cube와 spatial
acutance를 함께 사용합니다. Windows에서 이 둘을 한 번에 옮기면 색상 수치, Core Image 보간,
`CIUnsharpMask` 대응과 source routing을 동시에 추측하게 됩니다. 불완전한 구현을 실제 파이프라인에
연결하면 “Film Emulation 완료”라는 잘못된 제품 계약도 생깁니다.

## 결정

1. 같은 Apache-2.0 저장소의 `FilmEmulation.swift`, `FilmEmulationProfile.swift`와 slide/negative
   profile extension을 기준으로 C++20 색상 substage를 독립 작성합니다. 외부 LUT, 필름 측정 데이터,
   shader, 특허 수식이나 이미지 자산은 복사하지 않습니다.
2. 활성 명부는 macOS와 같은 11종입니다. Ektachrome E100, Provia 100F, Velvia 50, Portra
   160/400/800, Ektar 100, UltraMax 400, ColorPlus 200, Fujicolor C200, Pro 400H를 고정 enum으로
   표현합니다. 이름은 호환되는 recipe 식별을 위한 지명적 사용이며 제조사 보증을 뜻하지 않습니다.
3. cube는 한 변 33인 RGB table입니다. 각 node는 Float32 RGB 세 값이므로 고정 payload는
   `33³ × 12 = 431,244`바이트입니다. caller가 heap에서 소유하며 build/apply kernel은 내부 heap이나
   full-frame buffer를 할당하지 않습니다.
4. intensity는 유한해야 하며 계산 시 `[0, 1]`로 제한합니다. macOS와 같이 `round(value × 20)`으로
   5% 단계를 만들고 실제 색상 강도는 그 step을 20으로 나눈 값입니다. `none` 또는 step 0은 identity로
   처리합니다.
5. node 생성은 채널별 tone curve, 3×3 색 혼합, shadow/highlight tint, brightness·chroma·hue 의존
   saturation, source와 full-look 혼합 순서를 보존합니다. 계산은 double로 하고 cube payload는 Float32로
   고정합니다.
6. cube domain은 sRGB encoded `[0, 1]`입니다. extended-linear sRGB working pixel은 기존 고정 sRGB
   transfer로 encode한 뒤 제한하고, RGB33 table을 삼선형 보간한 뒤 다시 linear로 decode합니다.
   배열 순서는 blue plane 바깥, green row 중간, red column 안쪽으로 고정합니다.
7. identity는 active pixel의 extended RGB와 straight alpha를 bit-exact로 복사하고 stride padding은
   건드리지 않습니다. 활성 apply는 alpha를 그대로 보존하며 input/output alias를 허용합니다.
8. 알 수 없는 profile, 비유한 intensity·pixel·cube 값, 잘못된 view, 일치하지 않는 profile/step의 오래된
   cube를 pixel 처리 전에 거부합니다. cube 전체가 유한한 `[0, 1]`인지 확인합니다.
9. 이번 단계는 `chromabase-film-emulation-color-v1` standalone native 계약까지만 추가합니다.
   `WorkingToneAdjuster`, CLI, ABI, WinUI, source routing과 recipe persistence에는 연결하지 않습니다.
   `CIUnsharpMask` 기반 acutance도 이 계약 밖입니다.
10. 일반 이미지 SHA-256 기본값은 계속 `끔`이고 이 기능은 hash를 요구하지 않습니다. 새 runtime
    dependency도 추가하지 않습니다.

## 결과

11종 프로필과 bounded RGB33 reference가 spatial 처리와 분리되어 이후 CPU 최적화, DirectCompute/WARP,
recipe cache가 같은 node 계약을 사용할 수 있습니다. profile 상수와 cube 수학을 별도 파일로 나눠 한
객체가 명부·수학·파이프라인·UI를 모두 소유하지 않게 했습니다.

## 검증 한계

Apple 문서는 cube 순서와 색 공간 계약은 설명하지만 Core Image runtime의 모든 보간·경계 세부를
보장하지 않습니다. 이후 확보한 macOS opaque 4×3 golden에서 최대 절대 오차 `0.0018888685`의 platform
envelope를 고정했지만 fractional alpha와 전체 cube 경계는 아직 포괄하지 않습니다. acutance는 별도
ADR-0018의 standalone component로 구현했으며 source routing과 두 단계 orchestration이 없으므로 전체
`FilmEmulationStage`도 완료된 상태가 아닙니다.

## 공식 근거와 권리

- [Apple CIColorCubeWithColorSpace](https://developer.apple.com/documentation/coreimage/cicolorcubewithcolorspace)
- [Apple colorCubeWithColorSpace filter](https://developer.apple.com/documentation/coreimage/cifilter-swift.class/colorcubewithcolorspace%28%29?language=objc)
- [Apple CIUnsharpMask](https://developer.apple.com/documentation/coreimage/ciunsharpmask)
- [Apple CIContext](https://developer.apple.com/documentation/coreimage/cicontext)

필름 이름과 제조사 자료, 가까운 공개 특허 claims의 제한적 비교는
`research/film-emulation-color-sources.md`에 기록합니다. 법률 자문이나 freedom-to-operate 보증은
아닙니다.
