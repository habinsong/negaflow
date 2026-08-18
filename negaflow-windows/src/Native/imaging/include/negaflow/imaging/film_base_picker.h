#pragma once

#include "negaflow/imaging/manual_negative_developer.h"

#include <array>
#include <cstdint>
#include <optional>

namespace negaflow::imaging {

enum class FilmBasePickStatus : std::uint8_t {
    ok = 0,
    invalid_image,
    // 클릭한 자리가 필름 베이스로 성립하지 않습니다. macOS `isPlausibleBase` 가 nil 을 내는
    // 자리이며, 호출부는 Dmin 을 바꾸지 않고 사용자에게 다시 집으라고 알립니다.
    implausible,
};

struct FilmBasePickResult final {
    FilmBasePickStatus status{FilmBasePickStatus::invalid_image};
    std::array<float, 3> rgb{};
};

// macOS `Chromabase/Film/FilmBasePicker.swift` 의 `sample(in:atUnit:regionFraction:neutralBase:)`
// 를 그대로 옮긴 것입니다. 사용자가 캔버스에서 미노광 필름 베이스를 클릭하면 그 자리의
// Dmin 투과율을 냅니다.
//
//  1차: 클릭 주변 로컬 창(짧은 변 × 0.12)에서 베이스 연결 성분을 찾아 스냅합니다 — 조준
//       오차와 퍼포레이션/백라이트 인접을 무해하게 만듭니다.
//  2차: 성분이 없으면 영역(짧은 변 × `region_fraction`, 최소 3px)의 채널 **중앙값**입니다.
//       평균이 아닌 이유는 엣지 마킹·바코드·먼지가 영역에 걸리면 평균이 끌려가기 때문입니다.
//  둘 다 스캔 전체의 베이스 수준(`candidateLumaPeak`) 대비 타당성 검사를 통과해야 합니다.
//
// `unit_x`/`unit_y` 는 0…1 표시 정규 좌표이며 **y-down**(화면 관례)입니다. `WorkingImage` 도
// y-down 이므로 macOS 의 y-up 뒤집기는 하지 않습니다.
[[nodiscard]] FilmBasePickResult sample_film_base(
    const WorkingImage& image,
    double unit_x,
    double unit_y,
    NegativeFilmType film_type,
    double region_fraction = 0.01) noexcept;

[[nodiscard]] const char* film_base_pick_status_name(FilmBasePickStatus status) noexcept;

}  // namespace negaflow::imaging
