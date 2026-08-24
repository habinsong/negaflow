#include "wic_tiff_preflight.h"

#include "wic_tiff_support.h"

#include <Shlwapi.h>
#include <wincodec.h>

#include <limits>

namespace negaflow::imageio::wic_tiff_detail {

WicTiffDecodeStatus preflight_tiff_source(
    const std::filesystem::path& path,
    const WicTiffDecodeLimits& limits,
    const WicTiffDecodeControl& control,
    TiffPreflight& preflight,
    WicTiffDecodeResult& result) {
    Microsoft::WRL::ComPtr<IStream> stream{};
    const HRESULT status = SHCreateStreamOnFileEx(
        path.c_str(),
        STGM_READ | STGM_SHARE_DENY_WRITE,
        FILE_ATTRIBUTE_NORMAL,
        FALSE,
        nullptr,
        &stream);
    if (FAILED(status)) {
        return WicTiffDecodeStatus::stream_open_failed;
    }

    const IStreamTiffReader reader{stream.Get()};
    if (!reader.valid()) {
        return WicTiffDecodeStatus::stream_open_failed;
    }
    negaflow::core::TiffProbeControl probe_control{};
    probe_control.select_first_directory = control.select_first_frame;
    const negaflow::core::TiffProbeResult probe =
        negaflow::core::probe_tiff(reader, limits.probe, probe_control);
    result.preflight_status = probe.status;
    if (probe.status != negaflow::core::TiffProbeStatus::ok) {
        return WicTiffDecodeStatus::preflight_failed;
    }
    if (!is_supported_layout(
            probe.info,
            control.orientation_policy != WicTiffOrientationPolicy::require_normal)) {
        return WicTiffDecodeStatus::unsupported_layout;
    }
    const std::uint64_t channels = probe.info.samples_per_pixel;
    const std::uint64_t bytes_per_pixel = channels * sizeof(std::uint16_t);
    if (probe.info.width > std::numeric_limits<std::uint64_t>::max() / bytes_per_pixel) {
        return WicTiffDecodeStatus::memory_limit_exceeded;
    }
    const std::uint64_t expected_stride_bytes = probe.info.width * bytes_per_pixel;
    if (probe.info.height != 0U &&
        expected_stride_bytes >
            std::numeric_limits<std::uint64_t>::max() / probe.info.height) {
        return WicTiffDecodeStatus::memory_limit_exceeded;
    }
    const std::uint64_t expected_pixel_bytes =
        expected_stride_bytes * probe.info.height;
    result.info.decoded_pixel_bytes = expected_pixel_bytes;
    result.info.compressed_segment_bytes = probe.info.compressed_segment_bytes;
    if (expected_stride_bytes > std::numeric_limits<UINT>::max() ||
        expected_pixel_bytes > limits.max_decoded_pixel_bytes ||
        expected_pixel_bytes / sizeof(std::uint16_t) >
            static_cast<std::uint64_t>(std::numeric_limits<std::size_t>::max())) {
        return WicTiffDecodeStatus::memory_limit_exceeded;
    }

    if (control.validate_compressed_streams &&
        (probe.info.compression == 5U || probe.info.compression == 8U)) {
        negaflow::core::TiffProbeControl semantic_control{};
        semantic_control.validate_lzw_code_streams = probe.info.compression == 5U;
        semantic_control.validate_deflate_streams = probe.info.compression == 8U;
        semantic_control.select_first_directory = control.select_first_frame;
        semantic_control.stop_token = control.stop_token;
        const negaflow::core::TiffProbeResult semantic_probe =
            negaflow::core::probe_tiff(reader, limits.probe, semantic_control);
        result.preflight_status = semantic_probe.status;
        result.info.compressed_bytes_validated =
            semantic_probe.info.compressed_bytes_validated;
        result.info.lzw_code_count = semantic_probe.info.lzw_code_count;
        result.info.lzw_decoded_bytes_validated =
            semantic_probe.info.lzw_decoded_bytes_validated;
        result.info.deflate_decoded_bytes_validated =
            semantic_probe.info.deflate_decoded_bytes_validated;
        result.info.lzw_code_streams_validated =
            semantic_probe.info.lzw_code_streams_validated;
        result.info.deflate_streams_validated =
            semantic_probe.info.deflate_streams_validated;
        if (semantic_probe.status == negaflow::core::TiffProbeStatus::cancelled) {
            return WicTiffDecodeStatus::cancelled;
        }
        if (semantic_probe.status != negaflow::core::TiffProbeStatus::ok) {
            return WicTiffDecodeStatus::preflight_failed;
        }
    }
    if (control.stop_token.stop_requested()) {
        return WicTiffDecodeStatus::cancelled;
    }
    if (!rewind_stream(stream.Get())) {
        return WicTiffDecodeStatus::decoder_initialization_failed;
    }

    preflight.stream = stream;
    preflight.info = probe.info;
    preflight.stride_bytes = expected_stride_bytes;
    preflight.pixel_bytes = expected_pixel_bytes;
    return WicTiffDecodeStatus::ok;
}

}  // namespace negaflow::imageio::wic_tiff_detail
