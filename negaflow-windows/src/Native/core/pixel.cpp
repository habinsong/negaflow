#include "negaflow/core/pixel.h"

#include "negaflow/core/parallel_rows.h"

#include <atomic>
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

    // Row blocks are scanned concurrently, so the reported status is chosen by smallest
    // failing row rather than by which thread noticed first. That keeps the answer the
    // same as the single-threaded scan, which returns the first failure in raster order.
    std::atomic<std::uint64_t> first_failure{no_row_failure};
    const std::uint64_t work_units =
        static_cast<std::uint64_t>(view.width) * static_cast<std::uint64_t>(view.height);
    for_each_row_block(
        view.height,
        work_units,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t row = first_row; row < first_row + row_count; ++row) {
                const Rgba32F* const row_pixels =
                    view.pixels + (static_cast<std::size_t>(row) * view.stride_pixels);
                for (std::uint32_t column = 0U; column < view.width; ++column) {
                    const Rgba32F pixel = row_pixels[column];
                    if (!std::isfinite(pixel.red) || !std::isfinite(pixel.green) ||
                        !std::isfinite(pixel.blue) || !std::isfinite(pixel.alpha)) {
                        record_row_failure(
                            first_failure, row, KernelStatus::non_finite_input);
                        return;
                    }
                    if (pixel.alpha < 0.0F || pixel.alpha > 1.0F) {
                        record_row_failure(
                            first_failure, row, KernelStatus::alpha_out_of_range);
                        return;
                    }
                }
            }
        });

    const std::uint64_t packed = first_failure.load(std::memory_order_relaxed);
    return has_row_failure(packed)
               ? static_cast<KernelStatus>(row_failure_status_value(packed))
               : KernelStatus::ok;
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
