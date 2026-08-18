#include "tiff_deflate_validator.h"

#include "tiff_deflate_bits.h"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <limits>

namespace negaflow::core::detail {
namespace {

class DeflateValidator final {
public:
    DeflateValidator(
        LsbBitReader& input,
        const std::uint64_t expected_decoded_bytes,
        const std::stop_token stop_token) noexcept
        : input_(input), expected_decoded_bytes_(expected_decoded_bytes), stop_token_(stop_token) {}

    [[nodiscard]] TiffDeflateValidationStatus run() noexcept {
        std::uint32_t cmf = 0U;
        std::uint32_t flg = 0U;
        if (!input_.read_bits(8U, cmf) || !input_.read_bits(8U, flg)) {
            return read_failure();
        }
        if ((cmf & 0x0fU) != 8U || (cmf >> 4U) > 7U ||
            (((cmf << 8U) | flg) % 31U) != 0U || (flg & 0x20U) != 0U) {
            return TiffDeflateValidationStatus::invalid_stream;
        }
        window_limit_ = 1U << ((cmf >> 4U) + 8U);

        bool final_block = false;
        while (!final_block) {
            if (stop_token_.stop_requested()) {
                return TiffDeflateValidationStatus::cancelled;
            }
            std::uint32_t final = 0U;
            std::uint32_t type = 0U;
            if (!input_.read_bits(1U, final) || !input_.read_bits(2U, type)) {
                return read_failure();
            }
            final_block = final != 0U;
            TiffDeflateValidationStatus status = TiffDeflateValidationStatus::invalid_stream;
            if (type == 0U) {
                status = decode_stored_block();
            } else if (type == 1U) {
                status = decode_fixed_block();
            } else if (type == 2U) {
                status = decode_dynamic_block();
            }
            if (status != TiffDeflateValidationStatus::ok) {
                return status;
            }
        }
        if (decoded_bytes_ != expected_decoded_bytes_) {
            return TiffDeflateValidationStatus::invalid_stream;
        }

        input_.align_to_byte();
        std::uint32_t checksum = 0U;
        for (std::uint8_t index = 0U; index < 4U; ++index) {
            std::uint32_t byte = 0U;
            if (!input_.read_bits(8U, byte)) {
                return read_failure();
            }
            checksum = (checksum << 8U) | byte;
        }
        const std::uint32_t actual = (adler_second_ << 16U) | adler_first_;
        return checksum == actual && input_.has_no_trailing_bytes()
                   ? TiffDeflateValidationStatus::ok
                   : TiffDeflateValidationStatus::invalid_stream;
    }

    [[nodiscard]] std::uint64_t decoded_bytes() const noexcept {
        return decoded_bytes_;
    }

private:
    [[nodiscard]] TiffDeflateValidationStatus read_failure() const noexcept {
        return input_.io_failed() ? TiffDeflateValidationStatus::io_error
                                  : TiffDeflateValidationStatus::invalid_stream;
    }

    [[nodiscard]] bool append_byte(const std::uint8_t byte) noexcept {
        if (decoded_bytes_ >= expected_decoded_bytes_) {
            return false;
        }
        if ((decoded_bytes_ & 0xfffU) == 0U && stop_token_.stop_requested()) {
            cancelled_ = true;
            return false;
        }
        window_[static_cast<std::size_t>(decoded_bytes_ & (window_bytes - 1U))] = byte;
        ++decoded_bytes_;
        adler_first_ += byte;
        if (adler_first_ >= adler_modulus) {
            adler_first_ -= adler_modulus;
        }
        adler_second_ += adler_first_;
        if (adler_second_ >= adler_modulus) {
            adler_second_ -= adler_modulus;
        }
        return true;
    }

    [[nodiscard]] TiffDeflateValidationStatus append_failure() const noexcept {
        return cancelled_ ? TiffDeflateValidationStatus::cancelled
                          : TiffDeflateValidationStatus::invalid_stream;
    }

    [[nodiscard]] TiffDeflateValidationStatus decode_stored_block() noexcept {
        input_.align_to_byte();
        std::uint32_t length = 0U;
        std::uint32_t complement = 0U;
        if (!input_.read_bits(16U, length) || !input_.read_bits(16U, complement)) {
            return read_failure();
        }
        if ((length ^ 0xffffU) != complement) {
            return TiffDeflateValidationStatus::invalid_stream;
        }
        for (std::uint32_t index = 0U; index < length; ++index) {
            std::uint32_t byte = 0U;
            if (!input_.read_bits(8U, byte)) {
                return read_failure();
            }
            if (!append_byte(static_cast<std::uint8_t>(byte))) {
                return append_failure();
            }
        }
        return TiffDeflateValidationStatus::ok;
    }

