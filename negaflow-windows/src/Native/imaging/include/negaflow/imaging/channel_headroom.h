#pragma once

#include "negaflow/imaging/auto_adjust.h"

#include <cstddef>
#include <cstdint>
#include <vector>

// 자동 톤이 노출·기본 톤을 거친 뒤 채널이 1 에 닿는 화소를 미리 셉니다(macOS `ChannelHeadroom`).
//
// 노출(`apply_exposure`)은 휘도비로 RGB 를 함께 늘립니다. 기본 톤은 입력을 `tone_safe_unit_rgb` 로 [0,1] 에
// 넣고(휘도 유지, chroma 축소 — 최대 채널은 min(M, 1)), 휘도를 밝히면 세 채널에 같은 값을 더하고 어둡히면
// 채널비를 지킵니다(`with_luma`). 그래서 화소의 선형 휘도 Y 와 최대 채널 M 두 값으로 최종 최대 채널이
// 정해집니다:
//   노출 뒤  Yₑ = E(Y), Mₑ = M·Yₑ/Y
//   톤 뒤    Y' = T(Yₑ)(`basic_tone_model.h`), M' = Y' < Yₑ ? min(Mₑ, 1)·Y'/Yₑ : min(min(Mₑ, 1) + Y' − Yₑ, 1)
// 기본 톤 뒤의 단계(사용자 커브·스캐너 타깃·후처리)는 모형 밖이라 폐루프(`refine_auto_tone`)가 잰 값으로
// 다룹니다.
//
// 휘도만 보던 예전 한도(노출은 휘도 p98 ≤ 0.95, 흰색은 휘도 p99.5 → 0.90)는 채도 높은 명부의 최대 채널을
// 보지 못했습니다(2026-11-08 macOS 사용자 카탈로그: 노출 이득이 채도 높은 중간톤을, 흰색 리프트가 밝은
// 색을 1 위로 민 사진이 나왔습니다).

