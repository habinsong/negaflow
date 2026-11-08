#include "negaflow/imaging/tone_mapping.h"

#include "negaflow/color/srgb_transfer.h"
#include "negaflow/core/pointwise.h"
#include "negaflow/imaging/bounded_chroma_scale.h"
#include "negaflow/imaging/display_gamut_map.h"

#include <algorithm>
#include <array>
#include <cmath>

namespace negaflow::imaging {
namespace {

// 휘도 목표를 화소에 싣습니다(macOS `withLuma`). 어둡게 할 때는 채널 비율을 보존합니다 — 같은
// 값을 빼면 가장 작은 채널이 먼저 0 에 닿아 암부의 약한 색이 원색으로 폭주합니다(R/B 1.2 가
// 대비 +1 에서 131). 밝힐 때는 기존처럼 같은 값을 더합니다. 더한 결과의 한 채널이 1 을 넘으면
// 그 채널만 잘라 내지 않습니다 — 채널별로 자르면 목표 휘도에 못 미치고 남은 두 채널의 비율이
// 깨져 색조가 돕니다. 대신 목표 휘도를 지킨 채 chroma 만 1 에 맞게 줄입니다. 더해도 [0,1] 안에
// 머무는 화소는 이전과 같습니다. 입력 `safe` 는 [0,1] 안이어야 합니다(호출 쪽이
// `tone_safe_unit_rgb` 로 맞춥니다).
[[nodiscard]] negaflow::core::Rgba32F with_luma(
    const negaflow::core::Rgba32F safe,
    const float source_luma,
    const float new_luma,
    const float alpha) noexcept {
    if (new_luma < source_luma && source_luma > 1.0e-6F) {
        const float scale = new_luma / source_luma;
        return {
            std::clamp(safe.red * scale, 0.0F, 1.0F),
            std::clamp(safe.green * scale, 0.0F, 1.0F),
            std::clamp(safe.blue * scale, 0.0F, 1.0F),
            alpha,
        };
    }
    const float delta = new_luma - source_luma;
    const float lifted_red = safe.red + delta;
    const float lifted_green = safe.green + delta;
    const float lifted_blue = safe.blue + delta;
    if (lifted_red <= 1.0F && lifted_green <= 1.0F && lifted_blue <= 1.0F) {
        return {
            std::clamp(lifted_red, 0.0F, 1.0F),
            std::clamp(lifted_green, 0.0F, 1.0F),
            std::clamp(lifted_blue, 0.0F, 1.0F),
            alpha,
        };
    }
    // 같은 값을 더해도 휘도 기준 chroma 는 변하지 않습니다.
    const float chroma_red = safe.red - source_luma;
    const float chroma_green = safe.green - source_luma;
    const float chroma_blue = safe.blue - source_luma;
    const float fold = std::min(
        1.0F,
        negaflow::imaging::chroma_scale_headroom(
            new_luma, chroma_red, chroma_green, chroma_blue));
    return {
        std::clamp(new_luma + (chroma_red * fold), 0.0F, 1.0F),
        std::clamp(new_luma + (chroma_green * fold), 0.0F, 1.0F),
        std::clamp(new_luma + (chroma_blue * fold), 0.0F, 1.0F),
        alpha,
    };
}

constexpr std::array<float, 3> luma_coefficients{0.2126F, 0.7152F, 0.0722F};

[[nodiscard]] float clamp_unit(const float value) noexcept {
    return std::clamp(value, 0.0F, 1.0F);
}

[[nodiscard]] float smoothstep(
    const float edge_low,
    const float edge_high,
    const float value) noexcept {
    if (edge_low == edge_high) {
        return value < edge_low ? 0.0F : 1.0F;
    }
    const float position = clamp_unit((value - edge_low) / (edge_high - edge_low));
    return position * position * (3.0F - (2.0F * position));
}

[[nodiscard]] float luma(const negaflow::core::Rgba32F pixel) noexcept {
    return (pixel.red * luma_coefficients[0]) +
           (pixel.green * luma_coefficients[1]) +
           (pixel.blue * luma_coefficients[2]);
}


using negaflow::core::apply_pointwise;

[[nodiscard]] bool finite_basic_parameters(
    const BasicToneParameters& parameters) noexcept {
    return std::isfinite(parameters.contrast) && std::isfinite(parameters.density) &&
           std::isfinite(parameters.highlights) && std::isfinite(parameters.shadows) &&
           std::isfinite(parameters.whites) && std::isfinite(parameters.blacks);
}

[[nodiscard]] bool finite_curve_parameters(
    const ParametricToneCurveParameters& parameters) noexcept {
    return std::isfinite(parameters.highlights) && std::isfinite(parameters.lights) &&
           std::isfinite(parameters.darks) && std::isfinite(parameters.shadows);
}

// 매듭은 유한하고 (0,1) 안에서 증가해야 합니다. 그래야 구간 폭이 양수입니다.
[[nodiscard]] bool finite_bands(const ParametricToneCurveBands& bands) noexcept {
    double previous = 0.0;
    for (const double knot : bands.knots) {
        if (!std::isfinite(knot) || knot <= previous || knot >= 1.0) {
            return false;
        }
        previous = knot;
    }
    return true;
}

// 매듭이 양 끝과 떨어져야 하는 최소 거리 = 매듭끼리의 최소 간격(인코딩)입니다. 그래서 어떤 장면에서도
// ±1 이 매듭을 적어도 reach × 0.10 = 0.045 움직입니다(macOS `ParametricToneCurve`).
constexpr double curve_minimum_gap = 0.10;
constexpr double curve_reach = 0.45;

[[nodiscard]] double encode_srgb(const double linear) noexcept {
    return linear <= 0.0031308 ? linear * 12.92 : (1.055 * std::pow(linear, 1.0 / 2.4)) - 0.055;
}

// 블렌드 커널(`basic_tone.hlsl`)과 같은 연산 순서의 검정 한 단계(|amount| ≤ 1)입니다. 올리는 쪽은
// smoothstep 0~0.03 상승, 내리는 쪽은 t − c·min(1, t/0.03)·fall 이고 0 아래는 0 에 붙습니다.
[[nodiscard]] float basic_tone_blacks(const float t, const float amount) noexcept {
    const float fall = 1.0F - smoothstep(0.14F, 0.30F, t);
    if (amount >= 0.0F) {
        return t + (amount * 0.06F * smoothstep(0.0F, 0.03F, t) * fall);
    }
    return std::max(t + (amount * 0.06F * std::min(1.0F, std::max(t, 0.0F) / 0.03F) * fall), 0.0F);
}

}  // namespace

bool has_basic_tone_change(const BasicToneParameters& parameters) noexcept {
    return std::abs(parameters.contrast) > tone_change_threshold ||
           std::abs(parameters.density) > tone_change_threshold ||
           std::abs(parameters.highlights) > tone_change_threshold ||
           std::abs(parameters.shadows) > tone_change_threshold ||
           std::abs(parameters.whites) > tone_change_threshold ||
           std::abs(parameters.blacks) > tone_change_threshold;
}

bool has_parametric_tone_curve_change(
    const ParametricToneCurveParameters& parameters) noexcept {
    return std::abs(parameters.highlights) > tone_change_threshold ||
           std::abs(parameters.lights) > tone_change_threshold ||
           std::abs(parameters.darks) > tone_change_threshold ||
           std::abs(parameters.shadows) > tone_change_threshold;
}

negaflow::core::KernelStatus apply_basic_tone(
    const negaflow::core::ConstImageView input,
    const negaflow::core::ImageView output,
    const BasicToneParameters& parameters) noexcept {
    if (!finite_basic_parameters(parameters)) {
        return negaflow::core::KernelStatus::non_finite_parameter;
    }

    return apply_pointwise(input, output, [&parameters](
        const negaflow::core::Rgba32F source) noexcept {
        const negaflow::core::Rgba32F safe =
            negaflow::imaging::tone_safe_unit_rgb(source);
        const float source_luma = luma(safe);
        const float encoded_luma = negaflow::color::linear_to_srgb_encoded(
            clamp_unit(source_luma));
        float target = encoded_luma;

        const float contrast = std::clamp(parameters.contrast, -1.0F, 1.0F);
        if (std::abs(contrast) > 1.0e-4F) {
            constexpr float pivot = 0.46F;
            const float exponent = std::pow(
                2.0F,
                contrast * (contrast > 0.0F ? 0.9F : 0.7F));
            const float curved = target < pivot
                                     ? pivot * std::pow(target / pivot, exponent)
                                     : 1.0F - ((1.0F - pivot) * std::pow(
                                           (1.0F - target) / (1.0F - pivot),
                                           exponent));
            const float blend = contrast > 0.0F
                                    ? 1.0F
                                    : smoothstep(0.12F, 0.30F, target);
            target += (curved - target) * blend;
        }

        // 단계마다 앞 단계의 출력에 차례로 겁니다(macOS `basicTone`, `basic_tone_model.h`). 각 단계가
        // 그 자체로 단조라 합성도 단조이고, 어떤 슬라이더 조합에서도 톤이 뒤집히지 않습니다. 예전에는
        // 마스크를 모두 원래 휘도에서 재서 더했는데, 마스크 경계 기울기 × 계수가 1 을 넘는 곳에서
        // 뒤집혔습니다(암부 −1·흰색 −2·조합, 2026-11-08 실측).
        const float density = std::clamp(parameters.density, -1.0F, 1.0F);
        target -= density * 0.10F * smoothstep(0.18F, 0.36F, target) *
                  (1.0F - smoothstep(0.58F, 0.76F, target));

        const float highlights = std::clamp(parameters.highlights, -1.0F, 1.0F);
        target += highlights * 0.10F * smoothstep(0.55F, 0.80F, target);

        // 암부: 올리는 쪽은 0.02~0.08 에서 오르고(절대 검정 앵커), 내리는 쪽은 검정에서부터 0~0.20 에
        // 걸쳐 오릅니다. 위쪽 경계는 0.30~0.46 입니다(+1 에서 기울기 0.94).
        const float shadows = std::clamp(parameters.shadows, -1.0F, 1.0F);
        const float shadow_rise = shadows > 0.0F ? smoothstep(0.02F, 0.08F, target)
                                                 : smoothstep(0.0F, 0.20F, target);
        target += shadows * 0.10F * shadow_rise * (1.0F - smoothstep(0.30F, 0.46F, target));

        // 백점·흑점은 `DevelopToneRange` 의 ±2 입니다. ±1 을 넘는 몫은 같은 단계를 한 번 더 겁니다
        // (단계 하나의 기울기가 1 을 넘지 않습니다).
        const float whites = std::clamp(parameters.whites, -2.0F, 2.0F);
        const float whites_first = std::clamp(whites, -1.0F, 1.0F);
        target += whites_first * 0.12F * smoothstep(0.68F, 0.92F, target);
        target += (whites - whites_first) * 0.12F * smoothstep(0.68F, 0.92F, target);

        const float blacks = std::clamp(parameters.blacks, -2.0F, 2.0F);
        const float blacks_first = std::clamp(blacks, -1.0F, 1.0F);
        target = basic_tone_blacks(target, blacks_first);
        target = basic_tone_blacks(target, blacks - blacks_first);

        const float new_luma = negaflow::color::srgb_encoded_to_linear(
            clamp_unit(target));
        return with_luma(safe, source_luma, new_luma, source.alpha);
    });
}

ParametricToneCurveBands parametric_tone_curve_bands_from_percentiles(
    const double p10,
    const double p35,
    const double p65,
    const double p90) noexcept {
    const double percentiles[4]{p10, p35, p65, p90};
    for (const double value : percentiles) {
        if (!std::isfinite(value)) {
            return fallback_parametric_tone_curve_bands();
        }
    }
    constexpr double low = curve_minimum_gap;
    constexpr double high = 1.0 - curve_minimum_gap;
    ParametricToneCurveBands bands{};
    bands.knots[0] = std::clamp(encode_srgb(std::clamp(p10, 0.0, 1.0)), low, high - (3.0 * curve_minimum_gap));
    for (std::size_t i = 1U; i < 4U; ++i) {
        bands.knots[i] = std::max(encode_srgb(std::clamp(percentiles[i], 0.0, 1.0)),
                                  bands.knots[i - 1U] + curve_minimum_gap);
    }
    if (bands.knots[3] > high) {
        bands.knots[3] = high;
        for (std::size_t i = 3U; i-- > 0U;) {
            bands.knots[i] = std::min(bands.knots[i], bands.knots[i + 1U] - curve_minimum_gap);
        }
    }
    return bands;
}

ParametricToneCurveShape parametric_tone_curve_shape(
    const ParametricToneCurveParameters& parameters,
    const ParametricToneCurveBands& bands) noexcept {
    ParametricToneCurveShape shape{};
    shape.x[0] = 0.0;
    shape.x[5] = 1.0;
    for (std::size_t i = 0U; i < 4U; ++i) { shape.x[i + 1U] = bands.knots[i]; }
    for (std::size_t i = 0U; i < 6U; ++i) { shape.y[i] = shape.x[i]; }
    const float amounts[4]{parameters.shadows, parameters.darks, parameters.lights, parameters.highlights};
    for (std::size_t i = 0U; i < 4U; ++i) {
        const std::size_t k = i + 1U;
        const double raw = static_cast<double>(amounts[i]);
        const double a = std::clamp(std::isfinite(raw) ? raw : 0.0, -1.0, 1.0);
        shape.y[k] = shape.x[k] + (a > 0.0 ? a * curve_reach * (shape.x[k + 1U] - shape.x[k])
                                           : a * curve_reach * (shape.x[k] - shape.x[k - 1U]));
    }
    // Fritsch–Carlson 기울기입니다.
    double d[5]{};
    for (std::size_t i = 0U; i < 5U; ++i) {
        d[i] = (shape.y[i + 1U] - shape.y[i]) / (shape.x[i + 1U] - shape.x[i]);
    }
    shape.tangent[0] = d[0];
    shape.tangent[5] = d[4];
    for (std::size_t i = 1U; i < 5U; ++i) {
        shape.tangent[i] = d[i - 1U] * d[i] <= 0.0 ? 0.0 : (d[i - 1U] + d[i]) / 2.0;
    }
    for (std::size_t i = 0U; i < 5U; ++i) {
        if (!(d[i] > 0.0)) {
            shape.tangent[i] = 0.0;
            shape.tangent[i + 1U] = 0.0;
            continue;
        }
        const double a = shape.tangent[i] / d[i];
        const double b = shape.tangent[i + 1U] / d[i];
        const double sum = (a * a) + (b * b);
        if (sum > 9.0) {
            const double t = 3.0 / std::sqrt(sum);
            shape.tangent[i] = t * a * d[i];
            shape.tangent[i + 1U] = t * b * d[i];
        }
    }
    return shape;
}

double evaluate_parametric_tone_curve(const ParametricToneCurveShape& shape, const double encoded) noexcept {
    std::size_t i = 0U;
    while (i < 4U && encoded >= shape.x[i + 1U]) { ++i; }
    const double h = shape.x[i + 1U] - shape.x[i];
    const double t = std::clamp((encoded - shape.x[i]) / h, 0.0, 1.0);
    const double t2 = t * t;
    const double t3 = t2 * t;
    return (((2.0 * t3) - (3.0 * t2) + 1.0) * shape.y[i]) + ((t3 - (2.0 * t2) + t) * h * shape.tangent[i]) +
           (((-2.0 * t3) + (3.0 * t2)) * shape.y[i + 1U]) + ((t3 - t2) * h * shape.tangent[i + 1U]);
}

negaflow::core::KernelStatus apply_parametric_tone_curve(
    const negaflow::core::ConstImageView input,
    const negaflow::core::ImageView output,
    const ParametricToneCurveParameters& parameters,
    const ParametricToneCurveBands& bands) noexcept {
    if (!finite_curve_parameters(parameters) || !finite_bands(bands)) {
        return negaflow::core::KernelStatus::non_finite_parameter;
    }
    // 매듭은 한 번만 풉니다. 화소마다는 GPU(`parametric_tone_curve.hlsl`)와 같은 float 식입니다.
    const ParametricToneCurveShape shape = parametric_tone_curve_shape(parameters, bands);
    float x[6]{};
    float y[6]{};
    float m[6]{};
    for (std::size_t i = 0U; i < 6U; ++i) {
        x[i] = static_cast<float>(shape.x[i]);
        y[i] = static_cast<float>(shape.y[i]);
        m[i] = static_cast<float>(shape.tangent[i]);
    }

    return apply_pointwise(input, output, [&x, &y, &m](
        const negaflow::core::Rgba32F source) noexcept {
        const negaflow::core::Rgba32F safe =
            negaflow::imaging::tone_safe_unit_rgb(source);
        const float source_luma = luma(safe);
        const float g = negaflow::color::linear_to_srgb_encoded(clamp_unit(source_luma));
        std::size_t i = 0U;
        while (i < 4U && g >= x[i + 1U]) { ++i; }
        const float h = x[i + 1U] - x[i];
        const float t = clamp_unit((g - x[i]) / h);
        const float t2 = t * t;
        const float t3 = t2 * t;
        const float curved = (((2.0F * t3) - (3.0F * t2) + 1.0F) * y[i]) +
                             ((t3 - (2.0F * t2) + t) * h * m[i]) +
                             (((-2.0F * t3) + (3.0F * t2)) * y[i + 1U]) +
                             ((t3 - t2) * h * m[i + 1U]);
        const float target = negaflow::color::srgb_encoded_to_linear(clamp_unit(curved));
        return with_luma(safe, source_luma, target, source.alpha);
    });
}

}  // namespace negaflow::imaging
