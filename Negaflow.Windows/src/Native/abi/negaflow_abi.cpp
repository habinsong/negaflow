#include "negaflow_abi.h"

#include "negaflow/core/build_info.h"

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <string_view>

static_assert(sizeof(nf_build_info_v1) == 44U);
static_assert(offsetof(nf_build_info_v1, source_commit_sha1) == 24U);

namespace {

[[nodiscard]] std::uint8_t decode_hex_nibble(const char value) noexcept {
    if (value >= '0' && value <= '9') {
        return static_cast<std::uint8_t>(value - '0');
    }
    if (value >= 'a' && value <= 'f') {
        return static_cast<std::uint8_t>(value - 'a' + 10);
    }
    if (value >= 'A' && value <= 'F') {
        return static_cast<std::uint8_t>(value - 'A' + 10);
    }
    return 0xFFU;
}

void decode_source_commit(
    const std::string_view source_commit,
    std::uint8_t (&destination)[20]) noexcept {
    if (source_commit.size() != 40U) {
        return;
    }

    for (std::size_t index = 0; index < 20U; ++index) {
        const std::uint8_t high = decode_hex_nibble(source_commit[index * 2U]);
        const std::uint8_t low = decode_hex_nibble(source_commit[(index * 2U) + 1U]);
        if (high == 0xFFU || low == 0xFFU) {
            std::memset(destination, 0, 20U);
            return;
        }
        destination[index] = static_cast<std::uint8_t>((high << 4U) | low);
    }
}

}  // namespace

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
