#pragma once

#include "defect_component_repair_detail.h"

#include <array>
#include <cstdint>
#include <optional>
#include <vector>

namespace negaflow::imaging::defect_component_repair_detail {

// 걸어갈 방향 하나입니다.
struct Direction final {
    int dx{0};
    int dy{0};
};

// 손상되지 않은 자리에서 읽은 표본입니다. 거리와 좌표를 함께 들고 있어야 능선 점수를
// 매길 수 있습니다.
struct ClearSample final {
    float red{0.0F};
    float green{0.0F};
    float blue{0.0F};
    int distance{0};
    int x{0};
    int y{0};
};

// 채워 넣을 색입니다. 알파는 건드리지 않으므로 세 채널만 둡니다.
struct FillColor final {
    float red{0.0F};
    float green{0.0F};
    float blue{0.0F};
};

// 보통 굵기의 결함이 보는 네 방향입니다.
inline constexpr std::array<Direction, 4U> standard_directions{{
    {1, 0},
    {0, 1},
    {1, 1},
    {1, -1},
}};

// 가는 결함은 대각을 더 잘게 봐야 구조선을 놓치지 않습니다.
inline constexpr std::array<Direction, 8U> thin_directions{{
    {1, 0},
    {0, 1},
    {1, 1},
    {1, -1},
    {2, 1},
    {1, 2},
    {2, -1},
    {1, -2},
}};

[[nodiscard]] float luma(FillColor color) noexcept;

// 한 방향으로 걸으며 처음 만나는 성한 화소를 냅니다. 가장자리를 넘으면 답하지 않습니다.
[[nodiscard]] std::optional<ClearSample> nearest_clear(
    const std::vector<negaflow::core::Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    int width,
    int height,
    int x,
    int y,
    int dx,
    int dy,
    int maximum_step) noexcept;

// 끝점이 구조선(모서리·경계) 위에 있는지의 세기입니다. 진행 방향의 수직으로 세 걸음까지
// 훑어 색이 얼마나 갈리는지 봅니다 - 갈릴수록 구조선입니다.
[[nodiscard]] float ridge_support(
    const std::vector<negaflow::core::Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    int width,
    int height,
    ClearSample endpoint,
    Direction direction) noexcept;

// 획이 가로지르는 각도와 어긋난 방향에 매기는 벌점입니다.
[[nodiscard]] float cross_penalty(
    Direction direction,
    std::optional<double> cross_angle) noexcept;

}  // namespace negaflow::imaging::defect_component_repair_detail
