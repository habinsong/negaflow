#pragma once

#include "negaflow/imaging/film_base_measurement.h"
#include "negaflow/imaging/manual_negative_developer.h"

#include <array>
#include <optional>

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
    std::optional<FilmBaseMeasurementDiagnostics> diagnostics{};
    // 고른 베이스보다 밝은 필름 화소의 비율입니다. 필름에서 베이스보다 밝은 것은 없으므로
    // 이 값이 크다는 것은 고른 값이 베이스가 아니라는 뜻입니다. 진단이 "왜 어둡게 나왔나" 를
    // 되짚을 수 있어야 해서 남깁니다.
    double brighter_than_base{};
    // 위 비율이 커서 리베이트를 다시 재 값을 바꿨습니다.
    bool rebate_rescued{false};
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
