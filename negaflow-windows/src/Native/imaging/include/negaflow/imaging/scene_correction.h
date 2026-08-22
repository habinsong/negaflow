#pragma once

#include "negaflow/core/pixel.h"

#include <cstddef>
#include <cstdint>
#include <vector>

namespace negaflow::imaging {

struct SceneCorrectionParameters final {
    bool auto_levels{false};
    bool auto_neutral_balance{false};
    bool negative_source{true};
};

struct SceneCorrectionInfo final {
    bool auto_levels_applied{false};
    bool neutral_balance_applied{false};
    std::uint64_t sampled_pixels{0U};
};

// Applies the two opt-in scene-adaptive corrections at the same pipeline boundary as
// macOS Chromabase: after negative inversion (or positive decode) and before ColorModel.
// The image is modified in place; disabled or ineligible corrections are exact no-ops.
[[nodiscard]] negaflow::core::KernelStatus apply_scene_correction(
    negaflow::core::ImageView image,
    const SceneCorrectionParameters& parameters,
    SceneCorrectionInfo& info) noexcept;

// ── 판정 규칙 ────────────────────────────────────────────────────────────────
//
// 아래는 **표본에서 보정 계수를 정하는 규칙**입니다. 화소를 만지지 않습니다.
//
// 왜 공개하는가 — GPU 경로(`pipeline/gpu_accelerator_scene.cpp`)는 표본을 컴퓨트 셰이더로
// 모으고 적용도 셰이더로 합니다. 그때 **판정까지 따로 쓰면 규칙이 두 벌이 됩니다.**
// 임계값 하나가 어긋나면 프리뷰와 내보내기가 다른 사진이 됩니다. 그래서 판정은 여기
// 한 벌만 두고 두 경로가 같은 함수를 부릅니다 —
// `gpu_vibrance.cpp` 가 `select_vibrance_planes` 를 그대로 부르는 것과 같은 이유입니다.

// 면적 평균 표본 격자입니다. 세 채널 모두 목표 격자의 행 우선 순서로 채웁니다.
struct SceneSampleGrid final {
    std::vector<double> red{};
    std::vector<double> green{};
    std::vector<double> blue{};
};

// 표본 격자의 가로 칸 수입니다. macOS 와 같은 값이며 두 보정이 서로 다릅니다.
inline constexpr std::uint32_t scene_auto_levels_sample_width = 256U;
inline constexpr std::uint32_t scene_neutral_balance_sample_width = 192U;

// macOS `CIColorCube` 와 같은 32칸입니다.
inline constexpr std::size_t scene_cube_dimension = 32U;

struct SceneAutoLevelsPlan final {
    bool apply{false};
    double scale[3]{1.0, 1.0, 1.0};
    double bias[3]{0.0, 0.0, 0.0};
};

struct SceneNeutralBalancePlan final {
    bool apply{false};
    double gamma[3]{1.0, 1.0, 1.0};
    // 화소마다 `std::pow` 를 두 번 부르지 않도록 미리 편 32칸 표입니다.
    double cube[3][scene_cube_dimension]{};
};

// 목표 격자의 크기입니다. 원본이 너무 작거나 칸이 너무 많으면 false 이고, 그때 보정은
// 건너뜁니다 — CPU 판의 `collect_area_samples` 초입 판정 그대로입니다.
[[nodiscard]] bool scene_sample_grid_extent(
    std::uint32_t image_width,
    std::uint32_t image_height,
    std::uint32_t target_width,
    std::uint32_t& out_height) noexcept;

// 두 함수 모두 **표본을 자리에서 정렬합니다**(백분위·중앙값이 정렬을 요구합니다).
[[nodiscard]] SceneAutoLevelsPlan plan_scene_auto_levels(
    SceneSampleGrid& samples,
    bool negative_source) noexcept;

[[nodiscard]] SceneNeutralBalancePlan plan_scene_neutral_balance(
    SceneSampleGrid& samples) noexcept;

}  // namespace negaflow::imaging
