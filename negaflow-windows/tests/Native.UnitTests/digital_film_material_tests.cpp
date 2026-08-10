#include "negaflow/imaging/digital_film_grain.h"
#include "negaflow/imaging/digital_halation.h"
#include "negaflow/imaging/digital_film_color_preset.h"
#include "negaflow/imaging/film_emulation_acutance.h"
#include "negaflow/imaging/film_emulation_registry.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] negaflow::imaging::WorkingImage solid(
    const std::uint32_t width,
    const std::uint32_t height,
    const float value) {
    negaflow::imaging::WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.resize(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            image.pixels[static_cast<std::size_t>(y) * width + x] = {
                value, value, value,
                0.2F + 0.6F * static_cast<float>(y) /
                    static_cast<float>(std::max(1U, height - 1U))};
        }
    }
    return image;
}

[[nodiscard]] negaflow::imaging::WorkingImage highlight_spot() {
    auto image = solid(128U, 128U, 0.02F);
    for (std::uint32_t y = 58U; y < 70U; ++y) {
        for (std::uint32_t x = 58U; x < 70U; ++x) {
            auto& pixel = image.pixels[static_cast<std::size_t>(y) * 128U + x];
            pixel.red = 3.0F;
            pixel.green = 3.0F;
            pixel.blue = 3.0F;
        }
    }
    return image;
}

[[nodiscard]] negaflow::imaging::WorkingImage patterned(
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels) {
    negaflow::imaging::WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = stride_pixels;
    image.pixels.resize(static_cast<std::size_t>(stride_pixels) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        const std::size_t row_offset =
            static_cast<std::size_t>(y) * stride_pixels;
        for (std::uint32_t x = 0U; x < stride_pixels; ++x) {
            if (x >= width) {
                image.pixels[row_offset + x] = {
                    0.125F, 0.25F, 0.5F, 0.75F};
                continue;
            }
            image.pixels[row_offset + x] = {
                static_cast<float>((x * 17U + y * 13U) % 1021U) / 1020.0F,
                static_cast<float>((x * 7U + y * 29U) % 1013U) / 1012.0F,
                static_cast<float>((x * 31U + y * 5U) % 1009U) / 1008.0F,
                static_cast<float>((x + y) % 251U) / 250.0F,
            };
        }
    }
    return image;
}

[[nodiscard]] float reference_linear_to_srgb(const float value) noexcept {
    return value <= 0.0031308F
        ? value * 12.92F
        : 1.055F * std::pow(std::max(value, 0.0F), 1.0F / 2.4F) - 0.055F;
}

[[nodiscard]] float reference_srgb_to_linear(const float value) noexcept {
    return value <= 0.04045F
        ? value / 12.92F
        : std::pow(std::max((value + 0.055F) / 1.055F, 0.0F), 2.4F);
}

[[nodiscard]] negaflow::imaging::WorkingImage untiled_color_preset_reference(
    negaflow::imaging::WorkingImage image,
    const negaflow::imaging::FilmEmulation emulation,
    const double intensity) {
    const auto original = image;
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        const std::size_t row_offset =
            static_cast<std::size_t>(y) * image.stride_pixels;
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            auto& pixel = image.pixels[row_offset + x];
            pixel.red = reference_linear_to_srgb(pixel.red);
            pixel.green = reference_linear_to_srgb(pixel.green);
            pixel.blue = reference_linear_to_srgb(pixel.blue);
        }
    }
    const auto input = negaflow::core::ConstImageView{
        image.pixels.data(), image.pixels.size(), image.width, image.height,
        image.stride_pixels};
    const auto output = negaflow::core::ImageView{
        image.pixels.data(), image.pixels.size(), image.width, image.height,
        image.stride_pixels};
    const auto* const preset =
        negaflow::imaging::digital_film_color_preset(emulation);
    const auto mixer_status = negaflow::imaging::apply_color_mixer(
        input, output, preset->mixer);
    const auto grading_status = negaflow::imaging::apply_color_grading(
        input, output, preset->grading);
    const auto calibration_status =
        negaflow::imaging::apply_primary_calibration(
            input, output, preset->calibration);
    expect(
        mixer_status == negaflow::core::KernelStatus::ok &&
            grading_status == negaflow::core::KernelStatus::ok &&
            calibration_status == negaflow::core::KernelStatus::ok,
        "untiled color-preset reference kernels succeed");

    const float strength = static_cast<float>(
        std::clamp(intensity, 0.0, 1.0));
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        const std::size_t row_offset =
            static_cast<std::size_t>(y) * image.stride_pixels;
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            auto& pixel = image.pixels[row_offset + x];
            const auto& source = original.pixels[row_offset + x];
            const float red = reference_srgb_to_linear(pixel.red);
            const float green = reference_srgb_to_linear(pixel.green);
            const float blue = reference_srgb_to_linear(pixel.blue);
            pixel.red = source.red + (red - source.red) * strength;
            pixel.green = source.green + (green - source.green) * strength;
            pixel.blue = source.blue + (blue - source.blue) * strength;
        }
    }
    return image;
}