namespace negaflow::imaging::channel_headroom {

// 잰 클리핑의 기준(`compute_auto_adjust_stats` 와 같습니다).
inline constexpr double clip_level = 0.995;
// 예측의 여유. 예측과 렌더의 차이는 움직인 양에 비례합니다: macOS 사용자 카탈로그 90장(MAIN)의 칸별 차이는
// 95%가 0.002, 최대 0.0073 이고, 합성 노랑 면(상승 0.19)은 0.009(상승의 4.7%)였습니다(2026-11-08). 통계가
// 8 비트라 명부 반 코드(0.0045)는 늘 남습니다. 그래서 여유는 0.004 + 상승의 5%, 많아야 0.015 입니다. 고정
// 여유를 쓰면 원본에서 이미 0.98~0.995 에 있던 화소가 조금만 올라도 세어져, 원본이 날아간 JPEG 의 노출을
// 통째로 막았습니다(macOS `ChannelHeadroom.marginFloor`).
inline constexpr double margin_floor = 0.004;
inline constexpr double margin_per_rise = 0.05;
inline constexpr double maximum_margin = 0.015;
// 세어질 수 있는 가장 낮은 값(최대 여유를 뺀 클리핑 기준). 미리 거르기의 경계입니다.
inline constexpr double safe_level = clip_level - maximum_margin;
// 보호하는 휘도의 위 끝 — 자동 톤의 확산 화이트(백점 목표, 선형 0.90). 톤 뒤 휘도가 이보다 낮은데 채널이 1 에 닿는
// 화소는 채도 높은 색이 날아간 것입니다. 휘도가 그 위인 화소는 반사광·광원이라 백점 목표가 이미 확산 화이트 위에 두는
// 몫이고 날아가도 됩니다 — 세면 어두운 장면의 등불 1.7% 를 지키려 노출을 2.75 스톱 내렸습니다(macOS 사용자 카탈로그
// SP-3000 슬라이드, 2026-11-08; `ChannelHeadroom.diffuseWhite`).
inline constexpr double diffuse_white = 0.90;
// 8 비트 인코딩 휘도로 본 확산 화이트(이 코드 이하가 보호 대상, floor(encode(0.90)·255)).
inline constexpr std::uint8_t diffuse_white_code = 243U;

// 8 비트 BGRA 화소 하나의 인코딩 휘도 코드(round(encode(Y)·255)).
[[nodiscard]] std::uint8_t luma_code(std::uint8_t blue, std::uint8_t green, std::uint8_t red) noexcept;
// 자동 톤이 새로 만들어도 되는 채널 클리핑 비율. 백점 목표가 휘도 p99.5 라 상위 0.5% 는 확산 화이트를
// 넘어 반사광·광원으로 1 에 닿아도 됩니다 — 채널에도 같은 몫만 허용합니다.
inline constexpr double allowance = 0.005;
// 자동 톤의 기본 톤이 인코딩 휘도에 더할 수 있는 최대 몫: 대비 +0.55(0.07) + 농도 −0.4(0.04) + 암부 0.8(0.08)
// + 흰색 +1(0.12) + 검정 +0.15(0.009). 명부는 자동이 올리지 않습니다.
inline constexpr double maximum_auto_lift = 0.32;

// 표본 하나(선형 휘도, 최대 채널). 음수 채널은 0 으로 봅니다.
[[nodiscard]] AutoAdjustPeakSample sample(double red, double green, double blue) noexcept;

// 노출 ≤ `max_stops`, 인코딩 리프트 ≤ `max_lift` 로는 safe_level 에 못 닿는 표본을 미리 뺍니다(결과는 같고 셀
// 표본만 줄어듭니다). 숄더는 휘도를 접기만 하고 가산 리프트의 선형 몫은 휘도가 높을수록 크므로, 선형
// 이득과 그 휘도의 리프트로 잡은 값이 상한입니다. 메모리가 모자라면 예외를 던집니다.
[[nodiscard]] std::vector<AutoAdjustPeakSample> candidates(
    const std::vector<AutoAdjustPeakSample>& samples,
    double max_stops,
    double max_lift);

// 표본 하나의 노출·기본 톤 뒤 최대 채널.
[[nodiscard]] double predicted_peak(
    const AutoAdjustPeakSample& sample,
    const AutoToneResult& tone,
    double exposure_headroom_stops) noexcept;

// 중립 현상본에서 1 에 닿지 않던 채널이 `tone` 의 노출·기본 톤으로 올라 여유를 둔 클리핑 기준을 넘는 표본 비율.
// `samples` 는 `candidates` 로 거른 표본이어도 되고, 분모 `total` 은 전체 표본 수입니다.
[[nodiscard]] double induced_clipping(
    const std::vector<AutoAdjustPeakSample>& samples,
    std::size_t total,
    const AutoToneResult& tone,
    double exposure_headroom_stops) noexcept;

// 이미 렌더한 결과에 노출 `stops` 와 흰색 `whites` 를 더 얹을 때 새로 여유를 둔 클리핑 기준을 넘는 표본 비율. 폐루프가
// 더 밝히는 몫에만 씁니다 — 노출은 숄더 없이 선형 이득으로 봅니다(밝은 화소를 덜 접으므로 보수적입니다).
[[nodiscard]] double additional_clipping(
    const std::vector<AutoAdjustPeakSample>& samples,
    std::size_t total,
    double stops,
    double whites) noexcept;

// 상승 `rise` 에 두는 여유.
[[nodiscard]] double margin(double rise) noexcept;

// `before` 에서 올라 세어지지 않는 가장 높은 값.
[[nodiscard]] double ceiling(double before) noexcept;

// 폐루프 — 중립 현상본과 확인 렌더를 칸마다 맞대어 봅니다.

// 중립 현상본에서 255 가 아니던 화소 중 확인 렌더에서 어느 채널이든 255 인 화소의 비율 — 타깃·커브·후처리까지
// 거친 실제 결과입니다. 두 통계에 화소 표본이 없거나 크기가 다르면 칸으로 셉니다. 그것도 맞지 않으면 음수입니다.
[[nodiscard]] double measured_induced_clipping(
    const AutoAdjustStats& neutral,
    const AutoAdjustStats& measured) noexcept;

// 중립 현상본에서 닿지 않던 칸 중 확인 렌더에서 1 에 닿은 칸의 비율. 두 표본의 칸 수가 다르면 음수입니다.
[[nodiscard]] double measured_induced_clipping(
    const std::vector<AutoAdjustPeakSample>& neutral,
    const std::vector<AutoAdjustPeakSample>& measured) noexcept;

// 확인 렌더로 바로잡은 예측. 통계는 모형 밖 단계(스캐너 타깃·사용자 커브·후처리)까지 거친 값이라, 그 단계가 칸마다
// 더하는 몫은 중립 현상본에서 정의상 0 이고 첫 제안에서 잰 값 − 예측입니다. 그 사이는 예측이 중립에서 움직인 양에
// 비례한다고 보고 후보에 더합니다. 첫 제안에서 이미 1 에 닿은 칸은 잰 값이 1 에 묶여 그 몫이 하한이라 한 번에 덜
// 거둘 수 있습니다 — 호출 쪽이 다시 그려 이분합니다. 여유는 첫 제안에서 예측이 움직인 만큼입니다.
[[nodiscard]] double corrected_induced_clipping(
    const std::vector<AutoAdjustPeakSample>& neutral,
    const std::vector<AutoAdjustPeakSample>& measured,
    const AutoToneResult& first,
    const AutoToneResult& candidate,
    double exposure_headroom_stops) noexcept;

}  // namespace negaflow::imaging::channel_headroom
