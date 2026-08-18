#include "negaflow/abi/develop_entry.h"

#include "support/abi_text.h"
#include "request/develop_request_map.h"
#include "result/develop_result_write.h"

#include "negaflow/pipeline/develop_export.h"

#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>

using namespace negaflow::abi::detail;

// v23–v28: 소프트 프루프 미리보기와 적외선·출력 샤픈·캘리브레이션·JPEG.

nf_status_t NF_CALL nf_develop_preview_v23(
    const nf_develop_export_request_v21* const request,
    const nf_soft_proof_v1* const soft_proof,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* const run_state,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v3(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopPreviewProof proof{};
    if (soft_proof != nullptr) {
        if (soft_proof->struct_size < static_cast<std::uint32_t>(sizeof(*soft_proof))) {
            return NF_STATUS_STRUCT_TOO_SMALL;
        }
        proof.enabled = soft_proof->enabled != 0U;
        proof.simulate_paper_and_black_ink =
            soft_proof->simulate_paper_and_black_ink != 0U;
        proof.warn_out_of_gamut = soft_proof->warn_out_of_gamut != 0U;
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            proof.paper.white[channel] =
                static_cast<double>(soft_proof->paper_white_rgb[channel]);
            proof.paper.black[channel] =
                static_cast<double>(soft_proof->black_ink_rgb[channel]);
        }
    }
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v21(*request, false, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes),
            control,
            proof);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v3(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v24(
    const nf_develop_export_request_v24* const request,
    nf_develop_run_state_v1* const run_state,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v24(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v24(*request, true, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request, control);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v3(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v24(
    const nf_develop_export_request_v24* const request,
    const nf_soft_proof_v1* const soft_proof,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* const run_state,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v24(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopPreviewProof proof{};
    if (soft_proof != nullptr) {
        if (soft_proof->struct_size < static_cast<std::uint32_t>(sizeof(*soft_proof))) {
            return NF_STATUS_STRUCT_TOO_SMALL;
        }
        proof.enabled = soft_proof->enabled != 0U;
        proof.simulate_paper_and_black_ink =
            soft_proof->simulate_paper_and_black_ink != 0U;
        proof.warn_out_of_gamut = soft_proof->warn_out_of_gamut != 0U;
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            proof.paper.white[channel] =
                static_cast<double>(soft_proof->paper_white_rgb[channel]);
            proof.paper.black[channel] =
                static_cast<double>(soft_proof->black_ink_rgb[channel]);
        }
    }
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v24(*request, false, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes),
            control,
            proof);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v3(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v25(
    const nf_develop_export_request_v25* const request,
    nf_develop_run_state_v1* const run_state,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v25(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v25(*request, true, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request, control);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v3(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v25(
    const nf_develop_export_request_v25* const request,
    const nf_soft_proof_v1* const soft_proof,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* const run_state,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v25(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopPreviewProof proof{};
    if (soft_proof != nullptr) {
        if (soft_proof->struct_size < static_cast<std::uint32_t>(sizeof(*soft_proof))) {
            return NF_STATUS_STRUCT_TOO_SMALL;
        }
        proof.enabled = soft_proof->enabled != 0U;
        proof.simulate_paper_and_black_ink =
            soft_proof->simulate_paper_and_black_ink != 0U;
        proof.warn_out_of_gamut = soft_proof->warn_out_of_gamut != 0U;
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            proof.paper.white[channel] =
                static_cast<double>(soft_proof->paper_white_rgb[channel]);
            proof.paper.black[channel] =
                static_cast<double>(soft_proof->black_ink_rgb[channel]);
        }
    }
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v25(*request, false, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes),
            control,
            proof);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v3(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v26(
    const nf_develop_export_request_v26* const request,
    nf_develop_run_state_v1* const run_state,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v26(request, result, status)) return status;
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) return status;
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v26(*request, true, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const auto outcome = negaflow::pipeline::develop_and_export(pipeline_request, control);
    write_outcome_v3(outcome, elapsed_microseconds(started, std::chrono::steady_clock::now()), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v26(
    const nf_develop_export_request_v26* const request,
    const nf_soft_proof_v1* const soft_proof,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* const run_state,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v26(request, result, status)) return status;
    if (pixels == nullptr) return NF_STATUS_INVALID_ARGUMENT;
    negaflow::pipeline::DevelopPreviewProof proof{};
    if (soft_proof != nullptr) {
        if (soft_proof->struct_size < static_cast<std::uint32_t>(sizeof(*soft_proof))) {
            return NF_STATUS_STRUCT_TOO_SMALL;
        }
        proof.enabled = soft_proof->enabled != 0U;
        proof.simulate_paper_and_black_ink =
            soft_proof->simulate_paper_and_black_ink != 0U;
        proof.warn_out_of_gamut = soft_proof->warn_out_of_gamut != 0U;
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            proof.paper.white[channel] = static_cast<double>(soft_proof->paper_white_rgb[channel]);
            proof.paper.black[channel] = static_cast<double>(soft_proof->black_ink_rgb[channel]);
        }
    }
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) return status;
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v26(*request, false, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const auto outcome = negaflow::pipeline::develop_preview(
        pipeline_request, maximum_width, maximum_height, pixels,
        static_cast<std::size_t>(pixel_capacity_bytes), control, proof);
    write_outcome_v3(outcome, elapsed_microseconds(started, std::chrono::steady_clock::now()), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v27(
    const nf_develop_export_request_v27* const request,
    nf_develop_run_state_v1* const run_state,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v27(request, result, status)) return status;
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) return status;
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v27(*request, true, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const auto outcome = negaflow::pipeline::develop_and_export(pipeline_request, control);
    write_outcome_v3(outcome, elapsed_microseconds(started, std::chrono::steady_clock::now()), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v27(
    const nf_develop_export_request_v27* const request,
    const nf_soft_proof_v1* const soft_proof,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* const run_state,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v27(request, result, status)) return status;
    if (pixels == nullptr) return NF_STATUS_INVALID_ARGUMENT;
    negaflow::pipeline::DevelopPreviewProof proof{};
    if (soft_proof != nullptr) {
        if (soft_proof->struct_size < static_cast<std::uint32_t>(sizeof(*soft_proof))) {
            return NF_STATUS_STRUCT_TOO_SMALL;
        }
        proof.enabled = soft_proof->enabled != 0U;
        proof.simulate_paper_and_black_ink =
            soft_proof->simulate_paper_and_black_ink != 0U;
        proof.warn_out_of_gamut = soft_proof->warn_out_of_gamut != 0U;
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            proof.paper.white[channel] = static_cast<double>(soft_proof->paper_white_rgb[channel]);
            proof.paper.black[channel] = static_cast<double>(soft_proof->black_ink_rgb[channel]);
        }
    }
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) return status;
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v27(*request, false, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const auto outcome = negaflow::pipeline::develop_preview(
        pipeline_request, maximum_width, maximum_height, pixels,
        static_cast<std::size_t>(pixel_capacity_bytes), control, proof);
    write_outcome_v3(outcome, elapsed_microseconds(started, std::chrono::steady_clock::now()), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v28(
    const nf_develop_export_request_v28* const request,
    nf_develop_run_state_v1* const run_state,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v28(request, result, status)) return status;
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) return status;
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v28(*request, true, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const auto outcome = negaflow::pipeline::develop_and_export(pipeline_request, control);
    write_outcome_v3(outcome, elapsed_microseconds(started, std::chrono::steady_clock::now()), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v28(
    const nf_develop_export_request_v28* const request,
    const nf_soft_proof_v1* const soft_proof,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* const run_state,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v28(request, result, status)) return status;
    if (pixels == nullptr) return NF_STATUS_INVALID_ARGUMENT;
    negaflow::pipeline::DevelopPreviewProof proof{};
    if (soft_proof != nullptr) {
        if (soft_proof->struct_size < static_cast<std::uint32_t>(sizeof(*soft_proof))) {
            return NF_STATUS_STRUCT_TOO_SMALL;
        }
        proof.enabled = soft_proof->enabled != 0U;
        proof.simulate_paper_and_black_ink =
            soft_proof->simulate_paper_and_black_ink != 0U;
        proof.warn_out_of_gamut = soft_proof->warn_out_of_gamut != 0U;
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            proof.paper.white[channel] = static_cast<double>(soft_proof->paper_white_rgb[channel]);
            proof.paper.black[channel] = static_cast<double>(soft_proof->black_ink_rgb[channel]);
        }
    }
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) return status;
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v28(*request, false, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const auto outcome = negaflow::pipeline::develop_preview(
        pipeline_request, maximum_width, maximum_height, pixels,
        static_cast<std::size_t>(pixel_capacity_bytes), control, proof);
    write_outcome_v3(outcome, elapsed_microseconds(started, std::chrono::steady_clock::now()), *result);
    return NF_STATUS_OK;
}
