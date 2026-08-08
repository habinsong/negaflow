#pragma once

#include "negaflow/core/pixel.h"

#include <array>
#include <bit>
#include <cstdint>
#include <limits>
#include <string_view>

namespace negaflow::core {

inline constexpr std::string_view negative_inversion_algorithm_version =
    "shoulder-print-response-v4";

struct PrintResponse final {
    float normal_range;
    float base_toe;
    float white_output;
    float ceiling;
    float y_ceiling;
    float amplitude;
    float rate;
    float shape;
};

namespace detail {

[[nodiscard]] constexpr float float_from_bits(const std::uint32_t bits) noexcept {
    return std::bit_cast<float>(bits);
}

}  // namespace detail

static_assert(sizeof(float) == sizeof(std::uint32_t));
static_assert(std::numeric_limits<float>::is_iec559);

[[nodiscard]] constexpr PrintResponse color_negative_print_response() noexcept {
    return PrintResponse{
        detail::float_from_bits(0x3FC66666U),
        detail::float_from_bits(0x3A83126FU),
        detail::float_from_bits(0x3F333333U),
        detail::float_from_bits(0x3F666666U),
        detail::float_from_bits(0xBD3B6C35U),
        detail::float_from_bits(0x403D124FU),
        detail::float_from_bits(0x407B6C08U),
        detail::float_from_bits(0x3F5F49D0U),
    };
}

[[nodiscard]] constexpr PrintResponse black_and_white_negative_print_response() noexcept {
    return PrintResponse{
        detail::float_from_bits(0x400AE148U),
        detail::float_from_bits(0x3A03126FU),
        detail::float_from_bits(0x3F59999AU),
        detail::float_from_bits(0x3F7AE148U),
        detail::float_from_bits(0xBC0FC081U),
        detail::float_from_bits(0x4052B453U),
        detail::float_from_bits(0x4074F68DU),
        detail::float_from_bits(0x3F839CBAU),
    };
}

struct NegativeInversionParameters final {
    std::array<float, 3> dmin;
    std::array<float, 3> dmax_normalized;
};

[[nodiscard]] KernelStatus apply_negative_inversion(
    ConstImageView input,
    ImageView output,
    const NegativeInversionParameters& parameters,
    const PrintResponse& response) noexcept;

}  // namespace negaflow::core
