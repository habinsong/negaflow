#include "result/develop_result_write.h"

#include "support/abi_text.h"

#include <chrono>
#include <cstdint>
#include <cstring>

namespace negaflow::abi::detail {

// 파이프라인 성과를 v1/v2/v3 결과 구조체에 씁니다.

[[nodiscard]] std::uint64_t elapsed_microseconds(
    const std::chrono::steady_clock::time_point started,
    const std::chrono::steady_clock::time_point finished) noexcept {
    return static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(finished - started).count());
}

void write_outcome(
    const negaflow::pipeline::DevelopExportOutcome& outcome,
    const std::uint64_t wall_microseconds,
    nf_develop_export_result_v1& result) noexcept {
    result.succeeded = outcome.succeeded ? 1U : 0U;
    result.failed_stage = static_cast<std::uint32_t>(outcome.failed_stage);
    copy_failure_name(outcome.failure_name, result.failure_name);
    result.native_error_code = outcome.native_error_code;
    result.cleanup_error_code = outcome.cleanup_error_code;
    result.image_width = outcome.image_width;
    result.image_height = outcome.image_height;
    result.film_look_route = static_cast<std::uint32_t>(outcome.film_look_route);
    result.film_look_color_applied = outcome.film_look_color_applied ? 1U : 0U;
    result.film_look_acutance_applied = outcome.film_look_acutance_applied ? 1U : 0U;
    result.source_file_bytes = outcome.source_file_bytes;
    result.output_file_bytes = outcome.output_file_bytes;
    result.film_look_workspace_bytes =
        static_cast<std::uint64_t>(outcome.film_look_workspace_bytes);
    result.wall_microseconds = wall_microseconds;
}

void write_outcome_v2(
    const negaflow::pipeline::DevelopExportOutcome& outcome,
    const std::uint64_t wall_microseconds,
    nf_develop_export_result_v2& result) noexcept {
    result.succeeded = outcome.succeeded ? 1U : 0U;
    result.failed_stage = static_cast<std::uint32_t>(outcome.failed_stage);
    copy_failure_name(outcome.failure_name, result.failure_name);
    result.native_error_code = outcome.native_error_code;
    result.cleanup_error_code = outcome.cleanup_error_code;
    result.image_width = outcome.image_width;
    result.image_height = outcome.image_height;
    result.film_look_route = static_cast<std::uint32_t>(outcome.film_look_route);
    result.film_look_color_applied = outcome.film_look_color_applied ? 1U : 0U;
    result.film_look_acutance_applied = outcome.film_look_acutance_applied ? 1U : 0U;
    result.source_file_bytes = outcome.source_file_bytes;
    result.output_file_bytes = outcome.output_file_bytes;
    result.film_look_workspace_bytes =
        static_cast<std::uint64_t>(outcome.film_look_workspace_bytes);
    result.wall_microseconds = wall_microseconds;
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        result.applied_dmin[channel] = outcome.applied_dmin[channel];
    }
    switch (outcome.base_source) {
        case negaflow::pipeline::DevelopBaseSource::manual:
            result.base_source = NF_DEVELOP_BASE_SOURCE_MANUAL;
            break;
        case negaflow::pipeline::DevelopBaseSource::auto_scene_edge:
            result.base_source = NF_DEVELOP_BASE_SOURCE_AUTO_SCENE_EDGE;
            break;
        case negaflow::pipeline::DevelopBaseSource::auto_fallback:
            result.base_source = NF_DEVELOP_BASE_SOURCE_AUTO_FALLBACK;
            break;
        case negaflow::pipeline::DevelopBaseSource::auto_connected_component:
            result.base_source = NF_DEVELOP_BASE_SOURCE_AUTO_CONNECTED_COMPONENT;
            break;
        case negaflow::pipeline::DevelopBaseSource::auto_continuous_border:
            result.base_source = NF_DEVELOP_BASE_SOURCE_AUTO_CONTINUOUS_BORDER;
            break;
        case negaflow::pipeline::DevelopBaseSource::auto_distributed_mask:
            result.base_source = NF_DEVELOP_BASE_SOURCE_AUTO_DISTRIBUTED_MASK;
            break;
        case negaflow::pipeline::DevelopBaseSource::auto_strip_fallback:
            result.base_source = NF_DEVELOP_BASE_SOURCE_AUTO_STRIP_FALLBACK;
            break;
        case negaflow::pipeline::DevelopBaseSource::preset_measured:
            result.base_source = NF_DEVELOP_BASE_SOURCE_PRESET_MEASURED;
            break;
        case negaflow::pipeline::DevelopBaseSource::preset_fallback:
            result.base_source = NF_DEVELOP_BASE_SOURCE_PRESET_FALLBACK;
            break;
    }
}

