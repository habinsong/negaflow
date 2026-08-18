#include "negaflow/imaging/digital_bw_emulsion_response.h"

#include "negaflow/color/srgb_transfer.h"
#include "negaflow/imaging/digital_bw_film_profile.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace negaflow::imaging {
namespace {

constexpr double identity_threshold = 1.0e-3;
constexpr std::array<double, 3> neutral_weights{0.2126, 0.7152, 0.0722};
constexpr double reference_contrast_index = 0.55;
constexpr double reference_latitude = 9.0;
constexpr double reference_curve_shape = 0.50;

struct Response final {
    std::array<double, 3> weights;
    double contrast;
    double toe;
    double shoulder;
    double deepen;
    double black;
    double white;
    double intensity;
};

[[nodiscard]] double clamp_unit(const double value) noexcept {
    return std::clamp(value, 0.0, 1.0);
}

[[nodiscard]] Response make_response(
    const DigitalBwFilmProfile& profile,
    const double intensity) noexcept {
    const double strength = clamp_unit(intensity);
    Response response{};
    for (std::size_t channel = 0U; channel < response.weights.size(); ++channel) {
        response.weights[channel] =
            neutral_weights[channel] +
            ((profile.spectral_weights[channel] - neutral_weights[channel]) *
             strength);
    }
    const double contrast_gain = profile.reversal ? 1.4 : 1.1;
    response.contrast =
        (profile.contrast_index - reference_contrast_index) * contrast_gain;
    response.toe =
        (profile.toe_softness - reference_curve_shape) * 0.10;
    const double shape =
        (profile.shoulder_softness - reference_curve_shape) * 0.09;
    const double latitude =
        (profile.latitude_stops - reference_latitude) /
        reference_latitude * 0.05;
    response.shoulder = -(shape + latitude);
    response.deepen = profile.reversal
        ? (profile.dmax_multiplier - 1.0) * 0.10
        : 0.0;
    response.black = profile.reversal ? 0.0 : 0.008;
    response.white = profile.reversal ? 1.0 : 0.994;
    response.intensity = strength;
    return response;
}

void copy_active_pixels(
    const negaflow::core::ConstImageView input,
    const negaflow::core::ImageView output) noexcept {
    for (std::uint32_t row = 0U; row < input.height; ++row) {
        const std::size_t input_offset =
            static_cast<std::size_t>(row) * input.stride_pixels;
        const std::size_t output_offset =
            static_cast<std::size_t>(row) * output.stride_pixels;
        std::copy_n(
            input.pixels + input_offset,
            input.width,
            output.pixels + output_offset);
    }
}

}  // namespace

DigitalBwEmulsionSetup prepare_digital_bw_emulsion_response(
    const DigitalBwEmulsionResponseParameters& parameters) noexcept {
    DigitalBwEmulsionSetup setup{};
    const DigitalBwFilmProfile* const profile =
        digital_bw_film_profile(parameters.emulation);
    if (profile == nullptr || !std::isfinite(parameters.intensity) ||
        !has_digital_bw_emulsion_response_change(parameters)) {
        return setup;
    }
    const Response response = make_response(*profile, parameters.intensity);
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        setup.weights[channel] = static_cast<float>(response.weights[channel]);
    }
    setup.contrast = static_cast<float>(response.contrast);
    setup.toe = static_cast<float>(response.toe);
    setup.shoulder = static_cast<float>(response.shoulder);
    setup.deepen = static_cast<float>(response.deepen);
    setup.black = static_cast<float>(response.black);
    setup.white = static_cast<float>(response.white);
    setup.intensity = static_cast<float>(response.intensity);
    setup.active = true;
    return setup;
}

bool valid_digital_bw_emulsion_response_parameters(
    const DigitalBwEmulsionResponseParameters& parameters) noexcept {
    return std::isfinite(parameters.intensity) &&
           digital_bw_film_profile(parameters.emulation) != nullptr;
}

bool has_digital_bw_emulsion_response_change(
    const DigitalBwEmulsionResponseParameters& parameters) noexcept {
    return valid_digital_bw_emulsion_response_parameters(parameters) &&
           std::clamp(parameters.intensity, 0.0, 1.0) > identity_threshold;
}

negaflow::core::KernelStatus apply_digital_bw_emulsion_response(
    const negaflow::core::ConstImageView input,
    const negaflow::core::ImageView output,
    const DigitalBwEmulsionResponseParameters& parameters) noexcept {
    if (!std::isfinite(parameters.intensity)) {
        return negaflow::core::KernelStatus::non_finite_parameter;
    }
    const DigitalBwFilmProfile* const profile =
        digital_bw_film_profile(parameters.emulation);
    if (profile == nullptr) {
        return negaflow::core::KernelStatus::invalid_parameter;
    }
    const negaflow::core::KernelStatus compatibility_status =
        negaflow::core::validate_compatible_views(input, output);
    if (compatibility_status != negaflow::core::KernelStatus::ok) {
        return compatibility_status;
    }
    const negaflow::core::KernelStatus input_status =
        negaflow::core::validate_finite_pixels(input);
    if (input_status != negaflow::core::KernelStatus::ok) {
        return input_status;
    }
    if (!has_digital_bw_emulsion_response_change(parameters)) {
        copy_active_pixels(input, output);
        return negaflow::core::KernelStatus::ok;
    }

    // 준비 계산은 `prepare_digital_bw_emulsion_response` 와 같은 `make_response` 하나에서 옵니다.
    const Response response = make_response(*profile, parameters.intensity);
    for (std::uint32_t row = 0U; row < input.height; ++row) {
        const std::size_t input_offset =
            static_cast<std::size_t>(row) * input.stride_pixels;
        const std::size_t output_offset =
            static_cast<std::size_t>(row) * output.stride_pixels;
        for (std::uint32_t column = 0U; column < input.width; ++column) {
            const negaflow::core::Rgba32F source =
                input.pixels[input_offset + column];
            const double linear_gray =
                (std::max(static_cast<double>(source.red), 0.0) *
                 response.weights[0]) +
                (std::max(static_cast<double>(source.green), 0.0) *
                 response.weights[1]) +
                (std::max(static_cast<double>(source.blue), 0.0) *
                 response.weights[2]);
            const double bounded_linear = clamp_unit(linear_gray);
            const double over = linear_gray - bounded_linear;
            const double encoded = negaflow::color::linear_to_srgb_encoded(
                static_cast<float>(bounded_linear));
            const double smoother = encoded * encoded * encoded *
                ((encoded * ((encoded * 6.0) - 15.0)) + 10.0);
            double result = clamp_unit(
                encoded + ((smoother - encoded) * response.contrast));
            const double low = 1.0 - result;
            result = clamp_unit(result + (response.toe * low * low * low));
            result = clamp_unit(
                result + (response.shoulder * result * result * result));
            const double density = 1.0 - result;
            result = clamp_unit(
                result *
                (1.0 -
                 (response.deepen * density * density * density)));
            result = clamp_unit(
                response.black +
                (result * (response.white - response.black)));
            result = encoded + ((result - encoded) * response.intensity);
            const float output_gray =
                negaflow::color::srgb_encoded_to_linear(
                    static_cast<float>(result)) +
                static_cast<float>(over);
            if (!std::isfinite(output_gray)) {
                return negaflow::core::KernelStatus::non_finite_output;
            }
            output.pixels[output_offset + column] = {
                output_gray,
                output_gray,
                output_gray,
                source.alpha,
            };
        }
    }
    return negaflow::core::KernelStatus::ok;
}

}  // namespace negaflow::imaging
