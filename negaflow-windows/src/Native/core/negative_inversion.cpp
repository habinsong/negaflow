#include "negaflow/core/negative_inversion.h"

#include "negaflow/core/parallel_rows.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>

namespace negaflow::core {
namespace {

[[nodiscard]] bool finite_response(const PrintResponse& response) noexcept {
    return std::isfinite(response.normal_range) && std::isfinite(response.base_toe) &&
           std::isfinite(response.white_output) && std::isfinite(response.ceiling) &&
           std::isfinite(response.y_ceiling) && std::isfinite(response.amplitude) &&
           std::isfinite(response.rate) && std::isfinite(response.shape);
}

[[nodiscard]] KernelStatus validate_parameters(
    const NegativeInversionParameters& parameters,
    const PrintResponse& response) noexcept {
    if (!std::ranges::all_of(parameters.dmin, [](const float value) {
            return std::isfinite(value);
        }) ||
        !std::ranges::all_of(parameters.dmax_normalized, [](const float value) {
            return std::isfinite(value);
        }) ||
        !finite_response(response)) {
        return KernelStatus::non_finite_parameter;
    }

    const bool positive_dmin = std::ranges::all_of(parameters.dmin, [](const float value) {
        return value > 0.0F;
    });
    const bool positive_dmax =
        std::ranges::all_of(parameters.dmax_normalized, [](const float value) {
            return value > 0.0F;
        });
    const bool valid_response = response.normal_range > 0.0F && response.base_toe > 0.0F &&
                                response.white_output > response.base_toe &&
                                response.ceiling > response.white_output &&
                                response.ceiling <= 1.0F && response.amplitude > 0.0F &&
                                response.rate > 0.0F && response.shape > 0.0F;
    return positive_dmin && positive_dmax && valid_response
               ? KernelStatus::ok
               : KernelStatus::invalid_parameter;
}

[[nodiscard]] float invert_channel(
    const float transmission,
    const float dmin,
    const float dmax_normalized,
    const PrintResponse& response,
    const bool linear_output) noexcept {
    const float bounded_transmission = std::max(transmission, 1.0e-5F);
    const float density =
        std::log10(dmin / bounded_transmission) / std::max(dmax_normalized, 1.0e-6F);
    if (linear_output) {
        // This common gamma is a reference response, not scanner/film calibration.
        // Subtracting the base does not make real neutral densities equal in RGB.
        const float film_density = density * response.normal_range;
        const float toe_density = 0.60F + 0.62F * std::log10(0.25F);
        if (film_density < toe_density) {
            const float power = toe_density * std::log(10.0F) / 0.62F;
            return std::copysign(0.045F * std::pow(std::abs(film_density) / toe_density, power), film_density);
        }
        return 0.18F * std::pow(10.0F, (film_density - 0.60F) / 0.62F);
    }
    const float argument = std::pow(
        std::max(response.rate * std::abs(density), 1.0e-12F),
        response.shape);
    const float y = response.y_ceiling - (response.amplitude * std::exp(-argument));
    const float toe_y = response.y_ceiling - response.amplitude;
    const float output_y = density >= 0.0F ? y : (2.0F * toe_y) - y;
    return std::pow(10.0F, output_y);
}

}  // namespace

double negative_output_tone_input(const double output, const bool monochrome) noexcept {
    if (!std::isfinite(output) || output < 0 || output >= 1) {
        return std::numeric_limits<double>::quiet_NaN();
    }
    constexpr double shadow = 0.18 / 4;
    constexpr double highlight = 0.70;
    const double black = monochrome ? 0.0005 : 0.001;
    if (output <= black) { return 0; }
    if (output < shadow) {
        const double a = black / (shadow * shadow);
        const double b = 1 - 2 * black / shadow;
        const double distance = output - black;
        return 2 * distance / (b + std::sqrt(b * b + 4 * a * distance));
    }
    if (output > highlight) {
        return highlight + (1 - highlight) * (output - highlight) / (1 - output);
    }
    return output;
}

KernelStatus apply_negative_output_tone(const ImageView image, const float stops,
                                        const bool monochrome) noexcept {
    if (!std::isfinite(stops)) { return KernelStatus::non_finite_parameter; }
    const float gain = std::exp2(stops);
    if (!std::isfinite(gain) || gain <= 0) { return KernelStatus::invalid_parameter; }
    const ConstImageView input{image.pixels, image.pixel_capacity, image.width, image.height, image.stride_pixels};
    const auto status = validate_compatible_views(input, image);
    if (status != KernelStatus::ok) { return status; }
    const auto finite = validate_finite_pixels(input);
    if (finite != KernelStatus::ok) { return finite; }
    constexpr float shadow = 0.18F / 4.0F;
    constexpr float highlight = 0.70F;
    const float black = monochrome ? 0.0005F : 0.001F;
    for_each_row_block(image.height, static_cast<std::uint64_t>(image.width) * image.height,
        [&](const std::uint32_t first, const std::uint32_t count) noexcept {
            for (std::uint32_t row = first; row < first + count; ++row) {
                for (std::uint32_t x = 0; x < image.width; ++x) {
                    auto& p = image.pixels[static_cast<std::size_t>(row) * image.stride_pixels + x];
                    const auto map = [=](const float value) noexcept {
                        const float y = gain * value;
                        if (y <= 0) { return black; }
                        if (y < shadow) {
                            const float d = 1 - y / shadow;
                            return y + black * d * d;
                        }
                        if (y > highlight) {
                            return highlight + (1 - highlight) *
                                ((y - highlight) / (y - highlight + 1 - highlight));
                        }
                        return y;
                    };
                    p.red = map(p.red); p.green = map(p.green); p.blue = map(p.blue);
                }
            }
        });
    return validate_finite_pixels(input);
}

KernelStatus apply_negative_inversion(
    const ConstImageView input,
    const ImageView output,
    const NegativeInversionParameters& parameters,
    const PrintResponse& response) noexcept {
    const KernelStatus parameter_status = validate_parameters(parameters, response);
    if (parameter_status != KernelStatus::ok) {
        return parameter_status;
    }
    const KernelStatus compatibility_status = validate_compatible_views(input, output);
    if (compatibility_status != KernelStatus::ok) {
        return compatibility_status;
    }
    const KernelStatus input_status = validate_finite_pixels(input);
    if (input_status != KernelStatus::ok) {
        return input_status;
    }

    // Every output pixel depends only on the input pixel at the same coordinate, so the
    // rows split across cores without changing a single result bit. On a 16 MP scan this
    // is the most expensive stage in the whole develop, almost entirely transcendentals.
    std::atomic<std::uint64_t> first_failure{no_row_failure};
    const std::uint64_t work_units =
        static_cast<std::uint64_t>(input.width) * static_cast<std::uint64_t>(input.height);
    for_each_row_block(
        input.height,
        work_units,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t row = first_row; row < first_row + row_count; ++row) {
                const std::size_t input_offset =
                    static_cast<std::size_t>(row) * input.stride_pixels;
                const std::size_t output_offset =
                    static_cast<std::size_t>(row) * output.stride_pixels;
                for (std::uint32_t column = 0U; column < input.width; ++column) {
                    const Rgba32F source = input.pixels[input_offset + column];
                    const Rgba32F result{
                        invert_channel(
                            source.red,
                            parameters.dmin[0],
                            parameters.dmax_normalized[0],
                            response, parameters.linear_output),
                        invert_channel(
                            source.green,
                            parameters.dmin[1],
                            parameters.dmax_normalized[1],
                            response, parameters.linear_output),
                        invert_channel(
                            source.blue,
                            parameters.dmin[2],
                            parameters.dmax_normalized[2],
                            response, parameters.linear_output),
                        source.alpha,
                    };
                    if (!std::isfinite(result.red) || !std::isfinite(result.green) ||
                        !std::isfinite(result.blue)) {
                        record_row_failure(
                            first_failure, row, KernelStatus::non_finite_output);
                        return;
                    }
                    output.pixels[output_offset + column] = result;
                }
            }
        });

    const std::uint64_t packed = first_failure.load(std::memory_order_relaxed);
    return has_row_failure(packed)
               ? static_cast<KernelStatus>(row_failure_status_value(packed))
               : KernelStatus::ok;
}

}  // namespace negaflow::core
