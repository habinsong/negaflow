#pragma once

#include <array>
#include <cstdint>
#include <vector>

namespace negaflow::color {

// The colour space a published file is encoded in. The develop pipeline always works in
// linear light with sRGB/Rec.709 primaries; this is the last step before quantization.
enum class OutputColorSpace : std::uint8_t {
    srgb = 0,
    display_p3,
    adobe_rgb,
};

// Row-major 3x3, applied to linear RGB.
using ColorMatrix = std::array<float, 9>;

// Linear sRGB primaries into the target's linear primaries. Identity for sRGB.
//
// All three spaces are D65, so no chromatic adaptation happens here - only a change of
// primaries. Adapting to D50 belongs in the profile, not in the pixels.
[[nodiscard]] ColorMatrix linear_srgb_to(OutputColorSpace space) noexcept;

// The target's encoding curve. Display P3 shares the sRGB curve; Adobe RGB is gamma
// 563/256, which is the value the Adobe RGB (1998) specification states.
[[nodiscard]] float encode_output_component(float linear, OutputColorSpace space) noexcept;

// A v2 matrix/TRC ICC profile for the space. Windows ships a usable sRGB profile but not
// Display P3 or Adobe RGB, so the bytes are built here rather than read from the system -
// a file that may not exist cannot be a dependency of an export.
//
// `linear_transfer` is supported for sRGB primaries only and is used by the defect bake TIFF.
// Returns an empty vector if the space is unknown or the requested combination is unsupported.
[[nodiscard]] std::vector<std::uint8_t> build_icc_profile(
    OutputColorSpace space,
    bool linear_transfer = false);

[[nodiscard]] const char* output_color_space_name(OutputColorSpace space) noexcept;

}  // namespace negaflow::color
