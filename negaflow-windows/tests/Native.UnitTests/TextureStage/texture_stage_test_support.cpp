#include "texture_stage_test_support.h"

#include "negaflow/imaging/coreimage_gaussian.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <utility>
#include <vector>

namespace texture_stage_tests {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] negaflow::imaging::WorkingImage texture_patch(
    const std::uint32_t width,
    const std::uint32_t height) {
    negaflow::imaging::WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.resize(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float stripe = ((x / 4U) & 1U) == 0U ? 0.10F : -0.08F;
            const float gradient =
                static_cast<float>(x) / static_cast<float>(width - 1U) * 0.22F +
                static_cast<float>(y) / static_cast<float>(height - 1U) * 0.18F;
            const float value = std::clamp(0.32F + gradient + stripe, 0.05F, 0.92F);
            image.pixels[static_cast<std::size_t>(y) * width + x] = {
                value + 0.04F,
                value,
                value - 0.03F,
                0.25F + 0.5F * static_cast<float>(y) /
                    static_cast<float>(height - 1U),
            };
        }
    }
    return image;
}

[[nodiscard]] negaflow::imaging::WorkingImage halation_patch() {
    auto image = texture_patch();
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            const float dx = static_cast<float>(x) -
                             static_cast<float>(image.width) * 0.5F;
            const float dy = static_cast<float>(y) -
                             static_cast<float>(image.height) * 0.5F;
            const float value = std::sqrt(dx * dx + dy * dy) < 10.0F
                ? 0.82F
                : 0.30F;
            auto& pixel = image.pixels[
                static_cast<std::size_t>(y) * image.width + x];
            pixel.red = value;
            pixel.green = value;
            pixel.blue = value;
            pixel.alpha = 1.0F;
        }
    }
    return image;
}

[[nodiscard]] float luma(const negaflow::core::Rgba32F value) noexcept {
    return value.red * 0.2126F + value.green * 0.7152F +
           value.blue * 0.0722F;
}

[[nodiscard]] float mean_luma(
    const negaflow::imaging::WorkingImage& image) noexcept {
    double sum = 0.0;
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            sum += luma(image.pixels[
                static_cast<std::size_t>(y) * image.stride_pixels + x]);
        }
    }
    return static_cast<float>(sum /
        static_cast<double>(image.width * image.height));
}

[[nodiscard]] float local_noise(
    const negaflow::imaging::WorkingImage& image) noexcept {
    double sum = 0.0;
    std::size_t count = 0U;
    for (std::uint32_t y = 1U; y + 1U < image.height; ++y) {
        for (std::uint32_t x = 1U; x + 1U < image.width; ++x) {
            const auto sample = [&](const std::uint32_t sx, const std::uint32_t sy) {
                return luma(image.pixels[
                    static_cast<std::size_t>(sy) * image.stride_pixels + sx]);
            };
            const float around =
                (sample(x - 1U, y) + sample(x + 1U, y) +
                 sample(x, y - 1U) + sample(x, y + 1U)) *
                0.25F;
            sum += std::abs(sample(x, y) - around);
            ++count;
        }
    }
    return static_cast<float>(sum / static_cast<double>(count));
}

[[nodiscard]] float mean_edge(
    const negaflow::imaging::WorkingImage& image) noexcept {
    double sum = 0.0;
    std::size_t count = 0U;
    for (std::uint32_t y = 1U; y + 1U < image.height; ++y) {
        for (std::uint32_t x = 1U; x + 1U < image.width; ++x) {
            const auto sample = [&](const std::uint32_t sx, const std::uint32_t sy) {
                return luma(image.pixels[
                    static_cast<std::size_t>(sy) * image.stride_pixels + sx]);
            };
            const float dx = sample(x + 1U, y) - sample(x - 1U, y);
            const float dy = sample(x, y + 1U) - sample(x, y - 1U);
            sum += std::sqrt(dx * dx + dy * dy);
            ++count;
        }
    }
    return static_cast<float>(sum / static_cast<double>(count));
}

