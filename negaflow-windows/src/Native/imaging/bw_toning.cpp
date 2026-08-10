#include "negaflow/imaging/bw_toning.h"

#include <algorithm>
#include <cmath>
#include <utility>

namespace negaflow::imaging {
namespace {

struct Rgb final {
    float red;
    float green;
    float blue;
};

[[nodiscard]] float clamp_unit(const float value) noexcept {
    return std::clamp(value, 0.0F, 1.0F);
}

[[nodiscard]] float smoothstep(
    const float edge0,
    const float edge1,
    const float value) noexcept {
    const float t = clamp_unit((value - edge0) / (edge1 - edge0));
    return t * t * (3.0F - 2.0F * t);
}

[[nodiscard]] Rgb mix(
    const Rgb first,
    const Rgb second,
    const float amount) noexcept {
    return {
        first.red + (second.red - first.red) * amount,
        first.green + (second.green - first.green) * amount,
        first.blue + (second.blue - first.blue) * amount,
    };
}

[[nodiscard]] float luminance(const Rgb value) noexcept {
    return value.red * 0.2126F + value.green * 0.7152F +
           value.blue * 0.0722F;
}

[[nodiscard]] Rgb hsv_tint(const double hue_degrees) noexcept {
    constexpr double saturation = 0.78;
    double hue = std::fmod(hue_degrees / 360.0, 1.0);
    if (hue < 0.0) {
        hue += 1.0;
    }
    const double sector = hue * 6.0;
    const int index = static_cast<int>(sector);
    const double fraction = sector - static_cast<double>(index);
    const float p = static_cast<float>(1.0 - saturation);
    const float q = static_cast<float>(1.0 - saturation * fraction);
    const float t = static_cast<float>(1.0 - saturation * (1.0 - fraction));
    switch (index % 6) {
        case 0: return {1.0F, t, p};
        case 1: return {q, 1.0F, p};
        case 2: return {p, 1.0F, t};
        case 3: return {p, q, 1.0F};
        case 4: return {t, p, 1.0F};
        default: return {1.0F, p, q};
    }
}

[[nodiscard]] bool valid_image(const WorkingImage& image) noexcept {
    return image.width != 0U && image.height != 0U &&
           image.stride_pixels >= image.width &&
           image.pixels.size() >=
               static_cast<std::size_t>(image.stride_pixels) * image.height;
}

}  // namespace

bool valid_bw_toning_parameters(
    const BwToningParameters& parameters) noexcept {
    return (parameters.mode == BwToningMode::none ||
            parameters.mode == BwToningMode::selenium ||
            parameters.mode == BwToningMode::sepia) &&
           std::isfinite(parameters.shadow_hue) &&
           std::isfinite(parameters.highlight_hue) &&
           std::isfinite(parameters.strength) &&
           parameters.strength >= 0.0 && parameters.strength <= 1.0;
}

BwToningResult apply_bw_toning(
    WorkingImage image,
    const NegativeFilmType film_type,
    const BwToningParameters& parameters) noexcept {
    BwToningResult result{};
    if (!valid_bw_toning_parameters(parameters) ||
        (film_type != NegativeFilmType::color &&
         film_type != NegativeFilmType::black_and_white)) {
        std::vector<negaflow::core::Rgba32F>{}.swap(image.pixels);
        result.status = BwToningStatus::invalid_parameter;
        return result;
    }
    if (!valid_image(image)) {
        std::vector<negaflow::core::Rgba32F>{}.swap(image.pixels);
        result.status = BwToningStatus::invalid_image;
        return result;
    }
    if (film_type == NegativeFilmType::color) {
        result.status = BwToningStatus::ok;
        result.image = std::move(image);
        return result;
    }

    const bool tone = parameters.mode != BwToningMode::none &&
                      parameters.strength > 1.0e-4;
    const float strength = static_cast<float>(parameters.strength);
    const float mode = parameters.mode == BwToningMode::sepia ? 1.0F : 0.0F;
    const Rgb shadow_tint = hsv_tint(parameters.shadow_hue);
    const Rgb highlight_tint = hsv_tint(parameters.highlight_hue);

    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            auto& pixel = image.pixels[
                static_cast<std::size_t>(y) * image.stride_pixels + x];
            const float neutral = luminance({pixel.red, pixel.green, pixel.blue});
            pixel.red = neutral;
            pixel.green = neutral;
            pixel.blue = neutral;
            if (!tone) {
                continue;
            }

            const float value = clamp_unit(neutral);
            const float shadow_reach = 0.68F + (0.92F - 0.68F) * mode;
            const float highlight_reach = 0.38F + (0.76F - 0.38F) * mode;
            const float shadow_weight =
                1.0F - smoothstep(0.18F, shadow_reach, value);
            const float highlight_weight = smoothstep(
                1.0F - highlight_reach, 0.98F, value);
            const float crossover = smoothstep(0.22F, 0.86F, value);
            const Rgb tint = mix(shadow_tint, highlight_tint, crossover);
            const float tint_y = std::max(luminance(tint), 0.001F);
            const Rgb toned{
                value * tint.red / tint_y,
                value * tint.green / tint_y,
                value * tint.blue / tint_y,
            };
            const float tone_mask = clamp_unit(
                shadow_weight * (0.95F + (0.68F - 0.95F) * mode) +
                highlight_weight * (0.30F + (0.72F - 0.30F) * mode));
            const float amount =
                strength * (0.18F + (0.36F - 0.18F) * mode) * tone_mask;
            const float selenium_density =
                1.0F - 0.060F * strength * shadow_weight;
            const float sepia_density = 1.0F - 0.026F * strength *
                smoothstep(0.36F, 0.92F, value);
            const float density = selenium_density +
                (sepia_density - selenium_density) * mode;
            const Rgb rgb = mix({value, value, value}, toned, amount);
            pixel.red = clamp_unit(rgb.red * density);
            pixel.green = clamp_unit(rgb.green * density);
            pixel.blue = clamp_unit(rgb.blue * density);
        }
    }

    result.status = BwToningStatus::ok;
    result.info.neutralized = true;
    result.info.toned = tone;
    result.image = std::move(image);
    return result;
}

const char* bw_toning_status_name(const BwToningStatus status) noexcept {
    switch (status) {
        case BwToningStatus::ok: return "ok";
        case BwToningStatus::invalid_parameter: return "invalid_parameter";
        case BwToningStatus::invalid_image: return "invalid_image";
    }
    return "unknown_status";
}

}  // namespace negaflow::imaging
