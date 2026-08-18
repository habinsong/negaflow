#pragma once

/* Deflate 스트림을 읽는 최소 단위: LSB 우선 비트 읽기와 허프만 코드 표입니다.
   블록 해석은 tiff_deflate_validator.cpp 가 소유합니다. */

#include "tiff_deflate_validator.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <limits>

namespace negaflow::core::detail {

// 압축 스트림을 이만큼씩 읽어 옵니다.
inline constexpr std::size_t input_buffer_bytes = 16U * 1024U;

// Deflate 가 정한 되돌아보기 창 크기입니다.
inline constexpr std::size_t window_bytes = 32U * 1024U;

// zlib Adler-32 의 법입니다.
inline constexpr std::uint32_t adler_modulus = 65'521U;

class LsbBitReader final {
public:
    LsbBitReader(
        const TiffRandomAccessReader& reader,
        const std::uint64_t offset,
        const std::uint64_t byte_count) noexcept
        : reader_(reader), offset_(offset), byte_count_(byte_count) {}

    [[nodiscard]] bool read_bits(const std::uint8_t count, std::uint32_t& value) noexcept {
        if (count > 24U) {
            return false;
        }
        while (pending_bit_count_ < count) {
            std::uint8_t byte = 0U;
            if (!read_byte(byte)) {
                return false;
            }
            pending_bits_ |= static_cast<std::uint64_t>(byte) << pending_bit_count_;
            pending_bit_count_ = static_cast<std::uint8_t>(pending_bit_count_ + 8U);
        }
        const std::uint64_t mask = count == 0U ? 0U : ((1ULL << count) - 1ULL);
        value = static_cast<std::uint32_t>(pending_bits_ & mask);
        pending_bits_ >>= count;
        pending_bit_count_ = static_cast<std::uint8_t>(pending_bit_count_ - count);
        return true;
    }

    void align_to_byte() noexcept {
        const std::uint8_t discarded = static_cast<std::uint8_t>(pending_bit_count_ & 7U);
        pending_bits_ >>= discarded;
        pending_bit_count_ = static_cast<std::uint8_t>(pending_bit_count_ - discarded);
    }

    [[nodiscard]] bool io_failed() const noexcept {
        return io_failed_;
    }

    [[nodiscard]] std::uint64_t bytes_read() const noexcept {
        return bytes_read_;
    }

    [[nodiscard]] bool has_no_trailing_bytes() const noexcept {
        const std::uint64_t buffered_start =
            bytes_read_ - static_cast<std::uint64_t>(buffer_size_);
        const std::uint64_t consumed_bytes =
            buffered_start + static_cast<std::uint64_t>(buffer_position_);
        return pending_bit_count_ == 0U && consumed_bytes == byte_count_;
    }

private:
    [[nodiscard]] bool read_byte(std::uint8_t& byte) noexcept {
        if (buffer_position_ == buffer_size_ && !refill()) {
            return false;
        }
        byte = buffer_[buffer_position_++];
        return true;
    }

    [[nodiscard]] bool refill() noexcept {
        if (bytes_read_ == byte_count_) {
            return false;
        }
        const std::size_t requested = static_cast<std::size_t>(std::min(
            static_cast<std::uint64_t>(buffer_.size()),
            byte_count_ - bytes_read_));
        if (!reader_.read(offset_ + bytes_read_, buffer_.data(), requested)) {
            io_failed_ = true;
            return false;
        }
        bytes_read_ += requested;
        buffer_position_ = 0U;
        buffer_size_ = requested;
        return true;
    }

    const TiffRandomAccessReader& reader_;
    std::uint64_t offset_{0};
    std::uint64_t byte_count_{0};
    std::uint64_t bytes_read_{0};
    std::array<std::uint8_t, input_buffer_bytes> buffer_{};
    std::size_t buffer_position_{0};
    std::size_t buffer_size_{0};
    std::uint64_t pending_bits_{0};
    std::uint8_t pending_bit_count_{0};
    bool io_failed_{false};
};

struct HuffmanTable final {
    std::array<std::uint16_t, 16> counts{};
    std::array<std::uint16_t, 16> first_codes{};
    std::array<std::uint16_t, 16> first_symbols{};
    std::array<std::uint16_t, 288> symbols{};
    std::uint8_t maximum_length{0};
};

[[nodiscard]] bool build_huffman_table(
    const std::uint8_t* const lengths,
    const std::size_t length_count,
    HuffmanTable& table) noexcept {
    if (lengths == nullptr || length_count == 0U || length_count > table.symbols.size()) {
        return false;
    }
    table = {};
    for (std::size_t symbol = 0U; symbol < length_count; ++symbol) {
        const std::uint8_t length = lengths[symbol];
        if (length > 15U) {
            return false;
        }
        if (length != 0U) {
            ++table.counts[length];
            table.maximum_length = std::max(table.maximum_length, length);
        }
    }
    if (table.maximum_length == 0U) {
        return false;
    }

    std::int32_t available = 1;
    for (std::uint8_t length = 1U; length <= 15U; ++length) {
        available = (available << 1) - table.counts[length];
        if (available < 0) {
            return false;
        }
    }

    std::uint16_t code = 0U;
    std::uint16_t symbol_offset = 0U;
    for (std::uint8_t length = 1U; length <= 15U; ++length) {
        code = static_cast<std::uint16_t>(
            (code + table.counts[length - 1U]) << 1U);
        table.first_codes[length] = code;
        table.first_symbols[length] = symbol_offset;
        symbol_offset = static_cast<std::uint16_t>(symbol_offset + table.counts[length]);
    }

    std::array<std::uint16_t, 16> write_offsets = table.first_symbols;
    for (std::uint16_t symbol = 0U; symbol < length_count; ++symbol) {
        const std::uint8_t length = lengths[symbol];
        if (length != 0U) {
            table.symbols[write_offsets[length]++] = symbol;
        }
    }
    return true;
}

[[nodiscard]] bool decode_symbol(
    LsbBitReader& input,
    const HuffmanTable& table,
    std::uint16_t& symbol) noexcept {
    std::uint16_t code = 0U;
    for (std::uint8_t length = 1U; length <= table.maximum_length; ++length) {
        std::uint32_t bit = 0U;
        if (!input.read_bits(1U, bit)) {
            return false;
        }
        code = static_cast<std::uint16_t>((code << 1U) | bit);
        const std::uint16_t first = table.first_codes[length];
        const std::uint16_t count = table.counts[length];
        if (code >= first && static_cast<std::uint32_t>(code - first) < count) {
            symbol = table.symbols[
                table.first_symbols[length] + static_cast<std::uint16_t>(code - first)];
            return true;
        }
    }
    return false;
}

}  // namespace negaflow::core::detail