[[nodiscard]] bool same_pixels(
    const std::vector<negaflow::core::Rgba32F>& left,
    const std::vector<negaflow::core::Rgba32F>& right) noexcept {
    return left.size() == right.size() &&
           std::memcmp(
               left.data(), right.data(),
               left.size() * sizeof(left.front())) == 0;
}

[[nodiscard]] double channel_sum(
    const negaflow::imaging::WorkingImage& image,
    const std::size_t channel) noexcept {
    double sum = 0.0;
    for (const auto pixel : image.pixels) {
        const float values[]{pixel.red, pixel.green, pixel.blue};
        sum += values[channel];
    }
    return sum;
}

[[nodiscard]] double standard_deviation(
    const negaflow::imaging::WorkingImage& image) noexcept {
    double sum = 0.0;
    double square_sum = 0.0;
    for (const auto pixel : image.pixels) {
        sum += pixel.green;
        square_sum += static_cast<double>(pixel.green) * pixel.green;
    }
    const double count = static_cast<double>(image.pixels.size());
    const double mean = sum / count;
    return std::sqrt(std::max(0.0, square_sum / count - mean * mean));
}

void test_fixed_stock_material_table() {
    using negaflow::imaging::FilmEmulation;
    const FilmEmulation stocks[]{
        FilmEmulation::ektachrome_e100, FilmEmulation::provia_100f,
        FilmEmulation::velvia_50, FilmEmulation::portra_160,
        FilmEmulation::portra_400, FilmEmulation::portra_800,
        FilmEmulation::ektar_100, FilmEmulation::ultramax_400,
        FilmEmulation::colorplus_200, FilmEmulation::fujicolor_c200,
        FilmEmulation::pro_400h, FilmEmulation::velvia_100,
        FilmEmulation::e100_vs, FilmEmulation::astia_100f,
        FilmEmulation::kodachrome_64, FilmEmulation::gold_200,
        FilmEmulation::pro_image_100, FilmEmulation::superia_400,
        FilmEmulation::superia_premium_400, FilmEmulation::superia_200,
        FilmEmulation::reala_100, FilmEmulation::industrial_100,
        FilmEmulation::lomo_cn_800, FilmEmulation::vision3_500t,
        FilmEmulation::vision3_250d, FilmEmulation::vision3_50d,
        FilmEmulation::vision3_200t};
    bool complete = true;
    for (const FilmEmulation stock : stocks) {
        const auto* const physics =
            negaflow::imaging::digital_film_physics(stock);
        negaflow::imaging::FilmEmulationAcutanceProfile acutance{};
        complete = complete && physics != nullptr &&
                   physics->halation_radius_ratio > 0.0 &&
                   physics->grain.amplitude > 0.0 &&
                   physics->grain.size >= 1.0 &&
                   negaflow::imaging::digital_film_color_preset(stock) != nullptr &&
                   negaflow::imaging::try_get_film_emulation_acutance_profile(
                       stock, acutance);
    }
    expect(
        complete && negaflow::imaging::digital_film_physics(
                        FilmEmulation::none) == nullptr,
        "all 27 color and motion-picture stocks have complete material data");
}

void test_expanded_stock_material_ordering() {
    using negaflow::imaging::FilmEmulation;
    const auto* const astia =
        negaflow::imaging::digital_film_physics(FilmEmulation::astia_100f);
    const auto* const velvia =
        negaflow::imaging::digital_film_physics(FilmEmulation::velvia_100);
    const auto* const kodachrome =
        negaflow::imaging::digital_film_physics(FilmEmulation::kodachrome_64);
    const auto* const e100vs =
        negaflow::imaging::digital_film_physics(FilmEmulation::e100_vs);
    const auto* const vision50d =
        negaflow::imaging::digital_film_physics(FilmEmulation::vision3_50d);
    const auto* const vision200t =
        negaflow::imaging::digital_film_physics(FilmEmulation::vision3_200t);
    const auto* const vision250d =
        negaflow::imaging::digital_film_physics(FilmEmulation::vision3_250d);
    const auto* const vision500t =
        negaflow::imaging::digital_film_physics(FilmEmulation::vision3_500t);
    expect(
        astia != nullptr && velvia != nullptr && kodachrome != nullptr &&
            e100vs != nullptr &&
            astia->grain.amplitude < velvia->grain.amplitude &&
            velvia->grain.amplitude < kodachrome->grain.amplitude &&
            kodachrome->grain.amplitude < e100vs->grain.amplitude,
        "expanded slide stocks preserve the macOS grain ordering");
    expect(
        vision50d != nullptr && vision200t != nullptr && vision250d != nullptr &&
            vision500t != nullptr &&
            vision50d->grain.amplitude < vision200t->grain.amplitude &&
            vision200t->grain.amplitude < vision250d->grain.amplitude &&
            vision250d->grain.amplitude < vision500t->grain.amplitude &&
            vision500t->halation_strength[0] <= 0.034,
        "Vision3 stocks preserve speed-dependent grain and bounded halation");
}

