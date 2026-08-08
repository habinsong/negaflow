#include "scanner_to_working_detail.h"

#include <cstddef>

namespace negaflow::imaging::detail {

ScannerToWorkingStatus convert_linear_scanner_raw(
    const negaflow::imageio::DecodedImage& decoded,
    WorkingImage& output) {
    constexpr float u16_scale = 1.0F / 65'535.0F;
    const std::size_t channels = negaflow::imageio::channel_count(decoded.layout);
    const std::size_t source_stride = decoded.stride_bytes / sizeof(std::uint16_t);

    output.width = decoded.width;
    output.height = decoded.height;
    output.stride_pixels = decoded.width;
    output.pixels.resize(
        static_cast<std::size_t>(decoded.width) * static_cast<std::size_t>(decoded.height));

    for (std::uint32_t row = 0U; row < decoded.height; ++row) {
        const std::uint16_t* const source =
            decoded.samples.data() + static_cast<std::size_t>(row) * source_stride;
        negaflow::core::Rgba32F* const destination =
            output.pixels.data() + static_cast<std::size_t>(row) * output.stride_pixels;
        for (std::uint32_t column = 0U; column < decoded.width; ++column) {
            const std::size_t offset = static_cast<std::size_t>(column) * channels;
            destination[column] = {
                static_cast<float>(source[offset]) * u16_scale,
                static_cast<float>(source[offset + 1U]) * u16_scale,
                static_cast<float>(source[offset + 2U]) * u16_scale,
                1.0F,
            };
        }
    }
    return ScannerToWorkingStatus::ok;
}

}  // namespace negaflow::imaging::detail
