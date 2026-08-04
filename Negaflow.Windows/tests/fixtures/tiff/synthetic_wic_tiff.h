#pragma once

#include <array>
#include <cstdint>
#include <vector>

namespace negaflow::test_fixtures {

inline constexpr std::array<std::uint16_t, 3> lzw_rgb16_expected_samples{
    0x1234U,
    0x5678U,
    0x9abcU,
};

[[nodiscard]] std::vector<std::uint8_t> make_lzw_rgb16_tiff();

[[nodiscard]] std::vector<std::uint8_t> make_lzw_rgb16_rows_tiff(
    std::uint32_t row_count);

[[nodiscard]] std::vector<std::uint8_t> make_claimed_expansion_lzw_rgb16_tiff(
    std::uint32_t width,
    std::uint32_t height);

[[nodiscard]] std::vector<std::uint8_t> make_malformed_lzw_rgb16_tiff();

}  // namespace negaflow::test_fixtures