void test_expanded_profile_kinds() {
    using negaflow::imaging::FilmEmulation;
    using negaflow::imaging::FilmEmulationKind;
    expect(
        negaflow::imaging::film_emulation_kind(FilmEmulation::velvia_100) ==
                FilmEmulationKind::slide &&
            negaflow::imaging::film_emulation_kind(FilmEmulation::gold_200) ==
                FilmEmulationKind::negative &&
            negaflow::imaging::film_emulation_kind(
                FilmEmulation::vision3_500t) ==
                FilmEmulationKind::motion_picture,
        "expanded profiles preserve slide, negative, and motion-picture kinds");
}

void test_halation_identity_and_energy_redistribution() {
    const auto source = highlight_spot();
    const auto identity = negaflow::imaging::apply_digital_halation(source, {});
    expect(
        identity.status == negaflow::imaging::DigitalHalationStatus::ok &&
            !identity.info.applied && same_pixels(identity.image.pixels, source.pixels),
        "inactive digital halation is byte exact");

    negaflow::imaging::DigitalHalationParameters parameters{};
    parameters.emulation = negaflow::imaging::FilmEmulation::portra_800;
    parameters.strength = 1.0;
    const auto result = negaflow::imaging::apply_digital_halation(source, parameters);
    const auto ring = result.image.pixels[64U * 128U + 73U];
    bool alpha_preserved = true;
    for (std::size_t index = 0U; index < source.pixels.size(); ++index) {
        alpha_preserved = alpha_preserved &&
            result.image.pixels[index].alpha == source.pixels[index].alpha;
    }
    bool energy_bounded = true;
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        const double before = channel_sum(source, channel);
        const double after = channel_sum(result.image, channel);
        energy_bounded = energy_bounded && std::abs(after - before) / before < 0.01;
    }
    expect(
        result.status == negaflow::imaging::DigitalHalationStatus::ok &&
            result.info.applied && ring.red > ring.blue &&
            ring.red > source.pixels[64U * 128U + 73U].red &&
            alpha_preserved && energy_bounded,
        "halation redistributes highlight energy into a warm halo");
}

void test_halation_tile_boundary_is_seamless() {
    const auto source = solid(530U, 32U, 0.65F);
    const auto result = negaflow::imaging::apply_digital_halation(
        source,
        {negaflow::imaging::FilmEmulation::portra_800, 1.0});
    bool seamless = result.status ==
                    negaflow::imaging::DigitalHalationStatus::ok;
    for (std::uint32_t y = 0U; y < source.height; ++y) {
        const auto left = result.image.pixels[
            static_cast<std::size_t>(y) * source.width + 511U];
        const auto right = result.image.pixels[
            static_cast<std::size_t>(y) * source.width + 512U];
        seamless = seamless && std::abs(left.red - right.red) < 1.0e-6F &&
                   std::abs(left.green - right.green) < 1.0e-6F &&
                   std::abs(left.blue - right.blue) < 1.0e-6F;
    }
    expect(seamless, "halation has no seam at the 512-pixel tile boundary");
}

void test_grain_density_response_and_determinism() {
    negaflow::imaging::DigitalFilmGrainParameters parameters{};
    parameters.emulation = negaflow::imaging::FilmEmulation::portra_800;
    parameters.strength = 1.0;
    const auto middle_source = solid(96U, 64U, 0.018F);
    const auto middle = negaflow::imaging::apply_digital_film_grain(
        middle_source, parameters);
    const auto repeat = negaflow::imaging::apply_digital_film_grain(
        middle_source, parameters);
    const auto highlight = negaflow::imaging::apply_digital_film_grain(
        solid(96U, 64U, 0.95F), parameters);
    bool alpha_preserved = true;
    for (std::size_t index = 0U; index < middle.image.pixels.size(); ++index) {
        alpha_preserved = alpha_preserved &&
            middle.image.pixels[index].alpha == middle_source.pixels[index].alpha;
    }
    const double middle_noise = standard_deviation(middle.image);
    const double highlight_noise = standard_deviation(highlight.image);
    expect(
        middle.status == negaflow::imaging::DigitalFilmGrainStatus::ok &&
            middle.info.applied &&
            same_pixels(middle.image.pixels, repeat.image.pixels) &&
            middle_noise / 0.018 > (highlight_noise / 0.95) * 10.0 &&
            alpha_preserved,
        "density-domain grain is deterministic and strongest near density one");
}

