#pragma once

#include "negaflow/output/working_to_srgb16.h"
#include "negaflow/output/export_metadata.h"

#include <cstdint>
#include <filesystem>

namespace negaflow::output {

enum class WicTiffExportStatus : std::uint8_t {
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
    compression_configuration_failed,
    pixel_format_coerced,
    encode_failed,
    flush_failed,
    structure_verification_failed,
    metadata_verification_failed,
    decoder_initialization_failed,
    unexpected_decoder,
    readback_failed,
    pixel_verification_failed,
    profile_verification_failed,
    publish_failed,
    published_file_invalid,
};

enum class WicTiffCompression : std::uint8_t {
    none = 0,
    lzw,
    deflate,
};

struct WicTiffExportLimits final {
    WorkingToSrgb16Limits conversion{};
    // 8 or 16. Eight-bit output is dithered before quantization; sixteen is not.
    std::uint32_t bits_per_sample{16U};
    // The space the file is encoded in and whose profile it carries.
    negaflow::color::OutputColorSpace color_space{negaflow::color::OutputColorSpace::srgb};
    WicTiffCompression compression{WicTiffCompression::none};
    // Zero leaves the container's resolution unspecified; a positive value is metadata only.
    std::uint32_t output_dpi{0U};
    std::uint64_t max_artifact_bytes{2ULL * 1024ULL * 1024ULL * 1024ULL};
    std::uint32_t max_color_profile_bytes{4U * 1024U * 1024U};
    std::uint32_t write_buffer_bytes{16U * 1024U * 1024U};
    std::uint32_t readback_buffer_bytes{16U * 1024U * 1024U};
    std::uint32_t max_ifd_entries{128U};
    // 파일에 적을 메타데이터. 정책이 무엇을 적을지 가른다.
    ExportMetadataPolicy metadata_policy{ExportMetadataPolicy::minimal};
    ExportMetadataFields metadata{};
};

struct WicTiffExportInfo final {
    std::uint32_t width{0};
    std::uint32_t height{0};
    std::uint64_t encoded_pixel_bytes{0};
    std::uint64_t clipped_color_components{0};
    std::uint64_t artifact_bytes{0};
    std::uint64_t strip_count{0};
    std::uint32_t color_profile_bytes{0};
    std::uint32_t ifd_entry_count{0};
    std::uint32_t output_dpi{0};
    std::uint16_t compression{0};
    std::uint16_t unexpected_metadata_tag{0};
    bool structure_verified{false};
    bool metadata_verified{false};
    bool pixels_verified{false};
    bool profile_verified{false};
    bool resolution_verified{false};
    bool published{false};
};

struct WicTiffExportResult final {
    WicTiffExportStatus status{WicTiffExportStatus::working_conversion_failed};
    WorkingToSrgb16Status conversion_status{WorkingToSrgb16Status::invalid_dimensions};
    WicTiffExportInfo info{};
    std::uint32_t native_error_code{0};
    std::uint32_t cleanup_error_code{0};
};

[[nodiscard]] WicTiffExportResult export_working_to_srgb16_tiff(
    const negaflow::imaging::WorkingImage& working,
    const std::filesystem::path& destination,
    const WicTiffExportLimits& limits = {}) noexcept;

[[nodiscard]] const char* wic_tiff_export_status_name(
    WicTiffExportStatus status) noexcept;

}  // namespace negaflow::output
