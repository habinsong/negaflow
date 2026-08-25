#pragma once

#include "negaflow/core/cancel_flag.h"

#include <cstddef>
#include <cstdint>
#include <span>
#include <vector>

namespace negaflow::imaging {

enum class InfraredDetectionStatus : std::uint8_t {
    ok = 0,
    unreadable,
    too_small,
    no_defects,
    coverage_too_high,
    cancelled,
    allocation_failed,
};

enum class InfraredAlignmentStatus : std::uint8_t {
    not_requested = 0,
    aligned,
    insufficient_texture,
    weak_correlation,
    search_limit_reached,
};

enum class InfraredDefectClass : std::uint8_t {
    dust = 0,
    scratch_horizontal,
    scratch_vertical,
    scratch_diagonal,
};

struct InfraredDetectorParameters final {
    double sensitivity{0.5};
    std::int32_t dilate_radius{1};
    std::int32_t minimum_area{2};
    double maximum_coverage{0.05};
    std::int32_t alignment_search_radius{32};
    std::int32_t cluster_tile{768};
    std::int32_t cluster_padding{40};
};

struct InfraredAlignmentDiagnostics final {
    InfraredAlignmentStatus status{InfraredAlignmentStatus::not_requested};
    std::int32_t offset_x{0};
    std::int32_t offset_y{0};
    double peak_correlation{0.0};
    double runner_up_correlation{0.0};
    std::uint32_t search_radius{0U};
    std::uint32_t downsample_factor{1U};
};

struct InfraredPreviewPoint final {
    std::uint32_t x{0U};
    std::uint32_t y{0U};
};

struct InfraredDetectedComponent final {
    InfraredDefectClass classification{InfraredDefectClass::dust};
    double confidence{0.0};
    std::size_t area{0U};
    std::vector<InfraredPreviewPoint> preview_points{};
};

struct InfraredCorrectionCluster final {
    std::uint32_t roi_x{0U};
    std::uint32_t roi_y_up{0U};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::vector<std::uint8_t> core_mask{};
    std::vector<std::uint16_t> attenuation_r16{};
};

struct InfraredDetection final {
    std::vector<InfraredCorrectionCluster> clusters{};
    std::vector<InfraredDetectedComponent> components{};
    double coverage{0.0};
    std::int32_t offset_x{0};
    std::int32_t offset_y{0};
    InfraredAlignmentDiagnostics alignment{};
    std::size_t candidate_count{0U};
    std::size_t confirmed_count{0U};
    double median_gain{0.0};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
};

struct InfraredDetectionTimings final {
    std::uint64_t validation_microseconds{0U};
    std::uint64_t alignment_microseconds{0U};
    std::uint64_t preparation_microseconds{0U};
    std::uint64_t infrared_signal_microseconds{0U};
    std::uint64_t candidates_microseconds{0U};
    std::uint64_t visible_signal_microseconds{0U};
    std::uint64_t confirmation_microseconds{0U};
    std::uint64_t attenuation_microseconds{0U};
    std::uint64_t output_microseconds{0U};
    std::uint64_t total_microseconds{0U};
};

struct InfraredDetectionResult final {
    InfraredDetectionStatus status{InfraredDetectionStatus::unreadable};
    // 실패한 **자리**입니다. `unreadable` 하나에 여덟 갈래가 접혀 있어, 앱 안에서만 나는
    // 실패를 두고 어느 갈래인지 다투게 됩니다. 0 은 "사유 없음"입니다.
    std::uint32_t failure_detail{0U};
    InfraredDetection detection{};
    InfraredDetectionTimings timings{};
};

[[nodiscard]] InfraredDetectorParameters sanitize_infrared_detector_parameters(
    const InfraredDetectorParameters& parameters,
    std::uint32_t width,
    std::uint32_t height) noexcept;

[[nodiscard]] InfraredDetectionResult detect_infrared_defects(
    std::span<const float> infrared,
    std::span<const float> red,
    std::uint32_t width,
    std::uint32_t height,
    const InfraredDetectorParameters& parameters = {},
    negaflow::core::CancelFlag cancel = {}) noexcept;

[[nodiscard]] const char* infrared_detection_status_name(
    InfraredDetectionStatus status) noexcept;

}  // namespace negaflow::imaging
