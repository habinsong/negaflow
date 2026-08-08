#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/tone_mapping.h"

#include <cstddef>
#include <cstdint>

namespace negaflow::imaging {

enum class ToneCurveSamplingMode : std::uint8_t {
    none = 0,
    fixed_fallback,
    portable_area_v1,
};

enum class ToneCurveMeasurementStatus : std::uint8_t {
    ok = 0,
    invalid_input,
    sample_limit_exceeded,
    allocation_failed,
};

struct ToneCurveMeasurementLimits final {
    std::uint64_t max_sample_pixels{1ULL * 1024ULL * 1024ULL};
};

struct ToneCurveMeasurementInfo final {
    ParametricToneCurveBands bands{};
    ToneCurveSamplingMode sampling_mode{ToneCurveSamplingMode::none};
    std::uint32_t target_width{0};
    std::uint32_t target_height{0};
    std::uint64_t sampled_luma_count{0};
    std::uint64_t peak_temporary_bytes{0};
};

struct ToneCurveMeasurementResult final {
    ToneCurveMeasurementStatus status{ToneCurveMeasurementStatus::invalid_input};
    negaflow::core::KernelStatus kernel_status{
        negaflow::core::KernelStatus::invalid_argument};
    ToneCurveMeasurementInfo info{};
};

// Matches the macOS target dimensions, border exclusion, percentile indices, and band derivation.
// Apple's default high-quality affine downsampler does not publish its filter coefficients, so the
// Windows sampling raster is an explicit area average and is reported as portable_area_v1.
[[nodiscard]] ToneCurveMeasurementResult measure_parametric_tone_curve_bands(
    negaflow::core::ConstImageView image,
    const ToneCurveMeasurementLimits& limits = {}) noexcept;

[[nodiscard]] const char* tone_curve_sampling_mode_name(
    ToneCurveSamplingMode mode) noexcept;
[[nodiscard]] const char* tone_curve_measurement_status_name(
    ToneCurveMeasurementStatus status) noexcept;

}  // namespace negaflow::imaging
