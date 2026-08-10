#include "negaflow/imaging/film_scan_denoise.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <utility>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] negaflow::imaging::WorkingImage make_noisy_image(
    const std::uint32_t width,
    const std::uint32_t height) {
    negaflow::imaging::WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.resize(static_cast<std::size_t>(width) * height);
    std::uint32_t state = 0x6d2b79f5U;
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const bool right = x >= width / 2U;
            const float base_red = right ? 0.68F : 0.47F;
            const float base_green = right ? 0.14F : 0.43F;
            const float base_blue = right ? 0.12F : 0.375F;
            state = state * 1664525U + 1013904223U;
            const float luma_noise =
                (static_cast<float>((state >> 8U) & 0xffffU) / 65535.0F -
                 0.5F) *
                0.032F;
            state = state * 1664525U + 1013904223U;
            const float chroma_noise =
                (static_cast<float>((state >> 8U) & 0xffffU) / 65535.0F -
                 0.5F) *
                0.044F;
            const bool clean_edge_band =
                x + 8U >= width / 2U && x < width / 2U + 8U;
            const float applied_luma_noise =
                clean_edge_band ? 0.0F : luma_noise;
            const float applied_chroma_noise =
                clean_edge_band ? 0.0F : chroma_noise;
            image.pixels[static_cast<std::size_t>(y) * width + x] = {
                base_red + applied_luma_noise + applied_chroma_noise,
                base_green + applied_luma_noise - applied_chroma_noise * 0.55F,
                base_blue + applied_luma_noise - applied_chroma_noise * 0.45F,
                0.35F + 0.6F * static_cast<float>(y) /
                    static_cast<float>(height - 1U),
            };
        }
    }
    return image;
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

[[nodiscard]] float luma(
    const negaflow::core::Rgba32F value) noexcept {
    return value.red * 0.2126F + value.green * 0.7152F +
           value.blue * 0.0722F;
}

[[nodiscard]] float flat_field_error(
    const negaflow::imaging::WorkingImage& image,
    const bool right,
    const bool chroma) noexcept {
    const float base_red = right ? 0.68F : 0.47F;
    const float base_green = right ? 0.14F : 0.43F;
    const float base_blue = right ? 0.12F : 0.375F;
    const float base_luma =
        base_red * 0.2126F + base_green * 0.7152F + base_blue * 0.0722F;
    float total = 0.0F;
    std::size_t samples = 0U;
    const std::uint32_t left = right ? image.width / 2U + 8U : 8U;
    const std::uint32_t end = right ? image.width - 8U : image.width / 2U - 8U;
    for (std::uint32_t y = 8U; y + 8U < image.height; ++y) {
        for (std::uint32_t x = left; x < end; ++x) {
            const auto pixel =
                image.pixels[static_cast<std::size_t>(y) * image.stride_pixels + x];
            const float pixel_luma = luma(pixel);
            if (chroma) {
                const float red_chroma = pixel.red - pixel_luma;
                const float green_chroma = pixel.green - pixel_luma;
                const float blue_chroma = pixel.blue - pixel_luma;
                total += std::abs(red_chroma - (base_red - base_luma)) +
                         std::abs(green_chroma - (base_green - base_luma)) +
                         std::abs(blue_chroma - (base_blue - base_luma));
            } else {
                total += std::abs(pixel_luma - base_luma);
            }
            ++samples;
        }
    }
    return total / static_cast<float>(samples);
}

void test_identity_and_invalid_inputs() {
    auto source = make_noisy_image(64U, 48U);
    const auto original = source.pixels;
    const auto identity = negaflow::imaging::apply_film_scan_denoise(
        source,
        {});
    expect(
        identity.status == negaflow::imaging::FilmScanDenoiseStatus::ok &&
            !identity.info.applied && same_pixels(identity.image.pixels, original),
        "strength zero is a byte-exact no-op");

    negaflow::imaging::FilmScanDenoiseParameters invalid{};
    invalid.strength = std::numeric_limits<float>::quiet_NaN();
    const auto invalid_parameter =
        negaflow::imaging::apply_film_scan_denoise(source, invalid);
    expect(
        invalid_parameter.status ==
                negaflow::imaging::FilmScanDenoiseStatus::invalid_parameter &&
            invalid_parameter.image.pixels.empty(),
        "non-finite controls fail closed");

    source.pixels[0].blue = std::numeric_limits<float>::infinity();
    invalid.strength = 1.0F;
    const auto invalid_pixels = negaflow::imaging::apply_film_scan_denoise(
        std::move(source),
        invalid);
    expect(
        invalid_pixels.status ==
                negaflow::imaging::FilmScanDenoiseStatus::kernel_failed &&
            invalid_pixels.info.kernel_status ==
                negaflow::core::KernelStatus::non_finite_input &&
            invalid_pixels.image.pixels.empty(),
        "non-finite source pixels fail closed without partial output");
}

