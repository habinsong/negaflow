#pragma once

#include <array>
#include <string_view>

namespace negaflow::fixtures {

inline constexpr std::string_view scalar_foundation_fixture_id = "scalar-foundation-v1";
inline constexpr float negative_inversion_absolute_tolerance = 5.0e-6F;
inline constexpr float negative_inversion_relative_tolerance = 5.0e-6F;
inline constexpr float color_negative_dmin = 0.72F;
inline constexpr float color_negative_dmax_normalized = 1.55F;

struct NegativeInversionCase final {
    std::string_view name;
    float density;
    double expected;
};

inline constexpr std::array<NegativeInversionCase, 3> color_negative_cases{{
    {"base", 0.0F, 0.001},
    {"photometric_mid", 0.60F, 0.18},
    {"dense", 3.0F, 0.882836683855},
}};

}  // namespace negaflow::fixtures
