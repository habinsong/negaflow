#pragma once

#include "negaflow/core/pointwise.h"
#include "negaflow/imaging/neutral_axis_evidence.h"

#include <array>
#include <cstdint>
#include <optional>

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

    // Luma histogram in the sRGB gamma domain, normalised to sum to 1.
    std::array<double, auto_adjust_histogram_bins> luma_histogram{};
    double average_saturation{0.0};

    // 휘도대별 중립축 증거입니다. 있으면(그리고 고전 gray-world 폴백이 아니면) 자동 WB 가 대역
    // 중앙값의 중앙값을 씁니다 — 한 휘도대를 차지한 따뜻한 조명 면이 평균을 끌지 못합니다
    // (macOS `ImageStats.neutralAxis`).
    std::optional<NeutralAxisEvidence> neutral_axis{};
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

// Sends the near-neutral linear mean to grey by inverting ColorModel's warmth and tint
// gains. Deliberately partial: a full correction runs away into the opposite cast on
// scenes where the grey-world assumption fails, such as a sunset or a forest.
// 중립축 증거가 있으면 그 대역 중앙값을 씁니다. 결과는 ±1(예전 슬라이더 끝)로 묶습니다.
[[nodiscard]] AutoWhiteBalanceResult auto_white_balance(
    const AutoAdjustStats& stats) noexcept;

// Exposure, then whites/blacks, then highlights/shadows, then density, then contrast.
// Each step predicts where the previous one moved the percentiles, so the answers
// compose instead of fighting each other.
// `exposure_headroom_stops` 는 노출 + 쪽 숄더의 헤드룸입니다(`core::exposure_headroom_stops` —
// 흑백 네거티브만 다릅니다). 노출 뒤 백분위를 엔진과 같은 숄더 연산자로 예측합니다.
[[nodiscard]] AutoToneResult auto_tone(
    const AutoAdjustStats& stats,
    double exposure_headroom_stops =
        static_cast<double>(negaflow::core::color_exposure_headroom_stops)) noexcept;

// 자동 톤 폐루프 한 번입니다(macOS `AutoAdjust.refineTone`). `auto_tone` 은 슬라이더 전달함수를
// 모형으로 거꾸로 풀지만 사용자 커브·색 깊이·스캐너 타깃과의 상호작용은 모형 밖입니다. 첫 값을
// 실제로 적용해 다시 렌더한 통계(`measured`)로 미드(노출이 밝힌 경우만)와 백점을 한 번 바로잡습니다.
// 다른 값은 `first` 그대로입니다.
[[nodiscard]] AutoToneResult refine_auto_tone(
    const AutoToneResult& first,
    const AutoAdjustStats& measured,
    double exposure_headroom_stops =
        static_cast<double>(negaflow::core::color_exposure_headroom_stops)) noexcept;

}  // namespace negaflow::imaging
