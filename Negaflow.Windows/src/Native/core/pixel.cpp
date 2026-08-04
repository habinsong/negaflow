#include "negaflow/core/pixel.h"

#include <cmath>
#include <limits>

namespace negaflow::core {
namespace {

[[nodiscard]] KernelStatus validate_layout(
    const void* const pixels,
    const std::size_t pixel_capacity,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::size_t stride_pixels) noexcept {
    if (pixels == nullptr) {
        return KernelStatus::invalid_argument;
    }
    if (width == 0U || height == 0U) {
        return KernelStatus::invalid_dimensions;
    }
    if (stride_pixels < static_cast<std::size_t>(width)) {
        return KernelStatus::invalid_stride;
    }

    const std::size_t rows_before_last = static_cast<std::size_t>(height - 1U);
    const std::size_t row_width = static_cast<std::size_t>(width);
    const std::size_t maximum = std::numeric_limits<std::size_t>::max();
    if (rows_before_last > (maximum - row_width) / stride_pixels) {
        return KernelStatus::size_overflow;
    }

    const std::size_t required_pixels = (rows_before_last * stride_pixels) + row_width;
    if (pixel_capacity < required_pixels) {
        return KernelStatus::buffer_too_small;
    }
    return KernelStatus::ok;
}

}  // namespace

KernelStatus validate_image_view(const ConstImageView view) noexcept {
    return validate_layout(
        view.pixels,
        view.pixel_capacity,
        view.width,
        view.height,
        view.stride_pixels);
}

KernelStatus validate_image_view(const ImageView view) noexcept {
    return validate_layout(
        view.pixels,
        view.pixel_capacity,
        view.width,
        view.height,
        view.stride_pixels);
}

KernelStatus validate_finite_pixels(const ConstImageView view) noexcept {
    const KernelStatus layout_status = validate_image_view(view);
    if (layout_status != KernelStatus::ok) {
        return layout_status;
    }

    for (std::uint32_t row = 0U; row < view.height; ++row) {
        const Rgba32F* const row_pixels =
            view.pixels + (static_cast<std::size_t>(row) * view.stride_pixels);
        for (std::uint32_t column = 0U; column < view.width; ++column) {
            const Rgba32F pixel = row_pixels[column];
            if (!std::isfinite(pixel.red) || !std::isfinite(pixel.green) ||
                !std::isfinite(pixel.blue) || !std::isfinite(pixel.alpha)) {
                return KernelStatus::non_finite_input;
            }
            if (pixel.alpha < 0.0F || pixel.alpha > 1.0F) {
                return KernelStatus::alpha_out_of_range;
            }
        }
    }
    return KernelStatus::ok;
}

KernelStatus validate_compatible_views(
    const ConstImageView input,
    const ImageView output) noexcept {
    const KernelStatus input_status = validate_image_view(input);
    if (input_status != KernelStatus::ok) {
        return input_status;
    }
    const KernelStatus output_status = validate_image_view(output);
    if (output_status != KernelStatus::ok) {
        return output_status;
    }
    if (input.width != output.width || input.height != output.height) {
        return KernelStatus::dimension_mismatch;
    }
    return KernelStatus::ok;
}

const char* kernel_status_name(const KernelStatus status) noexcept {
    switch (status) {
        case KernelStatus::ok:
            return "ok";
        case KernelStatus::invalid_argument:
            return "invalid_argument";
        case KernelStatus::invalid_dimensions:
            return "invalid_dimensions";
        case KernelStatus::invalid_stride:
            return "invalid_stride";
        case KernelStatus::size_overflow:
            return "size_overflow";
        case KernelStatus::buffer_too_small:
            return "buffer_too_small";
        case KernelStatus::dimension_mismatch:
            return "dimension_mismatch";
        case KernelStatus::non_finite_parameter:
            return "non_finite_parameter";
        case KernelStatus::invalid_parameter:
            return "invalid_parameter";
        case KernelStatus::non_finite_input:
            return "non_finite_input";
        case KernelStatus::alpha_out_of_range:
            return "alpha_out_of_range";
        case KernelStatus::non_finite_output:
            return "non_finite_output";
        default:
            return "unknown";
    }
}

}  // namespace negaflow::core
