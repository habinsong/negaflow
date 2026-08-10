#pragma once

#include "negaflow/core/pixel.h"

#include <cstdint>
#include <string_view>

namespace negaflow::imaging {

enum class ScannerTargetStyle : std::uint8_t {
    noritsu = 0,
    sp3000,
    f135,
    hr,
};

struct ScannerTargetGradeInfo final {
    bool applied{false};
    bool texture_applied{false};
    bool relative_signature_applied{false};
    float scene_anchor_weight{0.0F};
};

// Applies the macOS documented target character and, where provenance permits,
// the matched NORITSU/SP-3000 relative signature in gamma-domain tone and Lab
// color, then the NORITSU-only bounded luminance texture. Positive sources use
// half documented strength and monochrome sources retain only tone and texture.
[[nodiscard]] negaflow::core::KernelStatus apply_scanner_target_grade(
    negaflow::core::ImageView image,
    ScannerTargetStyle target,
    bool monochrome,
    bool positive,
    std::wstring_view scanner_profile_id,
    ScannerTargetGradeInfo& info) noexcept;

}  // namespace negaflow::imaging