    [[nodiscard]] TiffDeflateValidationStatus decode_fixed_block() noexcept {
        std::array<std::uint8_t, 288> literal_lengths{};
        for (std::size_t symbol = 0U; symbol <= 143U; ++symbol) {
            literal_lengths[symbol] = 8U;
        }
        for (std::size_t symbol = 144U; symbol <= 255U; ++symbol) {
            literal_lengths[symbol] = 9U;
        }
        for (std::size_t symbol = 256U; symbol <= 279U; ++symbol) {
            literal_lengths[symbol] = 7U;
        }
        for (std::size_t symbol = 280U; symbol <= 287U; ++symbol) {
            literal_lengths[symbol] = 8U;
        }
        std::array<std::uint8_t, 32> distance_lengths{};
        distance_lengths.fill(5U);
        HuffmanTable literals{};
        HuffmanTable distances{};
        if (!build_huffman_table(literal_lengths.data(), literal_lengths.size(), literals) ||
            !build_huffman_table(distance_lengths.data(), distance_lengths.size(), distances)) {
            return TiffDeflateValidationStatus::invalid_stream;
        }
        return decode_huffman_block(literals, distances);
    }

    [[nodiscard]] TiffDeflateValidationStatus decode_dynamic_block() noexcept {
        std::uint32_t hlit_bits = 0U;
        std::uint32_t hdist_bits = 0U;
        std::uint32_t hclen_bits = 0U;
        if (!input_.read_bits(5U, hlit_bits) || !input_.read_bits(5U, hdist_bits) ||
            !input_.read_bits(4U, hclen_bits)) {
            return read_failure();
        }
        const std::size_t literal_count = hlit_bits + 257U;
        const std::size_t distance_count = hdist_bits + 1U;
        const std::size_t code_length_count = hclen_bits + 4U;
        if (literal_count > 286U || distance_count > 32U) {
            return TiffDeflateValidationStatus::invalid_stream;
        }

        constexpr std::array<std::uint8_t, 19> code_length_order{
            16U, 17U, 18U, 0U, 8U, 7U, 9U, 6U, 10U, 5U,
            11U, 4U, 12U, 3U, 13U, 2U, 14U, 1U, 15U,
        };
        std::array<std::uint8_t, 19> code_length_lengths{};
        for (std::size_t index = 0U; index < code_length_count; ++index) {
            std::uint32_t length = 0U;
            if (!input_.read_bits(3U, length)) {
                return read_failure();
            }
            code_length_lengths[code_length_order[index]] = static_cast<std::uint8_t>(length);
        }
        HuffmanTable code_lengths{};
        if (!build_huffman_table(
                code_length_lengths.data(), code_length_lengths.size(), code_lengths)) {
            return TiffDeflateValidationStatus::invalid_stream;
        }

        std::array<std::uint8_t, 318> lengths{};
        const std::size_t total = literal_count + distance_count;
        std::size_t written = 0U;
        while (written < total) {
            std::uint16_t symbol = 0U;
            if (!decode_symbol(input_, code_lengths, symbol)) {
                return read_failure();
            }
            if (symbol <= 15U) {
                lengths[written++] = static_cast<std::uint8_t>(symbol);
                continue;
            }
            std::uint32_t extra = 0U;
            std::size_t repeat = 0U;
            std::uint8_t value = 0U;
            if (symbol == 16U) {
                if (written == 0U || !input_.read_bits(2U, extra)) {
                    return input_.io_failed() ? read_failure()
                                              : TiffDeflateValidationStatus::invalid_stream;
                }
                repeat = extra + 3U;
                value = lengths[written - 1U];
            } else if (symbol == 17U) {
                if (!input_.read_bits(3U, extra)) {
                    return read_failure();
                }
                repeat = extra + 3U;
            } else if (symbol == 18U) {
                if (!input_.read_bits(7U, extra)) {
                    return read_failure();
                }
                repeat = extra + 11U;
            } else {
                return TiffDeflateValidationStatus::invalid_stream;
            }
            if (repeat > total - written) {
                return TiffDeflateValidationStatus::invalid_stream;
            }
            std::fill_n(lengths.begin() + static_cast<std::ptrdiff_t>(written), repeat, value);
            written += repeat;
        }
        if (lengths[256U] == 0U) {
            return TiffDeflateValidationStatus::invalid_stream;
        }

        HuffmanTable literals{};
        HuffmanTable distances{};
        if (!build_huffman_table(lengths.data(), literal_count, literals) ||
            !build_huffman_table(lengths.data() + literal_count, distance_count, distances)) {
            return TiffDeflateValidationStatus::invalid_stream;
        }
        return decode_huffman_block(literals, distances);
    }

