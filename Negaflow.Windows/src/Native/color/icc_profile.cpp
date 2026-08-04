#include "negaflow/color/icc_profile.h"

#include <algorithm>
#include <cstddef>
#include <limits>
#include <vector>

namespace negaflow::color {
namespace {

constexpr std::size_t icc_header_bytes = 128U;
constexpr std::size_t icc_tag_count_bytes = 4U;
constexpr std::size_t icc_tag_record_bytes = 12U;
constexpr std::uint32_t acsp_signature = 0x61637370U;

[[nodiscard]] std::uint32_t read_be_u32(
    const std::span<const std::uint8_t> bytes,
    const std::size_t offset) noexcept {
    return (static_cast<std::uint32_t>(bytes[offset]) << 24U) |
           (static_cast<std::uint32_t>(bytes[offset + 1U]) << 16U) |
           (static_cast<std::uint32_t>(bytes[offset + 2U]) << 8U) |
           static_cast<std::uint32_t>(bytes[offset + 3U]);
}

struct TagRange final {
    std::uint32_t signature;
    std::uint32_t offset;
    std::uint32_t size;
};

}  // namespace

IccProfileValidationResult validate_icc_profile(
    const std::span<const std::uint8_t> bytes,
    const IccProfileLimits& limits) noexcept {
    IccProfileValidationResult result{};
    try {
        if (bytes.empty()) {
            return result;
        }
        if (bytes.size() > limits.max_profile_bytes ||
            bytes.size() > std::numeric_limits<std::uint32_t>::max()) {
            result.status = IccProfileStatus::size_limit_exceeded;
            return result;
        }
        if (bytes.size() < icc_header_bytes + icc_tag_count_bytes) {
            result.status = IccProfileStatus::too_small;
            return result;
        }

        result.info.declared_bytes = read_be_u32(bytes, 0U);
        result.info.device_class = read_be_u32(bytes, 12U);
        result.info.data_color_space = read_be_u32(bytes, 16U);
        result.info.pcs = read_be_u32(bytes, 20U);
        result.info.tag_count = read_be_u32(bytes, icc_header_bytes);

        if (result.info.declared_bytes != bytes.size()) {
            result.status = IccProfileStatus::declared_size_mismatch;
            return result;
        }
        if (read_be_u32(bytes, 36U) != acsp_signature) {
            result.status = IccProfileStatus::invalid_signature;
            return result;
        }
        if (result.info.tag_count > limits.max_tags) {
            result.status = IccProfileStatus::tag_count_limit_exceeded;
            return result;
        }

        const std::uint64_t table_end = static_cast<std::uint64_t>(icc_header_bytes) +
                                        icc_tag_count_bytes +
                                        static_cast<std::uint64_t>(result.info.tag_count) *
                                            icc_tag_record_bytes;
        if (table_end > bytes.size()) {
            result.status = IccProfileStatus::tag_table_out_of_bounds;
            return result;
        }

        std::vector<TagRange> ranges{};
        ranges.reserve(result.info.tag_count);
        for (std::uint32_t index = 0U; index < result.info.tag_count; ++index) {
            const std::size_t record_offset = icc_header_bytes + icc_tag_count_bytes +
                                              static_cast<std::size_t>(index) *
                                                  icc_tag_record_bytes;
            const TagRange range{
                read_be_u32(bytes, record_offset),
                read_be_u32(bytes, record_offset + 4U),
                read_be_u32(bytes, record_offset + 8U),
            };
            const std::uint64_t range_end =
                static_cast<std::uint64_t>(range.offset) + range.size;
            if (range.size == 0U || range.offset % 4U != 0U ||
                range.offset < table_end || range_end > bytes.size()) {
                result.status = IccProfileStatus::invalid_tag;
                return result;
            }
            ranges.push_back(range);
        }

        std::vector<std::uint32_t> signatures{};
        signatures.reserve(ranges.size());
        for (const TagRange& range : ranges) {
            signatures.push_back(range.signature);
        }
        std::sort(signatures.begin(), signatures.end());
        if (std::adjacent_find(signatures.begin(), signatures.end()) != signatures.end()) {
            result.status = IccProfileStatus::duplicate_tag;
            return result;
        }

        std::sort(
            ranges.begin(),
            ranges.end(),
            [](const TagRange& left, const TagRange& right) {
                return left.offset < right.offset ||
                       (left.offset == right.offset && left.size < right.size);
            });
        for (std::size_t index = 1U; index < ranges.size(); ++index) {
            const TagRange& previous = ranges[index - 1U];
            const TagRange& current = ranges[index];
            const std::uint64_t previous_end =
                static_cast<std::uint64_t>(previous.offset) + previous.size;
            const bool exact_shared_range =
                previous.offset == current.offset && previous.size == current.size;
            if (!exact_shared_range && current.offset < previous_end) {
                result.status = IccProfileStatus::overlapping_tags;
                return result;
            }
        }

        result.status = IccProfileStatus::ok;
        return result;
    } catch (...) {
        result.status = IccProfileStatus::size_limit_exceeded;
        return result;
    }
}

const char* icc_profile_status_name(const IccProfileStatus status) noexcept {
    switch (status) {
        case IccProfileStatus::not_present:
            return "not_present";
        case IccProfileStatus::ok:
            return "ok";
        case IccProfileStatus::too_small:
            return "icc_too_small";
        case IccProfileStatus::size_limit_exceeded:
            return "icc_size_limit_exceeded";
        case IccProfileStatus::declared_size_mismatch:
            return "icc_declared_size_mismatch";
        case IccProfileStatus::invalid_signature:
            return "invalid_icc_signature";
        case IccProfileStatus::tag_count_limit_exceeded:
            return "icc_tag_count_limit_exceeded";
        case IccProfileStatus::tag_table_out_of_bounds:
            return "icc_tag_table_out_of_bounds";
        case IccProfileStatus::invalid_tag:
            return "invalid_icc_tag";
        case IccProfileStatus::duplicate_tag:
            return "duplicate_icc_tag";
        case IccProfileStatus::overlapping_tags:
            return "overlapping_icc_tags";
    }
    return "unknown_icc_profile_status";
}

std::array<char, 5> icc_fourcc_string(const std::uint32_t value) noexcept {
    return {
        static_cast<char>((value >> 24U) & 0xffU),
        static_cast<char>((value >> 16U) & 0xffU),
        static_cast<char>((value >> 8U) & 0xffU),
        static_cast<char>(value & 0xffU),
        '\0',
    };
}

}  // namespace negaflow::color
