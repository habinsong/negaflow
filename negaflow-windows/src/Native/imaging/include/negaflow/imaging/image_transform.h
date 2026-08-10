#pragma once

#include "negaflow/imaging/scanner_to_working.h"

#include <cstdint>

namespace negaflow::imaging {

inline constexpr char image_transform_algorithm_version[] =
    "chromabase-image-transform-cpu-v1";

enum class ImageRotation : std::uint8_t {
    degrees_0 = 0,
    degrees_90,
    degrees_180,
    degrees_270,
};

struct NormalizedCropRect final {
    double x{0.0};
    double y{0.0};
    double width{1.0};
    double height{1.0};
};

struct ImageTransformParameters final {
    ImageRotation rotation{ImageRotation::degrees_0};
    bool flip_horizontal{false};
    bool flip_vertical{false};
    bool has_crop{false};
    NormalizedCropRect crop{};
    double straighten_angle{0.0};
};

enum class ImageTransformStatus : std::uint8_t {
    ok = 0,
    invalid_parameter,
    invalid_image,
    allocation_failed,
};

struct ImageTransformInfo final {
    bool applied{false};
    bool resampled{false};
};

struct ImageTransformResult final {
    ImageTransformStatus status{ImageTransformStatus::invalid_parameter};
    ImageTransformInfo info{};
    WorkingImage image{};
};

[[nodiscard]] bool valid_image_transform_parameters(
    const ImageTransformParameters& parameters) noexcept;

// Fixed macOS geometry order: flip H, flip V, quarter-turn rotation,
// straighten with an inscribed same-aspect crop, then normalized y-up crop.
[[nodiscard]] ImageTransformResult apply_image_transform(
    WorkingImage image,
    const ImageTransformParameters& parameters) noexcept;

[[nodiscard]] const char* image_transform_status_name(
    ImageTransformStatus status) noexcept;

}  // namespace negaflow::imaging