    [[nodiscard]] TiffDeflateValidationStatus decode_huffman_block(
        const HuffmanTable& literals,
        const HuffmanTable& distances) noexcept {
        constexpr std::array<std::uint16_t, 29> length_bases{
            3U, 4U, 5U, 6U, 7U, 8U, 9U, 10U, 11U, 13U,
            15U, 17U, 19U, 23U, 27U, 31U, 35U, 43U, 51U, 59U,
            67U, 83U, 99U, 115U, 131U, 163U, 195U, 227U, 258U,
        };
        constexpr std::array<std::uint8_t, 29> length_extras{
            0U, 0U, 0U, 0U, 0U, 0U, 0U, 0U, 1U, 1U,
            1U, 1U, 2U, 2U, 2U, 2U, 3U, 3U, 3U, 3U,
            4U, 4U, 4U, 4U, 5U, 5U, 5U, 5U, 0U,
        };
        constexpr std::array<std::uint16_t, 30> distance_bases{
            1U, 2U, 3U, 4U, 5U, 7U, 9U, 13U, 17U, 25U,
            33U, 49U, 65U, 97U, 129U, 193U, 257U, 385U, 513U, 769U,
            1025U, 1537U, 2049U, 3073U, 4097U, 6145U, 8193U, 12289U,
            16385U, 24577U,
        };
        constexpr std::array<std::uint8_t, 30> distance_extras{
            0U, 0U, 0U, 0U, 1U, 1U, 2U, 2U, 3U, 3U,
            4U, 4U, 5U, 5U, 6U, 6U, 7U, 7U, 8U, 8U,
            9U, 9U, 10U, 10U, 11U, 11U, 12U, 12U, 13U, 13U,
        };

        while (true) {
            std::uint16_t symbol = 0U;
            if (!decode_symbol(input_, literals, symbol)) {
                return read_failure();
            }
            if (symbol < 256U) {
                if (!append_byte(static_cast<std::uint8_t>(symbol))) {
                    return append_failure();
                }
                continue;
            }
            if (symbol == 256U) {
                return TiffDeflateValidationStatus::ok;
            }
            if (symbol < 257U || symbol > 285U) {
                return TiffDeflateValidationStatus::invalid_stream;
            }

            const std::size_t length_index = symbol - 257U;
            std::uint32_t length_extra = 0U;
            if (!input_.read_bits(length_extras[length_index], length_extra)) {
                return read_failure();
            }
            const std::uint32_t length = length_bases[length_index] + length_extra;

            std::uint16_t distance_symbol = 0U;
            if (!decode_symbol(input_, distances, distance_symbol)) {
                return read_failure();
            }
            if (distance_symbol >= distance_bases.size()) {
                return TiffDeflateValidationStatus::invalid_stream;
            }
            std::uint32_t distance_extra = 0U;
            if (!input_.read_bits(distance_extras[distance_symbol], distance_extra)) {
                return read_failure();
            }
            const std::uint32_t distance = distance_bases[distance_symbol] + distance_extra;
            if (distance == 0U || distance > window_limit_ || distance > decoded_bytes_) {
                return TiffDeflateValidationStatus::invalid_stream;
            }
            for (std::uint32_t index = 0U; index < length; ++index) {
                const std::uint8_t byte = window_[static_cast<std::size_t>(
                    (decoded_bytes_ - distance) & (window_bytes - 1U))];
                if (!append_byte(byte)) {
                    return append_failure();
                }
            }
        }
    }

    LsbBitReader& input_;
    std::uint64_t expected_decoded_bytes_{0};
    std::stop_token stop_token_{};
    std::array<std::uint8_t, window_bytes> window_{};
    std::uint64_t decoded_bytes_{0};
    std::uint32_t adler_first_{1U};
    std::uint32_t adler_second_{0U};
    std::uint32_t window_limit_{window_bytes};
    bool cancelled_{false};
};

}  // namespace

TiffDeflateValidationResult validate_tiff_deflate_segment(
    const TiffRandomAccessReader& reader,
    const std::uint64_t offset,
    const std::uint64_t compressed_bytes,
    const std::uint64_t expected_decoded_bytes,
    const std::stop_token stop_token) noexcept {
    LsbBitReader input{reader, offset, compressed_bytes};
    DeflateValidator validator{input, expected_decoded_bytes, stop_token};
    const TiffDeflateValidationStatus status = validator.run();
    return {status, input.bytes_read(), validator.decoded_bytes()};
}

}  // namespace negaflow::core::detail
