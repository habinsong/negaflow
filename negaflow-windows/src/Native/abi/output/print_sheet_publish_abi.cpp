#include "negaflow/abi/print_sheet_publish.h"

#include "negaflow/output/print_sheet_publish.h"

#include <cstdint>
#include <cstring>
#include <filesystem>
#include <span>

// 완성된 인화 판을 파일로 게시합니다. 화소는 이미 게시할 색공간의 코드값이므로 여기서
// 옮기지 않고, 같은 프로파일을 파일에 답니다.

namespace {

[[nodiscard]] bool map_format(
    const std::uint32_t value,
    negaflow::output::PrintSheetFormat& format) noexcept {
    switch (value) {
        case 0U:
            format = negaflow::output::PrintSheetFormat::png16;
            return true;
        case 1U:
            format = negaflow::output::PrintSheetFormat::tiff16;
            return true;
        case 2U:
            format = negaflow::output::PrintSheetFormat::jpeg8;
            return true;
        default:
            return false;
    }
}

[[nodiscard]] bool map_compression(
    const std::uint32_t value,
    negaflow::output::PrintSheetTiffCompression& compression) noexcept {
    switch (value) {
        case 0U:
            compression = negaflow::output::PrintSheetTiffCompression::none;
            return true;
        case 1U:
            compression = negaflow::output::PrintSheetTiffCompression::lzw;
            return true;
        case 2U:
            compression = negaflow::output::PrintSheetTiffCompression::deflate;
            return true;
        default:
            return false;
    }
}

}  // namespace

nf_status_t NF_CALL nf_publish_print_sheet_v1(
    const nf_print_sheet_publish_request_v1* const request,
    nf_print_sheet_publish_result_v1* const result) {
    if (request == nullptr || result == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (request->struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    if (request->reserved != 0U) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (request->destination_path == nullptr || request->samples == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if ((request->output_icc_profile == nullptr) !=
        (request->output_icc_profile_size == 0U)) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    // ICC 헤더만도 128 바이트입니다. 그보다 짧은 것은 프로파일이 아닙니다 - 현상
    // 내보내기(`develop_request_v37`)도 같은 바닥을 씁니다.
    if (request->output_icc_profile_size != 0U && request->output_icc_profile_size < 128U) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::output::PrintSheetFormat format{};
    if (!map_format(request->format, format)) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::output::PrintSheetTiffCompression compression{};
    if (!map_compression(request->tiff_compression, compression)) {
        return NF_STATUS_INVALID_ARGUMENT;
    }

    negaflow::output::PrintSheetPublishLimits limits{};
    limits.output_dpi = request->output_dpi;
    limits.jpeg_quality = request->jpeg_quality;
    limits.tiff_compression = compression;
    if (request->output_icc_profile_size != 0U) {
        limits.output_icc_profile = std::span<const std::uint8_t>(
            request->output_icc_profile,
            static_cast<std::size_t>(request->output_icc_profile_size));
    }

    const std::span<const std::uint16_t> page(
        request->samples,
        static_cast<std::size_t>(request->sample_count));
    const negaflow::output::PrintSheetPublishResult published =
        negaflow::output::publish_print_sheet(
            page,
            request->width,
            request->height,
            request->stride_bytes,
            std::filesystem::path(request->destination_path),
            format,
            limits);

    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    result->status = static_cast<std::uint32_t>(published.status);
    result->native_error_code = published.native_error_code;
    result->cleanup_error_code = published.cleanup_error_code;
    result->bits_per_sample = published.info.bits_per_sample;
    result->color_profile_bytes = published.info.color_profile_bytes;
    result->artifact_bytes = published.info.artifact_bytes;
    result->published = published.info.published ? 1U : 0U;
    return NF_STATUS_OK;
}
