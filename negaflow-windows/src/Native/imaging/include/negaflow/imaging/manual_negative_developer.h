#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/analysis_region.h"
#include "negaflow/imaging/muted_scene_vibrance.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <array>
#include <cstdint>
#include <optional>

namespace negaflow::imaging {

enum class NegativeFilmType : std::uint8_t {
    color = 0,
    black_and_white,
};

enum class ManualNegativeDevelopStatus : std::uint8_t {
    ok = 0,
    invalid_parameter,
    kernel_failed,
};

// 채널 범위 교정으로 받아들이는 곱의 범위 — macOS `ChannelRangeCalibration.allowedMultiplier` 와 같다.
inline constexpr float minimum_channel_range_multiplier = 0.5F;
inline constexpr float maximum_channel_range_multiplier = 2.0F;

// The range the developer clamps a manual film base into. Declared here rather than kept
// inside the .cpp so the C ABI can report it: a UI that duplicates the numbers offers the
// user a value the engine will quietly move, which is worse than refusing it.
inline constexpr float minimum_manual_dmin = 1.0e-3F;
inline constexpr float maximum_manual_dmin = 1.0F;

// 장면 밀도 범위 측정의 결과. 같은 화상·베이스·측정 영역이면 다시 재도 같은 값이므로 호출자가
// 캐시해 두었다가 `ManualNegativeDevelopParameters::reused_scene_range` 로 돌려줄 수 있다.
struct SceneRangeMeasurement final {
    std::array<float, 3> dmax_normalized{};
    std::array<float, 3> black_input{};
};

struct ManualNegativeDevelopParameters final {
    std::array<float, 3> dmin;
    NegativeFilmType film_type{NegativeFilmType::color};
    // Stock-relative factors multiply the selected scene or nominal density range.
    // Manufacturer Status M is not scanner RGB.
    bool use_preset_response{false};
    std::array<float, 3> preset_range_factor{};
    std::optional<std::array<float, 3>> input_gamma_reference_range{};
    // 크롭한 사진 영역(원본 정규 좌표). 있으면 장면 밀도 범위와 뮤트 채도를 그 안에서만 잽니다.
    std::optional<AnalysisRegion> analysis_region{};
    // 장치×필름의 채널 밀도 범위 교정(R·G·B 곱, 기하평균 1). 장면을 읽지 않는 고정 범위
    // (명목 범위 × 필름 상대 계수)에만 곱한다. 컬러 전용이고, 장면 범위를 쓰는 경로에서는 무시한다.
    // macOS `DevelopParameters.channelRange` / `NegativeAutoBalance.fixedStats` 와 같다.
    std::optional<std::array<float, 3>> channel_range{};
    // 호출자가 **같은 화상·베이스(dmin)·측정 영역·legacy 여부**에서 이미 잰 값. 있으면 해당 측정을
    // 건너뛴다(측정은 결정적이라 결과 화소가 같다). 맞는지는 호출자가 보장한다.
    std::optional<SceneRangeMeasurement> reused_scene_range{};
    // 반전한 화상의 장면 평균 채도(뮤트 채도 보정의 입력). 위와 같은 조건에서 이미 쟀다면 넘긴다.
    std::optional<double> reused_mean_saturation{};
    bool adaptive_density{false};
    bool legacy_scene_response{false}; // MAIN/CS Auto Balance: 412bb31 range cap and vibrance.
    bool linear_output{false};   // Fixed base; output tone follows WB/exposure.
};

struct ManualNegativeDevelopInfo final {
    std::array<float, 3> applied_dmin{};
    std::array<float, 3> dmax_normalized{};
    // macOS DevelopDebugMetrics.blackInput - 장면 어두운 부분(p90 투과율)입니다.
    // 반전 수식에 들어가지 않는 지표 전용 값이며, 개발자 디버그 화면이 읽습니다.
    std::array<float, 3> black_input{};
    // 이번 호출이 쓴 장면 밀도 범위(새로 쟀거나 재사용한 값). 측정하지 않았으면 비어 있다.
    std::optional<SceneRangeMeasurement> scene_range{};
    MutedSceneVibranceInfo muted_scene_vibrance{};
    negaflow::core::KernelStatus kernel_status{
        negaflow::core::KernelStatus::invalid_argument};
};

struct ManualNegativeDevelopResult final {
    ManualNegativeDevelopStatus status{ManualNegativeDevelopStatus::invalid_parameter};
    ManualNegativeDevelopInfo info{};
    WorkingImage image{};
};

// Manual inversion uses fixed density units and no scene vibrance. Explicit
// scanner targets set adaptive_density. linear_output defers output tone
// until after WB/exposure. The owned image is transformed in place.
[[nodiscard]] ManualNegativeDevelopResult develop_manual_negative(
    WorkingImage image,
    const ManualNegativeDevelopParameters& parameters) noexcept;

// 한 프레임의 장면 밀도 범위를 잰다(`develop_manual_negative` 의 자동 밸런스 측정과 같은 함수).
// `dmin` 은 현상이 쓰는 것과 같이 허용 범위로 묶어 쓴다. 측정할 수 없으면 비어 있다.
[[nodiscard]] std::optional<SceneRangeMeasurement> measure_scene_range(
    const WorkingImage& image,
    const std::array<float, 3>& dmin,
    NegativeFilmType film_type,
    const std::optional<AnalysisRegion>& region,
    bool legacy_scene_response) noexcept;

[[nodiscard]] const char* manual_negative_develop_status_name(
    ManualNegativeDevelopStatus status) noexcept;
[[nodiscard]] const char* negative_film_type_name(NegativeFilmType film_type) noexcept;

}  // namespace negaflow::imaging
