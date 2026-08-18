#pragma once

/* Which engine binary is loaded: architecture, CPU features, compiler, source commit. */

#include "negaflow/abi/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

#define NF_ARCHITECTURE_UNKNOWN 0U
#define NF_ARCHITECTURE_X64 1U
#define NF_ARCHITECTURE_ARM64 2U

#define NF_CPU_FEATURE_AVX_USABLE (1U << 0U)
#define NF_CPU_FEATURE_AVX2 (1U << 1U)
#define NF_CPU_FEATURE_FMA (1U << 2U)
#define NF_CPU_FEATURE_NEON_BASELINE (1U << 3U)

#define NF_COMPILER_UNKNOWN 0U
#define NF_COMPILER_MSVC 1U

typedef struct nf_build_info_v1 {
    uint32_t struct_size;
    uint32_t abi_version;
    uint32_t architecture;
    uint32_t cpu_feature_flags;
    uint32_t compiler_id;
    uint32_t compiler_version;
    uint8_t source_commit_sha1[20];
} nf_build_info_v1;

NF_API uint32_t NF_CALL nf_get_abi_version(void);
NF_API nf_status_t NF_CALL nf_get_build_info_v1(nf_build_info_v1* output);

#ifdef __cplusplus
}
#endif
