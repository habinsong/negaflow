#pragma once

#include "negaflow/imaging/manual_negative_developer.h"

#include <array>

namespace negaflow::imaging {

enum class AutoNegativeBaseStatus : std::uint8_t {
    ok = 0,
    invalid_image,
};

enum class AutoNegativeBaseSource : std::uint8_t {
    connected_component = 0,
    scene_edge,
    fallback,
    continuous_border,
    distributed_mask,
    strip_fallback,
};

[[nodiscard]] inline constexpr bool confident_auto_negative_base_source(
    const AutoNegativeBaseSource source) noexcept {
    return source == AutoNegativeBaseSource::connected_component ||
           source == AutoNegativeBaseSource::continuous_border ||
           source == AutoNegativeBaseSource::distributed_mask;
}

struct AutoNegativeBaseResult final {
    AutoNegativeBaseStatus status{AutoNegativeBaseStatus::invalid_image};
    AutoNegativeBaseSource source{AutoNegativeBaseSource::fallback};
    std::array<float, 3> dmin{};
};

// The deterministic macOS-compatible automatic base resolver. It samples only the
// original linear working image and never invents a manual base; an invalid layout is
// reported to the pipeline instead.
[[nodiscard]] AutoNegativeBaseResult resolve_auto_negative_base(
    const WorkingImage& image,
    NegativeFilmType film_type) noexcept;

[[nodiscard]] const char* auto_negative_base_status_name(
    AutoNegativeBaseStatus status) noexcept;

}  // namespace negaflow::imaging
