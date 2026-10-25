#pragma once

#include "negaflow/imaging/muted_scene_vibrance.h"
#include "negaflow/imaging/muted_scene_vibrance_table.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace negaflow::imaging::detail {

/// 크로스플랫폼 Vibrance 3D 룩업 테이블 사상입니다.
///
/// 화소마다 산술 평균 `A = (R+G+B)/3` 을 기준으로 채널 편차를 스케일합니다:
///
///   out = A + (in − A) · f,   A = (R+G+B)/3,   f = 1 + amount · g
///
/// `g` 는 33³ × 6장 룩업 테이블에서 삼선형 보간으로 읽습니다.
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

    // amount 판 두 장의 선택은 **공개 함수 한 곳**에 있습니다 — GPU 판도 같은 것을
    // 씁니다. 두 곳에서 고르면 판이 어긋나는 순간 색이 통째로 달라집니다.
    const VibrancePlaneSelection selection = select_vibrance_planes(amount);
    const std::uint32_t low = selection.low;
    const float blend = selection.blend;

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

/// ColorModel 의 vibrance 슬라이더도 같은 크로스플랫폼 Vibrance 3D 룩업 테이블을 씁니다.
inline void apply_vibrance_to_channels(
    float& red,
    float& green,
    float& blue,
    const float amount) noexcept {
    apply_measured_vibrance_to_channels(red, green, blue, amount);
}

}  // namespace negaflow::imaging::detail
