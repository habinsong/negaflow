# Film Look source routing 공식 근거와 권리 조사

기준일: 2026-08-09

## 저장소 기준 구현

같은 Apache-2.0 저장소의 다음 source와 Windows 설계 문서를 읽어 실행 순서와 source 불변식을
옮겼습니다.

- `Sources/Chromabase/Engine/ChromabaseEngine+PostPipeline.swift`
- `Sources/Chromabase/Digital/DigitalFilmLook.swift`
- `Sources/Chromabase/Digital/DigitalHalation.swift`
- `Sources/Chromabase/Digital/DigitalFilmPhysics.swift`
- `Sources/Chromabase/Digital/DigitalFilmColorPresetStage.swift`
- `Sources/Chromabase/Digital/DigitalFilmColorPreset.swift`
- `Sources/Chromabase/Digital/DigitalFilmGrain.swift`
- `Sources/Chromabase/Models/DevelopParameters.swift`
- `windows_docs/01-render-engine/pipeline-shape.md`
- `windows_docs/15-digital-film/virtual-development.md`
- `windows_docs/99-plan/migration-roadmap.md`

확인한 제품 계약은 다음과 같습니다.

1. 공통 post-pipeline은 point curve→Color Mixer→Color Grading→Primary Calibration 뒤 source를 나눕니다.
2. 필름 스캔은 `FilmEmulationStage` 색상 뒤 `CIUnsharpMask`를 사용합니다.
3. 디지털 입력은 halation→Film Emulation color→digital color→grain의 별도 완전한 그래프입니다.
4. source 종류는 명시적 상태이며 decoder나 profile에서 추정하지 않습니다.

Windows 구현은 고정 baseline의 1~4 route와 순서, 11종 stock 물성, halation 합성, stock color preset
계수와 density grain 반응을 native C++로 옮겼습니다. Apple framework code, 사진, LUT, ICC profile이나
제3자 코드를 포함하지 않았습니다. `windows_docs/15-digital-film/virtual-development.md`의 더 큰
virtual-development 설계는 고정 baseline의 현재 활성 그래프와 다르므로 이번 제품 계약으로 사용하지
않았습니다.

## 공식 기술 근거

- [Apple: Processing an Image Using Built-in Filters](https://developer.apple.com/documentation/coreimage/processing-an-image-using-built-in-filters)는
  Core Image filter를 연결하고 최종 render 때 평가하는 공개 처리 모델을 설명합니다. Windows에서는
  macOS source에 기록된 filter 순서를 명시적 orchestration으로 보존합니다.
- [Apple: CIImage cropped(to:)](https://developer.apple.com/documentation/coreimage/ciimage/cropped%28to%3A%29)는
  image extent를 제한하는 API 경계를 제공합니다. 이는 macOS stage가 unsharp 결과를 입력 extent로
  되돌리는 동작을 읽는 근거이며, Windows bounded kernel의 자체 경계 계약과 같은 구현이라는 뜻은
  아닙니다.
- [C++ Core Guidelines R.3](https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines#Rr-ptr)는 raw pointer가
  기본적으로 non-owning임을 명시합니다. public workspace pointer는 caller-owned cube/scratch를 빌리지
  소유권을 이전하지 않습니다.
- [C++ Core Guidelines R.5](https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines#Rr-scoped)는 scoped
  object를 우선하라는 지침입니다. router는 전역 cache를 만들지 않고 호출자가 수명을 관리하게 합니다.

## CLI·통합 검증 공식 근거

- [Microsoft: Using `wmain`](https://learn.microsoft.com/en-us/cpp/c-language/using-wmain?view=msvc-170)은
  Unicode 모델에서 `wmain(int, wchar_t**)`로 wide-character argument를 받는 계약을 설명합니다. 기존
  CLI 진입점을 유지하고 source/profile 이름을 `std::wstring_view`로 해석합니다.
- [Microsoft: `<charconv>` functions](https://learn.microsoft.com/en-us/cpp/standard-library/charconv-functions?view=msvc-170)은
  `from_chars`가 locale 비의존·무할당·비예외 방식이며 반환 pointer와 error code로 부분 parsing을
  판정한다고 설명합니다. intensity는 고정 stack ASCII buffer에서 변환하고 입력 전체 소비와 finite를
  모두 확인합니다.
- [CMake: `add_test`](https://cmake.org/cmake/help/latest/command/add_test.html)와
  [CMake: `execute_process`](https://cmake.org/cmake/help/latest/command/execute_process.html)는 build target
  위치를 넘긴 실제 command test와 configure script 내부 process 결과 수집 계약을 제공합니다. 통합
  검증은 저장소 TIFF를 identity/활성 Film Look으로 각각 게시하고, 보고 단계 순서와 서로 다른 artifact,
  I/O 전 digital-source 거부를 확인한 뒤 test output만 삭제합니다.

source signal/process 구분에 따라 `film_scan`만 Dmin/base와 네거티브 반전을 수행하고,
`rendered_digital`은 decoded positive working image에서 시작합니다. 어느 쪽도 profile 없음으로 조용히
고치거나 파일명·decoder에서 source 종류를 추정하지 않습니다.

## 제한형 공개 특허 검색

- [US7034862B1](https://patents.google.com/patent/US7034862B1/en)은 전자적으로 촬영한 scene exposure를
  film density 기준 LUT/matrix로 변환하는 film tonescale/color emulation을 다룹니다. Google Patents에는
  `Expired - Fee Related`, 2023-02-25 만료로 표시됩니다. 현재 route는 scene exposure 변환이나 해당
  LUT/matrix를 구현하지 않습니다.
- [DE60222486T2](https://patents.google.com/patent/DE60222486T2/en)은 digital cinema image processing과
  film emulation을 다룹니다. Google Patents에는 `Expired - Lifetime`, 예상 만료 2022-02-19로 표시됩니다.
  현재 변경은 source enum과 완전한 graph 선택 경계뿐입니다.

Google Patents의 상태·예상 만료 표시는 법률 결론이 아닙니다. 이 검색은 가까운 공개 제목과 claims를
무심코 복제하지 않기 위한 제한형 engineering screen이며, 관할별 유효성 판단이나 freedom-to-operate
보증이 아닙니다.

## 라이선스·저작권 결론

- route 순서, profile 의미와 디지털 material 수학은 동일 Apache-2.0 저장소의 고정 제품 source를 기준으로
  native C++로 이식했습니다.
- Apple 문서는 공개 API 의미 확인에만 사용했고 sample code를 복사하지 않았습니다.
- 특허 문서는 회피 경계 확인에만 사용했고 code, 표, figure나 청구항 수식을 구현 자산으로 복사하지
  않았습니다.
- 새 runtime dependency와 외부 binary/data payload는 추가하지 않았습니다.
