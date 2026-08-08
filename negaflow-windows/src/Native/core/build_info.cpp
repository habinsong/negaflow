#include "negaflow/core/build_info.h"

#include "negaflow/core/build_config.h"

#include <string>
#include <Windows.h>

#if defined(_M_X64)
#include <intrin.h>
#elif !defined(_M_ARM64)
#error Negaflow Windows supports only x64 and ARM64 native targets.
#endif

namespace negaflow::core {
namespace {

[[nodiscard]] std::uint32_t detect_cpu_features() noexcept {
    std::uint32_t features = cpu_feature_none;

#if defined(_M_X64)
    int registers[4]{};
    __cpuid(registers, 0);
    const int maximum_leaf = registers[0];

    bool avx_hardware = false;
    bool os_xsave = false;
    bool fma_hardware = false;
    if (maximum_leaf >= 1) {
        __cpuidex(registers, 1, 0);
        const auto feature_ecx = static_cast<std::uint32_t>(registers[2]);
        fma_hardware = (feature_ecx & (1U << 12U)) != 0U;
        os_xsave = (feature_ecx & (1U << 27U)) != 0U;
        avx_hardware = (feature_ecx & (1U << 28U)) != 0U;
    }

    bool xmm_ymm_state = false;
    if (os_xsave) {
        const unsigned __int64 xcr0 = _xgetbv(0);
        xmm_ymm_state = (xcr0 & 0x6U) == 0x6U;
    }

    const bool avx_usable = avx_hardware && xmm_ymm_state;
    if (avx_usable) {
        features |= cpu_feature_avx_usable;
    }

    bool avx2_hardware = false;
    if (maximum_leaf >= 7) {
        __cpuidex(registers, 7, 0);
        const auto feature_ebx = static_cast<std::uint32_t>(registers[1]);
        avx2_hardware = (feature_ebx & (1U << 5U)) != 0U;
    }

    const bool windows_reports_avx2 =
        IsProcessorFeaturePresent(PF_AVX2_INSTRUCTIONS_AVAILABLE) != FALSE;
    if (avx_usable && avx2_hardware && windows_reports_avx2) {
        features |= cpu_feature_avx2;
    }
    if (avx_usable && fma_hardware) {
        features |= cpu_feature_fma;
    }
#elif defined(_M_ARM64)
    const bool arm_v8 = IsProcessorFeaturePresent(PF_ARM_V8_INSTRUCTIONS_AVAILABLE) != FALSE;
    const bool neon = IsProcessorFeaturePresent(PF_ARM_NEON_INSTRUCTIONS_AVAILABLE) != FALSE;
    if (arm_v8 && neon) {
        features |= cpu_feature_neon_baseline;
    }
#endif

    return features;
}

[[nodiscard]] Architecture compiled_architecture() noexcept {
#if defined(_M_X64)
    return Architecture::x64;
#elif defined(_M_ARM64)
    return Architecture::arm64;
#else
    return Architecture::unknown;
#endif
}

[[nodiscard]] std::string_view compiled_baseline_isa() noexcept {
#if defined(_M_X64)
    return "sse2";
#elif defined(_M_ARM64)
    return "armv8.0-neon";
#else
    return "unknown";
#endif
}

[[nodiscard]] std::string boolean_json(const bool value) {
    return value ? "true" : "false";
}

}  // namespace

BuildInfo query_build_info() noexcept {
    return BuildInfo{
        .architecture = compiled_architecture(),
        .cpu_features = detect_cpu_features(),
        .compiler_version = static_cast<std::uint32_t>(_MSC_FULL_VER),
        .source_dirty = NEGAFLOW_SOURCE_DIRTY != 0,
        .compiler_id = "MSVC",
        .product_version = NEGAFLOW_PRODUCT_VERSION,
        .source_commit = NEGAFLOW_SOURCE_COMMIT,
        .baseline_isa = compiled_baseline_isa(),
    };
}

std::string_view architecture_name(const Architecture architecture) noexcept {
    switch (architecture) {
        case Architecture::x64:
            return "x64";
        case Architecture::arm64:
            return "arm64";
        case Architecture::unknown:
        default:
            return "unknown";
    }
}

std::string build_info_json() {
    const BuildInfo info = query_build_info();
    const bool avx_usable = (info.cpu_features & cpu_feature_avx_usable) != 0U;
    const bool avx2 = (info.cpu_features & cpu_feature_avx2) != 0U;
    const bool fma = (info.cpu_features & cpu_feature_fma) != 0U;
    const bool neon = (info.cpu_features & cpu_feature_neon_baseline) != 0U;

    std::string result;
    result.reserve(512U);
    result += "{\"schema_version\":1,\"status\":\"ok\",\"product\":\"Negaflow Windows\"";
    result += ",\"production_features\":false,\"build\":{";
    result += "\"id\":\"";
    result += info.source_commit;
    if (info.source_dirty) {
        result += "-dirty";
    }
    result += "\",\"source_commit\":\"";
    result += info.source_commit;
    result += "\",\"source_dirty\":";
    result += boolean_json(info.source_dirty);
    result += ",\"product_version\":\"";
    result += info.product_version;
    result += "\",\"architecture\":\"";
    result += architecture_name(info.architecture);
    result += "\",\"compiler\":{\"id\":\"";
    result += info.compiler_id;
    result += "\",\"version\":";
    result += std::to_string(info.compiler_version);
    result += "}},\"cpu\":{\"baseline\":\"";
    result += info.baseline_isa;
    result += "\",\"avx_usable\":";
    result += boolean_json(avx_usable);
    result += ",\"avx2\":";
    result += boolean_json(avx2);
    result += ",\"fma\":";
    result += boolean_json(fma);
    result += ",\"neon_baseline\":";
    result += boolean_json(neon);
    result += "},\"graphics\":{\"status\":\"not_initialized\",\"adapters\":[]}}";
    return result;
}

}  // namespace negaflow::core
