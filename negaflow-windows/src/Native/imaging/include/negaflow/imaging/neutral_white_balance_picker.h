#pragma once

#include "negaflow/core/pixel.h"

#include <array>
#include <optional>

namespace negaflow::imaging {

// 중립 스포이드 — 사용자가 찍은 점이 무채색이 되는 온도·틴트를 풉니다. macOS
// `NeutralWhiteBalancePicker` 와 같은 규칙입니다.
//
// 값은 화이트밸런스 단계의 **입력**(반전·장면 보정·스캐너 타깃·레스큐·프로필 그레이드 뒤, ColorModel
// 직전)에서 잽니다. 게인은 그 값에 그대로 곱해지므로 역산이 정확하고, 그 뒤의 톤·커브(휘도 기반)는
// 중립을 중립으로 둡니다. 화면 결과에서 재면 커브의 가산 밝힘이 채널비를 줄여 한 번에 맞지 않습니다.

// 평균 창 반경(긴 변 대비). 그레인 한 알이 아니라 찍은 면의 색을 잽니다 — 3600px 프록시에서 ±14px.
inline constexpr double neutral_pick_radius_fraction = 0.004;

// 찍은 점(변형 전 원본 정규 좌표, y-down) 주위의 linear 평균입니다. 너무 어둡거나(채널비가 잡음)
// 클리핑에 가까우면 없습니다 — 자동 화이트밸런스의 중립 후보 조건(채널 > 0.004, 휘도 < 0.90)과
// 같습니다.
[[nodiscard]] std::optional<std::array<double, 3>> sample_neutral_white_balance_reference(
    negaflow::core::ConstImageView image,
    double unit_x,
    double unit_y) noexcept;

struct NeutralWhiteBalanceSolution final {
    double warmth{0.0};
    double tint{0.0};
};

// 화이트밸런스 입력값을 중립으로 만드는 온도·틴트입니다. 온도가 R/B 를, 틴트가 G/√(R·B) 를
// 맡습니다(틴트는 R/B 를 바꾸지 않습니다). 범위(±4)를 넘으면 끝값에서 멈춥니다.
[[nodiscard]] std::optional<NeutralWhiteBalanceSolution> solve_neutral_white_balance(
    const std::array<double, 3>& reference) noexcept;

}  // namespace negaflow::imaging
