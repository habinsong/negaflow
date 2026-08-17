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
// `valid` 는 macOS 가 넘기는 `DefectContrastField.valid` 입니다. 검출이 이미 만들어 둔 것을
// 넘기면 여기서 다시 만들지 않습니다 — 같은 형태학 두 패스를 타일마다 되풀이하지 않으려는
// 것이며, macOS `DefectSpeckDetector.detect(valid:)` 와 같은 계약입니다.
[[nodiscard]] bool merge_micro_speck_mask(
    const DetectionImage& image,
    double dust_sensitivity,
    std::vector<std::uint8_t>& mask,
    std::size_t& added_pixels,
    negaflow::core::CancelFlag cancel = {},
    const std::vector<std::uint8_t>* valid = nullptr);

}  // namespace negaflow::imaging::grain_mend_detail
