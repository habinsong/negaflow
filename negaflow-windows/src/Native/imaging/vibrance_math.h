#pragma once

#include "negaflow/imaging/muted_scene_vibrance_table.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace negaflow::imaging::detail {

/// macOS `CIVibrance` 의 실측 사상입니다.
///
/// 이 필터는 화소마다 **정확히 아핀**입니다 — 맥이 렌더한 격자에서 세 채널을 `α·in + β` 로
/// 맞춘 잔차가 33³ 에서 1.2e-5, 65³ 274,625 점에서 6.3e-6 이었습니다(float32 반올림 수준).
/// 그 앵커는 산술 평균이며, Rec.709 휘도가 아닙니다(휘도로 풀면 최대 0.38 어긋납니다).
/// 그래서 화소마다 필요한 것은 스칼라 하나뿐입니다.
///
///   out = A + (in − A) · f,   A = (R+G+B)/3,   f = 1 + amount · g
///
/// `g` 는 채도·크로마·명도 어느 하나의 함수도 아니고 색상까지 얽혀 있어(구간 내 퍼짐이
/// 0.122 → 0.033 으로 색상을 넣어야 줄어듭니다) 수식으로 되짚지 않습니다. 잰 값을 그대로
/// 표에서 읽습니다. 이 조사에서 방향만 보고 세운 가설 여덟 개가 전부 측정에서 떨어졌습니다.
///
/// 이 표는 ColorModel 이 쓰는 −0.80…+0.80 전 범위와 scanner-profile의 작은 양수까지
/// 덮습니다. muted-scene 단계는 그 안의 0…0.50만 씁니다
/// (`min(0.5, max(0, (0.24 − meanSat) × 3))`).
[[nodiscard]] inline float measured_vibrance_scale(
    const float red,
    const float green,
    const float blue,
    const float amount) noexcept {
    constexpr std::uint32_t side = vibrance_table_side;
    constexpr std::uint32_t last = side - 1U;
    constexpr std::size_t plane_stride =
        static_cast<std::size_t>(side) * side * side;

    const auto axis = [](const float value, std::uint32_t& index) noexcept {
        const float scaled = std::clamp(value, 0.0F, 1.0F) * static_cast<float>(last);
        const float floored = std::floor(scaled);
        index = std::min(static_cast<std::uint32_t>(floored), last - 1U);
        return scaled - static_cast<float>(index);
    };
    std::uint32_t r0 = 0U;
    std::uint32_t g0 = 0U;
    std::uint32_t b0 = 0U;
    const float fr = axis(red, r0);
    const float fg = axis(green, g0);
    const float fb = axis(blue, b0);

    // amount 판 두 장을 고른다. −0.05보다 낮은 쪽은 측정상 같은 음수 slope를 쓰고,
    // 나머지 표 밖은 양끝 slope를 쓴다. amount 자체는 그대로 곱하므로 0은 정확한 항등이다.
    std::uint32_t low = 0U;
    while (low + 2U < vibrance_table_plane_count &&
           amount > vibrance_table_amounts[low + 1U]) {
        ++low;
    }
    const float span =
        vibrance_table_amounts[low + 1U] - vibrance_table_amounts[low];
    const float blend = span > 0.0F
        ? std::clamp((amount - vibrance_table_amounts[low]) / span, 0.0F, 1.0F)
        : 0.0F;

    const auto sample = [&](const std::uint32_t plane,
                            const std::uint32_t dr,
                            const std::uint32_t dg,
                            const std::uint32_t db) noexcept {
        const std::size_t offset =
            (static_cast<std::size_t>(plane) * plane_stride) +
            (static_cast<std::size_t>(r0 + dr) * side * side) +
            (static_cast<std::size_t>(g0 + dg) * side) + (b0 + db);
        return static_cast<float>(vibrance_table_g[offset]);
    };

    float total = 0.0F;
    for (std::uint32_t dr = 0U; dr < 2U; ++dr) {
        const float wr = dr == 1U ? fr : 1.0F - fr;
        for (std::uint32_t dg = 0U; dg < 2U; ++dg) {
            const float wg = dg == 1U ? fg : 1.0F - fg;
            for (std::uint32_t db = 0U; db < 2U; ++db) {
                const float wb = db == 1U ? fb : 1.0F - fb;
                const float corner = sample(low, dr, dg, db) +
                    ((sample(low + 1U, dr, dg, db) - sample(low, dr, dg, db)) * blend);
                total += wr * wg * wb * corner;
            }
        }
    }
    return 1.0F + (amount * total * vibrance_table_quantum);
}

/// 잰 사상을 쓰는 쪽. muted-scene 단계 전용입니다.
inline void apply_measured_vibrance_to_channels(
    float& red,
    float& green,
    float& blue,
    const float amount) noexcept {
    const float scale = measured_vibrance_scale(red, green, blue, amount);
    const float anchor = (red + green + blue) / 3.0F;
    red = anchor + ((red - anchor) * scale);
    green = anchor + ((green - anchor) * scale);
    blue = anchor + ((blue - anchor) * scale);
}

/// ColorModel 의 vibrance 슬라이더도 같은 실측 CIVibrance 사상을 씁니다.
inline void apply_vibrance_to_channels(
    float& red,
    float& green,
    float& blue,
    const float amount) noexcept {
    apply_measured_vibrance_to_channels(red, green, blue, amount);
}

}  // namespace negaflow::imaging::detail
