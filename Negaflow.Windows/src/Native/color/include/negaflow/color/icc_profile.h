#pragma once

#include <array>
#include <cstdint>
#include <span>

namespace negaflow::color {

enum class IccProfileStatus : std::uint8_t {
    not_present = 0,
    ok,
    too_small,
    size_limit_exceeded,
    declared_size_mismatch,
    invalid_signature,
    tag_count_limit_exceeded,
    tag_table_out_of_bounds,
    invalid_tag,
    duplicate_tag,
    overlapping_tags,
};

struct IccProfileLimits final {
    std::uint64_t max_profile_bytes{16ULL * 1024ULL * 1024ULL};
    std::uint32_t max_tags{4'096U};
};

struct IccProfileInfo final {
    std::uint32_t declared_bytes{0};
    std::uint32_t device_class{0};
    std::uint32_t data_color_space{0};
    std::uint32_t pcs{0};
    std::uint32_t tag_count{0};
};

struct IccProfileValidationResult final {
    IccProfileStatus status{IccProfileStatus::not_present};
    IccProfileInfo info{};
};

[[nodiscard]] IccProfileValidationResult validate_icc_profile(
    std::span<const std::uint8_t> bytes,
    const IccProfileLimits& limits = {}) noexcept;

[[nodiscard]] const char* icc_profile_status_name(IccProfileStatus status) noexcept;
[[nodiscard]] std::array<char, 5> icc_fourcc_string(std::uint32_t value) noexcept;

}  // namespace negaflow::color
