#include "scanner_target_rendering.h"

#include "scanner_target_color.h"

#include <algorithm>
#include <cmath>

namespace negaflow::imaging::scanner_target_detail {

namespace {

// 표와 근거는 macOS `ScannerTargetGrade+Targets.swift` 와 같습니다. 값을 바꾸면 두 곳과
// 양쪽 골든 시험을 함께 고칩니다.
constexpr RenderingTable sp3000_rendering{
    {0.0464, 0.0734, 0.1025, 0.1370, 0.2044, 0.3105, 0.4671, 0.7152, 0.8381, 0.9540, 0.9780},
    {1.0, 1.0, 1.142, 1.375},
    {0.0, 0.0, 0.0, 0.0, 0.0, 0.0},
    {0.0, 0.0, 0.0},
    {0.0, 0.0, 0.0},
};

constexpr RenderingTable noritsu_rendering{
    {0.0490, 0.0741, 0.1012, 0.1330, 0.1928, 0.2828, 0.4160, 0.6688, 0.8397, 0.9665, 0.9820},
    {0.8793, 0.8793, 1.0042, 1.2090},
    {0.0, 0.0, 0.0, 0.0, 0.0, 0.0},
    {0.0778, -0.0737, -0.1429},
    {0.0326, -0.0370, -0.0397},
};

constexpr RenderingTable f135_rendering{
    {0.0251, 0.0440, 0.0664, 0.0931, 0.1554, 0.2781, 0.4671, 0.7152, 0.8381, 0.9540, 0.9780},
    {1.0, 1.0, 1.142, 1.375},
    {0.0, 0.0, 0.0, 0.0, 0.0, 0.0},
    {0.0, 0.0, 0.0},
    {0.0, 0.0, 0.0},
};

constexpr RenderingTable hr_rendering{
    {0.0464, 0.0734, 0.1025, 0.1356, 0.1903, 0.2781, 0.4671, 0.7152, 0.8381, 0.9540, 0.9780},
    {0.92, 0.92, 1.0506, 1.265},
    {0.0, 0.0, 0.0, 0.0, 0.0, 0.0},
    {0.0, 0.0, 0.0},
    {0.0, 0.0, 0.0},
};

template <std::size_t N>
[[nodiscard]] HermiteCurve<N> make_curve(
    const std::array<double, N>& xs,
    const std::array<double, N>& ys) noexcept {
    HermiteCurve<N> curve{};
    curve.xs = xs;
    curve.ys = ys;
    std::array<double, N - 1U> h{};
    std::array<double, N - 1U> d{};
    for (std::size_t i = 0U; i + 1U < N; ++i) {
        h[i] = xs[i + 1U] - xs[i];
        d[i] = (ys[i + 1U] - ys[i]) / h[i];
    }
    for (std::size_t i = 1U; i + 1U < N; ++i) {
        if (d[i - 1U] * d[i] > 0.0) {
            const double w1 = (2.0 * h[i]) + h[i - 1U];
            const double w2 = h[i] + (2.0 * h[i - 1U]);
            curve.ms[i] = (w1 + w2) / ((w1 / d[i - 1U]) + (w2 / d[i]));
        }
    }
    curve.ms[0U] = d[0U];
    curve.ms[N - 1U] = d[N - 2U];
    return curve;
}

constexpr double luma_r = 0.2126;
constexpr double luma_g = 0.7152;
constexpr double luma_b = 0.0722;

}  // namespace

template <std::size_t N>
double HermiteCurve<N>::value(const double x) const noexcept {
    if (x < xs[0U]) return ys[0U] + (ms[0U] * (x - xs[0U]));
    if (x > xs[N - 1U]) return ys[N - 1U] + (ms[N - 1U] * (x - xs[N - 1U]));
    std::size_t i = 0U;
    while (i < N - 2U && x > xs[i + 1U]) ++i;
    const double h = xs[i + 1U] - xs[i];
    const double t = (x - xs[i]) / h;
    const double t2 = t * t;
    const double t3 = t2 * t;
    return ((2.0 * t3 - 3.0 * t2 + 1.0) * ys[i]) + ((t3 - 2.0 * t2 + t) * h * ms[i]) +
        ((-2.0 * t3 + 3.0 * t2) * ys[i + 1U]) + ((t3 - t2) * h * ms[i + 1U]);
}

template struct HermiteCurve<11U>;
template struct HermiteCurve<4U>;
template struct HermiteCurve<3U>;

const RenderingTable& rendering_for(const ScannerTargetStyle target) noexcept {
    switch (target) {
    case ScannerTargetStyle::noritsu: return noritsu_rendering;
    case ScannerTargetStyle::sp3000: return sp3000_rendering;
    case ScannerTargetStyle::f135: return f135_rendering;
    case ScannerTargetStyle::hr: return hr_rendering;
    }
    return sp3000_rendering;
}

RenderingCurves rendering_curves(const RenderingTable& table) noexcept {
    return {
        make_curve(rendering_tone_stops, table.tone),
        make_curve(rendering_chroma_stops, table.chroma_gain),
        make_curve(rendering_balance_stops, table.red_balance),
        make_curve(rendering_balance_stops, table.blue_balance),
        table.crosstalk,
    };
}

Rgb render_linear(const Rgb input, const RenderingCurves& c, const bool monochrome) noexcept {
    const double r = std::max(input.red, 1.0e-5);
    const double g = std::max(input.green, 1.0e-5);
    const double b = std::max(input.blue, 1.0e-5);
    const double luma_y = std::max((luma_r * r) + (luma_g * g) + (luma_b * b), 1.0e-5);
    const double stops = std::log2(luma_y / 0.18);
    const double log_y = std::log2(luma_y);
    const double dr = std::log2(r) - log_y;
    const double dg = std::log2(g) - log_y;
    const double db = std::log2(b) - log_y;
    const auto& k = c.crosstalk;
    double mr = dr + (k[0] * (dg - dr)) + (k[1] * (db - dr));
    const double mg = dg + (k[2] * (dr - dg)) + (k[3] * (db - dg));
    double mb = db + (k[4] * (dr - db)) + (k[5] * (dg - db));
    if (!monochrome) {
        const double balance_stops = clamp(
            stops, rendering_balance_stops.front(), rendering_balance_stops.back());
        mr += c.red.value(balance_stops);
        mb += c.blue.value(balance_stops);
    }
    const double chroma_stops = clamp(
        stops, rendering_chroma_stops.front(), rendering_chroma_stops.back());
    const double gain = clamp(c.chroma_gain.value(chroma_stops), 0.0, 2.0);
    const double out_y = srgb_decode(clamp(c.tone.value(stops), 0.0, 1.0));
    const double rr = std::exp2(gain * mr);
    const double rg = std::exp2(gain * mg);
    const double rb = std::exp2(gain * mb);
    const double norm = out_y / std::max((luma_r * rr) + (luma_g * rg) + (luma_b * rb), 1.0e-6);
    double o_r = rr * norm;
    double o_g = rg * norm;
    double o_b = rb * norm;
    const double peak = std::max({o_r, o_g, o_b});
    if (peak > 1.0) {
        const double t = clamp((1.0 - out_y) / std::max(peak - out_y, 1.0e-9), 0.0, 1.0);
        o_r = out_y + ((o_r - out_y) * t);
        o_g = out_y + ((o_g - out_y) * t);
        o_b = out_y + ((o_b - out_y) * t);
    }
    return {std::max(o_r, 0.0), std::max(o_g, 0.0), std::max(o_b, 0.0)};
}

ScannerRenderingSetup rendering_setup(
    const RenderingCurves& c,
    const bool monochrome,
    const double strength) noexcept {
    ScannerRenderingSetup setup{};
    for (std::size_t i = 0U; i < ScannerRenderingSetup::tone_knots; ++i) {
        setup.tone_ys[i] = static_cast<float>(c.tone.ys[i]);
        setup.tone_ms[i] = static_cast<float>(c.tone.ms[i]);
    }
    for (std::size_t i = 0U; i < ScannerRenderingSetup::gain_knots; ++i) {
        setup.gain_ys[i] = static_cast<float>(c.chroma_gain.ys[i]);
        setup.gain_ms[i] = static_cast<float>(c.chroma_gain.ms[i]);
    }
    for (std::size_t i = 0U; i < 6U; ++i) {
        setup.crosstalk[i] = static_cast<float>(c.crosstalk[i]);
    }
    for (std::size_t i = 0U; i < ScannerRenderingSetup::balance_knots; ++i) {
        setup.red_ys[i] = static_cast<float>(c.red.ys[i]);
        setup.red_ms[i] = static_cast<float>(c.red.ms[i]);
        setup.blue_ys[i] = static_cast<float>(c.blue.ys[i]);
        setup.blue_ms[i] = static_cast<float>(c.blue.ms[i]);
    }
    setup.strength = static_cast<float>(strength);
    setup.monochrome = monochrome;
    return setup;
}

}  // namespace negaflow::imaging::scanner_target_detail
