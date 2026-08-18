#include "negaflow/abi/source_probe.h"

#include "negaflow/core/tiff_probe.h"

#include <cstdint>
#include <cstring>
#include <filesystem>
#include <limits>

// TIFF 원본 파일의 크기·샘플 레이아웃을 읽습니다.

nf_status_t NF_CALL nf_probe_tiff_source_v1(
    const wchar_t* const source_path,
    nf_tiff_source_info_v1* const result) {
    if (result == nullptr) return NF_STATUS_INVALID_ARGUMENT;
    if (result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    if (source_path == nullptr || source_path[0] == L'\0') return NF_STATUS_INVALID_ARGUMENT;

    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    try {
        const negaflow::core::TiffProbeResult probe =
            negaflow::core::probe_tiff_file(std::filesystem::path{source_path});
        if (probe.status != negaflow::core::TiffProbeStatus::ok) {
            result->status = NF_TIFF_SOURCE_PROBE_UNREADABLE;
            return NF_STATUS_OK;
        }
        const auto& info = probe.info;
        if (info.width == 0U || info.height == 0U ||
            info.width > std::numeric_limits<std::uint32_t>::max() ||
            info.height > std::numeric_limits<std::uint32_t>::max() ||
            info.samples_per_pixel == 0U || info.bits_per_sample_count == 0U ||
            info.sample_format_count == 0U || info.bits_per_sample[0] == 0U ||
            info.sample_format[0] == 0U || info.orientation == 0U || info.orientation > 8U) {
            result->status = NF_TIFF_SOURCE_PROBE_UNSUPPORTED;
            return NF_STATUS_OK;
        }
        result->status = NF_TIFF_SOURCE_PROBE_OK;
        result->pixel_width = static_cast<std::uint32_t>(info.width);
        result->pixel_height = static_cast<std::uint32_t>(info.height);
        result->samples_per_pixel = info.samples_per_pixel;
        result->bits_per_sample = info.bits_per_sample[0];
        result->sample_format = info.sample_format[0];
        result->orientation = info.orientation;
        result->file_bytes = info.file_bytes;
        return NF_STATUS_OK;
    } catch (...) {
        result->status = NF_TIFF_SOURCE_PROBE_UNREADABLE;
        return NF_STATUS_OK;
    }
}
