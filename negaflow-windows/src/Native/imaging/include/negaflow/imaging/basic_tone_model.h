#pragma once

// `apply_basic_tone`(CPU)·`basic_tone.hlsl`(GPU) 의 단계별 스칼라 판입니다(인코딩 휘도, double).
// macOS `BasicToneModel` 과 같은 순서·식입니다: 대비 → 농도 → 명부 → 암부 → 흰색 → 검정, 단계마다
// 앞 단계의 출력에 겁니다. 각 단계가 그 자체로 단조라 합성도 단조입니다. 자동 톤
// (`auto_adjust.cpp`)이 이 순서대로 앞 단계를 적용한 값에서 다음 단계의 양을 역산합니다.

#include <algorithm>
#include <cmath>

namespace negaflow::imaging::basic_tone_model {

[[nodiscard]] inline double smooth(const double low, const double high, const double x) noexcept {
    const double t = std::clamp((x - low) / (high - low), 0.0, 1.0);
    return t * t * (3.0 - (2.0 * t));
}

[[nodiscard]] inline double unit(const double value) noexcept { return std::clamp(value, -1.0, 1.0); }

[[nodiscard]] inline double contrast(const double t, const double amount) noexcept {
    const double c = unit(amount);
    if (std::abs(c) <= 1.0e-4) { return t; }
    constexpr double pivot = 0.46;
    const double e = std::pow(2.0, c * (c > 0.0 ? 0.9 : 0.7));
    const double curved = t < pivot ? pivot * std::pow(t / pivot, e)
                                    : 1.0 - ((1.0 - pivot) * std::pow((1.0 - t) / (1.0 - pivot), e));
    const double blend = c > 0.0 ? 1.0 : smooth(0.12, 0.30, t);
    return t + ((curved - t) * blend);
}

[[nodiscard]] inline double density_mask(const double t) noexcept {
    return smooth(0.18, 0.36, t) * (1.0 - smooth(0.58, 0.76, t));
}
[[nodiscard]] inline double density(const double t, const double amount) noexcept {
    return t - (unit(amount) * 0.10 * density_mask(t));
}

[[nodiscard]] inline double highlight_mask(const double t) noexcept { return smooth(0.55, 0.80, t); }
[[nodiscard]] inline double highlight(const double t, const double amount) noexcept {
    return t + (unit(amount) * 0.10 * highlight_mask(t));
}

// 암부를 올리는 쪽의 마스크입니다(자동 톤은 올리기만 합니다).
[[nodiscard]] inline double shadow_lift_mask(const double t) noexcept {
    return smooth(0.02, 0.08, t) * (1.0 - smooth(0.30, 0.46, t));
}
[[nodiscard]] inline double shadow(const double t, const double amount) noexcept {
    const double a = unit(amount);
    const double rise = a > 0.0 ? smooth(0.02, 0.08, t) : smooth(0.0, 0.20, t);
    return t + (a * 0.10 * rise * (1.0 - smooth(0.30, 0.46, t)));
}

[[nodiscard]] inline double whites_mask(const double t) noexcept { return smooth(0.68, 0.92, t); }
[[nodiscard]] inline double whites(const double t, const double amount) noexcept {
    const double w = std::clamp(amount, -2.0, 2.0);
    const double first = unit(w);
    const double once = t + (first * 0.12 * whites_mask(t));
    return once + ((w - first) * 0.12 * whites_mask(once));
}

// 검정 한 단계의 마스크입니다. 올리는 쪽은 smoothstep 상승, 내리는 쪽은 0~0.03 선형 상승입니다.
[[nodiscard]] inline double blacks_mask(const double t, const bool lifting) noexcept {
    const double rise = lifting ? smooth(0.0, 0.03, t) : std::min(1.0, std::max(t, 0.0) / 0.03);
    return rise * (1.0 - smooth(0.14, 0.30, t));
}
[[nodiscard]] inline double blacks_step(const double t, const double amount) noexcept {
    return amount >= 0.0 ? t + (amount * 0.06 * blacks_mask(t, true))
                         : std::max(t + (amount * 0.06 * blacks_mask(t, false)), 0.0);
}
[[nodiscard]] inline double blacks(const double t, const double amount) noexcept {
    const double b = std::clamp(amount, -2.0, 2.0);
    const double first = unit(b);
    return blacks_step(blacks_step(t, first), b - first);
}

}  // namespace negaflow::imaging::basic_tone_model
