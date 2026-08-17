#pragma once

#include "grain_mend_detector.h"

#include "negaflow/core/cancel_flag.h"
#include "negaflow/imaging/grain_mend_classifier.h"

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
// `confidence` 는 채택된 화소에 macOS `Speck.confidence` 를 씁니다. 타일이 프레임으로
// 옮긴 뒤 `merge_micro_specks_into` 가 컴포넌트 평균을 내는 데 씁니다.
[[nodiscard]] bool merge_micro_speck_mask(
    const DetectionImage& image,
    double dust_sensitivity,
    std::vector<std::uint8_t>& mask,
    std::size_t& added_pixels,
    negaflow::core::CancelFlag cancel = {},
    const std::vector<std::uint8_t>* valid = nullptr,
    std::vector<float>* confidence = nullptr);

// macOS `DefectSpeckDetector.merged(into:specks:)`. 기존 라벨과 한 화소라도 겹치면
// 그 입자 전체를 버리고, 겹치지 않으면 classification = microSpeck 컴포넌트를 더하고
// 마스크 화소를 켭니다. 채택 여부는 이미 타일 `detect` 가 끝냈습니다.
void merge_micro_specks_into(
    const std::vector<std::uint8_t>& speck_mask,
    const std::vector<float>& speck_confidence,
    std::uint32_t width,
    std::uint32_t height,
    std::vector<ClassifiedComponent>* components,
    std::vector<std::uint8_t>& mask,
    std::size_t& accepted_pixels,
    std::uint64_t* merged = nullptr,
    std::uint64_t* skipped_overlap = nullptr);

}  // namespace negaflow::imaging::grain_mend_detail
