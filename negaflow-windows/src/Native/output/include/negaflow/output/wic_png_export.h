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
    // The space the file is encoded in and whose profile it carries.
    negaflow::color::OutputColorSpace color_space{negaflow::color::OutputColorSpace::srgb};
    // Zero leaves the container's resolution unspecified; a positive value is metadata only.
    std::uint32_t output_dpi{0U};
    std::uint64_t max_artifact_bytes{2ULL * 1024ULL * 1024ULL * 1024ULL};
    std::uint32_t max_color_profile_bytes{4U * 1024U * 1024U};
    std::uint32_t write_buffer_bytes{16U * 1024U * 1024U};
    std::uint32_t readback_buffer_bytes{16U * 1024U * 1024U};
    // 쓴 파일을 다시 열어 화소를 전수 대조할지입니다. 기본은 끔 — macOS 는 이 대조를
    // 하지 않고(`ExportEngine.writePNG`), 파일 전체 디코드와 두 번째 sRGB16 변환을 집니다.
    // 구조·해상도·ICC 검사는 끄더라도 그대로 돕니다. 인코더가 맞다는 증명은 단위 시험이
    // 이 값을 켜서 들고 있습니다.
    bool verify_pixel_readback{false};
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
