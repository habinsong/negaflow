#include "outcome.h"

#include "negaflow/pipeline/gpu_accelerator.h"

#include <utility>

namespace negaflow::pipeline::develop_export_detail {

DevelopExportOutcome fail(
    const DevelopExportStage stage,
    const char* const name,
    const std::uint32_t native_error_code,
    const std::uint32_t cleanup_error_code) noexcept {
    DevelopExportOutcome outcome{};
    outcome.succeeded = false;
    outcome.failed_stage = stage;
    outcome.failure_name = name;
    outcome.native_error_code = native_error_code;
    outcome.cleanup_error_code = cleanup_error_code;
    return outcome;
}

DevelopExportOutcome cancelled_outcome(const DevelopExportStage stage) noexcept {
    DevelopExportOutcome outcome = fail(stage, "cancelled");
    outcome.cancelled = true;
    return outcome;
}

std::optional<DevelopExportOutcome> unbind_resident_and(
    const negaflow::imaging::WorkingImage& image,
    std::optional<DevelopExportOutcome> outcome) noexcept {
    GpuAccelerator::shared().flush_resident_if(image.pixels.data());
    return outcome;
}

}  // namespace negaflow::pipeline::develop_export_detail
