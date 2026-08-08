#include "negaflow/color/icc_profile.h"

#include <cstddef>
#include <cstdint>
#include <iostream>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

void write_be_u32(
    std::vector<std::uint8_t>& bytes,
    const std::size_t offset,
    const std::uint32_t value) {
    bytes[offset] = static_cast<std::uint8_t>((value >> 24U) & 0xffU);
    bytes[offset + 1U] = static_cast<std::uint8_t>((value >> 16U) & 0xffU);
    bytes[offset + 2U] = static_cast<std::uint8_t>((value >> 8U) & 0xffU);
    bytes[offset + 3U] = static_cast<std::uint8_t>(value & 0xffU);
}

[[nodiscard]] std::vector<std::uint8_t> make_profile(const std::uint32_t tag_count) {
    const std::size_t table_end = 132U + static_cast<std::size_t>(tag_count) * 12U;
    std::vector<std::uint8_t> bytes(table_end + (tag_count == 0U ? 0U : 8U), 0U);
    write_be_u32(bytes, 0U, static_cast<std::uint32_t>(bytes.size()));
    write_be_u32(bytes, 12U, 0x6d6e7472U);
    write_be_u32(bytes, 16U, 0x52474220U);
    write_be_u32(bytes, 20U, 0x58595a20U);
    write_be_u32(bytes, 36U, 0x61637370U);
    write_be_u32(bytes, 128U, tag_count);
    if (tag_count != 0U) {
        write_be_u32(bytes, 132U, 0x77747074U);
        write_be_u32(bytes, 136U, static_cast<std::uint32_t>(table_end));
        write_be_u32(bytes, 140U, 8U);
    }
    return bytes;
}

}  // namespace

int main() {
    const auto valid = make_profile(1U);
    const auto valid_result = negaflow::color::validate_icc_profile(valid);
    expect(valid_result.status == negaflow::color::IccProfileStatus::ok, "valid ICC probes");
    expect(valid_result.info.tag_count == 1U, "ICC tag count is reported");

    auto wrong_size = valid;
    write_be_u32(wrong_size, 0U, 132U);
    expect(
        negaflow::color::validate_icc_profile(wrong_size).status ==
            negaflow::color::IccProfileStatus::declared_size_mismatch,
        "declared size mismatch is rejected");

    auto wrong_signature = valid;
    write_be_u32(wrong_signature, 36U, 0U);
    expect(
        negaflow::color::validate_icc_profile(wrong_signature).status ==
            negaflow::color::IccProfileStatus::invalid_signature,
        "invalid ICC signature is rejected");

    auto out_of_bounds = valid;
    write_be_u32(out_of_bounds, 136U, 0xfffffff0U);
    expect(
        negaflow::color::validate_icc_profile(out_of_bounds).status ==
            negaflow::color::IccProfileStatus::invalid_tag,
        "out-of-range ICC tag is rejected");

    negaflow::color::IccProfileLimits limits{};
    limits.max_tags = 0U;
    expect(
        negaflow::color::validate_icc_profile(valid, limits).status ==
            negaflow::color::IccProfileStatus::tag_count_limit_exceeded,
        "ICC tag count limit is enforced");

    if (failures != 0) {
        std::cerr << failures << " ICC profile test(s) failed\n";
        return 1;
    }
    std::cout << "ICC profile tests passed\n";
    return 0;
}
