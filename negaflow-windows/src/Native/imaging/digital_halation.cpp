#include "negaflow/imaging/digital_halation.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

struct Rgb final {
    float red;
    float green;
    float blue;
};

void discard_pixels(WorkingImage& image) noexcept {
    std::vector<negaflow::core::Rgba32F>{}.swap(image.pixels);
}

[[nodiscard]] negaflow::core::ConstImageView const_view(
    const WorkingImage& image) noexcept {
    return {
        image.pixels.data(), image.pixels.size(), image.width, image.height,
        image.stride_pixels};
}

[[nodiscard]] std::size_t checked_count(
    const std::uint32_t width,
    const std::uint32_t height) {
    if (width == 0U || height == 0U ||
        static_cast<std::size_t>(width) >
            std::numeric_limits<std::size_t>::max() /
                static_cast<std::size_t>(height)) {
        throw std::bad_alloc{};
    }
    return static_cast<std::size_t>(width) * height;
}

[[nodiscard]] std::uint32_t clamp_coordinate(
    const std::int64_t value,
    const std::uint32_t upper) noexcept {
    return static_cast<std::uint32_t>(
        std::clamp<std::int64_t>(value, 0, upper));
}

[[nodiscard]] std::vector<float> gaussian_weights(
    const float sigma,
    std::uint32_t& radius) {
    radius = std::max(1U, static_cast<std::uint32_t>(std::ceil(3.0F * sigma)));
    std::vector<float> weights(static_cast<std::size_t>(radius) * 2U + 1U);
    double total = 0.0;
    for (std::int32_t offset = -static_cast<std::int32_t>(radius);
         offset <= static_cast<std::int32_t>(radius); ++offset) {
        const double distance = offset;
        const float weight = static_cast<float>(std::exp(
            -(distance * distance) /
            (2.0 * static_cast<double>(sigma) * sigma)));
        weights[static_cast<std::size_t>(
            offset + static_cast<std::int32_t>(radius))] = weight;
        total += weight;
    }
    for (float& weight : weights) {
        weight = static_cast<float>(weight / total);
    }
    return weights;
}

void accumulate_blur(
    const WorkingImage& source,
    const float sigma,
    const std::array<float, 3> scale,
    std::vector<Rgb>& accumulator,
    std::size_t& scratch_peak_bytes) {
    std::uint32_t radius = 0U;
    const std::vector<float> weights = gaussian_weights(sigma, radius);
    const std::int32_t signed_radius = static_cast<std::int32_t>(radius);
    for (std::uint32_t core_y = 0U; core_y < source.height;
         core_y += digital_halation_tile_side) {
        const std::uint32_t core_height = std::min(
            digital_halation_tile_side, source.height - core_y);
        for (std::uint32_t core_x = 0U; core_x < source.width;
             core_x += digital_halation_tile_side) {
            const std::uint32_t core_width = std::min(
                digital_halation_tile_side, source.width - core_x);
            const std::uint32_t tile_width = core_width + radius * 2U;
            const std::uint32_t tile_height = core_height + radius * 2U;
            const std::size_t tile_count = checked_count(tile_width, tile_height);
            std::vector<Rgb> tile(tile_count);
            std::vector<Rgb> horizontal(tile_count);
            scratch_peak_bytes = std::max(
                scratch_peak_bytes,
                accumulator.size() * sizeof(Rgb) +
                    tile_count * sizeof(Rgb) * 2U +
                    weights.size() * sizeof(float));

            for (std::uint32_t y = 0U; y < tile_height; ++y) {
                const std::uint32_t sy = clamp_coordinate(
                    static_cast<std::int64_t>(core_y) + y - radius,
                    source.height - 1U);
                for (std::uint32_t x = 0U; x < tile_width; ++x) {
                    const std::uint32_t sx = clamp_coordinate(
                        static_cast<std::int64_t>(core_x) + x - radius,
                        source.width - 1U);
                    const auto pixel = source.pixels[
                        static_cast<std::size_t>(sy) * source.stride_pixels + sx];
                    tile[static_cast<std::size_t>(y) * tile_width + x] = {
                        pixel.red, pixel.green, pixel.blue};
                }
            }
            for (std::uint32_t y = 0U; y < tile_height; ++y) {
                for (std::uint32_t x = 0U; x < tile_width; ++x) {
                    Rgb sum{};
                    for (std::int32_t offset = -signed_radius;
                         offset <= signed_radius; ++offset) {
                        const std::uint32_t sx = clamp_coordinate(
                            static_cast<std::int64_t>(x) + offset,
                            tile_width - 1U);
                        const float weight = weights[static_cast<std::size_t>(
                            offset + signed_radius)];
                        const Rgb sample = tile[
                            static_cast<std::size_t>(y) * tile_width + sx];
                        sum.red += sample.red * weight;
                        sum.green += sample.green * weight;
                        sum.blue += sample.blue * weight;
                    }
                    horizontal[static_cast<std::size_t>(y) * tile_width + x] = sum;
                }
            }
            for (std::uint32_t y = radius; y < radius + core_height; ++y) {
                for (std::uint32_t x = radius; x < radius + core_width; ++x) {
                    Rgb sum{};
                    for (std::int32_t offset = -signed_radius;
                         offset <= signed_radius; ++offset) {
                        const std::uint32_t sy = clamp_coordinate(
                            static_cast<std::int64_t>(y) + offset,
                            tile_height - 1U);
                        const float weight = weights[static_cast<std::size_t>(
                            offset + signed_radius)];
                        const Rgb sample = horizontal[
                            static_cast<std::size_t>(sy) * tile_width + x];
                        sum.red += sample.red * weight;
                        sum.green += sample.green * weight;
                        sum.blue += sample.blue * weight;
                    }
                    Rgb& destination = accumulator[
                        static_cast<std::size_t>(core_y + y - radius) *
                            source.width +
                        core_x + x - radius];
                    destination.red += sum.red * scale[0];
                    destination.green += sum.green * scale[1];
                    destination.blue += sum.blue * scale[2];
                }
            }
        }
    }
}

}  // namespace

