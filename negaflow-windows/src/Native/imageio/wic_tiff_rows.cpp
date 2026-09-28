#include "wic_tiff_rows.h"

#include "wic_tiff_support.h"

#include <algorithm>
#include <cstddef>
#include <limits>
#include <span>
#include <vector>

namespace negaflow::imageio::wic_tiff_detail {
namespace {

WicTiffDecodeStatus copy_tiff_row_bands(
    IWICBitmapSource* const pixel_source,
    const std::uint64_t stride_bytes,
    const UINT width,
    const UINT height,
    const std::span<const WicTiffRowBand> bands,
    const WicTiffDecodeControl& control,
    WicTiffRowSink* const row_sink,
    bool& sink_started,
    WicTiffDecodeResult& result) {
    const auto complete_sink = [&](const WicTiffDecodeStatus status) noexcept {
        if (sink_started) {
            row_sink->complete(status);
            sink_started = false;
        }
    };
    if (width > static_cast<UINT>(std::numeric_limits<INT>::max()) ||
        height > static_cast<UINT>(std::numeric_limits<INT>::max())) {
        complete_sink(WicTiffDecodeStatus::memory_limit_exceeded);
        return WicTiffDecodeStatus::memory_limit_exceeded;
    }
    std::uint32_t largest = 0U;
    std::uint32_t next_row = 0U;
    for (const WicTiffRowBand& band : bands) {
        if (band.row_count == 0U || band.first_row < next_row || band.first_row > height ||
            band.row_count > height - band.first_row) {
            complete_sink(WicTiffDecodeStatus::invalid_argument);
            return WicTiffDecodeStatus::invalid_argument;
        }
        next_row = band.first_row + band.row_count;
        largest = std::max(largest, band.row_count);
    }
    const std::uint64_t buffer_bytes = stride_bytes * largest;
    if (buffer_bytes > std::numeric_limits<UINT>::max()) {
        complete_sink(WicTiffDecodeStatus::memory_limit_exceeded);
        return WicTiffDecodeStatus::memory_limit_exceeded;
    }
    std::vector<std::uint16_t> row_buffer(static_cast<std::size_t>(buffer_bytes / sizeof(std::uint16_t)));
    for (const WicTiffRowBand& band : bands) {
        if (control.stop_token.stop_requested()) {
            complete_sink(WicTiffDecodeStatus::cancelled);
            return WicTiffDecodeStatus::cancelled;
        }
        const std::uint64_t copy_bytes = stride_bytes * band.row_count;
        const WICRect rectangle{
            0,
            static_cast<INT>(band.first_row),
            static_cast<INT>(width),
            static_cast<INT>(band.row_count),
        };
        const HRESULT status = pixel_source->CopyPixels(
            &rectangle,
            static_cast<UINT>(stride_bytes),
            static_cast<UINT>(copy_bytes),
            reinterpret_cast<BYTE*>(row_buffer.data()));
        if (FAILED(status)) {
            complete_sink(WicTiffDecodeStatus::pixel_decode_failed);
            return WicTiffDecodeStatus::pixel_decode_failed;
        }
        ++result.info.copy_operation_count;
        result.info.peak_copy_pixel_bytes = std::max(result.info.peak_copy_pixel_bytes, copy_bytes);
        const WicTiffRowChunk chunk{
            band.first_row,
            band.row_count,
            result.image.stride_bytes,
            std::span<const std::uint16_t>{
                row_buffer.data(), static_cast<std::size_t>(copy_bytes / sizeof(std::uint16_t))},
        };
        if (!row_sink->write(chunk)) {
            const WicTiffDecodeStatus sink_status = control.stop_token.stop_requested()
                ? WicTiffDecodeStatus::cancelled
                : WicTiffDecodeStatus::row_sink_failed;
            complete_sink(sink_status);
            return sink_status;
        }
        result.info.completed_rows = band.first_row + band.row_count;
        if (control.progress_observer != nullptr) {
            control.progress_observer->report({result.info.completed_rows, height});
        }
    }
    complete_sink(WicTiffDecodeStatus::ok);
    return WicTiffDecodeStatus::ok;
}

}  // namespace

WicTiffDecodeStatus copy_tiff_rows(
    IWICBitmapSource* const pixel_source,
    const std::uint64_t stride_bytes,
    const std::uint64_t pixel_bytes,
    const UINT width,
    const UINT height,
    const WicTiffDecodeControl& control,
    WicTiffRowSink* const row_sink,
    const WicTiffLanePlan& lanes,
    bool& sink_started,
    WicTiffDecodeResult& result) {
    const auto complete_sink = [&](const WicTiffDecodeStatus status) noexcept {
        if (sink_started) {
            row_sink->complete(status);
            sink_started = false;
        }
    };

    const std::uint64_t maximum_rows_per_copy =
        static_cast<std::uint64_t>(std::numeric_limits<UINT>::max()) /
        stride_bytes;
    if (maximum_rows_per_copy == 0U) {
        return WicTiffDecodeStatus::memory_limit_exceeded;
    }
    const bool whole_frame_copy =
        control.rows_per_copy == 0U && pixel_bytes <= std::numeric_limits<UINT>::max();
    if (!whole_frame_copy &&
        (width > static_cast<UINT>(std::numeric_limits<INT>::max()) ||
         height > static_cast<UINT>(std::numeric_limits<INT>::max()))) {
        return WicTiffDecodeStatus::memory_limit_exceeded;
    }
    const std::uint64_t requested_rows =
        control.rows_per_copy == 0U ? maximum_rows_per_copy : control.rows_per_copy;
    const std::uint32_t rows_per_copy = static_cast<std::uint32_t>(std::min(
        static_cast<std::uint64_t>(height),
        std::min(requested_rows, maximum_rows_per_copy)));
    if (rows_per_copy == 0U) {
        return WicTiffDecodeStatus::invalid_argument;
    }

    if (row_sink != nullptr) {
        const WicTiffFrameView frame_view{
            result.image.width,
            result.image.height,
            result.image.stride_bytes,
            result.image.layout,
            result.image.alpha_mode,
            result.image.icc_profile,
        };
        sink_started = true;
        if (!row_sink->begin(frame_view)) {
            complete_sink(WicTiffDecodeStatus::row_sink_failed);
            return WicTiffDecodeStatus::row_sink_failed;
        }
    }

    if (control.progress_observer != nullptr) {
        control.progress_observer->report({0U, height});
    }
    if (control.stop_token.stop_requested()) {
        complete_sink(WicTiffDecodeStatus::cancelled);
        return WicTiffDecodeStatus::cancelled;
    }

    // 싱크가 일부 줄만 원하면 그 띠만 풉니다. 입력 감마 추정은 64 곳의 9 줄만 보는데,
    // 예전에는 그것을 얻으려고 사진을 통째로 한 번 더 풀었습니다(사진을 열 때마다 수백 ms).
    const std::span<const WicTiffRowBand> bands =
        row_sink != nullptr ? row_sink->wanted_rows() : std::span<const WicTiffRowBand>{};
    if (!bands.empty()) {
        return copy_tiff_row_bands(
            pixel_source, stride_bytes, width, height, bands, control, row_sink, sink_started, result);
    }
    if (row_sink != nullptr && lanes.lane_count > 1U) {
        return copy_tiff_rows_in_lanes(
            pixel_source, lanes, stride_bytes, width, height, control, *row_sink, sink_started, result);
    }

    std::vector<std::uint16_t> row_buffer{};
    if (row_sink == nullptr) {
        result.image.samples.resize(
            static_cast<std::size_t>(pixel_bytes / sizeof(std::uint16_t)));
    } else {
        const std::uint64_t row_buffer_bytes = stride_bytes * rows_per_copy;
        row_buffer.resize(
            static_cast<std::size_t>(row_buffer_bytes / sizeof(std::uint16_t)));
    }
    for (std::uint32_t first_row = 0U; first_row < height;) {
        if (control.stop_token.stop_requested()) {
            discard_samples(result);
            complete_sink(WicTiffDecodeStatus::cancelled);
            return WicTiffDecodeStatus::cancelled;
        }

        const std::uint32_t row_count =
            std::min(rows_per_copy, height - first_row);
        const std::uint64_t copy_bytes = stride_bytes * row_count;
        const std::size_t destination_sample_offset = static_cast<std::size_t>(
            static_cast<std::uint64_t>(first_row) * stride_bytes /
            sizeof(std::uint16_t));
        WICRect rectangle{
            0,
            static_cast<INT>(first_row),
            static_cast<INT>(width),
            static_cast<INT>(row_count),
        };
        std::uint16_t* const destination =
            row_sink == nullptr
                ? result.image.samples.data() + destination_sample_offset
                : row_buffer.data();
        const HRESULT status = pixel_source->CopyPixels(
            whole_frame_copy ? nullptr : &rectangle,
            static_cast<UINT>(stride_bytes),
            static_cast<UINT>(copy_bytes),
            reinterpret_cast<BYTE*>(destination));
        if (FAILED(status)) {
            discard_samples(result);
            complete_sink(WicTiffDecodeStatus::pixel_decode_failed);
            return WicTiffDecodeStatus::pixel_decode_failed;
        }
        ++result.info.copy_operation_count;
        result.info.peak_copy_pixel_bytes =
            std::max(result.info.peak_copy_pixel_bytes, copy_bytes);
        if (control.stop_token.stop_requested()) {
            discard_samples(result);
            complete_sink(WicTiffDecodeStatus::cancelled);
            return WicTiffDecodeStatus::cancelled;
        }

        if (row_sink != nullptr) {
            const WicTiffRowChunk chunk{
                first_row,
                row_count,
                result.image.stride_bytes,
                std::span<const std::uint16_t>{
                    row_buffer.data(),
                    static_cast<std::size_t>(copy_bytes / sizeof(std::uint16_t))},
            };
            if (!row_sink->write(chunk)) {
                const WicTiffDecodeStatus sink_status =
                    control.stop_token.stop_requested()
                        ? WicTiffDecodeStatus::cancelled
                        : WicTiffDecodeStatus::row_sink_failed;
                complete_sink(sink_status);
                return sink_status;
            }
        }

        first_row += row_count;
        result.info.completed_rows = first_row;
        if (control.progress_observer != nullptr) {
            control.progress_observer->report({first_row, height});
        }
    }

    complete_sink(WicTiffDecodeStatus::ok);
    return WicTiffDecodeStatus::ok;
}

}  // namespace negaflow::imageio::wic_tiff_detail
