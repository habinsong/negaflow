#include "negaflow/abi/neutral_white_balance_pick.h"
#include "request/develop_request_map.h"
#include "result/develop_result_write.h"

#include "negaflow/pipeline/develop_export.h"

#include <chrono>
#include <cmath>

using namespace negaflow::abi::detail;
using namespace negaflow::pipeline;

// 중립 스포이드 C ABI 입니다. macOS `AppModel.pickNeutralWhiteBalance` 가 부르는
// `DevelopFrameRenderer.whiteBalanceInputSample` + `NeutralWhiteBalancePicker.solve` 자리입니다.
nf_status_t NF_CALL nf_pick_neutral_white_balance_v1(const nf_develop_export_request_v39* request,
    double unit_x, double unit_y, nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result, nf_neutral_white_balance_pick_v1* picked) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v39(request, result, status)) { return status; }
    if (picked == nullptr || picked->struct_size < sizeof(*picked) ||
        !std::isfinite(unit_x) || !std::isfinite(unit_y) ||
        unit_x < 0.0 || unit_x > 1.0 || unit_y < 0.0 || unit_y > 1.0) { return NF_STATUS_INVALID_ARGUMENT; }
    picked->status = NF_NEUTRAL_PICK_UNAVAILABLE;
    picked->reference_red = picked->reference_green = picked->reference_blue = 0.0;
    picked->warmth = picked->tint = 0.0;
    DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) { return status; }
    DevelopExportRequest mapped{};
    nf_develop_export_result_v2 failure{};
    failure.struct_size = static_cast<uint32_t>(sizeof(failure));
    if (!map_request_v39(*request, false, mapped, failure)) {
        write_request_rejection_v3(failure, *result);
        return NF_STATUS_OK;
    }
    // 화면 프리뷰와 같은 raw 슬롯을 함께 씁니다.
    mapped.retain_preview_raw = true;
    const auto started = std::chrono::steady_clock::now();
    const DevelopWhiteBalanceSample sample = develop_white_balance_sample(mapped, unit_x, unit_y, control);
    write_outcome_v3(sample.outcome, elapsed_microseconds(started, std::chrono::steady_clock::now()), *result);
    if (sample.outcome.succeeded) {
        picked->status = sample.sampled ? NF_NEUTRAL_PICK_OK : NF_NEUTRAL_PICK_REJECTED;
        if (sample.sampled) {
            picked->reference_red = sample.reference[0];
            picked->reference_green = sample.reference[1];
            picked->reference_blue = sample.reference[2];
            picked->warmth = sample.warmth;
            picked->tint = sample.tint;
        }
    }
    return NF_STATUS_OK;
}
