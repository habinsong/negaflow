#pragma once

#include "negaflow/imaging/film_scan_denoise.h"

#include <cstdint>

namespace negaflow::imaging::film_scan_denoise_detail {

// 필름 스캔 잡음 제거 전체가 공유하는 조율값 한 표입니다.
//
// ☠️ 값은 **공개 헤더 한 곳**(`negaflow/imaging/film_scan_denoise.h`)에 있습니다. GPU 이식이
//    같은 값을 필요로 해서 그리로 올렸습니다. 여기 있는 것은 짧은 이름 별칭뿐이고,
//    **숫자를 다시 적지 마십시오** — 두 벌이 되면 한쪽만 고쳐도 조용히 갈립니다.
inline constexpr float gamma_lift_power = film_scan_denoise_gamma_lift_power;
inline constexpr float inverse_gamma_lift_power = film_scan_denoise_inverse_gamma_lift_power;
inline constexpr float guided_epsilon = film_scan_denoise_guided_epsilon;
inline constexpr float gaussian_radius = film_scan_denoise_gaussian_radius;

// 알파를 뺀 세 채널입니다. 거르는 동안 알파는 건드리지 않으므로 들고 다니지 않습니다.
struct Rgb final {
    float red{0.0F};
    float green{0.0F};
    float blue{0.0F};
};

// 필름 종류가 정하는 세기입니다. 정의는 공개 헤더의 `FilmScanDenoiseFilmScalars` 하나뿐입니다.
using Profile = FilmScanDenoiseFilmScalars;

// 한 번에 처리할 타일입니다. 주변부(source)를 여유 있게 읽고 core 만 씁니다 - 그래야
// 타일 경계에 이음매가 남지 않습니다.
struct Tile final {
    std::uint32_t source_x{0U};
    std::uint32_t source_y{0U};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::uint32_t core_x{0U};
    std::uint32_t core_y{0U};
    std::uint32_t core_width{0U};
    std::uint32_t core_height{0U};
};

}  // namespace negaflow::imaging::film_scan_denoise_detail
