#pragma once

#include "negaflow/imaging/scanner_to_working.h"

#include <cstdint>

namespace negaflow::imaging {

enum class WorkingImageResampleStatus : std::uint8_t {
    ok = 0,
    invalid_source,
    invalid_dimensions,
    size_overflow,
    allocation_failed,
};

struct WorkingImageResampleResult final {
    WorkingImageResampleStatus status{WorkingImageResampleStatus::invalid_source};
    WorkingImage image{};
};

// High-quality separable Lanczos3 scaling in the linear working domain. Callers decide
// whether a resize is necessary; this routine only accepts a strictly positive target.
[[nodiscard]] WorkingImageResampleResult resample_working_image_lanczos3(
    const WorkingImage& source,
    std::uint32_t output_width,
    std::uint32_t output_height) noexcept;

[[nodiscard]] const char* working_image_resample_status_name(
    WorkingImageResampleStatus status) noexcept;

}  // namespace negaflow::imaging