bool valid_digital_halation_parameters(
    const DigitalHalationParameters& parameters) noexcept {
    return std::isfinite(parameters.strength) &&
           (parameters.emulation == FilmEmulation::none ||
            digital_film_physics(parameters.emulation) != nullptr);
}

DigitalHalationResult apply_digital_halation(
    WorkingImage image,
    const DigitalHalationParameters& parameters) noexcept {
    if (!valid_digital_halation_parameters(parameters)) {
        DigitalHalationResult result{};
        result.image = std::move(image);
        discard_pixels(result.image);
        return result;
    }
    const DigitalFilmPhysics* const physics =
        digital_film_physics(parameters.emulation);
    const DigitalHalationMaterial material = physics == nullptr
        ? DigitalHalationMaterial{}
        : DigitalHalationMaterial{
              physics->scatter_strength,
              physics->halation_strength,
              physics->halation_radius_ratio};
    return apply_digital_halation_material(
        std::move(image), material, parameters.strength);
}

DigitalHalationResult apply_digital_halation_material(
    WorkingImage image,
    const DigitalHalationMaterial& material,
    const double strength) noexcept {
    DigitalHalationResult result{};
    result.image = std::move(image);
    bool valid = std::isfinite(strength) &&
                 std::isfinite(material.radius_ratio) &&
                 material.radius_ratio >= 0.0;
    for (const double value : material.scatter_strength) {
        valid = valid && std::isfinite(value) && value >= 0.0;
    }
    for (const double value : material.halation_strength) {
        valid = valid && std::isfinite(value) && value >= 0.0;
    }
    if (!valid) {
        discard_pixels(result.image);
        return result;
    }
    result.info.kernel_status =
        negaflow::core::validate_finite_pixels(const_view(result.image));
    if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
        result.status = DigitalHalationStatus::kernel_failed;
        discard_pixels(result.image);
        return result;
    }
    const float amount = static_cast<float>(
        std::clamp(strength, 0.0, 1.0));
    const std::uint32_t reference = std::min(
        result.image.width, result.image.height);
    if (amount <= 1.0e-3F || reference <= 8U ||
        material.radius_ratio <= 0.0) {
        result.status = DigitalHalationStatus::ok;
        return result;
    }

    try {
        const std::size_t count = checked_count(
            result.image.width, result.image.height);
        std::vector<Rgb> accumulator(count);
        std::array<float, 3> scatter{};
        std::array<float, 3> halation{};
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            scatter[channel] = static_cast<float>(
                material.scatter_strength[channel] * amount);
            halation[channel] = static_cast<float>(
                material.halation_strength[channel] * amount);
        }
        for (std::uint32_t y = 0U; y < result.image.height; ++y) {
            for (std::uint32_t x = 0U; x < result.image.width; ++x) {
                const auto pixel = result.image.pixels[
                    static_cast<std::size_t>(y) * result.image.stride_pixels + x];
                accumulator[static_cast<std::size_t>(y) * result.image.width + x] = {
                    pixel.red * std::max(1.0F - scatter[0] - halation[0], 0.0F),
                    pixel.green * std::max(1.0F - scatter[1] - halation[1], 0.0F),
                    pixel.blue * std::max(1.0F - scatter[2] - halation[2], 0.0F),
                };
            }
        }
        const float far_radius = std::max(
            1.0F, static_cast<float>(reference * material.radius_ratio));
        const float near_radius = std::max(0.6F, far_radius * 0.28F);
        const float wide_radius = far_radius * 1.414F;
        accumulate_blur(
            result.image, near_radius, scatter, accumulator,
            result.info.scratch_peak_bytes);
        std::array<float, 3> far_scale{};
        std::array<float, 3> wide_scale{};
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            far_scale[channel] = halation[channel] * 0.68F;
            wide_scale[channel] = halation[channel] * 0.32F;
        }
        accumulate_blur(
            result.image, far_radius, far_scale, accumulator,
            result.info.scratch_peak_bytes);
        accumulate_blur(
            result.image, wide_radius, wide_scale, accumulator,
            result.info.scratch_peak_bytes);
        for (std::uint32_t y = 0U; y < result.image.height; ++y) {
            for (std::uint32_t x = 0U; x < result.image.width; ++x) {
                auto& pixel = result.image.pixels[
                    static_cast<std::size_t>(y) * result.image.stride_pixels + x];
                const Rgb value = accumulator[
                    static_cast<std::size_t>(y) * result.image.width + x];
                pixel.red = value.red;
                pixel.green = value.green;
                pixel.blue = value.blue;
            }
        }
    } catch (const std::bad_alloc&) {
        result.status = DigitalHalationStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    }

    result.info.applied = true;
    result.info.kernel_status = negaflow::core::KernelStatus::ok;
    result.status = DigitalHalationStatus::ok;
    return result;
}

const char* digital_halation_status_name(
    const DigitalHalationStatus status) noexcept {
    switch (status) {
        case DigitalHalationStatus::ok: return "ok";
        case DigitalHalationStatus::invalid_parameter: return "invalid_parameter";
        case DigitalHalationStatus::invalid_image: return "invalid_image";
        case DigitalHalationStatus::allocation_failed: return "allocation_failed";
        case DigitalHalationStatus::kernel_failed: return "kernel_failed";
    }
    return "unknown_status";
}

}  // namespace negaflow::imaging
