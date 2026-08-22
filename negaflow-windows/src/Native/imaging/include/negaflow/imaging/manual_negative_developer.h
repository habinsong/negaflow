#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/muted_scene_vibrance.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <array>
#include <cstdint>

namespace negaflow::imaging {

enum class NegativeFilmType : std::uint8_t {
    color = 0,
    black_and_white,
};

enum class ManualNegativeDevelopStatus : std::uint8_t {
    ok = 0,
    invalid_parameter,
    kernel_failed,
};

// The range the developer clamps a manual film base into. Declared here rather than kept
// inside the .cpp so the C ABI can report it: a UI that duplicates the numbers offers the
// user a value the engine will quietly move, which is worse than refusing it.
inline constexpr float minimum_manual_dmin = 1.0e-3F;
inline constexpr float maximum_manual_dmin = 1.0F;

struct ManualNegativeDevelopParameters final {
    std::array<float, 3> dmin;
    NegativeFilmType film_type{NegativeFilmType::color};
    // Film base mode keeps the scene-derived overall density scale while anchoring
    // the channel ratio to the selected stock's Dmax curve.
    bool use_preset_response{false};
    std::array<float, 3> preset_dmax_normalized{};
};

struct ManualNegativeDevelopInfo final {
    std::array<float, 3> applied_dmin{};
    std::array<float, 3> dmax_normalized{};
    // macOS DevelopDebugMetrics.blackInput - 장면 어두운 부분(p90 투과율)입니다.
    // 반전 수식에 들어가지 않는 지표 전용 값이며, 개발자 디버그 화면이 읽습니다.
    std::array<float, 3> black_input{};
    MutedSceneVibranceInfo muted_scene_vibrance{};
    negaflow::core::KernelStatus kernel_status{
        negaflow::core::KernelStatus::invalid_argument};
};

struct ManualNegativeDevelopResult final {
    ManualNegativeDevelopStatus status{ManualNegativeDevelopStatus::invalid_parameter};
    ManualNegativeDevelopInfo info{};
    WorkingImage image{};
};

// Deterministic manual path aligned with the macOS scene-range calculation:
// - Dmin is clamped to [1e-3, 1] per channel;
// - a sufficiently large source uses its robust scene density range; tiny or malformed
//   sources retain the selected fixed print response normal range;
// - non-preset color output receives the macOS muted-scene vibrance gate;
// - the owned WorkingImage is transformed in place, avoiding a second full-frame buffer.
[[nodiscard]] ManualNegativeDevelopResult develop_manual_negative(
    WorkingImage image,
    const ManualNegativeDevelopParameters& parameters) noexcept;

[[nodiscard]] const char* manual_negative_develop_status_name(
    ManualNegativeDevelopStatus status) noexcept;
[[nodiscard]] const char* negative_film_type_name(NegativeFilmType film_type) noexcept;

}  // namespace negaflow::imaging
