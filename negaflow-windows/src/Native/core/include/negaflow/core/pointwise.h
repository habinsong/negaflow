#pragma once

#include "negaflow/core/parallel_rows.h"
#include "negaflow/core/pixel.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>

namespace negaflow::core {

[[nodiscard]] inline bool finite_rgb(const Rgba32F pixel) noexcept {
    return std::isfinite(pixel.red) && std::isfinite(pixel.green) &&
           std::isfinite(pixel.blue);
}

// One input pixel to one output pixel at the same coordinate, with no other reads. Every
// stage shaped like that runs here so the row split and the first-failure rule are
// decided once instead of per stage.
//
// This overload assumes the caller has already run `validate_compatible_views` and
// `validate_finite_pixels`; stages that need to inspect the views first use it so the
// image is not scanned twice.
//
// The transform is called concurrently from several threads, so it must be pure: capture
// parameters by value and touch nothing shared.
template <typename Transform>
[[nodiscard]] KernelStatus transform_validated_pointwise(
    const ConstImageView input,
    const ImageView output,
    Transform transform) noexcept {
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
                    const Rgba32F result = transform(source);
                    if (!finite_rgb(result)) {
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

// Validates the views, then runs the transform. The order of the two validations is part
// of the contract: a layout problem is reported before a pixel problem.
template <typename Transform>
[[nodiscard]] KernelStatus apply_pointwise(
    const ConstImageView input,
    const ImageView output,
    Transform transform) noexcept {
    const KernelStatus compatibility_status = validate_compatible_views(input, output);
    if (compatibility_status != KernelStatus::ok) {
        return compatibility_status;
    }
    const KernelStatus input_status = validate_finite_pixels(input);
    if (input_status != KernelStatus::ok) {
        return input_status;
    }
    return transform_validated_pointwise(input, output, transform);
}

// Row-wise copy for the identity path of a stage that is switched off. Same contract as
// `transform_validated_pointwise`: the caller has already validated both views.
inline void copy_validated_rows(
    const ConstImageView input,
    const ImageView output) noexcept {
    const std::uint64_t work_units =
        static_cast<std::uint64_t>(input.width) * static_cast<std::uint64_t>(input.height);
    for_each_row_block(
        input.height,
        work_units,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t row = first_row; row < first_row + row_count; ++row) {
                const Rgba32F* const source =
                    input.pixels + (static_cast<std::size_t>(row) * input.stride_pixels);
                Rgba32F* const destination =
                    output.pixels + (static_cast<std::size_t>(row) * output.stride_pixels);
                std::copy_n(source, input.width, destination);
            }
        });
}

struct ColorMatrix3x4 final {
    std::array<float, 12> values;

    [[nodiscard]] static constexpr ColorMatrix3x4 identity() noexcept {
        return ColorMatrix3x4{{
            1.0F, 0.0F, 0.0F, 0.0F,
            0.0F, 1.0F, 0.0F, 0.0F,
            0.0F, 0.0F, 1.0F, 0.0F,
        }};
    }
};

[[nodiscard]] KernelStatus apply_exposure(
    ConstImageView input,
    ImageView output,
    float stops) noexcept;

[[nodiscard]] KernelStatus apply_color_matrix(
    ConstImageView input,
    ImageView output,
    const ColorMatrix3x4& matrix) noexcept;

}  // namespace negaflow::core
