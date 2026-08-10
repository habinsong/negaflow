# Working Film Look source routing 구현

## 현재 범위

`chromabase-working-film-look-v4`는 명시적 source 종류와 Film Emulation profile/intensity를 받아 다음
native 경로 하나를 선택합니다.

```text
효과 없음
  -> identity + finite pixel validation

film_scan
  -> identity + finite pixel validation

rendered_digital + 활성 profile
  -> profile kind와 process kind가 다르면 identity
  -> color stock: DigitalHalation → RGB33 Film Emulation 색상
                  → Film Emulation acutance → 0.5배 stock color preset
                  → density-domain DigitalFilmGrain
  -> B&W stock: DigitalHalation → spectral emulsion response
                → Film Emulation acutance → single-channel density grain
```

디지털 순서는 고정 baseline의 실제 활성 `DigitalFilmLook` 그래프이며, 필름 스캔 identity는 macOS
commit `6b51695e747aa5d98531b8abee3c110a2531c0c7`의 correctness fix입니다. 디지털 입력은 네거티브 반전을
건너뛰고 decoded positive working image에서 시작합니다.

## 파일 책임

- `working_film_look.h`: source/route/status, parameter, caller workspace와 결과 계약
- `working_film_look.cpp`: 명시적 route 선택과 source별 fail-closed orchestration
- `film_emulation_registry.*`: 27종 color/motion과 15종 B&W profile kind의 단일 registry
- `digital_bw_film_profile.*`: 고정 B&W spectral/emulsion/material profile
- `digital_bw_emulsion_response.*`: spectral luminance와 toe/shoulder/density 응답
- `digital_bw_film_look.*`: B&W halation→emulsion→acutance→grain orchestration
- `digital_halation.*`: stock 물성과 512픽셀 overlap tile 기반 warm halation
- `digital_film_color_preset.*`: 27종 color/motion stock color preset과 0.5배 적용
- `digital_film_grain.*`: stock grain 물성과 density-domain grain
- `digital_film_physics.*`: 고정 27종 color/motion stock의 활성 material table
- `working_film_look_tests.cpp`: film-scan identity, digital 순서, profile-kind gate와 실패 계약
- `film_look_command_support.h/.cpp`: CLI 이름·강도 parsing과 caller-owned cube/scratch 준비
- `develop_negative_tiff.cpp`: 단계별 픽셀 진단에서 Film Look 결과를 최종 상태로 보고
- `export_developed_image.cpp`: Primary Calibration 뒤 Film Look, 출력 변환 전 실행과 단계 보고
- `verify_developed_tiff_film_look.cmake`: 실제 TIFF identity/활성 산출물과 단계 순서 회귀 검증

색상 cube와 spatial kernel 수학은 기존 `film_emulation_color.*`와
`film_emulation_acutance.*`에 남깁니다. router는 source 정책과 실행 순서만 책임지며 TIFF, catalog,
UI나 출력 게시를 소유하지 않습니다.

## 입력 계약

`WorkingFilmLookParameters`는 다음 값을 받습니다.

- `source_kind`: `film_scan` 또는 `rendered_digital`
- `emulation`: `none` 또는 현재 구현된 고정 42종 profile
- `intensity`: finite `double`; 하위 component와 같이 `[0, 1]` 범위로 clamp
- `grain_override`, `halation_override`: `1e-3` 초과이면 stock 기본 강도 대신 사용하는 `[0, 1]` 값

source 종류는 import/catalog 또는 명시적 recipe 상태에서 와야 합니다. router는 파일명, 확장자,
decoder, 선택한 profile이나 image 통계로 source를 추정하지 않습니다. 알 수 없는 enum과 비유한 intensity는
`invalid_parameter`이며 pixel을 폐기합니다.

## route 표

| source | 유효 변화 | route | 현재 결과 |
|---|---|---|---|
| film scan | 없음 | `identity` | finite 검사 후 bit-exact 성공 |
| rendered digital | 없음 | `identity` | finite 검사 후 bit-exact 성공 |
| film scan | 있음 | `identity` | 유제 응답 중복 없이 finite 검사 후 bit-exact 성공 |
| rendered digital | process와 같은 kind | `digital_film_look` | color 또는 B&W 고정 그래프 성공, 아니면 fail-closed |
| rendered digital | process와 다른 kind | `identity` | 잘못된 유제 종류를 섞지 않고 bit-exact 성공 |

현재 Windows registry는 color/motion stock 27종과 B&W stock 15종, 합계 42종을 지원합니다. motion
picture profile은 color digital process에서 color graph를 사용합니다. profile 선택은
catalog와 JSON에서 보존하지만 실제 film scan은 항상 identity입니다. rendered digital은 color/B&W
process kind와 profile kind가 일치할 때만 룩을 실행하며, 이때만 공통 Texture의 grain/halation을 비웁니다.

