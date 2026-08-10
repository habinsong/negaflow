#pragma once

#include "negaflow/imaging/manual_negative_developer.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <cstdint>

namespace negaflow::imaging {

inline constexpr char bw_toning_algorithm_version[] =
    "chromabase-bw-toning-cpu-v1";

enum class BwToningMode : std::uint8_t {
    none = 0,
    selenium,
    sepia,
};

struct BwToningParameters final {
    BwToningMode mode{BwToningMode::none};
    double shadow_hue{285.0};
    double highlight_hue{34.0};
    double strength{0.0};
};

enum class BwToningStatus : std::uint8_t {
    ok = 0,
    invalid_parameter,
    invalid_image,
};

struct BwToningInfo final {
    bool neutralized{false};
    bool toned{false};
};

struct BwToningResult final {
    BwToningStatus status{BwToningStatus::invalid_parameter};
    BwToningInfo info{};
    WorkingImage image{};
};

[[nodiscard]] bool valid_bw_toning_parameters(
    const BwToningParameters& parameters) noexcept;

// Matches the fixed macOS post-pipeline boundary: color film is an exact no-op;
// B&W is first neutralized with Rec.709 coefficients and then optionally toned.
[[nodiscard]] BwToningResult apply_bw_toning(
    WorkingImage image,
    NegativeFilmType film_type,
    const BwToningParameters& parameters) noexcept;

[[nodiscard]] const char* bw_toning_status_name(BwToningStatus status) noexcept;

}  // namespace negaflow::imaging