void test_color_noise_reduction_preserves_edge_and_alpha() {
    auto source = make_noisy_image(128U, 80U);
    const auto original = source;
    negaflow::imaging::FilmScanDenoiseParameters parameters{};
    parameters.strength = 1.0F;
    const auto result = negaflow::imaging::apply_film_scan_denoise(
        std::move(source),
        parameters);
    expect(
        result.status == negaflow::imaging::FilmScanDenoiseStatus::ok &&
            result.info.applied && result.info.tiles_processed == 1U &&
            result.info.output_scratch_bytes == 128U * 80U * 12U,
        "the color-negative CPU oracle completes one bounded tile");

    const float luma_before =
        flat_field_error(original, false, false) +
        flat_field_error(original, true, false);
    const float luma_after =
        flat_field_error(result.image, false, false) +
        flat_field_error(result.image, true, false);
    const float chroma_before =
        flat_field_error(original, false, true) +
        flat_field_error(original, true, true);
    const float chroma_after =
        flat_field_error(result.image, false, true) +
        flat_field_error(result.image, true, true);
    expect(luma_after < luma_before * 0.92F,
           "flat-field luma noise is reduced");
    expect(chroma_after < chroma_before * 0.82F,
           "flat-field chroma noise is reduced");

    float left_luma = 0.0F;
    float right_luma = 0.0F;
    for (std::uint32_t y = 12U; y < 68U; ++y) {
        left_luma += luma(result.image.pixels[y * result.image.width + 62U]);
        right_luma += luma(result.image.pixels[y * result.image.width + 65U]);
    }
    const float output_edge = (right_luma - left_luma) / 56.0F;
    const float expected_edge =
        (0.68F * 0.2126F + 0.14F * 0.7152F + 0.12F * 0.0722F) -
        (0.47F * 0.2126F + 0.43F * 0.7152F + 0.375F * 0.0722F);
    expect(std::abs(output_edge) > std::abs(expected_edge) * 0.82F,
           "guided structure protection retains the step edge");

    bool alpha_preserved = true;
    for (std::size_t index = 0U; index < original.pixels.size(); ++index) {
        alpha_preserved = alpha_preserved &&
            result.image.pixels[index].alpha == original.pixels[index].alpha;
    }
    expect(alpha_preserved, "FilmScanDenoise preserves alpha exactly");
}

void test_monochrome_profile_and_tile_boundary() {
    auto source = make_noisy_image(530U, 32U);
    const auto original = source;
    negaflow::imaging::FilmScanDenoiseParameters parameters{};
    parameters.strength = 0.85F;
    parameters.film_profile =
        negaflow::imaging::FilmScanDenoiseFilmProfile::black_and_white_negative;
    const auto result = negaflow::imaging::apply_film_scan_denoise(
        std::move(source),
        parameters);
    expect(
        result.status == negaflow::imaging::FilmScanDenoiseStatus::ok &&
            result.info.tiles_processed == 2U,
        "a frame wider than 512 pixels uses two overlap tiles");

    float maximum_lifted_chroma_error = 0.0F;
    for (std::size_t index = 0U; index < original.pixels.size(); ++index) {
        const auto input = original.pixels[index];
        const auto output = result.image.pixels[index];
        const float input_red = std::pow(std::clamp(input.red, 0.0F, 1.0F), 0.45F);
        const float input_green = std::pow(std::clamp(input.green, 0.0F, 1.0F), 0.45F);
        const float input_blue = std::pow(std::clamp(input.blue, 0.0F, 1.0F), 0.45F);
        const float output_red = std::pow(output.red, 0.45F);
        const float output_green = std::pow(output.green, 0.45F);
        const float output_blue = std::pow(output.blue, 0.45F);
        maximum_lifted_chroma_error = std::max({
            maximum_lifted_chroma_error,
            std::abs((output_red - output_green) -
                     (input_red - input_green)),
            std::abs((output_blue - output_green) -
                     (input_blue - input_green)),
        });
    }
    expect(maximum_lifted_chroma_error < 2.0e-5F,
           "the black-and-white profile leaves lifted-domain chroma unchanged");

    float seam_jump = 0.0F;
    float neighboring_jump = 0.0F;
    for (std::uint32_t y = 4U; y + 4U < result.image.height; ++y) {
        const auto* const row = result.image.pixels.data() +
            static_cast<std::size_t>(y) * result.image.stride_pixels;
        seam_jump += std::abs(luma(row[512U]) - luma(row[511U]));
        neighboring_jump +=
            std::abs(luma(row[511U]) - luma(row[510U])) +
            std::abs(luma(row[513U]) - luma(row[512U]));
    }
    expect(seam_jump <= neighboring_jump * 1.5F,
           "the overlap apron does not introduce a 512-pixel tile seam");
}

}  // namespace

int main() {
    test_identity_and_invalid_inputs();
    test_color_noise_reduction_preserves_edge_and_alpha();
    test_monochrome_profile_and_tile_boundary();

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"film_scan_denoise\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
