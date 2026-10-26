#include "develop_request_map.h"
#include "result/develop_result_write.h"
#include "negaflow/imaging/film_base_scale.h"

#include <cstring>

namespace negaflow::abi::detail {
bool map_request_v39(const nf_develop_export_request_v39& request, bool require_destination,
                    negaflow::pipeline::DevelopExportRequest& pipeline_request,
                    nf_develop_export_result_v2& result) noexcept {
    const negaflow::color::InputGammaInterpretation gamma{request.input_gamma_mode, request.input_gamma_value};
    if (request.reserved != 0U || request.v38.proxy_reserved != 0U ||
        !gamma.valid() || !negaflow::imaging::valid_film_base_scale(request.base_scale)) {
        fail_defect_region_request(result, "invalid_input_gamma_or_base_scale");
        return false;
    }
    if (!map_request_v38(request.v38, require_destination, pipeline_request, result)) { return false; }
    std::uint32_t bytes = 0U;
    std::memcpy(&bytes, &request, sizeof(bytes));
    pipeline_request.auto_balance = false;
    if (bytes >= sizeof(nf_develop_export_request_v40)) {
        const auto* extended = reinterpret_cast<const nf_develop_export_request_v40*>(&request);
        if (extended->auto_balance > 1U || extended->auto_balance_reserved != 0U) {
            fail_defect_region_request(result, "invalid_auto_balance");
            return false;
        }
        pipeline_request.auto_balance = extended->auto_balance == 1U;
    }
    pipeline_request.input_gamma = gamma;
    pipeline_request.base_scale = request.base_scale;
    return true;
}

}  // namespace negaflow::abi::detail
