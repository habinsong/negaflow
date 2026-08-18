#include "manual_negative_test_support.h"

#include "negaflow/core/negative_inversion.h"
#include "negaflow/imaging/auto_negative_base_resolver.h"
#include "negaflow/imaging/film_stock_base_resolver.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <limits>
#include <utility>
#include <vector>

namespace manual_negative_tests {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] bool pixels_equal(
    const negaflow::core::Rgba32F& left,
    const negaflow::core::Rgba32F& right) noexcept {
    return left.red == right.red && left.green == right.green &&
           left.blue == right.blue && left.alpha == right.alpha;
}

[[nodiscard]] bool images_equal(
    const std::vector<negaflow::core::Rgba32F>& left,
    const std::vector<negaflow::core::Rgba32F>& right) noexcept {
    if (left.size() != right.size()) {
        return false;
    }
    for (std::size_t index = 0U; index < left.size(); ++index) {
        if (!pixels_equal(left[index], right[index])) {
            return false;
        }
    }
    return true;
}

negaflow::imaging::WorkingImage make_working_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 2U;
    image.height = 1U;
    image.stride_pixels = 2U;
    image.pixels = {
        {0.72F, 0.32F, 0.15F, 1.0F},
        {0.12F, 0.08F, 0.04F, 0.5F},
    };
    return image;
}

negaflow::imaging::WorkingImage make_scene_working_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 64U;
    image.height = 16U;
    image.stride_pixels = image.width;
    image.pixels.resize(static_cast<std::size_t>(image.width) * image.height);
    for (std::uint32_t row = 0U; row < image.height; ++row) {
        for (std::uint32_t column = 0U; column < image.width; ++column) {
            const float density = column < 8U ? 1.10F : 0.55F;
            image.pixels[static_cast<std::size_t>(row) * image.width + column] = {
                0.80F * std::pow(10.0F, -density),
                0.60F * std::pow(10.0F, -(density * 0.90F)),
                0.40F * std::pow(10.0F, -(density * 0.80F)),
                1.0F,
            };
        }
    }
    return image;
}

negaflow::imaging::WorkingImage make_affine_proxy_scene_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 640U;
    image.height = 65U;
    image.stride_pixels = image.width;
    image.pixels.resize(static_cast<std::size_t>(image.width) * image.height);
    for (std::uint32_t row = 0U; row < image.height; ++row) {
        for (std::uint32_t column = 0U; column < image.width; ++column) {
            image.pixels[static_cast<std::size_t>(row) * image.width + column] = {
                column % 2U == 0U ? 0.08F : 0.16F,
                row % 2U == 0U ? 0.08F : 0.16F,
                0.12F,
                1.0F,
            };
        }
    }
    return image;
}

negaflow::imaging::WorkingImage make_affine_auto_base_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 512U;
    image.height = 129U;
    image.stride_pixels = image.width;
    image.pixels.resize(static_cast<std::size_t>(image.width) * image.height);
    for (std::uint32_t row = 0U; row < image.height; ++row) {
        for (std::uint32_t column = 0U; column < image.width; ++column) {
            image.pixels[static_cast<std::size_t>(row) * image.width + column] = {
                column % 2U == 0U ? 0.56F : 0.72F,
                row % 2U == 0U ? 0.40F : 0.56F,
                0.32F,
                1.0F,
            };
        }
    }
    return image;
}

negaflow::imaging::WorkingImage make_auto_base_image(
    const negaflow::core::Rgba32F& base) {
    negaflow::imaging::WorkingImage image{};
    image.width = 64U;
    image.height = 16U;
    image.stride_pixels = image.width;
    image.pixels.resize(static_cast<std::size_t>(image.width) * image.height);
    for (std::uint32_t row = 0U; row < image.height; ++row) {
        for (std::uint32_t column = 0U; column < image.width; ++column) {
            const bool edge = column < 4U || column + 4U >= image.width ||
                row < 2U || row + 2U >= image.height;
            image.pixels[static_cast<std::size_t>(row) * image.width + column] = edge
                ? base
                : negaflow::core::Rgba32F{0.20F, 0.12F, 0.06F, 1.0F};
        }
    }
    return image;
}

negaflow::imaging::WorkingImage make_auto_base_component_with_luma_outliers() {
    negaflow::imaging::WorkingImage image{};
    image.width = 64U;
    image.height = 16U;
    image.stride_pixels = image.width;
    image.pixels.assign(
        static_cast<std::size_t>(image.width) * image.height,
        negaflow::core::Rgba32F{0.005F, 0.005F, 0.005F, 1.0F});

    std::size_t component_index = 0U;
    for (std::uint32_t row = 4U; row < 8U; ++row) {
        for (std::uint32_t column = 8U; column < 20U; ++column) {
            negaflow::core::Rgba32F pixel{};
            if (component_index < 24U) {
                pixel = {0.70F, 0.53F, 0.39F, 1.0F};
            } else if (component_index < 37U) {
                const float offset = static_cast<float>(component_index - 24U);
                pixel = {
                    0.72F + offset * 0.0002F,
                    0.54F + offset * 0.0001F,
                    0.40F + offset * 0.00005F,
                    1.0F,
                };
            } else {
                pixel = {0.77F, 0.59F, 0.45F, 1.0F};
            }
            image.pixels[static_cast<std::size_t>(row) * image.width + column] = pixel;
            ++component_index;
        }
    }
    return image;
}

