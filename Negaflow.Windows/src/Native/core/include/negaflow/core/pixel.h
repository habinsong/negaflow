#pragma once

#include <cstddef>
#include <cstdint>

namespace negaflow::core {

enum class KernelStatus : std::uint32_t {
    ok = 0,
    invalid_argument,
    invalid_dimensions,
    invalid_stride,
    size_overflow,
    buffer_too_small,
    dimension_mismatch,
    non_finite_parameter,
    invalid_parameter,
    non_finite_input,
    alpha_out_of_range,
    non_finite_output,
};

struct Rgba32F final {
    float red;
    float green;
    float blue;
    float alpha;
};

static_assert(sizeof(Rgba32F) == 16U);

struct ConstImageView final {
    const Rgba32F* pixels;
    std::size_t pixel_capacity;
    std::uint32_t width;
    std::uint32_t height;
    std::size_t stride_pixels;
};

struct ImageView final {
    Rgba32F* pixels;
    std::size_t pixel_capacity;
    std::uint32_t width;
    std::uint32_t height;
    std::size_t stride_pixels;
};

[[nodiscard]] KernelStatus validate_image_view(ConstImageView view) noexcept;
[[nodiscard]] KernelStatus validate_image_view(ImageView view) noexcept;
[[nodiscard]] KernelStatus validate_finite_pixels(ConstImageView view) noexcept;
[[nodiscard]] KernelStatus validate_compatible_views(
    ConstImageView input,
    ImageView output) noexcept;
[[nodiscard]] const char* kernel_status_name(KernelStatus status) noexcept;

}  // namespace negaflow::core
