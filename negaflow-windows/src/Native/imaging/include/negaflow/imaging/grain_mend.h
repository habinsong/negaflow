#pragma once

#include "negaflow/core/cancel_flag.h"
#include "negaflow/core/pixel.h"
#include "negaflow/imaging/grain_mend_classifier.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <cstddef>
#include <cstdint>
#include <vector>

namespace negaflow::imaging {

inline constexpr char grain_mend_algorithm_version[] =
    "chromabase-grain-mend-rgb-auto-v9";
inline constexpr double minimum_grain_mend_strength = 0.0;
inline constexpr double maximum_grain_mend_strength = 1.0;
inline constexpr double minimum_grain_mend_sensitivity = 0.0;
inline constexpr double maximum_grain_mend_sensitivity = 1.0;
inline constexpr double default_grain_mend_dust_sensitivity = 0.5;
inline constexpr double default_grain_mend_scratch_sensitivity = 0.5;
inline constexpr double default_grain_mend_protect_detail = 0.75;
inline constexpr double grain_mend_identity_threshold = 1.0e-3;
inline constexpr std::uint32_t grain_mend_maximum_detection_dimension = 1800U;

enum class GrainMendStatus : std::uint8_t {
    ok = 0,
    invalid_parameter,
    kernel_failed,
    allocation_failed,
    // The caller latched its cancel flag. Pixels are discarded, as with any failure,
    // so a half-repaired frame is never handed on.
    cancelled,
};

struct GrainMendParameters final {
    double strength{0.0};
    double dust_sensitivity{default_grain_mend_dust_sensitivity};
    double scratch_sensitivity{default_grain_mend_scratch_sensitivity};
    double protect_detail{default_grain_mend_protect_detail};
    bool reject_structure_lines{false};
    // macOS 는 표면 이물의 작은 무채색 어두운 점을 별도 패스로 찾아, 보통의
    // 색채 그레인과 섞이지 않게 합니다. false면 기존 dust/scratch 판정은 그대로입니다.
    bool detect_micro_specks{true};
};

// 검출 한 번을 단계로 나눈 시간입니다. "자동이 몇 초"만으로는 어디를 고쳐야 하는지 알 수
// 없어서, 형태학·스크래치 각도·성분 조립을 따로 잽니다.
struct GrainMendTimings final {
    std::uint64_t detection_image_microseconds{0U};
    std::uint64_t dust_morphology_microseconds{0U};
    std::uint64_t scratch_angles_microseconds{0U};
    std::uint64_t evidence_microseconds{0U};
    std::uint64_t speck_microseconds{0U};
    std::uint64_t stitch_microseconds{0U};
    std::uint64_t components_microseconds{0U};
    std::uint64_t total_microseconds{0U};
    std::uint32_t tile_count{0U};
    std::uint32_t worker_count{0U};
    // 검출 깔때기. 먼지 0 이 후보 부재인지 게이트 전멸인지 숫자로 가른다.
    std::uint64_t dust_weak_pixels{0U};
    std::uint64_t dust_raw_weak_pixels{0U};
    std::uint64_t dust_strong_pixels{0U};
    std::uint64_t dust_components_raw{0U};
    std::uint64_t dust_components_after_grain_field{0U};
    std::uint64_t speck_mask_pixels{0U};
    std::uint64_t speck_merged{0U};
    std::uint64_t speck_skipped_overlap{0U};
    std::uint64_t dust_components_collected{0U};
    std::uint64_t dust_dropped_no_strong{0U};
    std::uint64_t dust_dropped_strong_fraction{0U};
    std::uint64_t dust_dropped_gate{0U};
    std::uint64_t dust_dropped_isolation{0U};
    std::uint64_t dust_kept{0U};
    std::uint64_t dust_pixels_above_weak_abs{0U};
    std::uint64_t dust_pixels_above_abs{0U};
    std::uint64_t valid_pixels{0U};
    double dust_magnitude_sum{0.0};
    double dust_noise_sum{0.0};
};

struct GrainMendInfo final {
    bool applied{false};
    std::uint32_t detection_width{0U};
    std::uint32_t detection_height{0U};
    std::size_t candidate_pixels{0U};
    std::size_t repaired_pixels{0U};
    negaflow::core::KernelStatus kernel_status{
        negaflow::core::KernelStatus::ok};
};

struct GrainMendResult final {
    GrainMendStatus status{GrainMendStatus::invalid_parameter};
    GrainMendInfo info{};
    WorkingImage image{};
};

[[nodiscard]] bool valid_grain_mend_parameters(
    const GrainMendParameters& parameters) noexcept;

// RGB-only whole-frame GrainMend baseline. Detection runs in the sRGB-encoded
// analysis domain, capped at 1800 pixels on the long side. Sensitivity and
// detail protection use the same normalized 0...1 threshold controls as macOS.
// Accepted dust and thin-scratch components are repaired from the untouched
// full-resolution working image with the same 3x3 median fallback used by macOS
// automatic mode. A failure discards pixels so a partially repaired image
// cannot be published.
// Detection dominates this stage on a real scan, so cancellation is checked between the
// nine morphology passes, between the scratch angle batches and per detection tile —
// not only at the stage boundary.
[[nodiscard]] GrainMendResult apply_grain_mend(
    WorkingImage image,
    const GrainMendParameters& parameters,
    negaflow::core::CancelFlag cancel = {}) noexcept;

// Runs only the detection half of the automatic path and hands back the accepted
// dust/scratch mask instead of repairing. The reviewable GrainMend tools need the same
// decision the automatic repair makes, so this shares its three steps rather than
// reimplementing them: a mask from here and a mask used by apply_grain_mend cannot drift.
//
// The mask is one byte per pixel over the capped detection image, whose size is reported
// in `width`/`height`; it is not the full-resolution geometry. `strength` is ignored —
// detection does not depend on it.
struct GrainMendDetection final {
    GrainMendStatus status{GrainMendStatus::invalid_parameter};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    // The source-pixel rectangle that produced the analysis mask. Coordinates are
    // top-first because both the working image and the returned mask are top-first.
    std::uint32_t roi_x{0U};
    std::uint32_t roi_y{0U};
    std::uint32_t roi_width{0U};
    std::uint32_t roi_height{0U};
    std::size_t accepted_pixels{0U};
    GrainMendTimings timings{};
    std::vector<std::uint8_t> mask{};
    // 채택된 결함 하나하나. 분류(먼지·핀홀·가로/세로/대각 스크래치·유제손상·미세입자)와
    // confidence 가 붙어 있으며, 좌표는 검출 이미지(width×height) 기준입니다.
    // macOS `DefectLabelField.components` 와 같은 자리입니다.
    std::vector<grain_mend_detail::ClassifiedComponent> components{};
};

// `roi` 는 정규 좌표(좌상단 원점)이며 검출을 그 안에서만 돕니다. 가이드 도구가 쓰는 자리이고,
// 전체(0,0,1,1)를 넣으면 자동과 같습니다. 부분 ROI 는 그 부분만 잘라 분석하므로 전체를 재고
// 나중에 가리는 것과 다릅니다 — 검출은 주변 통계를 보기 때문입니다.
struct GrainMendRoi final {
    double x{0.0};
    double y{0.0};
    double width{1.0};
    double height{1.0};

    [[nodiscard]] bool covers_everything() const noexcept {
        return x <= 0.0 && y <= 0.0 && width >= 1.0 && height >= 1.0;
    }
};

[[nodiscard]] GrainMendDetection detect_grain_mend(
    const WorkingImage& image,
    const GrainMendParameters& parameters,
    GrainMendRoi roi = {},
    negaflow::core::CancelFlag cancel = {}) noexcept;

[[nodiscard]] const char* grain_mend_status_name(GrainMendStatus status) noexcept;

}  // namespace negaflow::imaging
