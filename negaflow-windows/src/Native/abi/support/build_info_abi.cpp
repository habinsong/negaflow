#include "negaflow/abi/build_info.h"

#include "support/abi_text.h"

#include "negaflow/core/build_info.h"

#include <cstdint>
#include <cstring>

using negaflow::abi::detail::decode_source_commit;

// ABI 버전과 네이티브 빌드 신원입니다.

uint32_t NF_CALL nf_get_abi_version(void) {
    return NF_ABI_VERSION;
}

nf_status_t NF_CALL nf_get_build_info_v1(nf_build_info_v1* const output) {
    if (output == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (output->struct_size < static_cast<std::uint32_t>(sizeof(nf_build_info_v1))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }

    const negaflow::core::BuildInfo source = negaflow::core::query_build_info();
    nf_build_info_v1 result{};
    result.struct_size = static_cast<std::uint32_t>(sizeof(nf_build_info_v1));
    result.abi_version = NF_ABI_VERSION;
    result.architecture = static_cast<std::uint32_t>(source.architecture);
    result.cpu_feature_flags = source.cpu_features;
    result.compiler_id = NF_COMPILER_MSVC;
    result.compiler_version = source.compiler_version;
    decode_source_commit(source.source_commit, result.source_commit_sha1);

    std::memcpy(output, &result, sizeof(result));
    return NF_STATUS_OK;
}
