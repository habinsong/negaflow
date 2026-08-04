#include "negaflow/core/build_info.h"
#include "negaflow_abi.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <iostream>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] bool is_hex_commit(const std::string_view value) {
    return value.size() == 40U &&
           std::ranges::all_of(value, [](const unsigned char character) {
               return std::isxdigit(character) != 0;
           });
}

void test_core_build_info() {
    const negaflow::core::BuildInfo info = negaflow::core::query_build_info();
    expect(info.architecture != negaflow::core::Architecture::unknown, "architecture is known");
    expect(is_hex_commit(info.source_commit), "source commit is a 40-character hexadecimal SHA");
    expect(info.compiler_id == "MSVC", "compiler is MSVC");
    expect(info.compiler_version != 0U, "compiler version is populated");

    const bool avx_usable =
        (info.cpu_features & negaflow::core::cpu_feature_avx_usable) != 0U;
    const bool avx2 = (info.cpu_features & negaflow::core::cpu_feature_avx2) != 0U;
    const bool fma = (info.cpu_features & negaflow::core::cpu_feature_fma) != 0U;
    expect(!avx2 || avx_usable, "AVX2 is never usable without AVX OS state");
    expect(!fma || avx_usable, "FMA is never usable without AVX OS state");
}

void test_c_abi() {
    expect(nf_get_abi_version() == NF_ABI_VERSION, "ABI version matches the public header");
    expect(
        nf_get_build_info_v1(nullptr) == NF_STATUS_INVALID_ARGUMENT,
        "null ABI output is rejected");

    nf_build_info_v1 too_small{};
    too_small.struct_size = sizeof(std::uint32_t);
    expect(
        nf_get_build_info_v1(&too_small) == NF_STATUS_STRUCT_TOO_SMALL,
        "undersized ABI struct is rejected");

    nf_build_info_v1 result{};
    result.struct_size = sizeof(result);
    expect(nf_get_build_info_v1(&result) == NF_STATUS_OK, "full ABI struct succeeds");
    expect(result.struct_size == sizeof(result), "ABI reports its exact struct size");
    expect(result.abi_version == NF_ABI_VERSION, "ABI result reports negotiated version");
    expect(result.compiler_id == NF_COMPILER_MSVC, "ABI compiler ID is stable");
    expect(result.architecture != NF_ARCHITECTURE_UNKNOWN, "ABI architecture is known");
    expect(
        std::ranges::any_of(result.source_commit_sha1, [](const std::uint8_t byte) {
            return byte != 0U;
        }),
        "ABI source commit digest is populated");
}

}  // namespace

int main() {
    test_core_build_info();
    test_c_abi();

    if (failures != 0) {
        std::cerr << failures << " test assertion(s) failed\n";
        return 1;
    }

    std::cout << "All native foundation tests passed\n";
    return 0;
}
