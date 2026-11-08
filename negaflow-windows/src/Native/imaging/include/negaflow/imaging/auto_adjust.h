#pragma once

#include "negaflow/core/pointwise.h"
#include "negaflow/imaging/neutral_axis_evidence.h"

#include <array>
#include <cstdint>
#include <optional>
#include <vector>

namespace negaflow::imaging {

// Automatic develop settings, the classic way — histogram percentiles inverted through
// the transfer functions the tone stage actually uses, not a learned model.
//
// The caller renders a neutral develop (the target sliders at zero) to an 8-bit sRGB
// bitmap and hands the statistics here; the returned values are **assigned** to the
// sliders, not accumulated, so pressing auto twice gives the same answer as pressing it
// once.
//
// Every coefficient below is the inverse of one in `tone_mapping.cpp` and `color_model`.
// If those masks are recalibrated, these have to move with them or auto will aim at the
// wrong place.

inline constexpr std::size_t auto_adjust_histogram_bins = 256U;

// 표본 칸 하나의 선형 휘도와 최대 채널입니다(`channel_headroom.h`).
struct AutoAdjustPeakSample final {
    double luminance{0.0};
    double peak{0.0};
};

struct AutoAdjustStats final {
    // sRGB gamma-domain means over the sampled grid.
    double average_red{0.0};
    double average_green{0.0};
    double average_blue{0.0};

    // Means over the near-neutral subset only, which is what a white balance estimate
    // should lean on when the scene provides one.
    double neutral_average_red{0.0};
    double neutral_average_green{0.0};
    double neutral_average_blue{0.0};
    double neutral_pixel_fraction{0.0};

    // The same neutral subset in linear light, because the colour gains being inverted
    // are linear multiplications.
    double neutral_linear_red{0.0};
    double neutral_linear_green{0.0};
    double neutral_linear_blue{0.0};

    // Minkowski p=6 linear mean (Shades-of-Gray). Weights bright pixels, which holds up
    // better than an arithmetic mean on scenes with one dominant colour.
    double minkowski_linear_red{0.0};
    double minkowski_linear_green{0.0};
    double minkowski_linear_blue{0.0};

    // sRGB-encoded linear luminance histogram, normalised to sum to 1.
    std::array<double, auto_adjust_histogram_bins> luma_histogram{};
    double average_saturation{0.0};
    double clipped_fraction{0.0};
    double white_balance_confidence{1.0};

    // 휘도대별 중립축 증거입니다. 자동 WB가 신뢰도로 강도를 줄이고 대역
    // 중앙값의 중앙값을 씁니다 — 한 휘도대를 차지한 따뜻한 조명 면이 평균을 끌지 못합니다
    // (macOS `ImageStats.neutralAxis`).
    std::optional<NeutralAxisEvidence> neutral_axis{};

    // 표본 칸마다 (선형 휘도, 선형 최대 채널). 자동 톤이 노출·기본 톤 뒤에 새로 1 에 닿는 채널을 세는 데
    // 씁니다(`channel_headroom.h`, macOS `ImageStats.peakSamples`). 휘도 히스토그램만 채운 합성 통계는
    // 비어 있고, 그때는 채널 한도를 걸지 않습니다.
    std::vector<AutoAdjustPeakSample> peak_samples{};

