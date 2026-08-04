#pragma once

#include "negaflow/core/pixel.h"

#include <array>

namespace negaflow::core {

struct ColorMatrix3x4 final {
    std::array<float, 12> values;

    [[nodiscard]] static constexpr ColorMatrix3x4 identity() noexcept {
        return ColorMatrix3x4{{
            1.0F, 0.0F, 0.0F, 0.0F,
            0.0F, 1.0F, 0.0F, 0.0F,
            0.0F, 0.0F, 1.0F, 0.0F,
        }};
    }
};

[[nodiscard]] KernelStatus apply_exposure(
    ConstImageView input,
    ImageView output,
    float stops) noexcept;

[[nodiscard]] KernelStatus apply_color_matrix(
    ConstImageView input,
    ImageView output,
    const ColorMatrix3x4& matrix) noexcept;

}  // namespace negaflow::core
