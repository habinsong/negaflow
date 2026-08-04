#include "tiff_lzw_validator.h"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <limits>

namespace negaflow::core::detail {
namespace {

constexpr std::uint16_t clear_code = 256U;
constexpr std::uint16_t end_of_information_code = 257U;
constexpr std::uint16_t first_dictionary_code = 258U;
constexpr std::uint16_t last_dictionary_code = 4094U;
constexpr std::size_t input_buffer_bytes = 16U * 1024U;

class MsbBitReader final {
public:
    MsbBitReader(
        const TiffRandomAccessReader& reader,
        const std::uint64_t offset,
        const std::uint64_t byte_count) noexcept
        : reader_(reader), offset_(offset), byte_count_(byte_count) {}

    [[nodiscard]] bool read_code(
        const std::uint8_t width,
        std::uint16_t& code) noexcept {
        while (pending_bit_count_ < width) {
            std::uint8_t byte = 0U;
            if (!read_byte(byte)) {
                return false;
            }
            pending_bits_ = (pending_bits_ << 8U) | byte;
            pending_bit_count_ += 8U;
        }

        const std::uint8_t remaining_bits =
            static_cast<std::uint8_t>(pending_bit_count_ - width);
        code = static_cast<std::uint16_t>(
            (pending_bits_ >> remaining_bits) & ((1U << width) - 1U));
        pending_bit_count_ = remaining_bits;
        pending_bits_ = remaining_bits == 0U
                            ? 0U
                            : pending_bits_ & ((1U << remaining_bits) - 1U);
        return true;
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
        return consumed_bytes == byte_count_;
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
    std::uint32_t pending_bits_{0};
    std::uint8_t pending_bit_count_{0};
    bool io_failed_{false};
};

[[nodiscard]] bool checked_add(
    const std::uint64_t left,
    const std::uint64_t right,
    std::uint64_t& result) noexcept {
    if (right > std::numeric_limits<std::uint64_t>::max() - left) {
        return false;
    }
    result = left + right;
    return true;
}

[[nodiscard]] bool append_decoded_bytes(
    const std::uint64_t amount,
    const std::uint64_t expected,
    std::uint64_t& decoded) noexcept {
    return checked_add(decoded, amount, decoded) && decoded <= expected;
}

[[nodiscard]] TiffLzwValidationResult finish(
    const TiffLzwValidationStatus status,
    const MsbBitReader& reader,
    const std::uint64_t code_count,
    const std::uint64_t decoded_bytes) noexcept {
    return {status, reader.bytes_read(), code_count, decoded_bytes};
}

}  // namespace

TiffLzwValidationResult validate_tiff_lzw_segment(
    const TiffRandomAccessReader& reader,
    const std::uint64_t offset,
    const std::uint64_t compressed_bytes,
    const std::uint64_t expected_decoded_bytes,
    const std::stop_token stop_token) noexcept {
    MsbBitReader input{reader, offset, compressed_bytes};
    std::array<std::uint64_t, 4096> dictionary_lengths{};
    std::uint64_t decoded_bytes = 0U;
    std::uint64_t code_count = 0U;
    std::uint16_t next_dictionary_code = first_dictionary_code;
    std::uint64_t previous_length = 0U;
    std::uint8_t code_width = 9U;

    const auto read_code = [&](std::uint16_t& code) noexcept {
        if ((code_count & 0xfffU) == 0U && stop_token.stop_requested()) {
            return TiffLzwValidationStatus::cancelled;
        }
        if (!input.read_code(code_width, code)) {
            return input.io_failed() ? TiffLzwValidationStatus::io_error
                                     : TiffLzwValidationStatus::invalid_code_stream;
        }
        ++code_count;
        return TiffLzwValidationStatus::ok;
    };
    const auto finish_after_eoi = [&]() noexcept {
        const bool valid =
            decoded_bytes == expected_decoded_bytes && input.has_no_trailing_bytes();
        return finish(
            valid ? TiffLzwValidationStatus::ok
                  : TiffLzwValidationStatus::invalid_code_stream,
            input,
            code_count,
            decoded_bytes);
    };

    std::uint16_t code = 0U;
    TiffLzwValidationStatus status = read_code(code);
    if (status != TiffLzwValidationStatus::ok || code != clear_code) {
        return finish(
            status == TiffLzwValidationStatus::ok
                ? TiffLzwValidationStatus::invalid_code_stream
                : status,
            input,
            code_count,
            decoded_bytes);
    }

    while (true) {
        status = read_code(code);
        if (status != TiffLzwValidationStatus::ok) {
            return finish(status, input, code_count, decoded_bytes);
        }
        if (code == end_of_information_code) {
            return finish_after_eoi();
        }
        if (code == clear_code) {
            return finish(
                TiffLzwValidationStatus::invalid_code_stream,
                input,
                code_count,
                decoded_bytes);
        }
        if (code > 255U || !append_decoded_bytes(1U, expected_decoded_bytes, decoded_bytes)) {
            return finish(
                TiffLzwValidationStatus::invalid_code_stream,
                input,
                code_count,
                decoded_bytes);
        }
        previous_length = 1U;
        break;
    }

    while (true) {
        status = read_code(code);
        if (status != TiffLzwValidationStatus::ok) {
            return finish(status, input, code_count, decoded_bytes);
        }
        if (code == end_of_information_code) {
            return finish_after_eoi();
        }
        if (code == clear_code) {
            code_width = 9U;
            next_dictionary_code = first_dictionary_code;
            status = read_code(code);
            if (status != TiffLzwValidationStatus::ok) {
                return finish(status, input, code_count, decoded_bytes);
            }
            if (code == end_of_information_code) {
                return finish_after_eoi();
            }
            if (code > 255U ||
                !append_decoded_bytes(1U, expected_decoded_bytes, decoded_bytes)) {
                return finish(
                    TiffLzwValidationStatus::invalid_code_stream,
                    input,
                    code_count,
                    decoded_bytes);
            }
            previous_length = 1U;
            continue;
        }
        if (next_dictionary_code > last_dictionary_code) {
            return finish(
                TiffLzwValidationStatus::invalid_code_stream,
                input,
                code_count,
                decoded_bytes);
        }

        std::uint64_t current_length = 0U;
        if (code <= 255U) {
            current_length = 1U;
        } else if (code < next_dictionary_code) {
            current_length = dictionary_lengths[code];
        } else if (code == next_dictionary_code) {
            if (!checked_add(previous_length, 1U, current_length)) {
                return finish(
                    TiffLzwValidationStatus::invalid_code_stream,
                    input,
                    code_count,
                    decoded_bytes);
            }
        } else {
            return finish(
                TiffLzwValidationStatus::invalid_code_stream,
                input,
                code_count,
                decoded_bytes);
        }
        if (current_length == 0U ||
            !append_decoded_bytes(current_length, expected_decoded_bytes, decoded_bytes)) {
            return finish(
                TiffLzwValidationStatus::invalid_code_stream,
                input,
                code_count,
                decoded_bytes);
        }

        std::uint64_t dictionary_length = 0U;
        if (!checked_add(previous_length, 1U, dictionary_length)) {
            return finish(
                TiffLzwValidationStatus::invalid_code_stream,
                input,
                code_count,
                decoded_bytes);
        }
        dictionary_lengths[next_dictionary_code] = dictionary_length;
        ++next_dictionary_code;
        if (next_dictionary_code == 511U) {
            code_width = 10U;
        } else if (next_dictionary_code == 1023U) {
            code_width = 11U;
        } else if (next_dictionary_code == 2047U) {
            code_width = 12U;
        }
        previous_length = current_length;
    }
}

}  // namespace negaflow::core::detail
