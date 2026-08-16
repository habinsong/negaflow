#pragma once

#include <cstdint>

namespace negaflow::imaging::detail {

/// 격자 한 변의 표본 수. RGB 각 축이 0…1 을 32 등분한 33 점입니다.
inline constexpr std::uint32_t vibrance_table_side = 33U;
/// 담아 둔 amount 판의 수.
inline constexpr std::uint32_t vibrance_table_plane_count = 3U;
inline constexpr std::uint32_t vibrance_table_entry_count =
    vibrance_table_side * vibrance_table_side * vibrance_table_side *
    vibrance_table_plane_count;

/// 각 판의 amount. 오름차순입니다.
extern const float vibrance_table_amounts[vibrance_table_plane_count];
/// `g` 를 uint16 으로 담을 때 한 눈금의 크기. 실제 값 = 저장값 × 이 값.
extern const float vibrance_table_quantum;
/// `g`. 판 순서로 이어 붙였고, 판 안에서는 R 이 가장 느리고 B 가 가장 빠릅니다.
extern const std::uint16_t vibrance_table_g[vibrance_table_entry_count];

}  // namespace negaflow::imaging::detail