[[nodiscard]] float mean_chroma(
    const negaflow::imaging::WorkingImage& image) noexcept {
    double sum = 0.0;
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            const auto pixel = image.pixels[
                static_cast<std::size_t>(y) * image.stride_pixels + x];
            const float value = luma(pixel);
            const float red = pixel.red - value;
            const float green = pixel.green - value;
            const float blue = pixel.blue - value;
            sum += std::sqrt(red * red + green * green + blue * blue);
        }
    }
    return static_cast<float>(sum /
        static_cast<double>(image.width * image.height));
}

[[nodiscard]] float region_mean(
    const negaflow::imaging::WorkingImage& image,
    const std::uint32_t x0,
    const std::uint32_t y0,
    const std::uint32_t width,
    const std::uint32_t height) noexcept {
    float sum = 0.0F;
    for (std::uint32_t y = y0; y < y0 + height; ++y) {
        for (std::uint32_t x = x0; x < x0 + width; ++x) {
            sum += luma(image.pixels[
                static_cast<std::size_t>(y) * image.stride_pixels + x]);
        }
    }
    return sum / static_cast<float>(width * height);
}

[[nodiscard]] bool same_pixels(
    const std::vector<negaflow::core::Rgba32F>& left,
    const std::vector<negaflow::core::Rgba32F>& right) noexcept {
    return left.size() == right.size() &&
           std::memcmp(
               left.data(),
               right.data(),
               left.size() * sizeof(negaflow::core::Rgba32F)) == 0;
}

[[nodiscard]] negaflow::imaging::WorkingImage load_rgba_f32(
    const std::filesystem::path& path) {
    constexpr std::uint32_t width = 256U;
    constexpr std::uint32_t height = 256U;
    std::ifstream input(path, std::ios::binary);
    std::vector<float> samples(
        static_cast<std::size_t>(width) * height * 4U);
    input.read(
        reinterpret_cast<char*>(samples.data()),
        static_cast<std::streamsize>(samples.size() * sizeof(float)));
    expect(
        input.good() || input.eof(),
        "Core Image f32 golden is readable");
    expect(
        input.gcount() == static_cast<std::streamsize>(samples.size() * sizeof(float)),
        "Core Image f32 golden has the expected RGBAf byte count");

    negaflow::imaging::WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.resize(static_cast<std::size_t>(width) * height);
    for (std::size_t index = 0U; index < image.pixels.size(); ++index) {
        image.pixels[index] = {
            samples[index * 4U],
            samples[index * 4U + 1U],
            samples[index * 4U + 2U],
            samples[index * 4U + 3U],
        };
    }
    return image;
}

[[nodiscard]] float max_abs_difference(
    const negaflow::imaging::WorkingImage& actual,
    const negaflow::imaging::WorkingImage& expected) noexcept {
    if (actual.width != expected.width || actual.height != expected.height ||
        actual.pixels.size() != expected.pixels.size()) {
        return std::numeric_limits<float>::infinity();
    }
    float maximum = 0.0F;
    for (std::size_t index = 0U; index < actual.pixels.size(); ++index) {
        const auto& left = actual.pixels[index];
        const auto& right = expected.pixels[index];
        maximum = std::max(maximum, std::abs(left.red - right.red));
        maximum = std::max(maximum, std::abs(left.green - right.green));
        maximum = std::max(maximum, std::abs(left.blue - right.blue));
        maximum = std::max(maximum, std::abs(left.alpha - right.alpha));
    }
    return maximum;
}

