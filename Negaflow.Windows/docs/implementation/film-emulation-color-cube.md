# Film Emulation RGB33 색상 cube 구현

## 현재 범위

`chromabase-film-emulation-color-v1`은 macOS 필름 스캔 후처리 분기의 Film Emulation 가운데 절차형
색상 cube만 Windows CPU reference로 옮깁니다.

```text
Primary Calibration 결과의 extended-linear sRGB
  → 기존 sRGB transfer로 encode하고 [0, 1] clamp
  → 선택한 11종 profile과 5% 단위 intensity로 만든 RGB33 cube
  → red column / green row / blue plane 삼선형 보간
  → 기존 sRGB transfer로 extended-linear sRGB 복원
  → alpha 보존
```

이 component의 수학은 독립적으로 유지합니다. 별도 `WorkingFilmLook` native route가 macOS
`FilmEmulationStage`와 같이 이 색상 cube 뒤 bounded acutance를 호출하지만, 기존 tone/export CLI
수직 경로는 아직 route를 호출하지 않습니다. 디지털 입력의 별도 `DigitalFilmLook`도 이 component에
포함하지 않습니다.

## 파일 책임

- `film_emulation_color.h`: 공개 profile enum, parameters, 고정 RGB33 cube와 build/apply 계약
- `film_emulation_profiles.h/.cpp`: 11종 고정 profile 데이터와 enum lookup
- `film_emulation_color.cpp`: intensity 양자화, node 생성, sRGB 왕복과 삼선형 sampling
- `film_emulation_color_fixture.h`: 저장소 소유 4×3 입력·Velvia 50 기대값과 11종 node signature
- `film_emulation_color_tests.cpp`: 명부, cube 크기, 수치, identity, alias, 오류 계약
- `scalar_conformance.cpp`: 48개 RGBA 오차와 cube 차원·payload·intensity step 보고

profile 데이터, cube 수학과 test/orchestration을 분리했습니다. 이 파일들은 TIFF, 경로, CLI 인수, UI,
source routing이나 full-frame image 소유권을 갖지 않습니다.

## 프로필과 intensity

| 계열 | profile |
|---|---|
| slide | Ektachrome E100, Provia 100F, Velvia 50 |
| color negative | Portra 160, Portra 400, Portra 800, Ektar 100, UltraMax 400, ColorPlus 200, Fujicolor C200, Pro 400H |

`FilmEmulation::none`은 색상 identity입니다. intensity 기본 구조체 값은 `0.5`이며, 유한한 값만
허용합니다. finite 범위 밖 값은 macOS와 같이 `[0, 1]`로 clamp하고 다음 step을 사용합니다.

```text
step = round(clamp(intensity, 0, 1) × 20)
effectiveIntensity = step / 20
```

C++ 구현은 `std::lround`를 사용하므로 정확히 0.025는 0이 아니라 step 1입니다. 0.024는 step 0,
0.73은 step 15로 양자화되어 실제 색상 강도는 0.75입니다. profile과 step은 cube metadata에 함께
기록하며 다른 값으로 재사용한 오래된 cube는 거부합니다.

## RGB33 node 계약

각 node는 다음 순서로 만들어집니다.

1. 입력 R/G/B에 profile별 channel tone curve를 적용합니다.
2. profile별 3×3 matrix를 적용합니다.
3. 밝기에 따라 shadow/highlight tint를 더합니다.
4. 밝기, chroma와 여섯 hue 기준점의 exposure-saturation을 섞습니다.
5. 결과를 `[0, 1]`로 제한하고 원본 node와 effective intensity만큼 혼합합니다.

node 계산은 double이며 저장 직전에 Float32가 됩니다. `FilmEmulationCubeEntry`는 padding 없는 RGB
12바이트이고 cube는 35,937개 entry, 431,244바이트입니다. 배열 index는 다음과 같습니다.

```text
index = ((blue × 33) + green) × 33 + red
```

apply는 encoded RGB의 각 축에서 인접 두 node를 구해 8개 RGB entry를 한 번씩 읽고 삼선형 보간합니다.
source와 destination은 같아도 됩니다.

## identity·오류·메모리

- `none`, intensity가 효과 임계값 이하이거나 양자화 step 0이면 cube 없이 active pixel만 복사합니다.
- identity는 음수·1 초과 RGB와 alpha를 bit-exact로 보존하고 row padding을 건드리지 않습니다.
- 활성 입력은 sRGB cube domain 때문에 RGB를 `[0, 1]` display reference에 매핑합니다.
- unknown enum, NaN/Inf intensity, 잘못된 stride/capacity, 비유한 pixel을 거부합니다.
- active apply에는 matching ready cube가 필요하며 profile/step이 다르면 거부합니다.
- 35,937개 cube entry가 모두 유한하고 `[0, 1]`인지 pixel loop 전에 확인합니다.
- caller가 cube를 heap에서 한 번 소유합니다. build/apply 내부 allocation과 추가 full-frame buffer는
  0입니다.

cube validation은 apply마다 431,244바이트를 순회합니다. 현재는 안전한 standalone reference를 우선한
선택이며 production route에서 immutable cache와 검증 완료 상태를 설계할 때 중복 scan을 줄일 수 있습니다.

## CLI·UI·파이프라인 경계

현재 CLI report, C ABI와 WinUI에는 Film Emulation profile/intensity가 없습니다. 기존
`WorkingToneAdjuster`의 실행 순서는 Primary Calibration에서 끝나며 이 cube를 자동 호출하지 않습니다.
`chromabase-working-film-look-v1` native route는 명시적 source 종류를 받아 film scan에서만 색상 뒤
acutance를 실행하고 미완성 digital graph는 fail-closed로 거부합니다.
canonical macOS run에서 opaque `CIColorCubeWithColorSpace`와 `CIUnsharpMask` 수치 기준을 확보했습니다.
색상 36개 RGB 값의 최대 절대 오차는 `0.0018888685`, RMSE는 `0.0005653865`였고 test envelope는
`0.0021`로 고정했습니다. 다음 제품 연결은 아래 경계를 먼저 닫습니다.

1. source 종류와 profile/intensity의 recipe serialization 및 CLI report
2. catalog/import source metadata와 WinUI 연결
3. cube/scratch cache 수명, 취소와 CPU/GPU dispatch 계약
4. cube 경계와 fractional-alpha golden 확대

## 남은 제한

- opaque 4×3 fixture는 실제 macOS Core Image render와 비교했지만 모든 cube 경계 동작을 포괄하지
  않습니다.
- fractional alpha는 보존하지만 scanner 수직 경로는 opaque만 허용하므로 실제 제품 경로 검증이
  남아 있습니다.
- acutance가 standalone으로 존재해도 색상과 source route를 묶은 전체 `FilmEmulationStage`는 아직
  아닙니다.
- scalar `pow`와 cube build 비용에 대한 megapixel benchmark, SIMD/GPU 최적화가 없습니다.
- ARM64는 교차 빌드만 했고 실제 ARM64 Windows에서 실행하지 않았습니다.
