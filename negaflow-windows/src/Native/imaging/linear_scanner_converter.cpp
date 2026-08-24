#include "scanner_to_working_detail.h"

#include <algorithm>
#include <cstddef>

namespace negaflow::imaging::detail {
namespace {

[[nodiscard]] float unassociated_component(
    const std::uint16_t component,
    const std::uint16_t alpha) noexcept {
    if (alpha == 0U) {
        return 0.0F;
    }
    const std::uint64_t restored =
        (static_cast<std::uint64_t>(component) * 65'535U + alpha / 2U) / alpha;
    return static_cast<float>(std::min<std::uint64_t>(restored, 65'535U)) / 65'535.0F;
}

}  // namespace

ScannerToWorkingStatus convert_linear_scanner_raw(
    const negaflow::imageio::DecodedImage& decoded,
    WorkingImage& output) {
    constexpr float u16_scale = 1.0F / 65'535.0F;
    const std::size_t channels = negaflow::imageio::channel_count(decoded.layout);
    const negaflow::imageio::RgbSampleOffsets rgb =
        negaflow::imageio::rgb_sample_offsets(decoded.layout);
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
            const bool has_alpha =
                decoded.layout == negaflow::imageio::DecodedPixelLayout::rgba16;
            const std::uint16_t alpha16 = has_alpha ? source[offset + 3U] : 65'535U;
            const bool associated =
                decoded.alpha_mode == negaflow::imageio::AlphaMode::associated;
            destination[column] = {
                associated ? unassociated_component(source[offset + rgb.red], alpha16)
                           : static_cast<float>(source[offset + rgb.red]) * u16_scale,
                associated ? unassociated_component(source[offset + rgb.green], alpha16)
                           : static_cast<float>(source[offset + rgb.green]) * u16_scale,
                associated ? unassociated_component(source[offset + rgb.blue], alpha16)
                           : static_cast<float>(source[offset + rgb.blue]) * u16_scale,
                static_cast<float>(alpha16) * u16_scale,
            };
        }
    }
    return ScannerToWorkingStatus::ok;
}

}  // namespace negaflow::imaging::detail
