#pragma once

#include "grain_mend_detector.h"

#include "negaflow/core/cancel_flag.h"

#include <cstddef>
#include <cstdint>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {

// Adds the optional micro-speck candidates to an already accepted automatic mask.
// The pass is deliberately additive: an overlap always remains owned by the legacy
// detector, and disabling it leaves the old mask byte-for-byte unchanged. `false`
// means cancellation was requested before the pass reached a complete decision.
[[nodiscard]] bool merge_micro_speck_mask(
    const DetectionImage& image,
    double dust_sensitivity,
    std::vector<std::uint8_t>& mask,
    std::size_t& added_pixels,
    negaflow::core::CancelFlag cancel = {});

}  // namespace negaflow::imaging::grain_mend_detail
