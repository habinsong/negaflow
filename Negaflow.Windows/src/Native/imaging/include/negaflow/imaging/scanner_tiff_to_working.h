#pragma once

#include "negaflow/imageio/wic_tiff_decoder.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <cstdint>
#include <filesystem>

namespace negaflow::imaging {

struct StreamedScannerToWorkingInfo final {
    std::uint64_t peak_conversion_temporary_pixel_bytes{0};
};

struct StreamedScannerToWorkingResult final {
    negaflow::imageio::WicTiffDecodeResult decode{};
    ScannerToWorkingResult working{};
    StreamedScannerToWorkingInfo info{};
};

// control.rows_per_copy must be positive. The WIC decoder retains no full decoded sample
// buffer; this v1 bridge still owns the final float32 WorkingImage.
[[nodiscard]] StreamedScannerToWorkingResult decode_scanner_tiff_to_working_rows(
    const std::filesystem::path& path,
    const negaflow::imageio::WicTiffDecodeLimits& decode_limits,
    const ScannerToWorkingLimits& working_limits,
    const negaflow::imageio::WicTiffDecodeControl& control) noexcept;

}  // namespace negaflow::imaging
