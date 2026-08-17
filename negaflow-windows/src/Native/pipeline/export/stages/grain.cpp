#include "grain.h"

#include "export/support/outcome.h"

#include "negaflow/core/cancel_flag.h"
#include "negaflow/core/pixel.h"

#include <cstring>
#include <utility>

namespace negaflow::pipeline::develop_export_detail {

std::optional<DevelopExportOutcome> apply_grain_stage(
    const DevelopExportRequest& request,
    const DevelopRunControl& control,
    const DetectTarget* const detect,
    RunTracker& tracker,
    negaflow::imaging::WorkingImage image,
    GrainStageOutput& out) noexcept {
    tracker.begin(
        DevelopExportStage::grain_mend,
        cost_of(
            grain_mend_cost,
            request.grain_mend.strength >
                negaflow::imaging::grain_mend_identity_threshold));
    if (detect != nullptr) {
        // 검토 도구는 수리 결과가 아니라 판정을 원합니다. 호출측이 cleaned raw
        // (반전 전 스캔)를 넘깁니다 — macOS `detectComponents(in: cleanedRaw)`.
        const auto detected = negaflow::imaging::detect_grain_mend(
            image,
            request.grain_mend,
            detect->roi,
            negaflow::core::CancelFlag{control.cancel_flag});
        if (detected.status == negaflow::imaging::GrainMendStatus::cancelled) {
            return cancelled_outcome(DevelopExportStage::grain_mend);
        }
        if (detected.status != negaflow::imaging::GrainMendStatus::ok) {
            return fail(
                DevelopExportStage::grain_mend,
                negaflow::imaging::grain_mend_status_name(detected.status));
        }
        if (detect->result != nullptr) {
            detect->result->width = detected.width;
            detect->result->height = detected.height;
            detect->result->accepted_pixels = detected.accepted_pixels;
            detect->result->mask_byte_count = detected.mask.size();
            detect->result->source_width = image.width;
            detect->result->source_height = image.height;
            detect->result->roi_x = detected.roi_x;
            detect->result->roi_y = detected.roi_y;
            detect->result->roi_width = detected.roi_width;
            detect->result->roi_height = detected.roi_height;
            detect->result->automatic_false_positive_risk =
                detected.automatic_false_positive_risk;
            detect->result->automatic_candidate_pixel_fraction =
                detected.automatic_candidate_pixel_fraction;
            detect->result->components = std::move(detected.components);
        }
        // 크기만 묻는 호출(mask 가 null)도 실패가 아니라 정상 결과입니다.
        if (detect->mask != nullptr) {
            if (detect->capacity_bytes < detected.mask.size()) {
                return fail(
                    DevelopExportStage::grain_mend, "mask_buffer_too_small");
            }
            std::memcpy(detect->mask, detected.mask.data(), detected.mask.size());
        }
        DevelopExportOutcome detected_outcome{};
        detected_outcome.succeeded = true;
        detected_outcome.failure_name = "ok";
        detected_outcome.image_width = detected.width;
        detected_outcome.image_height = detected.height;
        detected_outcome.grain_mend_candidate_pixels = detected.accepted_pixels;
        tracker.finish();
        tracker.complete();
        out.detect_complete = true;
        out.detect_outcome = detected_outcome;
        return std::nullopt;
    }

    // The one stage long enough that a stage-boundary check is not good enough. It gets
    // the caller's latch directly and stops between its own internal passes.
    auto grain_mend = negaflow::imaging::apply_grain_mend(
        std::move(image),
        request.grain_mend,
        negaflow::core::CancelFlag{control.cancel_flag});
    if (grain_mend.status == negaflow::imaging::GrainMendStatus::cancelled) {
        return cancelled_outcome(DevelopExportStage::grain_mend);
    }
    if (grain_mend.status != negaflow::imaging::GrainMendStatus::ok) {
        if (grain_mend.status ==
            negaflow::imaging::GrainMendStatus::kernel_failed) {
            return fail(
                DevelopExportStage::grain_mend,
                negaflow::core::kernel_status_name(
                    grain_mend.info.kernel_status));
        }
        return fail(
            DevelopExportStage::grain_mend,
            negaflow::imaging::grain_mend_status_name(grain_mend.status));
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::grain_mend);
    }
    out.applied = std::move(grain_mend);
    return std::nullopt;
}

}  // namespace negaflow::pipeline::develop_export_detail
