#pragma once

#include "negaflow/output/working_to_srgb16.h"

#include <cstdint>
#include <filesystem>

namespace negaflow::output {

enum class WicPngExportStatus : std::uint8_t {
    ok = 0,
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
    encode_failed,
    flush_failed,
    structure_verification_failed,
    decoder_initialization_failed,
    unexpected_decoder,
    readback_failed,
    pixel_verification_failed,
    profile_verification_failed,
    publish_failed,
    published_file_invalid,
};

struct WicPngExportLimits final {
    WorkingToSrgb16Limits conversion{};
    // 8 or 16. Eight-bit output is dithered before quantization; sixteen is not.
    std::uint32_t bits_per_sample{16U};
    // Zero leaves the container's resolution unspecified; a positive value is metadata only.
    std::uint32_t output_dpi{0U};
    std::uint64_t max_artifact_bytes{2ULL * 1024ULL * 1024ULL * 1024ULL};
    std::uint32_t max_color_profile_bytes{4U * 1024U * 1024U};
    std::uint32_t write_buffer_bytes{16U * 1024U * 1024U};
    std::uint32_t readback_buffer_bytes{16U * 1024U * 1024U};
};

struct WicPngExportInfo final {
    std::uint32_t width{0};
    std::uint32_t height{0};
    std::uint64_t encoded_pixel_bytes{0};
    std::uint64_t clipped_color_components{0};
    std::uint64_t artifact_bytes{0};
    std::uint32_t color_profile_bytes{0};
    std::uint32_t image_data_chunks{0};
    std::uint32_t output_dpi{0};
    bool structure_verified{false};
    bool pixels_verified{false};
    bool profile_verified{false};
    bool resolution_verified{false};
    bool published{false};
};

struct WicPngExportResult final {
    WicPngExportStatus status{WicPngExportStatus::working_conversion_failed};
    WorkingToSrgb16Status conversion_status{WorkingToSrgb16Status::invalid_dimensions};
    WicPngExportInfo info{};
    std::uint32_t native_error_code{0};
    std::uint32_t cleanup_error_code{0};
};

[[nodiscard]] WicPngExportResult export_working_to_srgb16_png(
    const negaflow::imaging::WorkingImage& working,
    const std::filesystem::path& destination,
    const WicPngExportLimits& limits = {}) noexcept;

[[nodiscard]] const char* wic_png_export_status_name(WicPngExportStatus status) noexcept;

}  // namespace negaflow::output
