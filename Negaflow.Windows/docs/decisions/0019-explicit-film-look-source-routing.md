# ADR-0019: Film Look은 명시적 source 종류로 완전한 경로를 선택한다

- 상태: 채택
- 날짜: 2026-08-04

## 문제

macOS 후처리는 Primary Calibration 다음에 입력 종류를 나눕니다. 필름 스캔은 RGB33
`FilmEmulationStage` 색상 뒤 `CIUnsharpMask` acutance를 적용하지만, 이미 양화된 디지털 입력은
halation·색상·grain을 포함하는 별도 `DigitalFilmLook` 전체 그래프를 사용합니다.

Windows가 파일 확장자, decoder, 선택한 필름 종류나 pixel 통계로 source 종류를 추정하면 같은 파일이
import 경로에 따라 다른 결과를 낼 수 있습니다. 또한 아직 없는 digital graph를 필름 스캔의 두 단계로
대체하면 일부 효과만 적용된 출력을 완성된 결과처럼 게시하게 됩니다.

## 결정

1. source 종류는 `DevelopSourceKind::film_scan` 또는 `rendered_digital`로 호출자가 명시합니다. native
   router는 경로, decoder, film profile과 pixel 통계로 이를 추정하지 않습니다.
2. 효과가 없는 요청은 source 종류와 무관하게 `identity`이며, pixel 유효성을 검사한 뒤 bit-exact로
   보존합니다.
3. 활성 필름 스캔은 `film_scan_emulation`으로 선택하고 RGB33 색상 cube 다음 bounded acutance를 정확히
   그 순서로 제자리 처리합니다.
4. 활성 디지털 입력은 별도 `digital_film_look`으로 선택합니다. halation·digital color·grain 전체 그래프가
   이식되기 전에는 `unsupported_route`로 실패하며 pixel을 비워 부분 결과 게시를 막습니다.
5. 잘못된 source/profile/intensity, cube 오류나 acutance scratch 오류도 결과 pixel을 비웁니다. 색상 적용
   뒤 공간 kernel이 실패해도 중간 색상 결과는 노출하지 않습니다.
6. `FilmEmulationColorCube`와 폭×11 acutance scratch는 호출자가 소유합니다. 일치하는 cube는 재사용하고,
   router 내부에는 이미지 크기에 비례한 추가 할당이나 전역 mutable cache를 두지 않습니다.
7. route 구현은 `WorkingToneAdjuster`에 합치지 않습니다. 공통 톤 단계와 source별 look은 서로 다른 변경
   이유와 자원 수명을 가지므로 작은 별도 orchestration으로 유지합니다.
8. 이번 경계는 native C++ contract와 unit test까지만 포함합니다. CLI recipe/report, C ABI, WinUI,
   cancellation/progress와 완전한 digital graph는 후속 단계입니다.
9. 일반 이미지 content SHA-256 기본값은 계속 `끔`입니다. 이 route는 이미지 hash를 계산하거나 켜지
   않습니다.

## 결과

필름 스캔은 macOS의 색상→acutance 순서를 한 함수에서 재현할 수 있고, 디지털 입력은 잘못된 부분
그래프로 흘러가지 않습니다. 호출자는 source 계약과 workspace 수명을 명시해야 하지만, route 선택이
재현 가능하고 실패 시 게시 가능한 부분 image가 남지 않습니다.

## 남은 한계

- `DigitalFilmLook`의 halation·digital color·grain은 아직 구현하지 않았습니다.
- CLI와 저장 recipe가 source 종류를 전달하지 않으므로 제품 수직 경로에는 아직 자동 적용되지 않습니다.
- acutance는 scalar reference이며 cancellation/progress, SIMD/GPU와 megapixel benchmark가 없습니다.
- 제한형 공개 특허 검색은 법률 자문이나 freedom-to-operate 보증이 아닙니다.

## 근거

- `Sources/Chromabase/Engine/ChromabaseEngine+PostPipeline.swift`
- `Sources/Chromabase/Digital/DigitalFilmLook.swift`
- `windows_docs/01-render-engine/pipeline-shape.md`
- `windows_docs/15-digital-film/virtual-development.md`
- `windows_docs/99-plan/migration-roadmap.md`
- [Apple: Processing an Image Using Built-in Filters](https://developer.apple.com/documentation/coreimage/processing-an-image-using-built-in-filters)
- [C++ Core Guidelines](https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines)

실행 증거와 권리 검색은 각각 `verification/2026-08-04-film-look-routing.md`와
`research/film-look-routing-sources.md`에 기록합니다.
