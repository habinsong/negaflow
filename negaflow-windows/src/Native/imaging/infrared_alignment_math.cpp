#include "infrared_alignment_math.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <vector>

namespace negaflow::imaging::infrared_detail {

DownsampledPlane block_mean(
    const std::span<const float> source,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t factor) {
    if (factor <= 1U) {
        return DownsampledPlane{
            std::vector<float>(source.begin(), source.end()), width, height};
    }
    DownsampledPlane result{};
    result.width = std::max(1U, width / factor);
    result.height = std::max(1U, height / factor);
    result.pixels.assign(static_cast<std::size_t>(result.width) * result.height, 0.0F);
    const float inverse = 1.0F / static_cast<float>(factor * factor);
    for (std::uint32_t block_y = 0U; block_y < result.height; ++block_y) {
        for (std::uint32_t block_x = 0U; block_x < result.width; ++block_x) {
            float sum = 0.0F;
            for (std::uint32_t y = block_y * factor; y < (block_y + 1U) * factor; ++y) {
                for (std::uint32_t x = block_x * factor; x < (block_x + 1U) * factor; ++x) {
                    sum += source[static_cast<std::size_t>(y) * width + x];
                }
            }
            result.pixels[static_cast<std::size_t>(block_y) * result.width + block_x] =
                sum * inverse;
        }
    }
    return result;
}

double correlation(
    const std::span<const float> first,
    const std::span<const float> second,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::int32_t dx,
    const std::int32_t dy,
    const std::uint32_t stride) noexcept {
    const std::int32_t inset = static_cast<std::int32_t>(stride == 1U ? 4U : 8U) +
        std::max(std::abs(dx), std::abs(dy));
    if (static_cast<std::int32_t>(width) <= 2 * inset ||
        static_cast<std::int32_t>(height) <= 2 * inset) return -1.0;
    double first_sum = 0.0;
    double second_sum = 0.0;
    double first_square = 0.0;
    double second_square = 0.0;
    double product = 0.0;
    double count = 0.0;
    for (std::int32_t y = inset; y < static_cast<std::int32_t>(height) - inset;
         y += static_cast<std::int32_t>(stride)) {
        for (std::int32_t x = inset; x < static_cast<std::int32_t>(width) - inset;
             x += static_cast<std::int32_t>(stride)) {
            const double a = first[static_cast<std::size_t>(y + dy) * width +
                static_cast<std::uint32_t>(x + dx)];
            const double b = second[static_cast<std::size_t>(y) * width +
                static_cast<std::uint32_t>(x)];
            first_sum += a;
            second_sum += b;
            first_square += a * a;
            second_square += b * b;
            product += a * b;
            count += 1.0;
        }
    }
    if (count <= static_cast<double>(stride == 1U ? 16U : 64U)) return -1.0;
    const double first_mean = first_sum / count;
    const double second_mean = second_sum / count;
    const double covariance = product / count - first_mean * second_mean;
    const double first_variance = first_square / count - first_mean * first_mean;
    const double second_variance = second_square / count - second_mean * second_mean;
    if (first_variance <= 1.0e-12 || second_variance <= 1.0e-12) return -1.0;
    return covariance / std::sqrt(first_variance * second_variance);
}

}  // namespace negaflow::imaging::infrared_detail
