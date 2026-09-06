#include "negaflow/abi/platform.h"
#include "negaflow/abi/input_gamma_source.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"

extern "C" NF_API nf_status_t NF_CALL nf_validate_input_gamma_source_v1(const wchar_t* path, uint32_t* supported) {
    if (path == nullptr || supported == nullptr) { return NF_STATUS_INVALID_ARGUMENT; }
    *supported = negaflow::imaging::is_input_gamma_source_supported(path) ? 1U : 0U;
    return NF_STATUS_OK;
}

static_assert(sizeof(nf_input_gamma_source_info_v1) == 40U);
extern "C" NF_API nf_status_t NF_CALL nf_inspect_input_gamma_source_v1(
    const wchar_t* path, nf_input_gamma_source_info_v1* info) {
    if (path == nullptr || info == nullptr || info->struct_size != sizeof(*info) || info->reserved != 0U || info->reserved_tail != 0U) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    const auto result = negaflow::imaging::inspect_input_gamma_source(path);
    *info = {sizeof(*info), result.supported ? 1U : 0U, result.curve, 0U, result.gamma,
        result.evidence, result.edge_count, 0U};
    return NF_STATUS_OK;
}
