#pragma once

#include <cstdint>

namespace negaflow::imaging::film_scan_denoise_detail {

// 필름 스캔 잡음 제거 전체가 공유하는 조율값 한 표입니다.

// 어두운 쪽 잡음을 균등하게 보려고 이 지수로 들어 올린 뒤 거릅니다.
inline constexpr float gamma_lift_power = 0.45F;
inline constexpr float inverse_gamma_lift_power = 1.0F / gamma_lift_power;

// 유도 필터의 정칙화 항입니다. 작을수록 경계를 더 살립니다.
inline constexpr float guided_epsilon = 0.001F;

inline constexpr float gaussian_radius = 1.3F;

// 알파를 뺀 세 채널입니다. 거르는 동안 알파는 건드리지 않으므로 들고 다니지 않습니다.
struct Rgb final {
    float red{0.0F};
    float green{0.0F};
    float blue{0.0F};
};

// 필름 종류가 정하는 세기입니다. 컬러 네거티브와 흑백은 잡음의 성질이 달라 같은 세기를
// 쓸 수 없습니다.
struct Profile final {
    float luma_scale;
    float chroma_scale;
    float shadow_boost;
    float highlight_chroma;
    float highlight_luma_protect;
    bool monochrome;
};

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