// The run state is optional. When present it is zeroed except for the caller's cancel
// latch, so a stale stage or progress reading from an earlier call cannot be mistaken for
// this one.
[[nodiscard]] bool prepare_run_state(
    nf_develop_run_state_v1* const run_state,
    negaflow::pipeline::DevelopRunControl& control,
    nf_status_t& status) noexcept {
    if (run_state == nullptr) {
        status = NF_STATUS_OK;
        return true;
    }
    if (run_state->struct_size < static_cast<std::uint32_t>(sizeof(*run_state))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }
    run_state->stage = NF_DEVELOP_STAGE_NONE;
    run_state->progress_permille = 0U;
    control.cancel_flag = &run_state->cancel_requested;
    control.progress_stage = &run_state->stage;
    control.progress_permille = &run_state->progress_permille;
    status = NF_STATUS_OK;
    return true;
}

// A request the mapper refused never reaches the pipeline, so its rejection is written
// into the v2 result the mapper knows about and copied across here. Only the fields the
// mapper actually sets are carried; everything else stays zeroed.
void write_request_rejection_v3(
    const nf_develop_export_result_v2& mapping_result,
    nf_develop_export_result_v3& result) noexcept {
    result.succeeded = 0U;
    result.failed_stage = mapping_result.failed_stage;
    std::memcpy(
        result.failure_name,
        mapping_result.failure_name,
        sizeof(result.failure_name));
    result.native_error_code = mapping_result.native_error_code;
    result.cleanup_error_code = mapping_result.cleanup_error_code;
    result.cancelled = 0U;
}

void write_outcome_v3(
    const negaflow::pipeline::DevelopExportOutcome& outcome,
    const std::uint64_t wall_microseconds,
    nf_develop_export_result_v3& result) noexcept {
    nf_develop_export_result_v2 shared{};
    shared.struct_size = static_cast<std::uint32_t>(sizeof(shared));
    write_outcome_v2(outcome, wall_microseconds, shared);

    const std::uint32_t declared_size = result.struct_size;
    result.succeeded = shared.succeeded;
    result.failed_stage = shared.failed_stage;
    std::memcpy(result.failure_name, shared.failure_name, sizeof(result.failure_name));
    result.native_error_code = shared.native_error_code;
    result.cleanup_error_code = shared.cleanup_error_code;
    result.image_width = shared.image_width;
    result.image_height = shared.image_height;
    result.film_look_route = shared.film_look_route;
    result.film_look_color_applied = shared.film_look_color_applied;
    result.film_look_acutance_applied = shared.film_look_acutance_applied;
    result.source_file_bytes = shared.source_file_bytes;
    result.output_file_bytes = shared.output_file_bytes;
    result.film_look_workspace_bytes = shared.film_look_workspace_bytes;
    result.wall_microseconds = shared.wall_microseconds;
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        result.applied_dmin[channel] = shared.applied_dmin[channel];
    }
    result.base_source = shared.base_source;
    result.cancelled = outcome.cancelled ? 1U : 0U;
    result.reserved = 0U;
    result.struct_size = declared_size;
}

}  // namespace negaflow::abi::detail