void test_stock_color_directions_remain_distinct() {
    const auto gray = solid(32U, 32U, 0.40F);
    const auto warm = negaflow::imaging::apply_digital_film_color_preset(
        gray,
        {negaflow::imaging::FilmEmulation::colorplus_200, 0.5});
    const auto cool = negaflow::imaging::apply_digital_film_color_preset(
        gray,
        {negaflow::imaging::FilmEmulation::fujicolor_c200, 0.5});
    const auto mean = [](const negaflow::imaging::WorkingImage& image) {
        negaflow::core::Rgba32F result{};
        for (const auto pixel : image.pixels) {
            result.red += pixel.red;
            result.green += pixel.green;
            result.blue += pixel.blue;
        }
        const float scale = 1.0F / static_cast<float>(image.pixels.size());
        result.red *= scale; result.green *= scale; result.blue *= scale;
        return result;
    };
    const auto warm_mean = mean(warm.image);
    const auto cool_mean = mean(cool.image);
    expect(
        warm.status ==
                negaflow::imaging::DigitalFilmColorPresetStatus::ok &&
            cool.status ==
                negaflow::imaging::DigitalFilmColorPresetStatus::ok &&
            warm_mean.red - warm_mean.blue > 0.005F &&
            cool_mean.red - cool_mean.blue < -0.003F &&
            warm_mean.red - warm_mean.blue >
                cool_mean.red - cool_mean.blue + 0.01F,
        "ColorPlus remains warm while Fujicolor C200 remains cool");
}

void test_color_preset_uses_bounded_bit_exact_tiles() {
    constexpr std::uint32_t width = 2048U;
    constexpr std::uint32_t height = 1025U;
    const auto source = patterned(width, height, width + 3U);
    const auto reference = untiled_color_preset_reference(
        source, negaflow::imaging::FilmEmulation::vision3_500t, 0.375);
    const auto result = negaflow::imaging::apply_digital_film_color_preset(
        source,
        {negaflow::imaging::FilmEmulation::vision3_500t, 0.375});
    const std::size_t rows_per_tile =
        negaflow::imaging::digital_film_color_preset_scratch_target_pixels /
        width;
    const std::size_t expected_scratch_bytes =
        static_cast<std::size_t>(width) * rows_per_tile * 3U * sizeof(float);
    const std::size_t previous_full_frame_scratch_bytes =
        static_cast<std::size_t>(width) * height * 3U * sizeof(float);
    expect(
        result.status ==
                negaflow::imaging::DigitalFilmColorPresetStatus::ok &&
            result.info.applied &&
            result.info.scratch_peak_bytes == expected_scratch_bytes &&
            result.info.scratch_peak_bytes < previous_full_frame_scratch_bytes &&
            same_pixels(result.image.pixels, reference.pixels),
        "color preset tiles are bounded and bit exact to the untiled graph");
}

void test_nonfinite_controls_fail_closed() {
    negaflow::imaging::DigitalHalationParameters halation{};
    halation.emulation = negaflow::imaging::FilmEmulation::portra_400;
    halation.strength = std::numeric_limits<double>::quiet_NaN();
    const auto bad_halation = negaflow::imaging::apply_digital_halation(
        solid(16U, 16U, 0.2F), halation);
    negaflow::imaging::DigitalFilmGrainParameters grain{};
    grain.emulation = negaflow::imaging::FilmEmulation::portra_400;
    grain.strength = std::numeric_limits<double>::infinity();
    const auto bad_grain = negaflow::imaging::apply_digital_film_grain(
        solid(16U, 16U, 0.2F), grain);
    expect(
        bad_halation.status ==
                negaflow::imaging::DigitalHalationStatus::invalid_parameter &&
            bad_halation.image.pixels.empty() &&
            bad_grain.status ==
                negaflow::imaging::DigitalFilmGrainStatus::invalid_parameter &&
            bad_grain.image.pixels.empty(),
        "non-finite digital material controls fail closed");
}

}  // namespace

int main() {
    test_fixed_stock_material_table();
    test_expanded_stock_material_ordering();
    test_expanded_profile_kinds();
    test_halation_identity_and_energy_redistribution();
    test_halation_tile_boundary_is_seamless();
    test_grain_density_response_and_determinism();
    test_stock_color_directions_remain_distinct();
    test_color_preset_uses_bounded_bit_exact_tiles();
    test_nonfinite_controls_fail_closed();
    return failures == 0 ? 0 : 1;
}
