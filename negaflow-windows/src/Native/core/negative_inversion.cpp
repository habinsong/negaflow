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
    const PrintResponse& response) noexcept {
    const float bounded_transmission = std::max(transmission, 1.0e-5F);
    const float density =
        std::log10(dmin / bounded_transmission) / std::max(dmax_normalized, 1.0e-6F);
    const float argument = std::pow(
        std::max(response.rate * std::abs(density), 1.0e-12F),
        response.shape);
    const float y = response.y_ceiling - (response.amplitude * std::exp(-argument));
    const float toe_y = response.y_ceiling - response.amplitude;
    const float output_y = density >= 0.0F ? y : (2.0F * toe_y) - y;
    return std::pow(10.0F, output_y);
}

}  // namespace

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
                            response),
                        invert_channel(
                            source.green,
                            parameters.dmin[1],
                            parameters.dmax_normalized[1],
                            response),
                        invert_channel(
                            source.blue,
                            parameters.dmin[2],
                            parameters.dmax_normalized[2],
                            response),
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
