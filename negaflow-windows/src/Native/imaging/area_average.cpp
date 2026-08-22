#include "negaflow/imaging/area_average.h"

#include "negaflow/imaging/kernel_accelerator.h"

#include <algorithm>
#include <cstddef>

namespace negaflow::imaging {
namespace {

[[nodiscard]] bool clip_region(
    const std::uint32_t width,
    const std::uint32_t height,
    std::uint32_t& origin_x,
    std::uint32_t& origin_y,
    std::uint32_t& extent_width,
    std::uint32_t& extent_height) noexcept {
    if (origin_x >= width || origin_y >= height) {
        return false;
    }
    extent_width = std::min(extent_width, width - origin_x);
    extent_height = std::min(extent_height, height - origin_y);
    return extent_width > 0U && extent_height > 0U;
}

void accumulate_cpu(
    const negaflow::core::Rgba32F* const pixels,
    const std::uint32_t stride_pixels,
    const std::uint32_t origin_x,
    const std::uint32_t origin_y,
    const std::uint32_t extent_width,
    const std::uint32_t extent_height,
    AreaAverage& average) noexcept {
    double red = 0.0;
    double green = 0.0;
    double blue = 0.0;
    double alpha = 0.0;
    std::uint64_t count = 0U;
    for (std::uint32_t y = 0U; y < extent_height; ++y) {
        const auto* const row = pixels +
            (static_cast<std::size_t>(origin_y + y) * stride_pixels) + origin_x;
        for (std::uint32_t x = 0U; x < extent_width; ++x) {
            red += static_cast<double>(row[x].red);
            green += static_cast<double>(row[x].green);
            blue += static_cast<double>(row[x].blue);
            alpha += static_cast<double>(row[x].alpha);
            ++count;
        }
    }
    const double inverse = 1.0 / static_cast<double>(count);
    average.red = red * inverse;
    average.green = green * inverse;
    average.blue = blue * inverse;
    average.alpha = alpha * inverse;
    average.count = count;
}

} // namespace

bool area_average(
    const WorkingImage& image,
    const std::uint32_t origin_x,
    const std::uint32_t origin_y,
    const std::uint32_t extent_width,
    const std::uint32_t extent_height,
    AreaAverage& average) noexcept {
    if (image.pixels.empty() || image.stride_pixels < image.width) {
        return false;
    }
    return area_average(
        image.pixels.data(),
        image.width,
        image.height,
        image.stride_pixels,
        origin_x,
        origin_y,
        extent_width,
        extent_height,
        average);
}

bool area_average(
    const negaflow::core::Rgba32F* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    std::uint32_t origin_x,
    std::uint32_t origin_y,
    std::uint32_t extent_width,
    std::uint32_t extent_height,
    AreaAverage& average) noexcept {
    average = {};
    if (pixels == nullptr || width == 0U || height == 0U || stride_pixels < width) {
        return false;
    }
    if (!clip_region(width, height, origin_x, origin_y, extent_width, extent_height)) {
        return false;
    }

    // **근사입니다**(GPU 트리 vs CPU 행 우선 double). 프리뷰·검출 스코프에서만 GPU.
    if (approximate_acceleration_allowed()) {
        if (const KernelAccelerator* const table = kernel_accelerator();
            table != nullptr && table->area_average != nullptr) {
            float mean[4]{};
            std::uint64_t count = 0U;
            if (table->area_average(
                    reinterpret_cast<const float*>(pixels),
                    width,
                    height,
                    stride_pixels,
                    origin_x,
                    origin_y,
                    extent_width,
                    extent_height,
                    mean,
                    &count)) {
                average.red = static_cast<double>(mean[0]);
                average.green = static_cast<double>(mean[1]);
                average.blue = static_cast<double>(mean[2]);
                average.alpha = static_cast<double>(mean[3]);
                average.count = count;
                return true;
            }
        }
    }

    accumulate_cpu(
        pixels,
        stride_pixels,
        origin_x,
        origin_y,
        extent_width,
        extent_height,
        average);
    return true;
}

} // namespace negaflow::imaging
