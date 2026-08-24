#pragma once

#include "negaflow/imaging/scanner_to_working.h"
#include "negaflow/color/output_color_space.h"

#include <cstddef>
#include <cstdint>
#include <vector>

namespace negaflow::output {

enum class WorkingToSrgb16Status : std::uint8_t {
    ok = 0,
    invalid_dimensions,
    invalid_stride,
    size_overflow,
    buffer_size_mismatch,
    memory_limit_exceeded,
    non_finite_pixel,
    non_opaque_alpha,
    allocation_failed,
};

struct WorkingToSrgb16Limits final {
    std::uint64_t max_encoded_pixel_bytes{512ULL * 1024ULL * 1024ULL};
    // The space the published file is encoded in. sRGB leaves the pixels alone.
    negaflow::color::OutputColorSpace color_space{negaflow::color::OutputColorSpace::srgb};
    // False keeps the working values linear for the macOS-compatible defect bake artifact.
    bool encode_transfer{true};
    // False publishes RGB and deliberately omits alpha, matching the macOS export option.
    // True keeps straight (unassociated) alpha as a fourth output component.
    bool preserve_alpha{false};
};

struct Srgb16Image final {
    std::uint32_t width{0};
    std::uint32_t height{0};
    std::uint32_t stride_bytes{0};
    // 8 or 16. Eight-bit output is dithered before quantization; sixteen is not, which is
    // the macOS rule - a half-step of noise is invisible at 16 bits and pointless there.
    std::uint32_t bits_per_sample{16};
    // Three for RGB, four for unassociated RGBA.
    std::uint32_t channels{3};
    std::vector<std::uint16_t> samples{};
};

struct WorkingToSrgb16Info final {
    std::uint64_t encoded_pixel_bytes{0};
    std::uint64_t clipped_color_components{0};
};

struct WorkingToSrgb16Result final {
    WorkingToSrgb16Status status{WorkingToSrgb16Status::invalid_dimensions};
    WorkingToSrgb16Info info{};
    Srgb16Image image{};
};

[[nodiscard]] WorkingToSrgb16Result convert_working_to_srgb16(
    const negaflow::imaging::WorkingImage& working,
    const WorkingToSrgb16Limits& limits = {}) noexcept;

// Validates the complete image and reports the packed output layout without
// materializing the 16-bit samples. The returned image has an empty samples vector.
[[nodiscard]] WorkingToSrgb16Result inspect_working_to_srgb16(
    const negaflow::imaging::WorkingImage& working,
    const WorkingToSrgb16Limits& limits = {}) noexcept;

// Reports the packed layout for a chosen sample depth without materializing samples.
[[nodiscard]] WorkingToSrgb16Result inspect_working_to_srgb(
    const negaflow::imaging::WorkingImage& working,
    std::uint32_t bits_per_sample,
    const WorkingToSrgb16Limits& limits = {}) noexcept;

// Converts one contiguous range of rows into caller-owned packed RGB(A) bytes at the chosen
// depth. The caller must provide row_count * width * channels * (bits_per_sample / 8) bytes;
// `channels` is controlled by WorkingToSrgb16Limits::preserve_alpha.
//
// Eight-bit output adds the macOS dither: plus or minus half a step of white noise in the
// sRGB-encoded space where quantization happens, which scatters the boundary pixels of a
// smooth gradient across neighbouring steps instead of banding them. The noise is a hash of
// the absolute pixel coordinate, not a running sequence, so a row range converts identically
// however the work is split - the readback check re-runs this and compares byte for byte.
[[nodiscard]] WorkingToSrgb16Status convert_working_to_srgb_rows(
    const negaflow::imaging::WorkingImage& working,
    std::uint32_t bits_per_sample,
    std::uint32_t first_row,
    std::uint32_t row_count,
    std::uint8_t* destination_bytes,
    std::size_t destination_byte_capacity,
    std::uint64_t& clipped_color_components,
    const WorkingToSrgb16Limits& limits = {}) noexcept;

// Converts one contiguous range of image rows into caller-owned packed RGB(A) samples.
// The caller must provide space for row_count * width * channels samples.
[[nodiscard]] WorkingToSrgb16Status convert_working_to_srgb16_rows(
    const negaflow::imaging::WorkingImage& working,
    std::uint32_t first_row,
    std::uint32_t row_count,
    std::uint16_t* destination_samples,
    std::size_t destination_sample_capacity,
    std::uint64_t& clipped_color_components,
    const WorkingToSrgb16Limits& limits = {}) noexcept;

[[nodiscard]] const char* working_to_srgb16_status_name(
    WorkingToSrgb16Status status) noexcept;

}  // namespace negaflow::output