    // 비트맵의 화소마다 가장 큰 채널 코드(0~255, 알파 0 은 0). 폐루프가 중립 현상본과 화소마다 맞대어 새로 255 에
    // 닿은 화소를 셉니다 — 칸 평균은 구름·잎사귀처럼 질감 있는 명부의 클리핑을 묻습니다(사용자 카탈로그 감사: 칸
    // 기준 0%, 화소 기준 5.75%). 합성 통계는 비어 있고, 그때는 칸으로 셉니다(macOS `ImageStats.pixelPeaks`).
    std::vector<std::uint8_t> pixel_peaks{};
    // 같은 화소의 인코딩 휘도 코드(0~255). 확산 화이트 위의 반사광·광원은 채널 한도에서 뺍니다
    // (`channel_headroom::diffuse_white`, macOS `ImageStats.pixelLuma`).
    std::vector<std::uint8_t> pixel_luma{};
};

struct AutoWhiteBalanceResult final {
    double warmth{0.0};
    double tint{0.0};
};

struct AutoToneResult final {
    double exposure{0.0};
    double contrast{0.0};
    double highlights{0.0};
    double shadows{0.0};
    double whites{0.0};
    double blacks{0.0};
    double density{0.0};
    // Retained for compatibility; Auto Tone leaves color controls unchanged.
    double vibrance{0.0};
};

// Long side of the sampling grid. The statistics are percentile and mean based, so a
// small proxy is enough and keeps auto instant on a full scan.
inline constexpr std::uint32_t auto_adjust_sample_extent = 200U;

// Reads a BGRA8 bitmap — the same layout the preview produces — and reduces it to the
// statistics above. Returns false only for an empty or malformed buffer.
[[nodiscard]] bool compute_auto_adjust_stats(
    const std::uint8_t* pixels,
    std::uint32_t width,
    std::uint32_t height,
    std::size_t stride_bytes,
    AutoAdjustStats& stats) noexcept;

// `compute_auto_adjust_stats` 와 같은 칸에서 휘도 히스토그램과 클리핑 비율만 만듭니다(장면 키·채널 한도의 바닥은 이것만
// 씁니다 — 중립축·채널 표본은 건너뛰어 폐루프 한 번에 렌더 수만큼 드는 통계 비용을 줄입니다).
[[nodiscard]] bool compute_auto_adjust_luminance_stats(
    const std::uint8_t* pixels,
    std::uint32_t width,
    std::uint32_t height,
    std::size_t stride_bytes,
    AutoAdjustStats& stats) noexcept;

// Sends the near-neutral linear mean to grey by inverting ColorModel's warmth and tint
// gains. Deliberately partial: a full correction runs away into the opposite cast on
// scenes where the grey-world assumption fails, such as a sunset or a forest.
// 중립축 증거가 있으면 그 대역 중앙값을 씁니다. 결과는 ±1(예전 슬라이더 끝)로 묶습니다.
[[nodiscard]] AutoWhiteBalanceResult auto_white_balance(
    const AutoAdjustStats& stats) noexcept;

// 노출을 정한 뒤 기본 톤 커널의 합성 순서(대비 → 농도 → 명부 → 암부 → 흰색 → 검정)대로 풉니다.
// 각 단계는 앞 단계를 이미 적용한 백분위에서 그 단계의 계수·마스크로 역산하므로(`basic_tone_model.h`)
// 답이 서로 싸우지 않고 합성됩니다. `peak_samples` 가 있으면 새로 1 에 닿는 채널이 0.5% 를 넘지 않게 흰색 →
// 노출(농도가 키를 채움) → 농도·대비 순서로 밝히는 몫을 거둡니다(`channel_headroom.h`).
// `exposure_headroom_stops` 는 노출 + 쪽 숄더의 헤드룸입니다(`core::exposure_headroom_stops` —
// 흑백 네거티브만 다릅니다). 노출 뒤 백분위를 엔진과 같은 숄더 연산자로 예측합니다.
[[nodiscard]] AutoToneResult auto_tone(
    const AutoAdjustStats& stats,
    double exposure_headroom_stops =
        static_cast<double>(negaflow::core::color_exposure_headroom_stops)) noexcept;

// 자동 톤 폐루프 한 번입니다(macOS `AutoAdjust.refineTone`). `auto_tone` 은 슬라이더 전달함수를
// 모형으로 거꾸로 풀지만 사용자 커브·색 깊이·스캐너 타깃과의 상호작용은 모형 밖입니다. 첫 값을
// 실제로 적용해 다시 렌더한 통계(`measured`)로 미드와 백점을 한 번 바로잡습니다. 더 밝히는 몫은 잰 클리핑과
// 합쳐 채널 한도 안에서만 줍니다. 다른 값은 `first` 그대로입니다.
// `neutral`(톤 슬라이더 0 의 중립 현상본 통계)을 주면 확인 렌더와 칸마다 맞대어 실제로 새로 날아간 채널을 셉니다 —
// 스캐너 타깃·사용자 커브처럼 첫 계산의 모형 밖 단계까지 거친 값입니다. 그 비율이 채널 한도를 넘으면 키·백점
// 보정 대신 흰색 → 노출 순서로 첫 제안의 밝히는 몫을 거둡니다. 넘지 않으면 키·백점 보정을 그대로 내고, 더 밝힌 몫이
// 넘치는지는 셸의 폐루프가 그려서 봅니다. `neutral` 이 없으면 잰 클리핑을 모두 이미 쓴 몫으로 보고 더 밝히는 몫을
// 모형으로 줄입니다(macOS `refineTone(_:measured:neutral:)`).
[[nodiscard]] AutoToneResult refine_auto_tone(
    const AutoToneResult& first,
    const AutoAdjustStats& measured,
    double exposure_headroom_stops =
        static_cast<double>(negaflow::core::color_exposure_headroom_stops),
    const AutoAdjustStats* neutral = nullptr) noexcept;

// 새로 날아간 채널이 한도를 넘는 양(넘지 않으면 0). 두 통계의 칸이 맞지 않으면 음수입니다
// (macOS `AutoAdjust.channelExcess`).
[[nodiscard]] double auto_tone_channel_excess(
    const AutoAdjustStats& neutral,
    const AutoAdjustStats& measured) noexcept;

// 같은 크기의 BGRA8 두 장에서 첫 장에 255 가 아니던 화소 중 둘째 장에서 어느 채널이든 255 이고 휘도가 확산 화이트
// 이하인 화소의 비율입니다(알파 0 은 셉니다만 닿지 않습니다 — `compute_auto_adjust_stats` 의 `pixel_peaks`·`pixel_luma`
// 와 같은 정의). 크기가 잘못이면 음수.
[[nodiscard]] double induced_pixel_clipping(
    const std::uint8_t* neutral, std::size_t neutral_stride_bytes,
    const std::uint8_t* measured, std::size_t measured_stride_bytes,
    std::uint32_t width, std::uint32_t height) noexcept;

// 채널 한도가 노출에서 거둘 수 있는 최대 몫(스톱). 그 아래로는 클리핑을 받아들입니다 — 어두운 SP-3000 슬라이드의 채도
// 높은 등불(화소 1.7%)을 지키려 폐루프가 노출을 1.2 스톱 내려 장면 키가 2.5 스톱 어두워졌고, 사용자는 같은 사진을
// 1.35% 클리핑을 감수하고 밝게 맞췄습니다(macOS `AutoAdjust.channelExposureBudget`, 2026-11-08 사용자 카탈로그).
inline constexpr double auto_tone_channel_exposure_budget = 1.0;

// 채널 한도가 노출을 내릴 수 있는 바닥: 휘도만 본 노출에서 예산을 뺀 값, 다만 0 아래로는 내리지 않습니다(휘도만 본
// 노출이 이미 음수면 그 값). `neutral` 의 채널 표본을 빼고 푼 노출이 기준입니다.
[[nodiscard]] double auto_tone_channel_exposure_floor(
    const AutoAdjustStats& neutral,
    double exposure_headroom_stops =
        static_cast<double>(negaflow::core::color_exposure_headroom_stops)) noexcept;

// 채널 한도가 폐루프에서 더 내줄 수 있는 장면 키(스톱): 예산에서 첫 계산이 휘도만 본 노출보다 이미 낮춘 몫을 뺀 값
// (macOS `AutoAdjust.remainingKeyBudget`). 폐루프는 확인 렌더의 장면 키에서 이만큼 아래를 바닥으로 씁니다 — 노출이
// 아니라 잰 키로 거는 것은 스캐너 타깃의 톤 곡선이 노출 변화를 키워서입니다(SP-3000 슬라이드: 노출 0.95 스톱에 키
// 2 스톱).
[[nodiscard]] double auto_tone_remaining_key_budget(
    const AutoAdjustStats& neutral,
    double first_exposure,
    double exposure_headroom_stops =
        static_cast<double>(negaflow::core::color_exposure_headroom_stops)) noexcept;

// 장면 키 — 선형 휘도의 로그 평균(macOS `ImageStats.logAverageLuminance`).
[[nodiscard]] double auto_tone_scene_key(const AutoAdjustStats& stats) noexcept;

// 채널 한도가 폐루프 뒤에도 넘칠 때 더 그려 보는 최대 횟수(macOS `AutoAdjust.channelRefinementLimit`).
inline constexpr int auto_tone_channel_refinement_limit = 3;

// Ranks rendered tone candidates by middle tone, endpoints, range, and clipping.
[[nodiscard]] double auto_tone_score(const AutoAdjustStats& stats, bool adjust_mid) noexcept;

}  // namespace negaflow::imaging
