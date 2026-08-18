#include "negaflow/imaging/channel_clipping_overlay.h"

#include "negaflow/core/parallel_rows.h"
#include "negaflow/imaging/kernel_accelerator.h"

#include <new>

namespace negaflow::imaging {

bool apply_channel_clipping_overlay(
    const WorkingImage& source,
    WorkingImage& destination) noexcept {
    if (source.width == 0U || source.height == 0U ||
        source.stride_pixels < source.width ||
        source.pixels.size() <
            static_cast<std::size_t>(source.stride_pixels) * source.height) {
        return false;
    }
    try {
        destination.width = source.width;
        destination.height = source.height;
        destination.stride_pixels = source.width;
        destination.pixels.assign(
            static_cast<std::size_t>(source.width) * source.height,
            negaflow::core::Rgba32F{});
    } catch (const std::bad_alloc&) {
        return false;
    }

    if (approximate_acceleration_allowed()) {
        if (const KernelAccelerator* const table = kernel_accelerator();
            table != nullptr && table->channel_clipping_overlay != nullptr) {
            if (table->channel_clipping_overlay(
                    reinterpret_cast<const float*>(source.pixels.data()),
                    reinterpret_cast<float*>(destination.pixels.data()),
                    source.width,
                    source.height,
                    source.stride_pixels,
                    destination.stride_pixels)) {
                return true;
            }
        }
    }

    const std::uint64_t work_units =
        static_cast<std::uint64_t>(source.width) * source.height;
    negaflow::core::for_each_row_block(
        source.height,
        work_units,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                const auto* const in_row = source.pixels.data() +
                    static_cast<std::size_t>(y) * source.stride_pixels;
                auto* const out_row = destination.pixels.data() +
                    static_cast<std::size_t>(y) * destination.stride_pixels;
                for (std::uint32_t x = 0U; x < source.width; ++x) {
                    const ChannelClippingOverlayPixel overlay =
                        channel_clipping_overlay_pixel(in_row[x]);
                    out_row[x].red = overlay.red;
                    out_row[x].green = overlay.green;
                    out_row[x].blue = overlay.blue;
                    out_row[x].alpha = overlay.alpha;
                }
            }
        });
    return true;
}

}  // namespace negaflow::imaging