negaflow::imaging::WorkingImage make_auto_base_component_order_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 64U;
    image.height = 16U;
    image.stride_pixels = image.width;
    image.pixels.assign(
        static_cast<std::size_t>(image.width) * image.height,
        negaflow::core::Rgba32F{0.005F, 0.005F, 0.005F, 1.0F});

    const auto fill_component = [&image](
                                    const std::uint32_t first_column,
                                    const float luma,
                                    const float lower_red_blue,
                                    const float upper_red_blue) {
        std::size_t component_index = 0U;
        for (std::uint32_t row = 2U; row < 6U; ++row) {
            for (std::uint32_t column = first_column; column < first_column + 6U; ++column) {
                const float red_blue = component_index < 12U
                    ? lower_red_blue
                    : upper_red_blue;
                image.pixels[static_cast<std::size_t>(row) * image.width + column] = {
                    luma + red_blue * 0.5F,
                    luma,
                    luma - red_blue * 0.5F,
                    1.0F,
                };
                ++component_index;
            }
        }
    };
    fill_component(2U, 0.70F, 0.08F, 0.14F);
    fill_component(14U, 0.50F, 0.12F, 0.12F);
    fill_component(26U, 0.35F, 0.22F, 0.22F);
    return image;
}

negaflow::imaging::WorkingImage make_auto_base_double_luma_boundary_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 32U;
    image.height = 32U;
    image.stride_pixels = image.width;
    image.pixels.assign(
        static_cast<std::size_t>(image.width) * image.height,
        negaflow::core::Rgba32F{0.005F, 0.005F, 0.005F, 1.0F});
    for (std::uint32_t row = 12U; row < 16U; ++row) {
        for (std::uint32_t column = 12U; column < 18U; ++column) {
            image.pixels[static_cast<std::size_t>(row) * image.width + column] = {
                0.949992359F,
                0.85F,
                0.7500076F,
                1.0F,
            };
        }
    }
    return image;
}

negaflow::imaging::WorkingImage make_auto_base_edge_fraction_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 100U;
    image.height = 50U;
    image.stride_pixels = image.width;
    image.pixels.assign(
        static_cast<std::size_t>(image.width) * image.height,
        negaflow::core::Rgba32F{0.005F, 0.005F, 0.005F, 1.0F});
    for (const std::uint32_t first_column : {0U, 15U, 30U, 45U, 60U}) {
        for (std::uint32_t column = first_column; column < first_column + 13U; ++column) {
            image.pixels[2U * image.width + column] = {0.70F, 0.50F, 0.30F, 1.0F};
        }
    }
    return image;
}

negaflow::imaging::WorkingImage make_scene_edge_fallback_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 128U;
    image.height = 64U;
    image.stride_pixels = image.width;
    image.pixels.assign(
        static_cast<std::size_t>(image.width) * image.height,
        negaflow::core::Rgba32F{0.005F, 0.005F, 0.005F, 1.0F});
    for (std::uint32_t index = 0U; index < 20U; ++index) {
        const std::uint32_t column = 4U + index * 6U;
        image.pixels[column] = {0.48F, 0.32F, 0.16F, 1.0F};
        image.pixels[
            static_cast<std::size_t>(image.height - 1U) * image.width + column] =
            {0.48F, 0.32F, 0.16F, 1.0F};
    }
    return image;
}

negaflow::imaging::WorkingImage make_affine_scene_edge_fallback_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 640U;
    image.height = 64U;
    image.stride_pixels = image.width;
    image.pixels.assign(
        static_cast<std::size_t>(image.width) * image.height,
        negaflow::core::Rgba32F{0.005F, 0.005F, 0.005F, 1.0F});
    for (std::uint32_t index = 0U; index < 20U; ++index) {
        const std::uint32_t target_column = 4U + index * 15U;
        const std::uint32_t source_column = target_column * 2U;
        for (const std::uint32_t row : {0U, 1U, image.height - 2U, image.height - 1U}) {
            image.pixels[static_cast<std::size_t>(row) * image.width + source_column] =
                {0.005F, 0.005F, 0.005F, 1.0F};
            image.pixels[static_cast<std::size_t>(row) * image.width + source_column + 1U] =
                {0.955F, 0.635F, 0.315F, 1.0F};
        }
    }
    return image;
}

negaflow::imaging::WorkingImage make_uniform_working_image(
    const negaflow::core::Rgba32F pixel,
    const std::uint32_t width,
    const std::uint32_t height) {
    negaflow::imaging::WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.assign(static_cast<std::size_t>(width) * height, pixel);
    return image;
}


}  // namespace manual_negative_tests
