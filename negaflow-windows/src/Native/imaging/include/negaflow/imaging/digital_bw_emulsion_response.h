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

// 화소마다 같은 값이라 한 번만 계산합니다. GPU 경로가 이것을 상수 버퍼로 올립니다 —
// **다시 구현하지 마십시오.** 두 벌이 되면 조용히 갈라집니다.
//
// macOS `digitalBWFilm` 이 `w`(분광 가중 + 강도) · `c0`(대비·토·숄더·deepen) ·
// `c1`(흑점·백점) 세 `float4` 로 받는 것과 같은 값입니다.
struct DigitalBwEmulsionSetup final {
    float weights[3]{0.2126F, 0.7152F, 0.0722F};
    float contrast{0.0F};
    float toe{0.0F};
    float shoulder{0.0F};
    float deepen{0.0F};
    float black{0.0F};
    float white{1.0F};
    float intensity{0.0F};
    // 프로파일이 없거나 강도가 임계 이하이면 거짓입니다. 그때 CPU 는 원본을 그대로 복사합니다.
    bool active{false};
};

[[nodiscard]] DigitalBwEmulsionSetup prepare_digital_bw_emulsion_response(
    const DigitalBwEmulsionResponseParameters& parameters) noexcept;

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
