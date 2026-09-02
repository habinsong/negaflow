#include "scanner_target_color.h"

#include "negaflow/color/srgb_transfer.h"

#include <algorithm>
#include <cmath>
#include <cstddef>

namespace negaflow::imaging::scanner_target_detail {

[[nodiscard]] double clamp(const double value, const double low, const double high) noexcept {
    return std::min(std::max(value, low), high);
}

[[nodiscard]] double smoothstep(
    const double low,
    const double high,
    const double value) noexcept {
    const double t = clamp((value - low) / std::max(high - low, 1.0e-9), 0.0, 1.0);
    return t * t * (3.0 - (2.0 * t));
}

[[nodiscard]] double srgb_encode(const double value) noexcept {
    return negaflow::color::linear_to_srgb_encoded(static_cast<float>(value));
}

[[nodiscard]] double srgb_decode(const double value) noexcept {
    return negaflow::color::srgb_encoded_to_linear(static_cast<float>(value));
}

[[nodiscard]] double lab_f(const double value) noexcept {
    constexpr double delta = 6.0 / 29.0;
    return value > delta * delta * delta
        ? std::cbrt(value)
        : value / (3.0 * delta * delta) + 4.0 / 29.0;
}

[[nodiscard]] double lab_f_inverse(const double value) noexcept {
    constexpr double delta = 6.0 / 29.0;
    return value > delta
        ? value * value * value
        : 3.0 * delta * delta * (value - 4.0 / 29.0);
}

[[nodiscard]] Lab srgb_to_lab(const Rgb value) noexcept {
    const double r = srgb_decode(value.red);
    const double g = srgb_decode(value.green);
    const double b = srgb_decode(value.blue);
    const double x = ((0.4124564 * r) + (0.3575761 * g) + (0.1804375 * b)) / 0.95047;
    const double y = (0.2126729 * r) + (0.7151522 * g) + (0.0721750 * b);
    const double z = ((0.0193339 * r) + (0.1191920 * g) + (0.9503041 * b)) / 1.08883;
    const double fx = lab_f(x);
    const double fy = lab_f(y);
    const double fz = lab_f(z);
    return {116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz)};
}

[[nodiscard]] double neutral_lab_lightness(const double value) noexcept {
    // `srgb_to_lab({value, value, value})` 의 밝기와 같은 식·같은 차례입니다.
    // 세 채널이 같으므로 `srgb_decode` 와 `lab_f` 를 한 번씩만 하고, a·b 를 쓰지
    // 않으므로 x·z 는 구하지 않습니다.
    const double r = srgb_decode(value);
    const double y = (0.2126729 * r) + (0.7151522 * r) + (0.0721750 * r);
    return 116.0 * lab_f(y) - 16.0;
}

[[nodiscard]] Rgb lab_to_extended_srgb(const Lab value) noexcept {
    const double fy = (value.lightness + 16.0) / 116.0;
    const double fx = fy + value.a / 500.0;
    const double fz = fy - value.b / 200.0;
    const double x = lab_f_inverse(fx) * 0.95047;
    const double y = lab_f_inverse(fy);
    const double z = lab_f_inverse(fz) * 1.08883;
    return {
        srgb_encode((3.2404542 * x) - (1.5371385 * y) - (0.4985314 * z)),
        srgb_encode((-0.9692660 * x) + (1.8760108 * y) + (0.0415560 * z)),
        srgb_encode((0.0556434 * x) - (0.2040259 * y) + (1.0572252 * z)),
    };
}

[[nodiscard]] double luma(const Rgb value) noexcept {
    return (0.2126 * value.red) + (0.7152 * value.green) + (0.0722 * value.blue);
}

[[nodiscard]] double percentile(std::vector<double>& values, const double fraction) {
    std::sort(values.begin(), values.end());
    const std::size_t index = static_cast<std::size_t>(
        clamp(static_cast<double>(values.size() - 1U) * fraction,
              0.0, static_cast<double>(values.size() - 1U)));
    return values[index];
}

}  // namespace negaflow::imaging::scanner_target_detail
