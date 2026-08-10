#pragma once

#include "negaflow/core/pixel.h"

#include <string_view>

namespace negaflow::imaging {

struct ScannerProfileGradeParameters final {
    float gamma{1.0F};
    float contrast{1.0F};
    float saturation{1.0F};
    float vibrance{0.0F};
    float red_gain{1.0F};
    float green_gain{1.0F};
    float blue_gain{1.0F};
    float shadow_point{0.23F};
    float mid_point{0.50F};
    float highlight_point{0.82F};
    float unsharp{0.0F};
};

struct ScannerProfileGradeInfo final {
    bool profile_found{false};
    bool applied{false};
    std::string_view profile_hash{};
};

// The immutable table is compiled from the validated macOS ScannerProfiles v2
// manifest. Unknown IDs are an exact no-op, matching the reference registry's
// optional load semantics.
[[nodiscard]] bool try_get_scanner_profile_grade_parameters(
    std::wstring_view profile_id,
    ScannerProfileGradeParameters& parameters,
    std::string_view& profile_hash) noexcept;

// Applies the reference grade order: gamma, color controls, vibrance,
// highlight-protected film tint, tone curve, bounded unsharp, unit clamp.
[[nodiscard]] negaflow::core::KernelStatus apply_scanner_profile_grade(
    negaflow::core::ImageView image,
    std::wstring_view profile_id,
    ScannerProfileGradeInfo& info) noexcept;

}  // namespace negaflow::imaging
