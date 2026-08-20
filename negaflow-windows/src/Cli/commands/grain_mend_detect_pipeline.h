#pragma once

#include "negaflow/imaging/grain_mend.h"

#include <cstdint>
#include <filesystem>
#include <vector>

namespace negaflow::cli {

// 앱이 실제로 지나는 길로 검출을 한 번 돌립니다.
//
// 왜 두 길을 다 재는가 — `--grain-mend-detect` 는 `imaging::detect_grain_mend` 를 바로
// 부릅니다. 앱은 그렇게 부르지 않고 `pipeline::develop_detect_grain_mend` 로 들어가
// 디코드·기존 recipe 적용을 지난 뒤에 같은 검출에 닿습니다. 둘의 결과가 다르면 원인은
// 검출기가 아니라 그 앞의 두 단계에 있습니다 — 화면 없이 그것을 가릅니다.
struct PipelineDetectSummary final {
    bool succeeded{false};
    const char* failure_stage{"none"};
    const char* failure_name{"ok"};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::uint64_t accepted_pixels{0U};
    std::uint64_t mask_byte_count{0U};
    std::uint32_t source_width{0U};
    std::uint32_t source_height{0U};
    std::uint32_t roi_x{0U};
    std::uint32_t roi_y{0U};
    std::uint32_t roi_width{0U};
    std::uint32_t roi_height{0U};
    bool automatic_false_positive_risk{false};
    double automatic_candidate_pixel_fraction{0.0};
    std::uint64_t marked_mask_bytes{0U};
    std::vector<negaflow::imaging::grain_mend_detail::ClassifiedComponent> components{};
};

[[nodiscard]] PipelineDetectSummary run_pipeline_detect(
    const std::filesystem::path& source,
    const negaflow::imaging::GrainMendParameters& parameters,
    const negaflow::imaging::GrainMendRoi& roi);

}  // namespace negaflow::cli
