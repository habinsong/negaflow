#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/film_emulation_color.h"

namespace negaflow::imaging {

inline constexpr char digital_bw_emulsion_response_algorithm_version[] =
    "chromabase-digital-bw-emulsion-response-v1";

struct DigitalBwEmulsionResponseParameters final {
    FilmEmulation emulation{FilmEmulation::none};
    double intensity{0.0};
};

[[nodiscard]] bool valid_digital_bw_emulsion_response_parameters(
    const DigitalBwEmulsionResponseParameters& parameters) noexcept;
[[nodiscard]] bool has_digital_bw_emulsion_response_change(
    const DigitalBwEmulsionResponseParameters& parameters) noexcept;

// Input/output is extended-linear sRGB. Spectral RGB-to-gray conversion is
// linear-light; the characteristic curve is evaluated in sRGB encoding, then
// converted back to linear light. Alpha is preserved exactly. Input and output
// may alias exactly.
[[nodiscard]] negaflow::core::KernelStatus
apply_digital_bw_emulsion_response(
    negaflow::core::ConstImageView input,
    negaflow::core::ImageView output,
    const DigitalBwEmulsionResponseParameters& parameters) noexcept;

}  // namespace negaflow::imaging
