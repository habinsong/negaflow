#include "film_scan_denoise_filters.h"

#include "film_scan_denoise_math.h"

#include "negaflow/imaging/coreimage_gaussian.h"

#include <algorithm>
#include <cmath>
#include <cstddef>

namespace negaflow::imaging::film_scan_denoise_detail {

[[nodiscard]] std::vector<Rgb> gaussian_blur(
    const std::vector<Rgb>& source,
    const std::uint32_t width,
    const std::uint32_t height) {
    const float sigma = coreimage_gaussian_effective_sigma(gaussian_radius);
    const int support_radius = coreimage_gaussian_support_radius(gaussian_radius);
    std::vector<float> weights(
        static_cast<std::size_t>(support_radius * 2 + 1));
    float total = 0.0F;
    for (int offset = -support_radius; offset <= support_radius; ++offset) {
        const float value = std::exp(
            -static_cast<float>(offset * offset) /
            (2.0F * sigma * sigma));
        weights[static_cast<std::size_t>(offset + support_radius)] = value;
        total += value;
    }
    for (float& weight : weights) {
        weight /= total;
    }

    std::vector<Rgb> horizontal(source.size());
    std::vector<Rgb> result(source.size());
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            Rgb value{};
            for (int offset = -support_radius;
                 offset <= support_radius;
                 ++offset) {
                const std::uint32_t sample_x = static_cast<std::uint32_t>(
                    std::clamp(
                        static_cast<int>(x) + offset,
                        0,
                        static_cast<int>(width) - 1));
                value = value + source[index_of(sample_x, y, width)] *
                    weights[static_cast<std::size_t>(offset + support_radius)];
            }
            horizontal[index_of(x, y, width)] = value;
        }
    }
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            Rgb value{};
            for (int offset = -support_radius;
                 offset <= support_radius;
                 ++offset) {
                const std::uint32_t sample_y = static_cast<std::uint32_t>(
                    std::clamp(
                        static_cast<int>(y) + offset,
                        0,
                        static_cast<int>(height) - 1));
                value = value + horizontal[index_of(x, sample_y, width)] *
                    weights[static_cast<std::size_t>(offset + support_radius)];
            }
            result[index_of(x, y, width)] = value;
        }
    }
    return result;
}

[[nodiscard]] float median9(std::array<float, 9U> values) noexcept {
    std::nth_element(values.begin(), values.begin() + 4, values.end());
    return values[4];
}

[[nodiscard]] std::vector<Rgb> median3(
    const std::vector<Rgb>& source,
    const std::uint32_t width,
    const std::uint32_t height) {
    std::vector<Rgb> result(source.size());
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            std::array<float, 9U> red{};
            std::array<float, 9U> green{};
            std::array<float, 9U> blue{};
            std::size_t cursor = 0U;
            for (int dy = -1; dy <= 1; ++dy) {
                const std::uint32_t sample_y = static_cast<std::uint32_t>(
                    std::clamp(
                        static_cast<int>(y) + dy,
                        0,
                        static_cast<int>(height) - 1));
                for (int dx = -1; dx <= 1; ++dx) {
                    const std::uint32_t sample_x = static_cast<std::uint32_t>(
                        std::clamp(
                            static_cast<int>(x) + dx,
                            0,
                            static_cast<int>(width) - 1));
                    const Rgb sample = source[index_of(sample_x, sample_y, width)];
                    red[cursor] = sample.red;
                    green[cursor] = sample.green;
                    blue[cursor] = sample.blue;
                    ++cursor;
                }
            }
            result[index_of(x, y, width)] = {
                median9(red),
                median9(green),
                median9(blue),
            };
        }
    }
    return result;
}

[[nodiscard]] std::vector<float> box_blur(
    const std::vector<float>& source,
    const std::uint32_t width,
    const std::uint32_t height,
    const int radius) {
    std::vector<float> horizontal(source.size());
    std::vector<float> result(source.size());
    const float inverse = 1.0F / static_cast<float>(radius * 2 + 1);

    for (std::uint32_t y = 0U; y < height; ++y) {
        float sum = 0.0F;
        for (int offset = -radius; offset <= radius; ++offset) {
            const std::uint32_t sample_x = static_cast<std::uint32_t>(
                std::clamp(offset, 0, static_cast<int>(width) - 1));
            sum += source[index_of(sample_x, y, width)];
        }
        for (std::uint32_t x = 0U; x < width; ++x) {
            horizontal[index_of(x, y, width)] = sum * inverse;
            const std::uint32_t remove_x = static_cast<std::uint32_t>(
                std::clamp(
                    static_cast<int>(x) - radius,
                    0,
                    static_cast<int>(width) - 1));
            const std::uint32_t add_x = static_cast<std::uint32_t>(
                std::clamp(
                    static_cast<int>(x) + radius + 1,
                    0,
                    static_cast<int>(width) - 1));
            sum += source[index_of(add_x, y, width)] -
                   source[index_of(remove_x, y, width)];
        }
    }
    for (std::uint32_t x = 0U; x < width; ++x) {
        float sum = 0.0F;
        for (int offset = -radius; offset <= radius; ++offset) {
            const std::uint32_t sample_y = static_cast<std::uint32_t>(
                std::clamp(offset, 0, static_cast<int>(height) - 1));
            sum += horizontal[index_of(x, sample_y, width)];
        }
        for (std::uint32_t y = 0U; y < height; ++y) {
            result[index_of(x, y, width)] = sum * inverse;
            const std::uint32_t remove_y = static_cast<std::uint32_t>(
                std::clamp(
                    static_cast<int>(y) - radius,
                    0,
                    static_cast<int>(height) - 1));
            const std::uint32_t add_y = static_cast<std::uint32_t>(
                std::clamp(
                    static_cast<int>(y) + radius + 1,
                    0,
                    static_cast<int>(height) - 1));
            sum += horizontal[index_of(x, add_y, width)] -
                   horizontal[index_of(x, remove_y, width)];
        }
    }
    return result;
}

