# Working Film Look source routing 구현

## 현재 범위

`chromabase-working-film-look-v1`은 명시적 source 종류와 Film Emulation profile/intensity를 받아 다음
native 경로 하나를 선택합니다.

```text
효과 없음
  -> identity + finite pixel validation

film_scan + 활성 profile
  -> RGB33 Film Emulation 색상
  -> Film Emulation acutance

rendered_digital + 활성 profile
  -> digital_film_look
  -> 현재 unsupported_route, pixel 폐기
```

macOS의 디지털 경로는 halation, 별도 digital color, grain을 포함합니다. Windows는 이 전체 그래프가
준비되기 전까지 필름 스캔의 색상·acutance 부분집합을 디지털 입력에 적용하지 않습니다.

## 파일 책임

- `working_film_look.h`: source/route/status, parameter, caller workspace와 결과 계약
- `working_film_look.cpp`: 명시적 route 선택, 색상→acutance 순서와 fail-closed orchestration
- `working_film_look_tests.cpp`: route, 순서, cube 재사용, 경계 강도와 실패 계약

색상 cube와 spatial kernel 수학은 기존 `film_emulation_color.*`와
`film_emulation_acutance.*`에 남깁니다. router는 source 정책과 실행 순서만 책임지며 TIFF, catalog,
UI나 출력 게시를 소유하지 않습니다.

## 입력 계약

`WorkingFilmLookParameters`는 다음 값을 받습니다.

- `source_kind`: `film_scan` 또는 `rendered_digital`
- `emulation`: `none` 또는 고정 11종 profile
- `intensity`: finite `double`; 하위 component와 같이 `[0, 1]` 범위로 clamp

source 종류는 import/catalog 또는 명시적 recipe 상태에서 와야 합니다. router는 파일명, 확장자,
decoder, 선택한 profile이나 image 통계로 source를 추정하지 않습니다. 알 수 없는 enum과 비유한 intensity는
`invalid_parameter`이며 pixel을 폐기합니다.

## route 표

| source | 유효 변화 | route | 현재 결과 |
|---|---|---|---|
| film scan | 없음 | `identity` | finite 검사 후 bit-exact 성공 |
| rendered digital | 없음 | `identity` | finite 검사 후 bit-exact 성공 |
| film scan | 있음 | `film_scan_emulation` | 색상→acutance 성공 또는 fail-closed |
| rendered digital | 있음 | `digital_film_look` | `unsupported_route`, pixel 폐기 |

색상 cube는 5% intensity step을 사용하지만 acutance는 원래 사용자 intensity를 사용합니다. 따라서 첫 색상
step보다 낮은 `0.024`에서도 색상은 identity이고 spatial acutance만 활성일 수 있습니다. router는 두
component의 `has_*_change`를 각각 확인해 이 경계를 보존합니다.

## workspace와 비용

호출자가 `WorkingFilmLookWorkspace`로 다음 자원을 전달합니다.

- 활성 색상 단계: heap에 둔 431,244바이트 `FilmEmulationColorCube`
- 활성 acutance: `width × 11 × 12`바이트 scratch

cube의 profile과 quantized intensity step이 일치하면 다시 만들지 않습니다. acutance scratch는 높이에
따라 커지지 않습니다. route 함수는 별도 full-frame image를 할당하지 않고 전달받은 `WorkingImage`를
제자리 갱신합니다. 오류 때 `pixels`를 비워 중간 결과 게시를 막습니다.

## 결과 진단

`WorkingFilmLookInfo`는 route, cube build/reuse, 색상·acutance 적용 여부, quantized 색상 step, 실제
acutance amount와 필요한 scratch pixel 수를 기록합니다. 구체적인 하위 오류는
`WorkingFilmLookStatus::kernel_failed`일 때 `kernel_status`로 판단하며, 그 밖의 최종 상태는
`WorkingFilmLookStatus`를 사용합니다.

## 아직 연결하지 않은 것

- CLI recipe와 단계 report
- C ABI와 관리 코드/WinUI
- catalog/import source metadata persistence
- cancellation/progress와 workspace cache 수명 관리자
- digital halation·color·grain 전체 그래프
- SIMD/DirectCompute/WARP 및 대형 이미지 benchmark

일반 이미지 SHA-256은 이 경로와 무관하며 기본 `끔` 정책이 유지됩니다.
