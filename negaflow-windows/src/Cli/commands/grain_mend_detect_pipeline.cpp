#include "grain_mend_detect_pipeline.h"

#include "negaflow/pipeline/develop_export.h"

#include <algorithm>
#include <cstddef>

namespace negaflow::cli {

PipelineDetectSummary run_pipeline_detect(
    const std::filesystem::path& source,
    const negaflow::imaging::GrainMendParameters& parameters,
    const negaflow::imaging::GrainMendRoi& roi) {
    PipelineDetectSummary summary{};

    // 앱과 같은 요청입니다. 검출은 반전·톤·룩 앞에서 끝나므로 그 뒤 항목은 결과를 바꾸지
    // 않지만, 디코드와 기존 recipe 적용은 그대로 지납니다 — 그것이 재려는 것입니다.
    negaflow::pipeline::DevelopExportRequest request{};
    request.source = source;
    request.film_polarity = negaflow::pipeline::FilmPolarity::negative;
    request.base_estimation_mode =
        negaflow::pipeline::NegativeBaseEstimationMode::auto_estimate;
    request.grain_mend = parameters;

    // 크기를 먼저 묻습니다. 앱도 버퍼를 한 번 잡아 두고 다시 씁니다.
    negaflow::pipeline::GrainMendDetectionOutcome sized =
        negaflow::pipeline::develop_detect_grain_mend(request, nullptr, 0U, {}, roi);
    std::vector<std::uint8_t> mask(
        static_cast<std::size_t>(std::max<std::uint64_t>(1U, sized.mask_byte_count)));

    const negaflow::pipeline::GrainMendDetectionOutcome detected =
        negaflow::pipeline::develop_detect_grain_mend(
            request, mask.data(), mask.size(), {}, roi);

    summary.succeeded = detected.outcome.succeeded;
    summary.failure_stage =
        negaflow::pipeline::develop_export_stage_name(detected.outcome.failed_stage);
    summary.failure_name = detected.outcome.failure_name;
    summary.width = detected.width;
    summary.height = detected.height;
    summary.accepted_pixels = detected.accepted_pixels;
    summary.mask_byte_count = detected.mask_byte_count;
    summary.source_width = detected.source_width;
    summary.source_height = detected.source_height;
    summary.roi_x = detected.roi_x;
    summary.roi_y = detected.roi_y;
    summary.roi_width = detected.roi_width;
    summary.roi_height = detected.roi_height;
    summary.automatic_false_positive_risk = detected.automatic_false_positive_risk;
    summary.automatic_candidate_pixel_fraction =
        detected.automatic_candidate_pixel_fraction;
    summary.components = detected.components;
    const std::size_t counted = std::min<std::size_t>(
        mask.size(), static_cast<std::size_t>(detected.mask_byte_count));
    for (std::size_t index = 0U; index < counted; ++index) {
        if (mask[index] != 0U) {
            ++summary.marked_mask_bytes;
        }
    }
    return summary;
}

}  // namespace negaflow::cli
