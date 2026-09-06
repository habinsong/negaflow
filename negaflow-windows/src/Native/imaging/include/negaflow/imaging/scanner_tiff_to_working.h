#pragma once

#include "negaflow/imageio/wic_tiff_decoder.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <cstdint>
#include <filesystem>

namespace negaflow::imaging {
struct InputGammaSourceInfo final {
    bool supported{false};
    // 0: 미확인, 1: 내장 power, 2: 내장 복합 곡선, 3: 선형 기본값, 4: sRGB 기본값, 5: 추정
    std::uint32_t curve{0U};
    double gamma{0.0};
    double evidence{0.0};
    std::uint32_t edge_count{0U};
};
[[nodiscard]] InputGammaSourceInfo inspect_input_gamma_source(const std::filesystem::path& path) noexcept;
[[nodiscard]] negaflow::color::InputGammaInterpretation resolve_input_gamma_source(
    const std::filesystem::path& path, negaflow::color::InputGammaInterpretation requested) noexcept;
[[nodiscard]] bool is_input_gamma_source_supported(const std::filesystem::path& path) noexcept;
[[nodiscard]] bool supports_input_gamma_layout(const negaflow::core::TiffProbeInfo& info) noexcept;

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
    const negaflow::imageio::WicTiffDecodeControl& control,
    negaflow::color::InputGammaInterpretation input_gamma = {}) noexcept;

}  // namespace negaflow::imaging
