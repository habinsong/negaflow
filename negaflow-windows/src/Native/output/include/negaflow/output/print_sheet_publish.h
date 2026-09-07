#pragma once

#include "negaflow/core/machine_memory.h"

#include <cstdint>
#include <filesystem>
#include <span>

namespace negaflow::output {

// 이미 합성이 끝난 인화 판 한 장을 파일로 게시합니다.
//
// **화소를 건드리지 않습니다.** 들어오는 RGB16 은 이미 게시할 색공간의 코드값이며(판에 얹은
// 임시 현상본이 그 프로파일로 나왔기 때문입니다), 여기서는 그 값을 그대로 쓰고 같은 프로파일을
// 파일에 박습니다. 한 번 더 변환하면 랩이 받는 색이 화면과 달라집니다.
//
// 현상 내보내기(`export_working_to_srgb16_*`)와 다른 진입점인 이유: 저쪽은 선형 working 이미지를
// 받아 색공간으로 옮기며 내고, 이쪽은 옮길 것이 없는 완성된 판을 받습니다.
enum class PrintSheetPublishStatus : std::uint8_t {
    ok = 0,
    invalid_dimensions,
    invalid_format,
    buffer_size_mismatch,
    memory_limit_exceeded,
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
    publish_failed,
    published_file_invalid,
};

// 출력 탭에서 고른 형식입니다. PNG·TIFF 는 16-bit, JPEG 는 8-bit 로 게시합니다 -
// `DevelopExportFormat` 의 Png16 · Tiff16 · Jpeg8 과 같은 순서입니다.
enum class PrintSheetFormat : std::uint8_t {
    png16 = 0,
    tiff16 = 1,
    jpeg8 = 2,
};

enum class PrintSheetTiffCompression : std::uint8_t {
    none = 0,
    lzw = 1,
    deflate = 2,
};

struct PrintSheetPublishLimits final {
    // 0 이면 해상도를 적지 않습니다. 양수는 그대로 파일에 적습니다 - 인화소는 그 값으로
    // 실제 크기를 정합니다.
    std::uint32_t output_dpi{0U};
    // macOS 와 같은 0…1 범위입니다. JPEG 에서만 씁니다.
    float jpeg_quality{1.0F};
    PrintSheetTiffCompression tiff_compression{PrintSheetTiffCompression::lzw};
    std::uint32_t max_color_profile_bytes{4U * 1024U * 1024U};
    std::uint64_t max_encoded_pixel_bytes{negaflow::core::default_max_pixel_bytes()};
    // 비어 있으면 시스템 sRGB 프로파일을 박습니다. 비어 있지 않으면 그 바이트를 그대로
    // 박습니다 - 랩이 준 프로파일과 파일에 박힌 것이 한 바이트도 달라서는 안 됩니다.
    std::span<const std::uint8_t> output_icc_profile{};
};

struct PrintSheetPublishInfo final {
    std::uint32_t width{0};
    std::uint32_t height{0};
    std::uint32_t bits_per_sample{0};
    std::uint32_t color_profile_bytes{0};
    std::uint32_t output_dpi{0};
    std::uint64_t artifact_bytes{0};
    bool published{false};
};

struct PrintSheetPublishResult final {
    PrintSheetPublishStatus status{PrintSheetPublishStatus::invalid_dimensions};
    PrintSheetPublishInfo info{};
    std::uint32_t native_error_code{0};
    std::uint32_t cleanup_error_code{0};
};

// `page` 는 3 채널 RGB16 이며 행마다 `stride_bytes` 간격으로 놓입니다. 게시는 다른 출력과 같은
// 규칙입니다: CreateNew 임시 파일에 굽고, 기존 파일을 대체하지 않는 rename 으로 올립니다.
[[nodiscard]] PrintSheetPublishResult publish_print_sheet(
    std::span<const std::uint16_t> page,
    std::uint32_t width,
    std::uint32_t height,
    std::uint32_t stride_bytes,
    const std::filesystem::path& destination,
    PrintSheetFormat format,
    const PrintSheetPublishLimits& limits = {}) noexcept;

[[nodiscard]] const char* print_sheet_publish_status_name(
    PrintSheetPublishStatus status) noexcept;

}  // namespace negaflow::output
