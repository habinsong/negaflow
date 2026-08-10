#pragma once

#include "negaflow/core/cancel_flag.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <cstddef>
#include <cstdint>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {

// Full-resolution automatic detection uses non-overlapping cores with a
// detector halo. Candidate kinds stay separate until frame-wide stitching so
// structure-line rejection never drops dust that touches a scratch.
[[nodiscard]] std::vector<std::uint8_t> build_tiled_automatic_mask(
    const WorkingImage& image,
    double dust_sensitivity,
    double scratch_sensitivity,
    double protect_detail,
    std::size_t& accepted_pixels,
    negaflow::core::CancelFlag cancel = {});

}  // namespace negaflow::imaging::grain_mend_detail
