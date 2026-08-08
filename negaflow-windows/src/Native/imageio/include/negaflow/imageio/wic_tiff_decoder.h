#pragma once

#include "negaflow/color/icc_profile.h"
#include "negaflow/core/tiff_probe.h"
#include "negaflow/imageio/decoded_image.h"

#include <cstdint>
#include <filesystem>
#include <span>
#include <stop_token>

namespace negaflow::imageio {

enum class WicPixelFormat : std::uint8_t {
    unknown = 0,
    rgb16,
    rgba16,
    prgba16,
    bgra16,
    pbgra16,
};

enum class WicTiffDecodeStatus : std::uint8_t {
    ok = 0,
    invalid_argument,
    preflight_failed,
    unsupported_layout,
    com_apartment_mismatch,
    wic_unavailable,
    stream_open_failed,
    decoder_initialization_failed,
    unexpected_decoder,
    frame_count_unsupported,
    dimension_mismatch,
    unsupported_pixel_format,
    color_context_failed,
    invalid_icc_profile,
    memory_limit_exceeded,
    allocation_failed,
    pixel_decode_failed,
    row_sink_failed,
    cancelled,
};

struct WicTiffDecodeProgress final {
    std::uint32_t completed_rows{0};
    std::uint32_t total_rows{0};
};

class WicTiffDecodeProgressObserver {
public:
    WicTiffDecodeProgressObserver() noexcept = default;
    WicTiffDecodeProgressObserver(const WicTiffDecodeProgressObserver&) = delete;
    WicTiffDecodeProgressObserver& operator=(const WicTiffDecodeProgressObserver&) = delete;
    virtual ~WicTiffDecodeProgressObserver() = default;

    virtual void report(WicTiffDecodeProgress progress) noexcept = 0;
};

struct WicTiffDecodeControl final {
    // Zero keeps the legacy whole-frame CopyPixels call when its buffer fits UINT.
    // A positive value creates explicit cooperative row boundaries.
    std::uint32_t rows_per_copy{0};
    std::stop_token stop_token{};
    WicTiffDecodeProgressObserver* progress_observer{nullptr};
};

struct WicTiffFrameView final {
    std::uint32_t width{0};
    std::uint32_t height{0};
    std::uint32_t stride_bytes{0};
    DecodedPixelLayout layout{DecodedPixelLayout::rgb16};
    AlphaMode alpha_mode{AlphaMode::opaque};
    std::span<const std::uint8_t> icc_profile{};
};

struct WicTiffRowChunk final {
    std::uint32_t first_row{0};
    std::uint32_t row_count{0};
    std::uint32_t stride_bytes{0};
    std::span<const std::uint16_t> samples{};
};

class WicTiffRowSink {
public:
    WicTiffRowSink() noexcept = default;
    WicTiffRowSink(const WicTiffRowSink&) = delete;
    WicTiffRowSink& operator=(const WicTiffRowSink&) = delete;
    virtual ~WicTiffRowSink() = default;

    // Views are valid only for the duration of the callback. complete() is called exactly
    // once after begin(), including cancellation and failure paths.
    [[nodiscard]] virtual bool begin(const WicTiffFrameView& frame) noexcept = 0;
    [[nodiscard]] virtual bool write(const WicTiffRowChunk& rows) noexcept = 0;
    virtual void complete(WicTiffDecodeStatus status) noexcept = 0;
};

struct WicTiffDecodeLimits final {
    negaflow::core::TiffProbeLimits probe{};
    negaflow::color::IccProfileLimits icc{};
    std::uint64_t max_decoded_pixel_bytes{512ULL * 1024ULL * 1024ULL};
    std::uint32_t max_color_contexts{4U};
};

struct WicTiffDecodeInfo final {
    WicPixelFormat source_pixel_format{WicPixelFormat::unknown};
    WicPixelFormat output_pixel_format{WicPixelFormat::unknown};
    bool format_conversion_used{false};
    std::uint32_t frame_count{0};
    std::uint64_t decoded_pixel_bytes{0};
    std::uint64_t compressed_segment_bytes{0};
    std::uint64_t compressed_bytes_validated{0};
    std::uint64_t lzw_code_count{0};
    std::uint64_t lzw_decoded_bytes_validated{0};
    std::uint64_t peak_copy_pixel_bytes{0};
    std::uint32_t copy_operation_count{0};
    std::uint32_t completed_rows{0};
    bool lzw_code_streams_validated{false};
    negaflow::color::IccProfileInfo icc{};
};

struct WicTiffDecodeResult final {
    WicTiffDecodeStatus status{WicTiffDecodeStatus::invalid_argument};
    negaflow::core::TiffProbeStatus preflight_status{
        negaflow::core::TiffProbeStatus::io_error};
    negaflow::color::IccProfileStatus icc_status{
        negaflow::color::IccProfileStatus::not_present};
    WicTiffDecodeInfo info{};
    DecodedImage image{};
};

[[nodiscard]] WicTiffDecodeResult decode_tiff_with_wic(
    const std::filesystem::path& path,
    const WicTiffDecodeLimits& limits = {},
    const WicTiffDecodeControl& control = {}) noexcept;

// rows_per_copy must be positive. The returned image retains descriptor/ICC metadata but no
// pixel samples; the sink owns any staging and publishes only after complete(ok).
[[nodiscard]] WicTiffDecodeResult decode_tiff_rows_with_wic(
    const std::filesystem::path& path,
    WicTiffRowSink& sink,
    const WicTiffDecodeLimits& limits,
    const WicTiffDecodeControl& control) noexcept;

[[nodiscard]] const char* wic_tiff_decode_status_name(WicTiffDecodeStatus status) noexcept;
[[nodiscard]] const char* wic_pixel_format_name(WicPixelFormat format) noexcept;

}  // namespace negaflow::imageio
