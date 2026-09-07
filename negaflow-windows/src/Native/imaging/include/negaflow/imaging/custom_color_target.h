#pragma once

#include "negaflow/core/pixel.h"
#include <array>
#include <cstdint>

namespace negaflow::imaging {

inline constexpr std::uint32_t first_custom_color_target = 7U;
inline constexpr std::uint32_t last_custom_color_target = 24U;
inline constexpr const char* custom_color_target_revision = "custom-3";

struct CustomColorTargetProfile final {
    std::array<double, 10> tone{};
    std::array<double, 10> slopes{};
    std::array<double, 8> gain{}, density{}, hue_shadow{}, hue_mid{}, hue_high{}, highlight_hue{};
    std::array<double, 4> controls{}; // q, A, B, M
    std::array<double, 2> tint_shadow{}, tint_mid{}, tint_high{};
};

using CustomColorTriple = std::array<double, 3>;

[[nodiscard]] const CustomColorTargetProfile* custom_color_target_profile(std::uint32_t target) noexcept;
[[nodiscard]] CustomColorTriple custom_target_linear_to_lab(CustomColorTriple rgb) noexcept;
[[nodiscard]] CustomColorTriple custom_target_lab_to_linear(CustomColorTriple lab) noexcept;
[[nodiscard]] CustomColorTriple evaluate_custom_color_target(
    CustomColorTriple lab, const CustomColorTargetProfile& profile) noexcept;
[[nodiscard]] core::KernelStatus apply_custom_color_target(
    core::ConstImageView input, core::ImageView output, std::uint32_t target) noexcept;

} // namespace negaflow::imaging
