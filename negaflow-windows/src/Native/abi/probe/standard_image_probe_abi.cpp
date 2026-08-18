#include "negaflow/abi/source_probe.h"

#include "negaflow/imageio/wic_standard_image_decoder.h"

#include <cstdint>
#include <cstring>
#include <filesystem>
#include <limits>
#include <system_error>

// JPEG/PNG 등 표준 이미지를 WIC 로 열어 원본 정보를 읽습니다.

nf_status_t NF_CALL nf_probe_standard_image_source_v1(
    const wchar_t* const source_path,
    nf_standard_image_source_info_v1* const result) {
    if (result == nullptr) return NF_STATUS_INVALID_ARGUMENT;
    if (result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    if (source_path == nullptr || source_path[0] == L'\0') return NF_STATUS_INVALID_ARGUMENT;

    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    try {
        const auto decoded = negaflow::imageio::decode_standard_image_with_wic(
            std::filesystem::path{source_path});
        if (decoded.status != negaflow::imageio::WicStandardImageDecodeStatus::ok) {
            result->status = decoded.status ==
                    negaflow::imageio::WicStandardImageDecodeStatus::decoder_initialization_failed ||
                decoded.status == negaflow::imageio::WicStandardImageDecodeStatus::wic_unavailable
                ? NF_STANDARD_IMAGE_SOURCE_PROBE_UNREADABLE
                : NF_STANDARD_IMAGE_SOURCE_PROBE_UNSUPPORTED;
            return NF_STATUS_OK;
        }
        bool opaque = true;
        for (std::size_t index = 3U; index < decoded.image.samples.size(); index += 4U) {
            opaque = opaque && decoded.image.samples[index] == 65535U;
        }
        if (decoded.image.width == 0U || decoded.image.height == 0U ||
            decoded.image.layout != negaflow::imageio::DecodedPixelLayout::rgba16 ||
            decoded.image.samples.size() < 4U || decoded.image.samples.size() % 4U != 0U ||
            !opaque) {
            result->status = NF_STANDARD_IMAGE_SOURCE_PROBE_UNSUPPORTED;
            return NF_STATUS_OK;
        }
        std::error_code error;
        const std::uintmax_t bytes = std::filesystem::file_size(source_path, error);
        if (error || bytes == 0U || bytes > std::numeric_limits<std::uint64_t>::max()) {
            result->status = NF_STANDARD_IMAGE_SOURCE_PROBE_UNREADABLE;
            return NF_STATUS_OK;
        }
        result->status = NF_STANDARD_IMAGE_SOURCE_PROBE_OK;
        result->pixel_width = decoded.image.width;
        result->pixel_height = decoded.image.height;
        result->samples_per_pixel = 4U;
        result->bits_per_sample = 16U;
        result->sample_format = 1U;
        result->orientation = 1U;
        result->file_bytes = static_cast<std::uint64_t>(bytes);
        return NF_STATUS_OK;
    } catch (...) {
        result->status = NF_STANDARD_IMAGE_SOURCE_PROBE_UNREADABLE;
        return NF_STATUS_OK;
    }
}
