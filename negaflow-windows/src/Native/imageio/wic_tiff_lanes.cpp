#include "wic_tiff_lanes.h"

#include "wic_tiff_support.h"

#include "negaflow/core/parallel_rows.h"

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <limits>
#include <span>
#include <vector>

namespace negaflow::imageio::wic_tiff_detail {

using Microsoft::WRL::ComPtr;

WicTiffLanePlan plan_tiff_lanes(
    const negaflow::core::TiffProbeInfo& info,
    const WicTiffDecodeControl& control,
    const UINT output_height,
    const bool scaled) noexcept {
    WicTiffLanePlan plan{};
    if (control.orientation_policy == WicTiffOrientationPolicy::apply_metadata &&
        info.orientation != 1U) {
        return plan;
    }
    if (info.organization != negaflow::core::TiffOrganization::stripped ||
        info.segment_count == 0U || info.height == 0U || output_height < 2U) {
        return plan;
    }
    const std::uint64_t threads = negaflow::core::physical_cores();
    if (threads < 2U) {
        return plan;
    }
    const std::uint64_t rows_per_strip =
        (info.height + info.segment_count - 1U) / info.segment_count;
    const bool compressed = info.compression != 1U;
    std::uint64_t rows_per_lane = 0U;
    if (scaled) {
        rows_per_lane = (output_height + threads - 1U) / threads;
        // 축소본 한 띠가 덮는 원본 줄이 스트립 하나보다 적으면 레인마다 같은 스트립을
        // 되풀어 이득이 없습니다.
        if (compressed && rows_per_lane * info.height / output_height < rows_per_strip) {
            return plan;
        }
    } else {
        rows_per_lane = std::max<std::uint64_t>(control.rows_per_copy, 1U);
        if (compressed) {
            rows_per_lane = (rows_per_lane + rows_per_strip - 1U) / rows_per_strip * rows_per_strip;
        }
    }
    const std::uint64_t lanes =
        std::min(threads, (output_height + rows_per_lane - 1U) / rows_per_lane);
    if (lanes < 2U || rows_per_lane > std::numeric_limits<std::uint32_t>::max()) {
        return plan;
    }
    plan.lane_count = static_cast<std::uint32_t>(lanes);
    plan.rows_per_lane = static_cast<std::uint32_t>(rows_per_lane);
    return plan;
}

WicTiffDecodeStatus copy_tiff_rows_in_lanes(
    IWICBitmapSource* const first_lane,
    const WicTiffLanePlan& plan,
    const std::uint64_t stride_bytes,
    const UINT width,
    const UINT height,
    const WicTiffDecodeControl& control,
    WicTiffRowSink& row_sink,
    bool& sink_started,
    WicTiffDecodeResult& result) {
    const auto finish = [&](const WicTiffDecodeStatus status) noexcept {
        if (sink_started) {
            row_sink.complete(status);
            sink_started = false;
        }
        return status;
    };
    if (plan.opener == nullptr || plan.lane_count < 2U || plan.rows_per_lane == 0U ||
        width > static_cast<UINT>(std::numeric_limits<INT>::max()) ||
        height > static_cast<UINT>(std::numeric_limits<INT>::max())) {
        return finish(WicTiffDecodeStatus::invalid_argument);
    }
    const std::uint64_t chunk_rows = std::min<std::uint64_t>(
        height, static_cast<std::uint64_t>(plan.rows_per_lane) * plan.lane_count);
    if (stride_bytes * plan.rows_per_lane > std::numeric_limits<UINT>::max() ||
        stride_bytes * chunk_rows / sizeof(std::uint16_t) >
            std::numeric_limits<std::size_t>::max()) {
        return finish(WicTiffDecodeStatus::memory_limit_exceeded);
    }
    std::vector<std::uint16_t> buffer(
        static_cast<std::size_t>(stride_bytes * chunk_rows / sizeof(std::uint16_t)));
    std::vector<ComPtr<IWICBitmapSource>> lanes(plan.lane_count);
    lanes[0] = first_lane;
    const std::size_t stride_samples = static_cast<std::size_t>(stride_bytes / sizeof(std::uint16_t));

    for (std::uint32_t first_row = 0U; first_row < height;) {
        if (control.stop_token.stop_requested()) {
            return finish(WicTiffDecodeStatus::cancelled);
        }
        const auto rows = static_cast<std::uint32_t>(
            std::min<std::uint64_t>(chunk_rows, height - first_row));
        const std::uint32_t used = (rows + plan.rows_per_lane - 1U) / plan.rows_per_lane;
        std::atomic<bool> failed{false};
        negaflow::core::for_each_row_block(
            used,
            stride_bytes * rows,
            [&](const std::uint32_t first_lane_index, const std::uint32_t lane_count) noexcept {
                // 레인은 다른 스레드가 연 MTA 객체입니다. 풀 스레드도 같은 MTA 에 들어갑니다.
                const ComApartment apartment{};
                for (std::uint32_t lane = first_lane_index;
                     lane < first_lane_index + lane_count; ++lane) {
                    if (failed.load(std::memory_order_relaxed) ||
                        control.stop_token.stop_requested()) {
                        return;
                    }
                    if (!lanes[lane]) {
                        lanes[lane] = plan.opener->open();
                    }
                    const std::uint32_t band_first = lane * plan.rows_per_lane;
                    const std::uint32_t band_rows = std::min(plan.rows_per_lane, rows - band_first);
                    const WICRect rectangle{
                        0,
                        static_cast<INT>(first_row + band_first),
                        static_cast<INT>(width),
                        static_cast<INT>(band_rows),
                    };
                    if (!lanes[lane] ||
                        FAILED(lanes[lane]->CopyPixels(
                            &rectangle,
                            static_cast<UINT>(stride_bytes),
                            static_cast<UINT>(stride_bytes * band_rows),
                            reinterpret_cast<BYTE*>(buffer.data() + band_first * stride_samples)))) {
                        failed.store(true, std::memory_order_relaxed);
                        return;
                    }
                }
            });
        if (control.stop_token.stop_requested()) {
            return finish(WicTiffDecodeStatus::cancelled);
        }
        if (failed.load(std::memory_order_relaxed)) {
            return finish(WicTiffDecodeStatus::pixel_decode_failed);
        }
        result.info.copy_operation_count += used;
        result.info.peak_copy_pixel_bytes =
            std::max(result.info.peak_copy_pixel_bytes, stride_bytes * rows);
        const WicTiffRowChunk chunk{
            first_row,
            rows,
            result.image.stride_bytes,
            std::span<const std::uint16_t>{buffer.data(), rows * stride_samples},
        };
        if (!row_sink.write(chunk)) {
            return finish(
                control.stop_token.stop_requested() ? WicTiffDecodeStatus::cancelled
                                                    : WicTiffDecodeStatus::row_sink_failed);
        }
        first_row += rows;
        result.info.completed_rows = first_row;
        if (control.progress_observer != nullptr) {
            control.progress_observer->report({first_row, height});
        }
    }
    return finish(WicTiffDecodeStatus::ok);
}

}  // namespace negaflow::imageio::wic_tiff_detail
