#pragma once

#include "negaflow/core/cancel_flag.h"

#include <cstdint>
#include <span>
#include <vector>

namespace negaflow::imaging {

// Aperture dimensions are expressed in the strip direction first. The detector does not infer
// an aperture from image brightness: it needs the selected physical format and scan size.
enum class FlatbedFrameFormat : std::uint8_t {
    full_frame_35mm = 0,
    square_35mm,
    half_frame_35mm,
    medium_645,
    medium_66,
    medium_67,
    medium_68,
    medium_69,
    medium_612,
    medium_617,
};

enum class FlatbedFrameGridStatus : std::uint8_t {
    ok = 0,
    invalid_input,
    cancelled,
    allocation_failed,
};

struct FlatbedFramePreview final {
    std::span<const float> luminance{};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    double physical_width_mm{0.0};
    double physical_height_mm{0.0};
};

struct FlatbedFrameDetection final {
    // Source-image normalized coordinates with top-left origin.
    double x{0.0};
    double y{0.0};
    double width{0.0};
    double height{0.0};
    double confidence{0.0};
    std::uint32_t row{0U};
    std::uint32_t column{0U};
};

struct FlatbedFrameGridResult final {
    FlatbedFrameGridStatus status{FlatbedFrameGridStatus::invalid_input};
    std::vector<FlatbedFrameDetection> detections{};
};

[[nodiscard]] FlatbedFrameGridResult detect_flatbed_frame_grid(
    const FlatbedFramePreview& preview,
    FlatbedFrameFormat format = FlatbedFrameFormat::full_frame_35mm,
    negaflow::core::CancelFlag cancel = {}) noexcept;

[[nodiscard]] const char* flatbed_frame_grid_status_name(
    FlatbedFrameGridStatus status) noexcept;

}  // namespace negaflow::imaging
