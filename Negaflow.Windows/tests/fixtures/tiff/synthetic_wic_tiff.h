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

[[nodiscard]] std::vector<std::uint8_t> make_lzw_code_width_transition_rgb16_tiff();

[[nodiscard]] std::vector<std::uint8_t> make_lzw_dictionary_limit_rgb16_tiff();

[[nodiscard]] std::vector<std::uint8_t> make_lzw_forward_reference_rgb16_tiff();

[[nodiscard]] std::vector<std::uint8_t> make_nonzero_fill_bits_lzw_rgb16_tiff();

[[nodiscard]] std::vector<std::uint8_t> make_claimed_expansion_lzw_rgb16_tiff(
    std::uint32_t width,
    std::uint32_t height);

[[nodiscard]] std::vector<std::uint8_t> make_malformed_lzw_rgb16_tiff();

[[nodiscard]] std::vector<std::uint8_t> make_missing_clear_lzw_rgb16_tiff();

[[nodiscard]] std::vector<std::uint8_t> make_missing_eoi_lzw_rgb16_tiff();

[[nodiscard]] std::vector<std::uint8_t> make_short_decoded_lzw_rgb16_tiff();

[[nodiscard]] std::vector<std::uint8_t> make_long_decoded_lzw_rgb16_tiff();

[[nodiscard]] std::vector<std::uint8_t> make_invalid_forward_code_lzw_rgb16_tiff();

[[nodiscard]] std::vector<std::uint8_t> make_trailing_data_lzw_rgb16_tiff();

[[nodiscard]] std::vector<std::uint8_t> make_deflate_rgb16_tiff();

[[nodiscard]] std::vector<std::uint8_t> make_malformed_deflate_rgb16_tiff();

}  // namespace negaflow::test_fixtures