[[nodiscard]] std::vector<Rgb> box_blur(
    const std::vector<Rgb>& source,
    const std::uint32_t width,
    const std::uint32_t height,
    const int radius) {
    std::vector<Rgb> horizontal(source.size());
    std::vector<Rgb> result(source.size());
    const float inverse = 1.0F / static_cast<float>(radius * 2 + 1);

    for (std::uint32_t y = 0U; y < height; ++y) {
        Rgb sum{};
        for (int offset = -radius; offset <= radius; ++offset) {
            const std::uint32_t sample_x = static_cast<std::uint32_t>(
                std::clamp(offset, 0, static_cast<int>(width) - 1));
            sum = sum + source[index_of(sample_x, y, width)];
        }
        for (std::uint32_t x = 0U; x < width; ++x) {
            horizontal[index_of(x, y, width)] = sum * inverse;
            const std::uint32_t remove_x = static_cast<std::uint32_t>(
                std::clamp(
                    static_cast<int>(x) - radius,
                    0,
                    static_cast<int>(width) - 1));
            const std::uint32_t add_x = static_cast<std::uint32_t>(
                std::clamp(
                    static_cast<int>(x) + radius + 1,
                    0,
                    static_cast<int>(width) - 1));
            sum = sum + source[index_of(add_x, y, width)] -
                  source[index_of(remove_x, y, width)];
        }
    }
    for (std::uint32_t x = 0U; x < width; ++x) {
        Rgb sum{};
        for (int offset = -radius; offset <= radius; ++offset) {
            const std::uint32_t sample_y = static_cast<std::uint32_t>(
                std::clamp(offset, 0, static_cast<int>(height) - 1));
            sum = sum + horizontal[index_of(x, sample_y, width)];
        }
        for (std::uint32_t y = 0U; y < height; ++y) {
            result[index_of(x, y, width)] = sum * inverse;
            const std::uint32_t remove_y = static_cast<std::uint32_t>(
                std::clamp(
                    static_cast<int>(y) - radius,
                    0,
                    static_cast<int>(height) - 1));
            const std::uint32_t add_y = static_cast<std::uint32_t>(
                std::clamp(
                    static_cast<int>(y) + radius + 1,
                    0,
                    static_cast<int>(height) - 1));
            sum = sum + horizontal[index_of(x, add_y, width)] -
                  horizontal[index_of(x, remove_y, width)];
        }
    }
    return result;
}

[[nodiscard]] std::vector<Rgb> guided_base(
    const std::vector<Rgb>& source,
    const std::vector<float>& guide,
    const std::uint32_t width,
    const std::uint32_t height,
    const int radius) {
    std::vector<float> guide_squared(guide.size());
    std::vector<Rgb> guide_product(source.size());
    for (std::size_t index = 0U; index < source.size(); ++index) {
        guide_squared[index] = guide[index] * guide[index];
        guide_product[index] = source[index] * guide[index];
    }

    const std::vector<float> mean_guide =
        box_blur(guide, width, height, radius);
    const std::vector<Rgb> mean_source =
        box_blur(source, width, height, radius);
    const std::vector<float> mean_guide_squared =
        box_blur(guide_squared, width, height, radius);
    const std::vector<Rgb> mean_guide_product =
        box_blur(guide_product, width, height, radius);

    std::vector<Rgb> coefficient_a(source.size());
    std::vector<Rgb> coefficient_b(source.size());
    for (std::size_t index = 0U; index < source.size(); ++index) {
        const float variance = std::max(
            0.0F,
            mean_guide_squared[index] -
                mean_guide[index] * mean_guide[index]);
        const Rgb covariance =
            mean_guide_product[index] - mean_source[index] * mean_guide[index];
        coefficient_a[index] = covariance * (1.0F / (variance + guided_epsilon));
        coefficient_b[index] =
            mean_source[index] - coefficient_a[index] * mean_guide[index];
    }

    const std::vector<Rgb> mean_a =
        box_blur(coefficient_a, width, height, radius);
    const std::vector<Rgb> mean_b =
        box_blur(coefficient_b, width, height, radius);
    std::vector<Rgb> result(source.size());
    for (std::size_t index = 0U; index < source.size(); ++index) {
        result[index] = clamp_unit(mean_a[index] * guide[index] + mean_b[index]);
    }
    return result;
}

}  // namespace negaflow::imaging::film_scan_denoise_detail
