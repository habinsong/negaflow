#pragma once

#include "negaflow/imaging/scanner_to_working.h"

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
};

struct Srgb16Image final {
    std::uint32_t width{0};
    std::uint32_t height{0};
    std::uint32_t stride_bytes{0};
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

[[nodiscard]] const char* working_to_srgb16_status_name(
    WorkingToSrgb16Status status) noexcept;

}  // namespace negaflow::output
