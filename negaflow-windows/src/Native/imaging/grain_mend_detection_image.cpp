#include "grain_mend_detection_image.h"

#include "grain_mend_resample.h"
#include "negaflow/color/srgb_transfer.h"
#include "negaflow/imaging/grain_mend.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <new>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {

[[nodiscard]] std::size_t checked_pixel_count(
    const std::uint32_t width,
    const std::uint32_t height) {
    if (width == 0U || height == 0U ||
        static_cast<std::size_t>(width) >
            std::numeric_limits<std::size_t>::max() /
                static_cast<std::size_t>(height)) {
        throw std::bad_alloc{};
    }
    return static_cast<std::size_t>(width) * static_cast<std::size_t>(height);
}

[[nodiscard]] std::uint32_t scaled_dimension(
    const std::uint32_t value,
    const std::uint32_t long_side) noexcept {
    if (long_side <= grain_mend_maximum_detection_dimension) {
        return value;
    }
    const double scaled =
        static_cast<double>(value) *
        static_cast<double>(grain_mend_maximum_detection_dimension) /
        static_cast<double>(long_side);
    return std::max(1U, static_cast<std::uint32_t>(std::lround(scaled)));
}

void finish_detection_channels(DetectionImage& image) {
    const std::size_t count = checked_pixel_count(image.width, image.height);
    image.luminance.resize(count);
    image.brightest_channel.resize(count);
    for (std::size_t index = 0U; index < count; ++index) {
        const float red = image.channels[0][index];
        const float green = image.channels[1][index];
        const float blue = image.channels[2][index];
        image.luminance[index] =
            red * 0.2126F + green * 0.7152F + blue * 0.0722F;
        image.brightest_channel[index] = std::max({red, green, blue});
    }
}


DetectionImage make_detection_image(const WorkingImage& image) {
    DetectionImage result{};
    const std::uint32_t long_side = std::max(image.width, image.height);
    result.width = scaled_dimension(image.width, long_side);
    result.height = scaled_dimension(image.height, long_side);
    render_detection_rgb(
        image, result.width, result.height, result.channels);
    finish_detection_channels(result);
    return result;
}

DetectionImage make_detection_image_region(
    const WorkingImage& image,
    const std::uint32_t origin_x,
    const std::uint32_t origin_y,
    const std::uint32_t width,
    const std::uint32_t height) {
    DetectionImage result{};
    make_detection_image_region(
        image, origin_x, origin_y, width, height, result);
    return result;
}

void make_detection_image_region(
    const WorkingImage& image,
    const std::uint32_t origin_x,
    const std::uint32_t origin_y,
    const std::uint32_t width,
    const std::uint32_t height,
    DetectionImage& result) {
    if (width == 0U || height == 0U || origin_x > image.width ||
        origin_y > image.height || width > image.width - origin_x ||
        height > image.height - origin_y) {
        throw std::bad_alloc{};
    }
    result.width = width;
    result.height = height;
    const std::size_t count = checked_pixel_count(width, height);
    for (auto& channel : result.channels) {
        channel.resize(count);
    }
    for (std::uint32_t y = 0U; y < height; ++y) {
        const auto* const source = image.pixels.data() +
            static_cast<std::size_t>(origin_y + y) * image.stride_pixels +
            origin_x;
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::size_t index = static_cast<std::size_t>(y) * width + x;
            result.channels[0][index] =
                negaflow::color::linear_to_srgb_encoded(source[x].red);
            result.channels[1][index] =
                negaflow::color::linear_to_srgb_encoded(source[x].green);
            result.channels[2][index] =
                negaflow::color::linear_to_srgb_encoded(source[x].blue);
        }
    }
    finish_detection_channels(result);
}


}  // namespace negaflow::imaging::grain_mend_detail
