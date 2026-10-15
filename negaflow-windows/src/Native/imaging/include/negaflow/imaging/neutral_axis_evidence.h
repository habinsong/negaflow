#pragma once

#include <array>
#include <cstddef>
#include <optional>
#include <vector>

namespace negaflow::imaging {

// 장면의 중립축 증거 — 무채색이어야 할 화소들의 채널 캐스트를 휘도대별로 모읍니다. 자동 색상
// (자동 중성 균형)과 자동 화이트밸런스가 함께 씁니다. macOS `NeutralAxisEvidence` 와 같은
// 규칙입니다.
//
// 반전은 채널별 Dmax 정규화로 이미 거의 중립이므로 남은 캐스트는 작다고 봅니다: 중립에서 0.5
// 스톱 안의 화소만 후보로 잡고(숲의 초록·노을 같은 지배색은 그보다 멀어 빠집니다), 후보의 중앙
// 캐스트 주위로 두 번 좁혀 고릅니다. 그리고 휘도대(1 스톱)마다 중앙값을 따로 냅니다 — 한
// 휘도대를 차지한 따뜻한 조명 면이 전체를 끌고 가지 못하게 합니다(2026-10-14 실측: 화면 15% 의
// 웜 영역 때문에 자동 WB 가 진짜 중립을 R/B 0.90 으로 식혔습니다).
struct NeutralAxisBand final {
    // 대역 화소의 ln(기하평균 휘도) 중앙값입니다.
    double log_luminance{0.0};
    // ln c − ln Ȳ 의 채널별 중앙값(합 ≈ 0). 0 이면 중립입니다.
    std::array<double, 3> cast{};
    std::size_t count{0U};
};

struct NeutralAxisEvidence final {
    std::vector<NeutralAxisBand> bands{};
    // 중립 후보로 고른 화소 비율입니다.
    double selected_fraction{0.0};
    // 중립 근처에 후보가 거의 없어 장면 중앙 캐스트 주위에서 고른 경우(고전 gray-world)입니다.
    // 장면이 정말 한 색일 수 있으므로 쓰는 쪽이 보정을 줄입니다.
    bool is_fallback{false};
};

// 대역 중앙값의 중앙값 — 대역마다 한 표입니다(면적이 큰 대역이 지배하지 않습니다).
[[nodiscard]] std::array<double, 3> neutral_axis_median_cast(const NeutralAxisEvidence& evidence);

// linear RGB 화소에서 잽니다. 근거가 모자라면(후보 32 개 미만 등) 없습니다.
[[nodiscard]] std::optional<NeutralAxisEvidence> measure_neutral_axis(
    const std::vector<std::array<double, 3>>& pixels);

}  // namespace negaflow::imaging