[[nodiscard]] negaflow::imaging::WorkingImage direct_coreimage_gaussian(
    const negaflow::imaging::WorkingImage& input,
    const float radius) {
    const float sigma = negaflow::imaging::coreimage_gaussian_effective_sigma(radius);
    const int support_radius =
        negaflow::imaging::coreimage_gaussian_support_radius(radius);
    std::vector<float> weights(
        static_cast<std::size_t>(support_radius * 2 + 1));
    float total = 0.0F;
    for (int offset = -support_radius; offset <= support_radius; ++offset) {
        const float weight = std::exp(
            -static_cast<float>(offset * offset) / (2.0F * sigma * sigma));
        weights[static_cast<std::size_t>(offset + support_radius)] = weight;
        total += weight;
    }
    for (float& weight : weights) {
        weight /= total;
    }

    auto horizontal = input;
    auto output = input;
    for (std::uint32_t y = 0U; y < input.height; ++y) {
        for (std::uint32_t x = 0U; x < input.width; ++x) {
            negaflow::core::Rgba32F value{};
            for (int offset = -support_radius;
                 offset <= support_radius;
                 ++offset) {
                const int sample_x = static_cast<int>(x) + offset;
                if (sample_x < 0 || sample_x >= static_cast<int>(input.width)) {
                    continue;
                }
                const auto& sample = input.pixels[
                    static_cast<std::size_t>(y) * input.stride_pixels +
                    static_cast<std::uint32_t>(sample_x)];
                const float weight =
                    weights[static_cast<std::size_t>(offset + support_radius)];
                value.red += sample.red * weight;
                value.green += sample.green * weight;
                value.blue += sample.blue * weight;
                value.alpha += sample.alpha * weight;
            }
            horizontal.pixels[static_cast<std::size_t>(y) * horizontal.stride_pixels + x] =
                value;
        }
    }
    for (std::uint32_t y = 0U; y < input.height; ++y) {
        for (std::uint32_t x = 0U; x < input.width; ++x) {
            negaflow::core::Rgba32F value{};
            for (int offset = -support_radius;
                 offset <= support_radius;
                 ++offset) {
                const int sample_y = static_cast<int>(y) + offset;
                if (sample_y < 0 || sample_y >= static_cast<int>(input.height)) {
                    continue;
                }
                const auto& sample = horizontal.pixels[
                    static_cast<std::size_t>(sample_y) * horizontal.stride_pixels + x];
                const float weight =
                    weights[static_cast<std::size_t>(offset + support_radius)];
                value.red += sample.red * weight;
                value.green += sample.green * weight;
                value.blue += sample.blue * weight;
                value.alpha += sample.alpha * weight;
            }
            output.pixels[static_cast<std::size_t>(y) * output.stride_pixels + x] = value;
        }
    }
    return output;
}

void expect_coreimage_close(
    const negaflow::imaging::WorkingImage& actual,
    const negaflow::imaging::WorkingImage& expected,
    const char* const message) {
    const float difference = max_abs_difference(actual, expected);
    // The CPU implementation is within 0.008 (about two encoded 8-bit levels) of every
    // supplied CIUnsharpMask/ CIGaussianBlur output. The remaining maximum is confined to
    // Core Image's undocumented CIUnsharpMask boundary kernel, while interior and direct
    // Gaussian values are substantially tighter; retain this executable ceiling so it cannot
    // silently drift farther from the golden contract.
    constexpr float coreimage_abs_error_budget = 0.0080F;
    if (difference >= coreimage_abs_error_budget) {
        for (std::uint32_t y = 0U; y < actual.height; ++y) {
            for (std::uint32_t x = 0U; x < actual.width; ++x) {
                const auto& left = actual.pixels[static_cast<std::size_t>(y) * actual.stride_pixels + x];
                const auto& right = expected.pixels[static_cast<std::size_t>(y) * expected.stride_pixels + x];
                if (std::abs(left.red - right.red) == difference ||
                    std::abs(left.green - right.green) == difference ||
                    std::abs(left.blue - right.blue) == difference ||
                    std::abs(left.alpha - right.alpha) == difference) {
                    std::cerr << "  max_abs_difference=" << difference
                              << " at=" << x << ',' << y << '\n';
                    y = actual.height;
                    break;
                }
            }
        }
    }
    expect(difference < coreimage_abs_error_budget, message);
}

[[nodiscard]] negaflow::imaging::WorkingImage mixed(
    const negaflow::imaging::WorkingImage& source,
    const negaflow::imaging::WorkingImage& blurred,
    const float amount) {
    auto result = source;
    for (std::size_t index = 0U; index < result.pixels.size(); ++index) {
        auto& destination = result.pixels[index];
        const auto& target = blurred.pixels[index];
        destination.red += (target.red - destination.red) * amount;
        destination.green += (target.green - destination.green) * amount;
        destination.blue += (target.blue - destination.blue) * amount;
        destination.alpha += (target.alpha - destination.alpha) * amount;
    }
    return result;
}

}  // namespace texture_stage_tests