macOS `DigitalFilmPhysics`의 gamma·latitude·layer 항목 전체를 Windows 구조로 복제하지 않습니다. 현재
고정 `DigitalFilmLook` 그래프가 실제 소비하는 scatter, halation, radius와 grain material만 이 table에
보존하고, tone/color response는 같은 macOS `FilmEmulationProfile`을 옮긴 RGB33 cube가 담당합니다.

## workspace와 비용

호출자가 `WorkingFilmLookWorkspace`로 다음 자원을 전달합니다.

- color stock: heap에 둔 431,244바이트 `FilmEmulationColorCube`와 `width × 11 × 12`바이트 acutance scratch
- B&W stock: color cube 없이 `width × 11 × 12`바이트 acutance scratch만 사용

cube의 profile과 quantized intensity step이 일치하면 다시 만들지 않습니다. acutance scratch는 높이에
따라 커지지 않습니다. film-scan route는 workspace를 할당하지 않습니다. digital
halation은 full-frame RGB accumulator와 bounded tile scratch를 사용합니다. digital color preset의 원본
RGB 보존 버퍼는 1,048,576 pixel(약 12 MiB)을 목표로 행 단위 타일링하며, 한 행 자체가 목표보다 크면
한 행까지만 허용합니다. Color Mixer→Color Grading→Primary Calibration 순서와 픽셀 수학은 타일 전과
같습니다. 오류 때 `pixels`를 비워 중간 결과 게시를 막습니다.

## 결과 진단

`WorkingFilmLookInfo`는 route, cube build/reuse, 색상·B&W emulsion·acutance·digital
halation/preset/grain 적용 여부, quantized 색상 step, 실제 acutance amount와 필요한 scratch pixel 수를
기록합니다. 구체적인 하위 오류는
`WorkingFilmLookStatus::kernel_failed`일 때 `kernel_status`로 판단하며, 그 밖의 최종 상태는
`WorkingFilmLookStatus`를 사용합니다.

CLI의 `stages.film_look`은 위 값에 algorithm version, 명시적 인수 여부, source/profile/intensity,
workspace byte와 wall/process-CPU 시간을 더합니다. 일반 export는 이 보고를 위해 pixel을 다시 훑지
않습니다.

## CLI와 실제 출력 연결

진단, PNG16과 TIFF16 명령은 기존 인수 뒤에 Film Look 세 값을 모두 받거나 모두 생략합니다.

```powershell
negaflow-cli --develop-negative-tiff <source> <dmin-r> <dmin-g> <dmin-b> <color|bw> [<tone-6-values>] [<film_scan> <film-emulation> <film-look-intensity>]
negaflow-cli --export-developed-tiff16 <source> <destination> <dmin-r> <dmin-g> <dmin-b> <color|bw> [<tone-6-values>] [<film_scan> <film-emulation> <film-look-intensity>]
```

PNG16도 TIFF16과 같은 인수와 orchestration을 사용합니다. Film Look 인수를 생략하면
`film_scan + none + 0.5` identity로 기존 명령 결과를 보존합니다. 명령의 실제 순서는 다음과 같습니다.

```text
decode/scanner color → film scan이면 negative develop, rendered digital이면 positive 유지
  → tone/Primary Calibration
  → explicit Working Film Look → sRGB16 convert/encode/verify/publish
```

`rendered_digital`은 decoded positive working image에서 시작해 Dmin/base state를 사용하지 않습니다.
`film_scan`의 negative polarity만 수동/자동/preset base와 반전을 수행합니다. positive film scan은
base와 반전을 건너뛰되 Film Look identity 정책은 같습니다. 어느 경로도 파일 확장자로 source 종류를
추정하지 않습니다.

## catalog projection 연결 상태

`Negaflow.Catalog.Core`가 persisted frame의 `sourceKind`, explicit `sourceSignalKind`, legacy
`isDigitalSource`, film type/profile/intensity를 `DevelopRouteSnapshot`으로 읽고 씁니다. 따라서 source를
파일 확장자나 import transport로 추측하지 않는 저장 경계와 legacy 강도 호환을 마련했습니다. snapshot은
C ABI parameter로 변환돼 preview/export에 전달됩니다.

## 아직 연결하지 않은 것

- 새 color/motion profile 16종의 macOS Core Image pixel golden과 실제 촬영 TIFF 비교
- cancellation/progress와 workspace cache 수명 관리자
- Local Dodge/Burn 가변 mask의 ABI/catalog projection
- B&W 비기준 radius의 Core Image Gaussian sigma golden, 전체 macOS numeric golden과 shared-seed 없는
  grain의 cross-platform 통계 허용오차
- untagged rendered-digital TIFF의 명시적 색공간 계약
- SIMD/DirectCompute/WARP 및 대형 이미지 benchmark

일반 이미지 SHA-256은 이 경로와 무관하며 기본 `끔` 정책이 유지됩니다.
