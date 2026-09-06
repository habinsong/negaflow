#include "negaflow/abi/develop_entry.h"
#include "request/develop_request_map.h"
#include "result/develop_result_write.h"
#include "support/abi_text.h"
#include "negaflow/pipeline/develop_export.h"

#include <chrono>
#include <cstddef>

using namespace negaflow::abi::detail;

namespace {
nf_status_t preview(const nf_develop_export_request_v39* request,
                    const nf_soft_proof_v1* soft_proof,
                    uint32_t maximum_width, uint32_t maximum_height,
                    uint8_t* pixels, uint32_t capacity, nf_develop_run_state_v1* run_state,
                    nf_develop_export_result_v3* result, bool background) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v39(request, result, status)) { return status; }
    if (pixels == nullptr) { return NF_STATUS_INVALID_ARGUMENT; }
    negaflow::pipeline::DevelopPreviewProof proof{};
    if (soft_proof != nullptr) {
        if (soft_proof->struct_size < sizeof(*soft_proof)) { return NF_STATUS_STRUCT_TOO_SMALL; }
        proof.enabled = soft_proof->enabled != 0U;
        proof.simulate_paper_and_black_ink = soft_proof->simulate_paper_and_black_ink != 0U;
        proof.warn_out_of_gamut = soft_proof->warn_out_of_gamut != 0U;
        proof.clipping_overlay = soft_proof->clipping_overlay != 0U;
        for (std::size_t i = 0; i < 3U; ++i) {
            proof.paper.white[i] = soft_proof->paper_white_rgb[i];
            proof.paper.black[i] = soft_proof->black_ink_rgb[i];
        }
    }
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) { return status; }
    negaflow::pipeline::DevelopExportRequest mapped{};
    nf_develop_export_result_v2 failure{};
    failure.struct_size = static_cast<uint32_t>(sizeof(failure));
    if (!map_request_v39(*request, false, mapped, failure)) {
        write_request_rejection_v3(failure, *result);
        return NF_STATUS_OK;
    }
    mapped.retain_preview_raw = !background;
    const auto started = std::chrono::steady_clock::now();
    const auto outcome = negaflow::pipeline::develop_preview(mapped, maximum_width, maximum_height,
        pixels, static_cast<std::size_t>(capacity), control, proof);
    write_outcome_v3(outcome, elapsed_microseconds(started, std::chrono::steady_clock::now()), *result);
    return NF_STATUS_OK;
}
}  // namespace

nf_status_t NF_CALL nf_develop_export_v39(const nf_develop_export_request_v39* request,
    nf_develop_run_state_v1* run_state, nf_develop_export_result_v3* result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v39(request, result, status)) { return status; }
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) { return status; }
    negaflow::pipeline::DevelopExportRequest mapped{};
    nf_develop_export_result_v2 failure{};
    failure.struct_size = static_cast<uint32_t>(sizeof(failure));
    if (!map_request_v39(*request, true, mapped, failure)) {
        write_request_rejection_v3(failure, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const auto outcome = negaflow::pipeline::develop_and_export(mapped, control);
    write_outcome_v3(outcome, elapsed_microseconds(started, std::chrono::steady_clock::now()), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v39(const nf_develop_export_request_v39* request,
    const nf_soft_proof_v1* soft_proof, uint32_t width, uint32_t height, uint8_t* pixels,
    uint32_t capacity, nf_develop_run_state_v1* run_state, nf_develop_export_result_v3* result) {
    return preview(request, soft_proof, width, height, pixels, capacity, run_state, result, false);
}

nf_status_t NF_CALL nf_develop_preview_background_v2(const nf_develop_export_request_v39* request,
    uint32_t width, uint32_t height, uint8_t* pixels, uint32_t capacity,
    nf_develop_run_state_v1* run_state, nf_develop_export_result_v3* result) {
    return preview(request, nullptr, width, height, pixels, capacity, run_state, result, true);
}
