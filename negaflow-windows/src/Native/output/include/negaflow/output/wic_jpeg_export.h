#pragma once

#include "negaflow/output/working_to_srgb16.h"

#include <cstdint>
#include <filesystem>

namespace negaflow::output {

// JPEG is intentionally a separate writer from the lossless 16-bit writers: it
// quantizes only at the output boundary and keeps the opaque/sRGB contract explicit.
enum class WicJpegExportStatus : std::uint8_t {
    ok = 0,
    invalid_quality,
    working_conversion_failed,
    allocation_failed,
    com_apartment_mismatch,
    wic_unavailable,
    destination_profile_unavailable,
    destination_profile_invalid,
    destination_exists,
    staging_create_failed,
    encoder_initialization_failed,
    unexpected_encoder,
    pixel_format_coerced,
    resolution_configuration_failed,
    encode_failed,
    flush_failed,
    structure_verification_failed,
    decoder_initialization_failed,
    unexpected_decoder,
    readback_failed,
    profile_verification_failed,
    resolution_verification_failed,
    publish_failed,
    published_file_invalid,
};

struct WicJpegExportLimits final {
    WorkingToSrgb16Limits conversion{};
    std::uint64_t max_artifact_bytes{2ULL * 1024ULL * 1024ULL * 1024ULL};
    std::uint32_t max_color_profile_bytes{4U * 1024U * 1024U};
};

struct WicJpegExportInfo final {
    std::uint32_t width{0};
    std::uint32_t height{0};
    std::uint64_t encoded_pixel_bytes{0};
    std::uint64_t clipped_color_components{0};
    std::uint64_t artifact_bytes{0};
    std::uint32_t color_profile_bytes{0};
    float quality{1.0F};
    std::uint32_t dpi{0};
    std::uint8_t chroma_subsampling{0};
    bool structure_verified{false};
    bool profile_verified{false};
    bool resolution_verified{false};
    bool published{false};
};

struct WicJpegExportResult final {
    WicJpegExportStatus status{WicJpegExportStatus::working_conversion_failed};
    WorkingToSrgb16Status conversion_status{WorkingToSrgb16Status::invalid_dimensions};
    WicJpegExportInfo info{};
    std::uint32_t native_error_code{0};
    std::uint32_t cleanup_error_code{0};
};

// Quality uses the macOS-visible normalized 0...1 range. dpi zero deliberately
// leaves resolution unspecified, while a positive value is embedded and read back.
[[nodiscard]] WicJpegExportResult export_working_to_srgb8_jpeg(
    const negaflow::imaging::WorkingImage& working,
    const std::filesystem::path& destination,
    float quality = 1.0F,
    std::uint32_t dpi = 0U,
    const WicJpegExportLimits& limits = {}) noexcept;

[[nodiscard]] const char* wic_jpeg_export_status_name(
    WicJpegExportStatus status) noexcept;

}  // namespace negaflow::output
