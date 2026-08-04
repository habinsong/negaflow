#pragma once

#include "negaflow/core/tiff_probe.h"

#include <cstdint>
#include <stop_token>

namespace negaflow::core::detail {

enum class TiffLzwValidationStatus : std::uint8_t {
    ok = 0,
    io_error,
    invalid_code_stream,
    cancelled,
};

struct TiffLzwValidationResult final {
    TiffLzwValidationStatus status{TiffLzwValidationStatus::invalid_code_stream};
    std::uint64_t compressed_bytes_read{0};
    std::uint64_t code_count{0};
    std::uint64_t decoded_bytes{0};
};

[[nodiscard]] TiffLzwValidationResult validate_tiff_lzw_segment(
    const TiffRandomAccessReader& reader,
    std::uint64_t offset,
    std::uint64_t compressed_bytes,
    std::uint64_t expected_decoded_bytes,
    std::stop_token stop_token) noexcept;

}  // namespace negaflow::core::detail
