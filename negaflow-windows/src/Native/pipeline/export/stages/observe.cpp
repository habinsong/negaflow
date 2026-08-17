#include "observe.h"

#include "export/support/outcome.h"

#include "negaflow/imageio/image_content_hash.h"

namespace negaflow::pipeline::develop_export_detail {

std::optional<DevelopExportOutcome> observe_source_before(
    const DevelopExportRequest& request,
    RunTracker& tracker,
    std::stop_source& stop,
    ObservedSource& observed) noexcept {
    observed.before = negaflow::imageio::observe_image_file(request.source);
    if (observed.before.status != negaflow::imageio::ImageFileObservationStatus::ok) {
        return fail(
            DevelopExportStage::observe_source_before,
            negaflow::imageio::image_file_observation_status_name(observed.before.status),
            observed.before.native_error_code);
    }
    if (request.expected_defect_source_identity) {
        tracker.begin(DevelopExportStage::observe_source_before, 0U);
        HashProgressBridge hash_progress{tracker, stop};
        negaflow::imageio::ImageContentHashControl hash_control{};
        hash_control.mode = negaflow::imageio::ImageContentHashMode::sha256;
        hash_control.stop_token = stop.get_token();
        hash_control.progress_observer = &hash_progress;
        const negaflow::imageio::ImageContentHashResult hashed =
            negaflow::imageio::hash_image_content(request.source, hash_control);
        if (hashed.status == negaflow::imageio::ImageContentHashStatus::cancelled) {
            return cancelled_outcome(DevelopExportStage::observe_source_before);
        }
        if (hashed.status != negaflow::imageio::ImageContentHashStatus::ok) {
            return fail(
                DevelopExportStage::observe_source_before,
                negaflow::imageio::image_content_hash_status_name(hashed.status),
                hashed.native_error_code);
        }
        if (!negaflow::imageio::same_image_file_observation(
                observed.before.observation,
                hashed.observation)) {
            return fail(
                DevelopExportStage::observe_source_before,
                "source_changed_before_decode");
        }
        const ExpectedSourceIdentity& expected =
            *request.expected_defect_source_identity;
        if (hashed.file_bytes != expected.file_bytes ||
            hashed.sha256 != expected.sha256) {
            return fail(
                DevelopExportStage::observe_source_before,
                "defect_source_identity_mismatch");
        }
    }
    return std::nullopt;
}

}  // namespace negaflow::pipeline::develop_export_detail
