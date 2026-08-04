#pragma once

#include <cstdint>
#include <string>
#include <string_view>

namespace negaflow::core {

enum class Architecture : std::uint32_t {
    unknown = 0,
    x64 = 1,
    arm64 = 2,
};

enum CpuFeature : std::uint32_t {
    cpu_feature_none = 0,
    cpu_feature_avx_usable = 1U << 0U,
    cpu_feature_avx2 = 1U << 1U,
    cpu_feature_fma = 1U << 2U,
    cpu_feature_neon_baseline = 1U << 3U,
};

struct BuildInfo final {
    Architecture architecture;
    std::uint32_t cpu_features;
    std::uint32_t compiler_version;
    bool source_dirty;
    std::string_view compiler_id;
    std::string_view product_version;
    std::string_view source_commit;
    std::string_view baseline_isa;
};

[[nodiscard]] BuildInfo query_build_info() noexcept;
[[nodiscard]] std::string_view architecture_name(Architecture architecture) noexcept;
[[nodiscard]] std::string build_info_json();

}  // namespace negaflow::core
