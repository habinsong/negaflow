#include "negaflow/abi/develop_entry.h"

#include "request/develop_request_map.h"
#include "result/develop_result_write.h"
#include "support/abi_text.h"

#include "negaflow/pipeline/develop_export.h"

#include <chrono>
#include <cstdint>

using namespace negaflow::abi::detail;

nf_status_t NF_CALL nf_develop_export_v38(
    const nf_develop_export_request_v38* const request,
    nf_develop_run_state_v1* const run_state,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v35(
            request == nullptr ? nullptr : &request->v37.v36.v35,
            result,
            status)) {
        return status;
    }
    if (request->v37.v36.v35.v34.v33.v32.v31.v30.v29.v28.v27.v26.v25.v24.v21.v20.v19.v18
            .v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size <
            static_cast<std::uint32_t>(sizeof(*request))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v38(*request, true, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const auto outcome = negaflow::pipeline::develop_and_export(pipeline_request, control);
    write_outcome_v3(
        outcome,
        elapsed_microseconds(started, std::chrono::steady_clock::now()),
        *result);
    return NF_STATUS_OK;
}
