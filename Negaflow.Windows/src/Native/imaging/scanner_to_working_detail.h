#pragma once

#include "negaflow/imaging/scanner_to_working.h"

#include <cstdint>
#include <span>
#include <vector>

namespace negaflow::imaging::detail {

struct EncodedSrgb16Result final {
    ScannerToWorkingStatus status{ScannerToWorkingStatus::invalid_argument};
    std::uint32_t native_error_code{0};
    std::vector<std::uint16_t> samples{};
};

[[nodiscard]] ScannerToWorkingStatus validate_scanner_icc_profile(
    std::span<const std::uint8_t> profile_bytes,
    const ScannerToWorkingLimits& limits,
    negaflow::color::IccProfileStatus& icc_status,
    ScannerToWorkingInfo& info) noexcept;

[[nodiscard]] ScannerToWorkingStatus convert_linear_scanner_raw(
    const negaflow::imageio::DecodedImage& decoded,
    WorkingImage& output);

[[nodiscard]] EncodedSrgb16Result convert_embedded_icc_to_srgb16(
    const negaflow::imageio::DecodedImage& decoded,
    const ScannerToWorkingLimits& limits) noexcept;

}  // namespace negaflow::imaging::detail
