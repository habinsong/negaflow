#include "negaflow/imaging/manual_negative_developer.h"

#include "negaflow/core/negative_inversion.h"

#include <algorithm>
#include <cmath>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

void discard_pixels(WorkingImage& image) noexcept {
    std::vector<negaflow::core::Rgba32F>{}.swap(image.pixels);
}

}  // namespace

ManualNegativeDevelopResult develop_manual_negative(
    WorkingImage image,
    const ManualNegativeDevelopParameters& parameters) noexcept {
    ManualNegativeDevelopResult result{};
    result.image = std::move(image);

    negaflow::core::PrintResponse response{};
    switch (parameters.film_type) {
        case NegativeFilmType::color:
            response = negaflow::core::color_negative_print_response();
            break;
        case NegativeFilmType::black_and_white:
            response = negaflow::core::black_and_white_negative_print_response();
            break;
        default:
            discard_pixels(result.image);
            return result;
    }

    for (std::size_t channel = 0U; channel < parameters.dmin.size(); ++channel) {
        if (!std::isfinite(parameters.dmin[channel])) {
            discard_pixels(result.image);
            return result;
        }
        result.info.applied_dmin[channel] =
            std::clamp(parameters.dmin[channel], 1.0e-3F, 1.0F);
        result.info.dmax_normalized[channel] = response.normal_range;
    }

    const negaflow::core::NegativeInversionParameters kernel_parameters{
        result.info.applied_dmin,
        result.info.dmax_normalized,
    };
    const negaflow::core::ConstImageView input{
        result.image.pixels.data(),
        result.image.pixels.size(),
        result.image.width,
        result.image.height,
        result.image.stride_pixels,
    };
    const negaflow::core::ImageView output{
        result.image.pixels.data(),
        result.image.pixels.size(),
        result.image.width,
        result.image.height,
        result.image.stride_pixels,
    };
    result.info.kernel_status = negaflow::core::apply_negative_inversion(
        input,
        output,
        kernel_parameters,
        response);
    if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
        result.status = ManualNegativeDevelopStatus::kernel_failed;
        discard_pixels(result.image);
        return result;
    }

    result.status = ManualNegativeDevelopStatus::ok;
    return result;
}

const char* manual_negative_develop_status_name(
    const ManualNegativeDevelopStatus status) noexcept {
    switch (status) {
        case ManualNegativeDevelopStatus::ok:
            return "ok";
        case ManualNegativeDevelopStatus::invalid_parameter:
            return "invalid_parameter";
        case ManualNegativeDevelopStatus::kernel_failed:
            return "kernel_failed";
    }
    return "unknown";
}

const char* negative_film_type_name(const NegativeFilmType film_type) noexcept {
    switch (film_type) {
        case NegativeFilmType::color:
            return "color";
        case NegativeFilmType::black_and_white:
            return "bw";
    }
    return "unknown";
}

}  // namespace negaflow::imaging
