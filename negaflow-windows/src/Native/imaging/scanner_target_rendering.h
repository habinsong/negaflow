#pragma once

#include "scanner_target_profile.h"

#include <array>
#include <cstddef>

namespace negaflow::imaging::scanner_target_detail {

// 스캐너 렌더링 — 장면과 무관한 고정 변환입니다(macOS `ScannerTargetGrade+Rendering.swift`,
// 표와 근거는 `+Targets.swift`). 화소 하나의 계산(작업공간 선형 sRGB):
//   1. 휘도 Y 와 스탑 y = log2(Y / 0.18), 채널 색비 d = log2(rgb) − log2(Y)
//   2. 색비 크로스토크(행 합 1)
//   3. 밝기별 R·B 색비 오프셋(스탑) — 회색 축의 크로스오버
//   4. 휘도 톤 곡선 T(y) → 출력 sRGB 코드, 밝기별 색비 게인 g(y)
//   5. 휘도를 지킨 채 색비를 되돌리고, 색역을 넘으면 같은 휘도에서 채도만 줄인다
// 색 쪽 곡선(게인·오프셋)은 knot 범위 밖에서 평평하고 톤 곡선만 끝 기울기로 연장합니다.
struct RenderingTable final {
    std::array<double, 11U> tone;
    std::array<double, 4U> chroma_gain;
    std::array<double, 6U> crosstalk;
    std::array<double, 3U> red_balance;
    std::array<double, 3U> blue_balance;
};

inline constexpr std::array<double, 11U> rendering_tone_stops{
    -8.0, -6.0, -4.0, -3.0, -2.0, -1.0, 0.0, 1.0, 1.5, 2.0, 2.5};
inline constexpr std::array<double, 4U> rendering_chroma_stops{-5.0, -2.0, 0.0, 2.0};
inline constexpr std::array<double, 3U> rendering_balance_stops{-4.0, -1.0, 2.0};
inline constexpr double rendering_positive_strength = 0.5;

[[nodiscard]] const RenderingTable& rendering_for(ScannerTargetStyle target) noexcept;

// 단조 3차 Hermite(PCHIP). 내부 기울기는 가중 조화평균, 양끝은 할선이고 범위 밖은 끝
// 기울기로 직선 연장합니다. macOS `RenderingCurve` 와 같은 정의입니다.
template <std::size_t N>
struct HermiteCurve final {
    std::array<double, N> xs{};
    std::array<double, N> ys{};
    std::array<double, N> ms{};
    [[nodiscard]] double value(double x) const noexcept;
};

struct RenderingCurves final {
    HermiteCurve<11U> tone;
    HermiteCurve<4U> chroma_gain;
    HermiteCurve<3U> red;
    HermiteCurve<3U> blue;
    std::array<double, 6U> crosstalk;
};

[[nodiscard]] RenderingCurves rendering_curves(const RenderingTable& table) noexcept;

// CPU 참조 구현입니다. 입력·출력 모두 선형 sRGB 이고, 흑백은 호출부가 luma 로 붕괴한
// 회색을 넣습니다(`monochrome` 은 회색축 오프셋을 끕니다).
[[nodiscard]] Rgb render_linear(Rgb input, const RenderingCurves& curves, bool monochrome) noexcept;

[[nodiscard]] ScannerRenderingSetup rendering_setup(
    const RenderingCurves& curves,
    bool monochrome,
    double strength) noexcept;

}  // namespace negaflow::imaging::scanner_target_detail
