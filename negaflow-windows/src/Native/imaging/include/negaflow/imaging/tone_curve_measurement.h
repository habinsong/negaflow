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
// `pixels_already_finite` — 호출부가 **이미 전 화소 유한성을 증명했다**는 뜻입니다.
// 참이면 `validate_finite_pixels` 를 건너뜁니다. 그 확인은 전 화소를 한 번 더 훑고,
// 실측(`docs/audit/13-performance-playbook.md` 17절)에서 톤 단계 비용의 큰 몫이었습니다.
//
// ☠️ **거짓말하면 안 됩니다.** 비유한 화소가 들어오면 정렬·백분위가 무의미해지고
//    밴드가 쓰레기가 됩니다. GPU 경로는 `GpuFiniteCheck`(원자 플래그 + 4바이트 회수)로
//    같은 판정을 먼저 내린 뒤에만 참을 넘깁니다. 확인 없이 참을 넘기지 마십시오.
//    레이아웃 확인은 이 값과 무관하게 **언제나** 합니다.
[[nodiscard]] ToneCurveMeasurementResult measure_parametric_tone_curve_bands(
    negaflow::core::ConstImageView image,
    const ToneCurveMeasurementLimits& limits = {},
    bool pixels_already_finite = false) noexcept;

[[nodiscard]] const char* tone_curve_sampling_mode_name(
    ToneCurveSamplingMode mode) noexcept;
[[nodiscard]] const char* tone_curve_measurement_status_name(
    ToneCurveMeasurementStatus status) noexcept;

}  // namespace negaflow::imaging
