#pragma once

#include <algorithm>
#include <cmath>

namespace negaflow::imaging {

// 화이트밸런스(온도·틴트) 게인입니다 — macOS `WhiteBalanceGains` 와 같은 식입니다.
//
// * |v| <= 1 : 예전 선형 게인을 그대로 씁니다. 온도 R 1+0.18v · G 1+0.03v · B 1−0.18v,
//   틴트 R·B 1−0.12v · G 1+0.24v. 저장된 편집의 채널비가 바뀌지 않습니다.
// * |v| > 1  : 끝점 기울기로 로그 공간에서 이어 붙입니다(C1). 범위 ±4 = 온도 ±2.14 스톱
//   (예전 끝 ±0.525 스톱 — 2026-10-14 실측 "끝까지 당겨도 영향이 없다"의 원인).
// * 두 조정을 로그로 더한 뒤 Rec.709 휘도를 1 로 정규화합니다. 예전에는 틴트 ±1 이 밝기를
//   ±13.7% 바꿨습니다 — 색만 바꾸고 밝기는 그대로 둡니다.
inline constexpr float maximum_white_balance_control = 4.0F;
inline constexpr float white_balance_identity_threshold = 1.0e-3F;

struct WhiteBalanceGains final {
    float red{1.0F};
    float green{1.0F};
    float blue{1.0F};
    bool active{false};
};

namespace white_balance_detail {

struct ChannelLog final {
    double red;
    double green;
    double blue;
};

inline constexpr double warmth_red = 0.18;
inline constexpr double warmth_green = 0.03;
inline constexpr double warmth_blue = -0.18;
inline constexpr double tint_red_blue = -0.12;
inline constexpr double tint_green = 0.24;

// 채널마다 log2(1 + k·v) — |v| > 1 은 끝점 기울기 k / ((1 + k·s)·ln2) 로 선형 연장합니다.
[[nodiscard]] inline ChannelLog channel_log(
    const double value,
    const double red,
    const double green,
    const double blue) noexcept {
    const double edge = std::clamp(value, -1.0, 1.0);
    const double beyond = value - edge;
    const auto channel = [edge, beyond](const double k) noexcept {
        const double at_edge = 1.0 + (k * edge);
        return std::log2(at_edge) + ((k / (at_edge * std::log(2.0))) * beyond);
    };
    return {channel(red), channel(green), channel(blue)};
}

[[nodiscard]] inline ChannelLog warmth_log(const double warmth) noexcept {
    return channel_log(warmth, warmth_red, warmth_green, warmth_blue);
}

[[nodiscard]] inline ChannelLog tint_log(const double tint) noexcept {
    return channel_log(tint, tint_red_blue, tint_green, tint_red_blue);
}

}  // namespace white_balance_detail

[[nodiscard]] inline WhiteBalanceGains white_balance_gains(
    const float warmth,
    const float tint) noexcept {
    const bool use_warmth = std::abs(warmth) > white_balance_identity_threshold;
    const bool use_tint = std::abs(tint) > white_balance_identity_threshold;
    if (!use_warmth && !use_tint) {
        return {};
    }
    white_balance_detail::ChannelLog sum{0.0, 0.0, 0.0};
    if (use_warmth) {
        const auto log = white_balance_detail::warmth_log(warmth);
        sum = {sum.red + log.red, sum.green + log.green, sum.blue + log.blue};
    }
    if (use_tint) {
        const auto log = white_balance_detail::tint_log(tint);
        sum = {sum.red + log.red, sum.green + log.green, sum.blue + log.blue};
    }
    const double red = std::exp2(sum.red);
    const double green = std::exp2(sum.green);
    const double blue = std::exp2(sum.blue);
    const double luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue);
    return {
        static_cast<float>(red / luminance),
        static_cast<float>(green / luminance),
        static_cast<float>(blue / luminance),
        true,
    };
}

// 자동 화이트밸런스의 역산용 — 온도가 만드는 log2(R/B), 녹색 log2(G/√(R·B)) 성분입니다.
[[nodiscard]] inline double warmth_red_blue_stops(const double warmth) noexcept {
    const auto log = white_balance_detail::warmth_log(warmth);
    return log.red - log.blue;
}

[[nodiscard]] inline double warmth_green_stops(const double warmth) noexcept {
    const auto log = white_balance_detail::warmth_log(warmth);
    return log.green - (0.5 * (log.red + log.blue));
}

[[nodiscard]] inline double tint_green_stops(const double tint) noexcept {
    const auto log = white_balance_detail::tint_log(tint);
    return log.green - (0.5 * (log.red + log.blue));
}

// 단조 증가 함수의 역 — [−4, 4] 에서 이분법(정밀도 4·2^-50).
template <typename Function>
[[nodiscard]] double solve_white_balance(const double target_stops, Function function) noexcept {
    double low = -static_cast<double>(maximum_white_balance_control);
    double high = static_cast<double>(maximum_white_balance_control);
    if (target_stops <= function(low)) {
        return low;
    }
    if (target_stops >= function(high)) {
        return high;
    }
    for (int iteration = 0; iteration < 50; ++iteration) {
        const double middle = 0.5 * (low + high);
        if (function(middle) < target_stops) {
            low = middle;
        } else {
            high = middle;
        }
    }
    return 0.5 * (low + high);
}

}  // namespace negaflow::imaging
