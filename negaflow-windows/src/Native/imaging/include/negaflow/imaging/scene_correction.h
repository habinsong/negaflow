#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/analysis_region.h"

#include <cstddef>
#include <cstdint>
#include <optional>
#include <vector>

namespace negaflow::imaging {

struct SceneCorrectionParameters final {
    bool auto_levels{false};
    bool auto_neutral_balance{false};
    bool negative_source{true};
    // 크롭한 사진 영역(원본 정규 좌표). 있으면 그 안에서만 표본을 모읍니다. 없으면 프레임
    // 가장자리 6% 를 버립니다(홀더·백라이트가 화이트/블랙포인트가 되지 않게 — macOS
    // `AutoLevels.frameBorderInset`).
    std::optional<AnalysisRegion> analysis_region{};
    bool linear_negative_output{false};
    bool monochrome{false};
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
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::vector<double> red{};
    std::vector<double> green{};
    std::vector<double> blue{};
};

// 표본 격자의 긴 변 상한입니다. macOS 와 같은 값이며 두 보정이 서로 다릅니다.
inline constexpr std::uint32_t scene_auto_levels_sample_width = 256U;
inline constexpr std::uint32_t scene_neutral_balance_sample_width = 192U;

// 크롭 영역이 없을 때 버리는 격자 가장자리 비율입니다 — 반전 측정과 같습니다.
inline constexpr double scene_frame_border_inset = 0.06;

// 자동 레벨의 위쪽 묶음입니다. 백포인트 너머(스펙큘러)는 작업 화상의 확장값 계약대로 남겨
// 노출 숄더와 출력 경계가 접게 합니다 — 1 에서 자르면 명부 계조가 평탄면이 됩니다.
inline constexpr double scene_auto_levels_upper_clamp = 1.0e4;

struct SceneAutoLevelsPlan final {
    bool apply{false};
    double scale[3]{1.0, 1.0, 1.0};
    double bias[3]{0.0, 0.0, 0.0};
};

// 자동 색상(중성 균형)입니다. 채널마다 c' = gain·c^exponent — 장면의 중립축 증거에 맞춘
// ln c = α + β·ln Ȳ 를 정확히 뒤집습니다(exponent = 1/β, gain = exp(−α/β)). 0 이하 값은
// 그대로 둡니다(거듭제곱이 정의되지 않습니다). macOS `NeutralBalance` 와 같은 규칙입니다.
//
// 예전에는 전체 화소의 채널 중앙값을 목표로 채널별 감마(0·1 고정)를 걸었습니다. 감마는 균일한
// 캐스트(광원·WB 성분)를 고치지 못하고 교차 캐스트로 바꿨고(R/B 0.667 의 균일 캐스트가 암부
// +0.30 스톱 과보정, 명부 −0.49 스톱 미보정), 전체 중앙값은 지배색 장면을 무채색으로 끌었습니다.
struct SceneNeutralBalancePlan final {
    bool apply{false};
    double exponent[3]{1.0, 1.0, 1.0};
    double gain[3]{1.0, 1.0, 1.0};
};

// 목표 격자의 크기입니다. 원본이 너무 작거나 칸이 너무 많으면 false 이고, 그때 보정은
// 건너뜁니다 — CPU 판의 `collect_area_samples` 초입 판정 그대로입니다.
[[nodiscard]] bool scene_sample_grid_extent(
    std::uint32_t image_width,
    std::uint32_t image_height,
    std::uint32_t target_width,
    std::uint32_t& out_width, std::uint32_t& out_height) noexcept;

// 크롭 영역이 없을 때 격자 가장자리 `fraction` 을 버립니다(macOS `sampleBlackWhite` 의
// `insetFraction` 과 같은 칸). `grid_width` 는 격자 가로 칸 수입니다.
void inset_scene_samples(
    SceneSampleGrid& samples,
    std::uint32_t grid_width,
    double fraction);

// 두 함수 모두 **표본을 자리에서 정렬하거나 소비합니다**(백분위·중앙값이 정렬을 요구합니다).
[[nodiscard]] SceneAutoLevelsPlan plan_scene_auto_levels(
    SceneSampleGrid& samples,
    bool negative_source, bool linear_negative_output = false, bool monochrome = false) noexcept;

[[nodiscard]] SceneNeutralBalancePlan plan_scene_neutral_balance(
    SceneSampleGrid& samples) noexcept;

}  // namespace negaflow::imaging
