#include "negaflow/imaging/custom_color_target.h"
#include "negaflow/core/pointwise.h"

#include <algorithm>
#include <cmath>
#include <numbers>

namespace negaflow::imaging {
namespace {
constexpr std::array<double, 10> knots{0, 5, 10, 20, 35, 50, 65, 80, 90, 100};

double mix(double a, double b, double t) noexcept { return a + (b - a) * t; }
double unit(double x) noexcept { return std::clamp(x, 0.0, 1.0); }
double smooth(double x, double a, double b) noexcept {
    const double t = unit((x - a) / (b - a));
    return t * t * (3 - 2 * t);
}
double sample(const std::array<double, 8>& values, double hue) noexcept {
    const double index = hue / 45;
    const auto lower = static_cast<std::size_t>(index) % 8U;
    return mix(values[lower], values[(lower + 1U) % 8U], index - std::floor(index));
}
double tone(double l, const CustomColorTargetProfile& p) noexcept {
    if (l <= 0) { return p.tone[0] + l * p.slopes[0]; }
    if (l >= 100) { return p.tone[9] + (l - 100) * p.slopes[9]; }
    std::size_t i = 0;
    while (i < 8U && l >= knots[i + 1U]) { ++i; }
    const double dx = knots[i + 1U] - knots[i];
    const double z = (l - knots[i]) / dx, z2 = z * z, z3 = z2 * z;
    return (2 * z3 - 3 * z2 + 1) * p.tone[i]
        + (z3 - 2 * z2 + z) * dx * p.slopes[i]
        + (-2 * z3 + 3 * z2) * p.tone[i + 1U]
        + (z3 - z2) * dx * p.slopes[i + 1U];
}
double lab_transfer(double x) noexcept {
    return x > 216.0 / 24389.0 ? std::cbrt(x) : ((24389.0 / 27.0) * x + 16) / 116;
}
double inverse_lab_transfer(double x) noexcept {
    constexpr double delta = 6.0 / 29.0;
    return x > delta ? x * x * x : 3 * delta * delta * (x - 4.0 / 29.0);
}
} // namespace

CustomColorTriple custom_target_linear_to_lab(CustomColorTriple rgb) noexcept {
    const double x = 0.4124564 * rgb[0] + 0.3575761 * rgb[1] + 0.1804375 * rgb[2];
    const double y = 0.2126729 * rgb[0] + 0.7151522 * rgb[1] + 0.0721750 * rgb[2];
    const double z = 0.0193339 * rgb[0] + 0.1191920 * rgb[1] + 0.9503041 * rgb[2];
    const double fx = lab_transfer((1.0478112 * x + 0.0228866 * y - 0.0501270 * z) / 0.96422);
    const double fy = lab_transfer(0.0295424 * x + 0.9904844 * y - 0.0170491 * z);
    const double fz = lab_transfer((-0.0092345 * x + 0.0150436 * y + 0.7521316 * z) / 0.82521);
    return {116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)};
}

CustomColorTriple custom_target_lab_to_linear(CustomColorTriple lab) noexcept {
    const double fy = (lab[0] + 16) / 116;
    const double x = inverse_lab_transfer(fy + lab[1] / 500) * 0.96422;
    const double y = inverse_lab_transfer(fy);
    const double z = inverse_lab_transfer(fy - lab[2] / 200) * 0.82521;
    const double xd = 0.9555766 * x - 0.0230393 * y + 0.0631636 * z;
    const double yd = -0.0282895 * x + 1.0099416 * y + 0.0210077 * z;
    const double zd = 0.0122982 * x - 0.0204830 * y + 1.3299098 * z;
    return {3.2404542 * xd - 1.5371385 * yd - 0.4985314 * zd,
            -0.9692660 * xd + 1.8760108 * yd + 0.0415560 * zd,
            0.0556434 * xd - 0.2040259 * yd + 1.0572252 * zd};
}

CustomColorTriple evaluate_custom_color_target(CustomColorTriple lab, const CustomColorTargetProfile& p) noexcept {
    const double l = lab[0], c = std::hypot(lab[1], lab[2]);
    const double h = c == 0 ? 0 : std::fmod(std::atan2(lab[2], lab[1]) * 180 / std::numbers::pi + 360, 360);
    const double t = tone(l, p) / 100;
    const double k = sample(p.density, h) * c / (c + 24);
    const double dense = t < 0 ? t / (1 + k) : (t > 1 ? 1 + (1 + k) * (t - 1) : t / (1 + k * (1 - t)));
    const double lout = 100 * dense, weight = smooth(c, 2, 10);
    const double gain = 1 + (sample(p.gain, h) - 1) * weight;
    const double shadow = p.controls[0] + (1 - p.controls[0]) * smooth(l, 0, 28);
    const double graded = c * gain * shadow;
    const double excess = graded - 48;
    const double base = graded <= 48 ? graded : 48 + excess / (1 + excess / 48);
    const double drive = (1 - p.controls[3]) * l + p.controls[3] * lout;
    const double v = std::max((drive - p.controls[1]) / (100 - p.controls[1]), 0.0);
    const double cout = base / (1 + p.controls[2] * v * v * (1 + base / 80));
    const double loss = base == 0 ? 0 : unit((base - cout) / base);
    const double rotation = l < 50
        ? mix(sample(p.hue_shadow, h), sample(p.hue_mid, h), unit((l - 20) / 30))
        : mix(sample(p.hue_mid, h), sample(p.hue_high, h), unit((l - 50) / 30));
    const double radians = (h + (rotation + sample(p.highlight_hue, h) * loss) * weight) * std::numbers::pi / 180;
    std::array<double, 2> tint{};
    for (std::size_t i = 0; i < 2; ++i) {
        if (l < 20) { tint[i] = p.tint_shadow[i] * unit(l / 20); }
        else if (l < 50) { tint[i] = mix(p.tint_shadow[i], p.tint_mid[i], (l - 20) / 30); }
        else if (l < 80) { tint[i] = mix(p.tint_mid[i], p.tint_high[i], (l - 50) / 30); }
        else { tint[i] = p.tint_high[i] * (1 - unit((l - 80) / 20)); }
    }
    const double neutral = 1 - smooth(c, 25, 75);
    return {lout, cout * std::cos(radians) + tint[0] * neutral,
                  cout * std::sin(radians) + tint[1] * neutral};
}

core::KernelStatus apply_custom_color_target(core::ConstImageView input, core::ImageView output,
                                             std::uint32_t target) noexcept {
    if (target > last_custom_color_target) { return core::KernelStatus::invalid_parameter; }
    const auto* profile = custom_color_target_profile(target);
    return core::apply_pointwise(input, output, [profile](core::Rgba32F source) noexcept {
        if (profile == nullptr) { return source; }
        // Windows 작업 RGB는 unassociated입니다. macOS CI의 premultiplied 버퍼와 구분합니다.
        if (source.alpha == 0) { return core::Rgba32F{0, 0, 0, 0}; }
        const auto rgb = custom_target_lab_to_linear(evaluate_custom_color_target(
            custom_target_linear_to_lab({source.red, source.green, source.blue}), *profile));
        return core::Rgba32F{static_cast<float>(rgb[0]), static_cast<float>(rgb[1]),
                            static_cast<float>(rgb[2]), source.alpha};
    }, 16U);
}
} // namespace negaflow::imaging
