#pragma once
#include "negaflow/abi/platform.h"

typedef struct nf_input_gamma_source_info_v1 {
    uint32_t struct_size;
    uint32_t supported;
    uint32_t curve;
    uint32_t reserved;
    double gamma;
    double evidence;
    uint32_t edge_count;
    uint32_t reserved_tail;
} nf_input_gamma_source_info_v1;

#ifdef __cplusplus
extern "C" {
#endif
NF_API nf_status_t NF_CALL nf_inspect_input_gamma_source_v1(
    const wchar_t* path, nf_input_gamma_source_info_v1* info);
#ifdef __cplusplus
}
#endif
