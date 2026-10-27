#pragma once

#include <algorithm>
#include <cmath>
#include <initializer_list>

namespace negaflow::imaging {

// 채도·색 깊이 배율의 끝 보호입니다 — macOS `BoundedChromaScale` / Metal `chromaScaleBounded` 와
// 같은 식입니다. 상수와 조건을 바꾸려면 두 앱을 함께 고치십시오.
//
// 휘도를 앵커로 chroma 를 factor 배 할 때, 키우는 쪽(factor > 1)은 어느 채널이 0 또는 1 에 닿는
// 배율(limit)을 넘지 못하게 접습니다. 선형 배율만 쓰면 채도가 높은 화소의 한 채널이 범위 밖으로
// 나가고, 뒤 단계에서 채널별로 잘리면서 그 채널의 비율이 깨져 색조가 돌아갑니다.
//   factor <= knee : 그대로 factor            (knee = 1 + 비율 · (limit − 1))
//   factor  > knee : knee + room · (1 − exp(−(factor − knee) / room)),  room = limit − knee
// 접히는 구간은 knee 에서 기울기 1 로 이어지고 limit 에 점근하므로 슬라이더는 단조이고 경계에
// 정확히 닿지는 않습니다. 이미 경계 밖인 화소(limit 1)는 더 키우지 않습니다. 줄이는 쪽은 경계
// 안에서 안전하므로 손대지 않습니다.

/// 경계까지 남은 배율 여유(limit − 1) 중 선형으로 두는 비율. HLSL `BoundedChromaKneeFraction`
/// (`gpu/shaders/tone_shared.hlsli`) 이 같은 값을 씁니다.
/// 이 값은 측정으로 최적화한 것이 아니라 설계 선택입니다. 크면 이전 결과를 더 넓게 유지하고
/// 작으면 접힘이 일찍 시작합니다. 합성 색 계산 예: 피부색 (0.55, 0.28, 0.20) 의 limit 는 약
/// 2.5, 연한 하늘 (0.35, 0.50, 0.75) 는 약 1.9 라서 채도 +1(×1.6)에서도 접히지 않고, 노을
/// 주황 (0.80, 0.25, 0.05) 는 약 1.17 이라 채도 +0.2 부터 접힙니다. 실사진으로는 확인하지
/// 않았습니다.
inline constexpr float bounded_chroma_knee_fraction = 0.75F;

/// 휘도 `luma` 를 고정한 채 chroma 를 몇 배까지 키울 수 있는지입니다. 가장 먼저 0 또는 1 에 닿는
/// 채널이 정합니다. [0,1] 안의 화소는 1 이상을, 이미 밖에 나간 화소는 1 미만을 돌려줍니다.
/// chroma 가 0 에 가까워 어느 배율로도 경계에 닿지 않으면 아주 큰 값입니다. 휘도 자체가 (0,1)
/// 밖이면 경계까지의 거리를 정의할 수 없으므로 0 입니다(호출 쪽은 "더 키우지 않음"으로 읽습니다).
/// `tone_safe_unit_rgb`(display_gamut_map.h)는 같은 계산에 상한 1 을 씌운 것이라 따로 둡니다.
[[nodiscard]] inline float chroma_scale_headroom(
    const float luma,
    const float chroma_red,
    const float chroma_green,
    const float chroma_blue) noexcept {
    if (luma <= 0.0F || luma >= 1.0F) {
        return 0.0F;
    }
    float limit = 1.0e9F;
    for (const float chroma : {chroma_red, chroma_green, chroma_blue}) {
        if (chroma > 1.0e-5F) {
            limit = std::min(limit, (1.0F - luma) / chroma);
        } else if (chroma < -1.0e-5F) {
            limit = std::min(limit, -luma / chroma);
        }
    }
    return limit;
}

/// 실제로 곱할 chroma 배율입니다. `factor` 는 슬라이더가 정한 배율, 나머지는 화소의 휘도와
/// 휘도 기준 chroma 입니다.
[[nodiscard]] inline float bounded_chroma_scale(
    const float factor,
    const float luma,
    const float chroma_red,
    const float chroma_green,
    const float chroma_blue) noexcept {
    if (!(factor > 1.0F)) {
        return factor;
    }
    const float limit = std::max(
        chroma_scale_headroom(luma, chroma_red, chroma_green, chroma_blue), 1.0F);
    const float knee = 1.0F + (bounded_chroma_knee_fraction * (limit - 1.0F));
    if (!(factor > knee)) {
        return factor;
    }
    const float room = limit - knee;
    return room > 1.0e-6F
        ? knee + (room * (1.0F - std::exp(-(factor - knee) / room)))
        : knee;
}

} // namespace negaflow::imaging
