#include "negaflow/imaging/auto_adjust.h"
#include "negaflow/imaging/white_balance.h"
#include "negaflow/imaging/basic_tone_model.h"
#include "negaflow/imaging/channel_headroom.h"

#include "negaflow/core/pointwise.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

[[nodiscard]] double clamp_range(
    const double value,
    const double lower,
    const double upper) noexcept {
    return std::min(upper, std::max(lower, value));
}

[[nodiscard]] double smoothstep(
    const double lower,
    const double upper,
    const double value) noexcept {
    const double t = clamp_range((value - lower) / std::max(upper - lower, 1.0e-9), 0.0, 1.0);
    return t * t * (3.0 - (2.0 * t));
}

[[nodiscard]] double srgb_decode(const double value) noexcept {
    return value <= 0.04045 ? value / 12.92
                            : std::pow((value + 0.055) / 1.055, 2.4);
}

[[nodiscard]] double srgb_encode(const double value) noexcept {
    return value <= 0.0031308 ? value * 12.92
                              : (1.055 * std::pow(value, 1.0 / 2.4)) - 0.055;
}

// Only 85% of the measured cast is removed. Neutralising fully overshoots into the
// opposite cast whenever the scene is legitimately dominated by one colour, and reads
// cold even when it does not.
constexpr double white_balance_strength = 0.85;
// 슬라이더 전 범위(±4)가 아니라 잔차 캐스트 상한(±1 = 예전 슬라이더 끝, R/B ±0.525 스톱)까지만
// 움직입니다. 고정 반전은 WB를 자동으로 맞추지 않습니다. 근거가 부족한 자동 추정은 제한하고
// 큰 캐스트는 수동 WB로 맞춥니다.
// 휘도대별 중립축 증거로 지배색 장면의 폭주가 줄어 ±0.6 에서 넓혔습니다(macOS `wbClamp`).
constexpr double white_balance_clamp = 1.0;
// Below roughly 1.5% channel-ratio error the frame is already neutral; moving it would
// be noise, not correction.
constexpr double white_balance_deadband = 0.015;
constexpr double neutral_subset_minimum_fraction = 0.03;

constexpr double diffuse_white_linear = 0.90;
// Black point target, following the ordinary 0.1-0.5% clipping practice.
constexpr double black_point_linear = 0.005;
// Pulling exposure down is for real clipping only. A handful of speculars is the
// highlight recovery slider's job, not a reason to darken the whole frame.
constexpr double clip_recovery_threshold = 0.05;
constexpr double auto_exposure_limit = 3.0;
// 노출이 맞추는 장면 키(로그 평균 휘도) — Reinhard 의 자동 키 식 k = r·s^z,
// z = (2·log Lav − log Lmin − log Lmax) / (log Lmax − log Lmin) (Reinhard 2002 JGT, US7636496).
// 하이키는 키를 높게, 로우키는 낮게 잡습니다. Lmin 은 검정 목표(black_point_linear), Lmax 는 장면 명부
// p99 입니다. r 0.08·s 8 은 macOS 사용자 카탈로그에서 손으로 톤을 맞춘 145장과 실제 파이프라인으로 비교해
// 고른 값입니다(macOS `AutoAdjust.sceneKeyCenter`, 후보별 수치는 그쪽 주석).
// 노출로 어둡게 할 때 백점(p995)의 바닥(선형). 자동 톤의 대비 최대(+0.55)와 흰색 계열 최대(+1)로
// 확산 화이트(0.90)까지 되돌릴 수 있는 가장 낮은 백점입니다(macOS `AutoAdjust.whiteRecoveryFloor`).
constexpr double white_recovery_floor = 0.584;
constexpr double scene_key_center = 0.08;
constexpr double scene_key_spread = 8.0;

// 장면 키 — 선형 휘도의 로그 평균(Reinhard 외 2002, 식 1). 휘도 히스토그램 칸 가운데를 선형으로
// 풀어 계산합니다(macOS `ImageStats.logAverageLuminance` 와 같은 식). δ = 1e-4 가 검정 칸의 log 0 을
// 막습니다.
[[nodiscard]] double log_average_luminance(const AutoAdjustStats& stats) noexcept {
    double sum = 0.0;
    double weight = 0.0;
    for (std::size_t i = 0; i < stats.luma_histogram.size(); ++i) {
        const double h = stats.luma_histogram[i];
        if (h <= 0.0) { continue; }
        sum += h * std::log(std::max(srgb_decode(static_cast<double>(i) / 255.0), 1.0e-4));
        weight += h;
    }
    return weight > 0.0 ? std::exp(sum / weight) : 0.0;
}

// 장면 키(목표 로그 평균). `highlight` 는 장면 명부(p99, 선형). macOS `AutoAdjust.sceneKey`.
[[nodiscard]] double scene_key(const double log_average, const double highlight) noexcept {
    const double low = std::log2(black_point_linear);
    const double high = std::log2(std::max(highlight, black_point_linear * 2.0));
    const double z = std::clamp(
        ((2.0 * std::log2(std::max(log_average, 1.0e-4))) - low - high) / (high - low), -1.0, 1.0);
    return scene_key_center * std::pow(scene_key_spread, z);
}

// 노출을 준 뒤의 로그 평균이 그 장면의 키와 같아지는 ev. 키가 노출에 따라 변하므로
// f(ev) = log2(키 / 로그 평균) = 0 을 이분법으로 풉니다(±16 스톱, 60 회). 예전 고정점 반복(6 회)은
// 명부가 1 에 닿는 영역에서 수렴이 느려 최대 0.10 스톱(s 4)·1.09 스톱(s 8)이 남았습니다.
// macOS `AutoAdjust.sceneKeyExposure`.
[[nodiscard]] double scene_key_exposure(const double log_average, const double highlight) noexcept {
    const auto residual = [log_average, highlight](const double ev) noexcept {
        const double gain = std::exp2(ev);
        const double average = std::max(log_average, 1.0e-4) * gain;
        return std::log2(scene_key(average, std::min(highlight * gain, 1.0)) / average);
    };
    double low = -16.0;
    double high = 16.0;
    for (int i = 0; i < 60; ++i) {
        const double mid = 0.5 * (low + high);
        if (residual(mid) > 0.0) {
            low = mid;
        } else {
            high = mid;
        }
    }
    return 0.5 * (low + high);
}

[[nodiscard]] double histogram_percentile(
    const std::array<double, auto_adjust_histogram_bins>& histogram,
    const double fraction) noexcept {
    double accumulated = 0.0;
    for (std::size_t index = 0U; index < histogram.size(); ++index) {
        accumulated += histogram[index];
        if (accumulated >= fraction) {
            return static_cast<double>(index) / 255.0;
        }
    }
    return 1.0;
}

// 잰 휘도(노출 숄더에 이미 접힌 값)를 노출 전 휘도로 되돌립니다. 숄더는 단조 증가라 이분법으로
// 풉니다. ÷2^EV 로 되돌리면 한 번 접힌 값을 다시 숄더에 넣어 두 번 접게 되고, 그러면 백점을 낮게
// 예측해 화이트를 거꾸로 올립니다(2026-10-14 실측: 커브로 247 인 백점을 250 으로 밀었습니다 —
// 목표 243).
[[nodiscard]] double unexposed_luminance(
    const double exposed,
    const double stops,
    const double headroom_stops) noexcept {
    double low = exposed / std::exp2(stops);
    if (!(stops > 0.0) || negaflow::core::exposed_luminance(low, stops, headroom_stops) >= exposed) {
        return low;
    }
    double high = std::max(low * 2.0, 64.0);
    if (negaflow::core::exposed_luminance(high, stops, headroom_stops) < exposed) {
        return high;
    }
    for (int iteration = 0; iteration < 60; ++iteration) {
        const double middle = 0.5 * (low + high);
        if (negaflow::core::exposed_luminance(middle, stops, headroom_stops) < exposed) {
            low = middle;
        } else {
            high = middle;
        }
    }
    return 0.5 * (low + high);
}

}  // namespace

namespace {
// 이보다 덜 덮인 칸은 원근 보정의 빈 곳이 섞인 것입니다(macOS 와 같은 값).
constexpr double auto_adjust_minimum_coverage = 0.999;
}  // namespace

namespace {

// `full` 이 거짓이면 휘도 히스토그램과 클리핑 비율만 만듭니다(장면 키·채널 한도의 바닥용 — 중립축·표본은 건너뜁니다).
[[nodiscard]] bool compute_stats(
    const std::uint8_t* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::size_t stride_bytes,
    AutoAdjustStats& stats,
    const bool full) noexcept {
    if (pixels == nullptr || width == 0U || height == 0U ||
        stride_bytes < static_cast<std::size_t>(width) * 4U) {
        return false;
    }

    // Area-weighted linear sampling, bounded by the long edge on both platforms.
    const double scale = std::min(1.0, static_cast<double>(auto_adjust_sample_extent) / std::max(width, height));
    const auto w = std::max(1U, static_cast<std::uint32_t>(width * scale));
    const auto h = std::max(1U, static_cast<std::uint32_t>(height * scale));
    std::array<double, 256> decode{};
    for (std::size_t i = 0; i < decode.size(); ++i) { decode[i] = srgb_decode(static_cast<double>(i) / 255.0); }
    std::array<double, 3> sum{}, neutral{}, neutral_linear{}, minkowski{};
    std::size_t neutral_count = 0, eligible_count = 0;
    double saturation_sum = 0, clipped = 0;
    stats.luma_histogram.fill(0);
    std::vector<std::array<double, 3>> eligible;
    std::vector<AutoAdjustPeakSample> peaks;
    std::vector<std::uint8_t> pixel_peaks;
    std::vector<std::uint8_t> pixel_luma;
    if (full) {
        try {
            eligible.reserve(static_cast<std::size_t>(w) * h);
            peaks.reserve(static_cast<std::size_t>(w) * h);
            pixel_peaks.resize(static_cast<std::size_t>(width) * height);
            pixel_luma.resize(static_cast<std::size_t>(width) * height);
        } catch (...) { return false; }
        for (std::uint32_t sy = 0U; sy < height; ++sy) {
            const std::uint8_t* row = pixels + static_cast<std::size_t>(sy) * stride_bytes;
            const std::size_t at = static_cast<std::size_t>(sy) * width;
            for (std::uint32_t sx = 0U; sx < width; ++sx) {
                const std::uint8_t* q = row + static_cast<std::size_t>(sx) * 4U;
                const std::uint8_t peak = q[3] != 0U ? std::max({q[0], q[1], q[2]}) : std::uint8_t{0};
                pixel_peaks[at + sx] = peak;
                // 휘도는 255 에 닿은 화소에서만 봅니다(확산 화이트 판정) — 나머지는 계산하지 않습니다.
                pixel_luma[at + sx] = peak == 255U ? channel_headroom::luma_code(q[0], q[1], q[2]) : std::uint8_t{0};
            }
        }
    }
    const auto overlap = [](double a, double b, double c, double d) { return std::max(0.0, std::min(b,d) - std::max(a,c)); };
    std::size_t included = 0;
    for (std::uint32_t y = 0; y < h; ++y) {
        const double top = static_cast<double>(y) * height / h, bottom = static_cast<double>(y + 1U) * height / h;
        for (std::uint32_t x = 0; x < w; ++x) {
            const double left = static_cast<double>(x) * width / w, right = static_cast<double>(x + 1U) * width / w;
            std::array<double, 3> p{};
            double weight_sum = 0;
            double coverage_sum = 0;
            for (auto sy = static_cast<std::uint32_t>(std::floor(top)); sy < std::min(height, static_cast<std::uint32_t>(std::ceil(bottom))); ++sy) {
                const double wy = overlap(top,bottom,sy,sy+1.0);
                for (auto sx = static_cast<std::uint32_t>(std::floor(left)); sx < std::min(width, static_cast<std::uint32_t>(std::ceil(right))); ++sx) {
                    const double weight = wy * overlap(left,right,sx,sx+1.0);
                    const auto* q = pixels + static_cast<std::size_t>(sy) * stride_bytes + static_cast<std::size_t>(sx) * 4U;
                    p[0] += decode[q[2]] * weight; p[1] += decode[q[1]] * weight; p[2] += decode[q[0]] * weight;
                    weight_sum += weight;
                    coverage_sum += (static_cast<double>(q[3]) / 255.0) * weight;
                }
            }
            // 원근 보정의 빈 곳(알파 0, 색은 흰색)이 섞인 칸은 사진이 아닙니다 — macOS
            // `SceneAnalysisSampler.minimumCoverage` 와 같은 기준으로 뺍니다. 불투명한 입력은 그대로입니다.
            if (weight_sum <= 0.0 || coverage_sum / weight_sum < auto_adjust_minimum_coverage) { continue; }
            ++included;
            for (auto& c : p) { c /= weight_sum; }
            const double luma = 0.2126*p[0] + 0.7152*p[1] + 0.0722*p[2];
            const double encoded_y = srgb_encode(luma);
            const auto bin = static_cast<std::size_t>(std::clamp(static_cast<int>(std::lround(encoded_y * 255)),0,255));
            stats.luma_histogram[bin] += 1;
            const bool channel_clipped = std::max({p[0],p[1],p[2]}) >= 0.995;
            clipped += channel_clipped ? 1.0 : 0.0;
            if (!full) { continue; }
            peaks.push_back(channel_headroom::sample(p[0], p[1], p[2]));
            const std::array<double, 3> rgb{srgb_encode(p[0]),srgb_encode(p[1]),srgb_encode(p[2])};
            for (std::size_t c = 0; c < 3; ++c) { sum[c] += rgb[c]; }
            const double mx = std::max({rgb[0],rgb[1],rgb[2]}), mn = std::min({rgb[0],rgb[1],rgb[2]});
            const double saturation = mx > 1e-6 ? (mx-mn)/mx : 0;
            saturation_sum += saturation;
            if (channel_clipped || std::min({p[0],p[1],p[2]}) <= 0.0003 || luma <= 0.002 || luma >= 0.90) { continue; }
            eligible.push_back(p); ++eligible_count;
            for (std::size_t c = 0; c < 3; ++c) { minkowski[c] += std::pow(p[c],6); }
            if (saturation <= 0.22 && encoded_y > 0.10 && encoded_y < 0.90) {
                for (std::size_t c = 0; c < 3; ++c) { neutral[c] += rgb[c]; neutral_linear[c] += p[c]; }
                ++neutral_count;
            }
        }
    }
    if (included == 0) { return false; }
    if (!full) {
        const double count = static_cast<double>(included);
        for (auto& bin : stats.luma_histogram) { bin /= count; }
        stats.clipped_fraction = clipped / count;
        return true;
    }
    const double n = static_cast<double>(included), nc = static_cast<double>(std::max<std::size_t>(neutral_count,1));
    const double ec = static_cast<double>(std::max<std::size_t>(eligible_count,1));
    const bool has_neutral = neutral_count >= std::max<std::size_t>(16U,static_cast<std::size_t>(n)/100U);
    stats.average_red=sum[0]/n; stats.average_green=sum[1]/n; stats.average_blue=sum[2]/n;
    stats.average_saturation=saturation_sum/n; stats.clipped_fraction=clipped/n;
    for (auto& bin : stats.luma_histogram) { bin /= n; }
    stats.neutral_average_red=has_neutral?neutral[0]/nc:stats.average_red;
    stats.neutral_average_green=has_neutral?neutral[1]/nc:stats.average_green;
    stats.neutral_average_blue=has_neutral?neutral[2]/nc:stats.average_blue;
    stats.neutral_linear_red=has_neutral?neutral_linear[0]/nc:srgb_decode(stats.neutral_average_red);
    stats.neutral_linear_green=has_neutral?neutral_linear[1]/nc:srgb_decode(stats.neutral_average_green);
    stats.neutral_linear_blue=has_neutral?neutral_linear[2]/nc:srgb_decode(stats.neutral_average_blue);
    stats.neutral_pixel_fraction=static_cast<double>(neutral_count)/n;
    stats.minkowski_linear_red=std::pow(minkowski[0]/ec,1.0/6.0);
    stats.minkowski_linear_green=std::pow(minkowski[1]/ec,1.0/6.0);
    stats.minkowski_linear_blue=std::pow(minkowski[2]/ec,1.0/6.0);
    try { stats.neutral_axis=measure_neutral_axis(eligible);
        if(stats.neutral_axis){stats.neutral_axis->confidence*=std::min(1.0,static_cast<double>(eligible_count)/(n*0.10));} } catch (...) { stats.neutral_axis.reset(); }
    stats.white_balance_confidence = stats.neutral_axis ? stats.neutral_axis->confidence : 0.0;
    stats.peak_samples = std::move(peaks);
    stats.pixel_peaks = std::move(pixel_peaks);
    stats.pixel_luma = std::move(pixel_luma);
    return true;
}

}  // namespace

bool compute_auto_adjust_stats(
    const std::uint8_t* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::size_t stride_bytes,
    AutoAdjustStats& stats) noexcept {
    return compute_stats(pixels, width, height, stride_bytes, stats, true);
}

bool compute_auto_adjust_luminance_stats(
    const std::uint8_t* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::size_t stride_bytes,
    AutoAdjustStats& stats) noexcept {
    return compute_stats(pixels, width, height, stride_bytes, stats, false);
}

AutoWhiteBalanceResult auto_white_balance(const AutoAdjustStats& stats) noexcept {
    double red = 0.0;
    double green = 0.0;
    double blue = 0.0;
    double confidence = stats.white_balance_confidence;
    if (stats.neutral_axis.has_value()) {
        confidence = stats.neutral_axis->confidence;
        // 휘도대마다 한 표 — 한 휘도대를 차지한 따뜻한 조명 면이 평균을 끌지 못합니다.
        const std::array<double, 3> cast = neutral_axis_median_cast(*stats.neutral_axis);
        red = std::exp(cast[0]);
        green = std::exp(cast[1]);
        blue = std::exp(cast[2]);
    } else {
        const bool use_neutral =
            stats.neutral_pixel_fraction >= neutral_subset_minimum_fraction;
        red = use_neutral ? stats.neutral_linear_red : stats.minkowski_linear_red;
        green = use_neutral ? stats.neutral_linear_green : stats.minkowski_linear_green;
        blue = use_neutral ? stats.neutral_linear_blue : stats.minkowski_linear_blue;
    }
    if (red <= 1.0e-5 || green <= 1.0e-5 || blue <= 1.0e-5) {
        return {};
    }

    // ColorModel 의 화이트밸런스 게인(white_balance.h)을 거꾸로 풉니다. 온도는 R/B 를,
    // 틴트는 온도가 남긴 G/√(R·B) 를 맞춥니다. |w| <= 1 에서 온도 해는 예전
    // R(1 + 0.18w) = B(1 − 0.18w) 의 해와 같습니다(같은 식의 로그). 이미 따뜻한 프레임은
    // 음수 온도로 식힙니다.
    double warmth = solve_white_balance(std::log2(blue / red), [](const double value) noexcept {
        return warmth_red_blue_stops(value);
    });
    if (std::abs(blue - red) / std::max(red + blue, 1.0e-6) * 2.0 < white_balance_deadband) {
        warmth = 0.0;
    }
    warmth = clamp_range(
        warmth * white_balance_strength * confidence,
        -white_balance_clamp,
        white_balance_clamp);

    // 틴트는 온도를 적용한 뒤의 잔차로 풉니다(온도 자신의 녹색 성분 포함).
    const double warmed_green_stops =
        (0.5 * (std::log2(red) + std::log2(blue))) - std::log2(green) -
        warmth_green_stops(warmth);
    double tint = solve_white_balance(warmed_green_stops, [](const double value) noexcept {
        return tint_green_stops(value);
    });
    if (std::abs(warmed_green_stops) * std::log(2.0) < white_balance_deadband) {
        tint = 0.0;
    }
    tint = clamp_range(
        tint * white_balance_strength * confidence,
        -white_balance_clamp,
        white_balance_clamp);

    return {warmth, tint};
}

AutoToneResult auto_tone(const AutoAdjustStats& stats, const double headroom_stops) noexcept {
    const auto percentile = [&stats](const double fraction) noexcept {
        return histogram_percentile(stats.luma_histogram, fraction);
    };

    const double clip_high = std::max(stats.luma_histogram[255], stats.clipped_fraction);
    const double clip_low = stats.luma_histogram[0];
    // Black and shadow points use percentiles thick enough to step over a scan's black
    // frame border. A thinner one treats the border as the shadow point and hauls the
    // real shadows up with it.
    const double black_srgb = percentile(0.02);
    const double shadow_srgb = percentile(0.08);
    const double mid_srgb = percentile(0.50);
    const double p975_srgb = percentile(0.975);
    const double p98_srgb = percentile(0.98);
    const double p995_srgb = percentile(0.995);
    const double p10_srgb = percentile(0.10);
    const double p90_srgb = percentile(0.90);

    // Exposure — 장면 키(로그 평균 휘도)를 scene_key 로 보냅니다. 양방향입니다: 밝은 장면은 내리고
    // 어두운 장면은 올립니다(현상소 LATD 전량 보정, Lightroom 자동과 같은 방향). 예전에는 밝히는
    // 쪽만 허용해, 중립 현상본이 18% 보다 밝은 사진(macOS 사용자 카탈로그 398장 중 49%, 컬러
    // 네거티브는 85%)에서 노출이 늘 0 이었습니다(2026-11-08 실측). 밝힐 때는 p98 이 0.95 를 넘지 않게,
    // 어둡힐 때는 백점이 white_recovery_floor 아래로 내려가지 않게 막고, 실질 클리핑(≥5%)이면 적어도
    // p995 를 0.92 로 내릴 만큼 어둡게 합니다.
    const double wanted_exposure =
        scene_key_exposure(log_average_luminance(stats), srgb_decode(percentile(0.99)));
    double exposure = clamp_range(wanted_exposure, -auto_exposure_limit, auto_exposure_limit);
    if (exposure > 0.0) {
        exposure = std::min(
            exposure, std::max(0.0, std::log2(0.95 / std::max(srgb_decode(p98_srgb), 1.0e-4))));
    }
    if (exposure < 0.0) {
        exposure = std::max(exposure, std::min(0.0,
            std::log2(white_recovery_floor / std::max(srgb_decode(p995_srgb), 1.0e-4))));
    }
    if (clip_high >= clip_recovery_threshold) {
        exposure = std::min(exposure, clamp_range(
            std::log2(0.92 / std::max(srgb_decode(p995_srgb), 1.0e-4)),
            -auto_exposure_limit,
            0.0));
    }
    // 노출 뒤의 기본 톤입니다. 채널 한도(아래)가 노출을 줄이면 그 노출로 다시 풉니다. `caps` 는 밝히는
    // 단계의 상한입니다(흰색·대비는 양수 상한, 농도는 밝히는 쪽 크기의 상한).
    struct LiftCaps final {
        double whites{std::numeric_limits<double>::infinity()};
        double density_lift{std::numeric_limits<double>::infinity()};
        double contrast{std::numeric_limits<double>::infinity()};
    };
    const auto solve = [&](const double ev, const LiftCaps& caps) noexcept {
        AutoToneResult result{};
        result.exposure = ev;

        // 노출 뒤 백분위는 엔진과 같은 노출 연산자(EV>0 명부 숄더)로 예측합니다.
        const auto after_exposure = [ev, headroom_stops](const double srgb) noexcept {
            return srgb_encode(std::min(
                negaflow::core::exposed_luminance(srgb_decode(srgb), ev, headroom_stops), 1.0));
        };
        const double black_after = after_exposure(black_srgb);
        const double shadow_after = after_exposure(shadow_srgb);
        const double mid_after = after_exposure(mid_srgb);
        const double p975_after = after_exposure(p975_srgb);
        const double p995_after = after_exposure(p995_srgb);

        // 기본 톤은 대비 → 농도 → 명부 → 암부 → 흰색 → 검정 순서로 단계를 합성합니다
        // (`basic_tone_model.h`). 각 슬라이더는 앞 단계를 이미 적용한 값에서, 그 단계의 실제 계수·마스크로
        // 역산합니다(macOS `AutoAdjust.autoTone` 과 같습니다).
        namespace model = negaflow::imaging::basic_tone_model;

        // Contrast targets a perceptual spread, measured after the exposure move. 평평한 장면은
        // 올리되 깎는 쪽은 소량만 — 스프레드 목표는 평균적인 컬러 장면의 값이라 원래 대비가 큰 장면
        // (흑백 프린트·역광)을 그 값까지 깎으면 계조가 무너집니다. 양 끝 복구는 하이라이트/섀도의 몫입니다.
        const double p10_after = after_exposure(p10_srgb);
        const double p90_after = after_exposure(p90_srgb);
        result.contrast = std::min(clamp_range(
            (0.52 - (p90_after - p10_after)) * 1.15,
            -0.15,
            0.55), caps.contrast);
        const auto through_contrast = [&result](const double v) noexcept {
            return model::contrast(v, result.contrast);
        };

        // Density — 노출이 명부 여유(p98 ≤ 0.95)·채널 한도·노출 한도(±3 스톱)에 막혀 키까지 못 밝힌 만큼만
        // 중간톤을 밝힙니다(명부 불침범, density < 0 = 밝게). 장면 키는 노출이 맞추므로 그 밖에서는 0 입니다
        // (macOS 와 같습니다).
        if (wanted_exposure - ev > 0.05) {
            const double goal = srgb_encode(std::min(
                srgb_decode(mid_after) * std::exp2(wanted_exposure - ev), diffuse_white_linear));
            const double mid = through_contrast(mid_after);
            const double mid_mask = std::max(model::density_mask(mid), 0.3);
            result.density = std::max(clamp_range((mid - goal) / (0.10 * mid_mask), -0.4, 0.0), -caps.density_lift);
        }
        const auto through_density = [&result, &through_contrast](const double v) noexcept {
            return model::density(through_contrast(v), result.density);
        };

        // Highlights and shadows are recovery only, one direction each. The pure end bins
        // include a scan's black border and specular dots, so their contribution is capped.
        const double high = through_density(p975_after);
        const double highlight_mask = std::max(model::highlight_mask(high), 0.3);
        result.highlights = clamp_range(
            (-std::min(clip_high, 0.05) * 4.0) -
                (std::max(0.0, high - 0.89) * 0.5 / (0.10 * highlight_mask)),
            -1.0,
            0.0);
        const auto through_highlight = [&result, &through_density](const double v) noexcept {
            return model::highlight(through_density(v), result.highlights);
        };
        // 섀도는 그 톤에서 슬라이더가 실제로 먹는 만큼(마스크)만 반응하고 초과분의 절반만 회수합니다.
        // 예전엔 마스크를 하한(0.3)으로 나눠 역산해, 슬라이더가 거의 안 닿는 깊은 검정(흑백 프린트의
        // 검정·스캔 테두리)을 끌어올리려 최대치(0.8)로 밀었고 그 위의 중간 암부가 통째로 들렸습니다
        // (2026-10-15 macOS 실측: 흑백 7 장 중 5 장·컬러 19 장 중 8 장이 0.8).
        const double low = through_highlight(shadow_after);
        result.shadows = clamp_range(
            (std::min(clip_low, 0.05) * 4.0) +
                (std::max(0.0, 0.10 - low) * 0.5 / 0.10 * model::shadow_lift_mask(low)),
            0.0,
            0.8);
        const auto through_shadow = [&result, &through_highlight](const double v) noexcept {
            return model::shadow(through_highlight(v), result.shadows);
        };

        // Endpoint stretch, inverted through the whites and blacks masks. The mask floors
        // stop a target that lands where the mask is nearly zero from demanding an enormous
        // slider value.
        const double diffuse_white_srgb = srgb_encode(diffuse_white_linear);
        const double black_point_srgb = srgb_encode(black_point_linear);
        const double white = through_shadow(p995_after);
        const double white_mask = std::max(model::whites_mask(white), 0.25);
        result.whites = clamp_range(
            (diffuse_white_srgb - white) / (0.12 * white_mask),
            -1.0,
            1.0);
        if (clip_high > 0.001) {
            result.whites = std::min(result.whites, 0.0);
        }
        result.whites = std::min(result.whites, caps.whites);
        // Blacks mainly pulls lifted blacks back down. Lifting already-deep blacks up to the
        // target washes the image out, so that direction is capped hard while recovery is not.
        const double black = model::whites(through_shadow(black_after), result.whites);
        const double black_mask = std::max(model::blacks_mask(black, black < black_point_srgb), 0.25);
        result.blacks = clamp_range(
            (black_point_srgb - black) / (0.06 * black_mask),
            -1.0,
            0.15);

        // Vibrance only ever increases, which is what every other auto tool does too.
        result.vibrance = 0.0;
        return result;
    };

    // 채널 한도 — 휘도 목표가 채도 높은 명부·중간톤의 최대 채널을 1 쪽으로 밀면(새로 안전 상한을 넘는 표본 >
    // channel_headroom::allowance) 밝히는 몫을 거둡니다. 내주는 순서는 흰색(백점을 클리핑 직전까지 보내는
    // 단계) → 장면 키(노출을 줄이고 모자란 중간톤은 농도가 채웁니다 — 가산 리프트는 채도 높은 화소의 최대
    // 채널을 휘도만큼만 올려 노출 이득보다 덜 밉니다) → 농도·대비 리프트입니다. 그 뒤 흰색을 맞는 만큼
    // 되돌립니다. 각 한도는 이분법입니다(macOS `AutoAdjust.autoTone` 7 단계).
    AutoToneResult result = solve(exposure, LiftCaps{});
    if (stats.peak_samples.empty()) {
        return result;
    }
    // 탐색은 노출을 줄이기만 하므로 지금 노출과 최대 리프트로 닿을 수 없는 표본은 미리 뺍니다. 메모리가
    // 모자라면 전체 표본으로 셉니다(결과는 같습니다).
    std::vector<AutoAdjustPeakSample> pruned;
    const std::vector<AutoAdjustPeakSample>* pool = &stats.peak_samples;
    try {
        pruned = channel_headroom::candidates(
            stats.peak_samples, std::max(exposure, 0.0), channel_headroom::maximum_auto_lift);
        pool = &pruned;
    } catch (...) {
        pool = &stats.peak_samples;
    }
    const std::size_t total = stats.peak_samples.size();
    const auto fits = [&](const AutoToneResult& tone) noexcept {
        return channel_headroom::induced_clipping(*pool, total, tone, headroom_stops) <=
               channel_headroom::allowance;
    };
    // [0, upper] 에서 맞는 가장 큰 값(0 도 맞지 않으면 0). 9 회면 노출 3 스톱 구간에서 0.006 스톱,
    // 흰색 1 구간에서 0.002 — 슬라이더 표시(0.01)보다 곱습니다.
    const auto largest = [](const double upper, const auto& ok) noexcept {
        if (ok(upper)) { return upper; }
        double low = 0.0;
        double high = upper;
        for (int i = 0; i < 9; ++i) {
            const double mid = 0.5 * (low + high);
            if (ok(mid)) { low = mid; } else { high = mid; }
        }
        return low;
    };
    if (!fits(result)) {
        double ev = exposure;
        // 노출은 휘도만 본 값에서 예산(auto_tone_channel_exposure_budget)까지만 내줍니다.
        const double floor = std::max(exposure - auto_tone_channel_exposure_budget, std::min(exposure, 0.0));
        LiftCaps caps{};
        caps.whites = 0.0;
        if (!fits(solve(ev, caps))) {
            if (ev > floor && fits(solve(floor, caps))) {
                ev = floor + largest(ev - floor, [&](const double value) noexcept { return fits(solve(floor + value, caps)); });
            } else {
                caps.density_lift = 0.0;
                caps.contrast = 0.0;
                if (ev > floor) {
                    ev = floor + largest(ev - floor, [&](const double value) noexcept { return fits(solve(floor + value, caps)); });
                }
                LiftCaps whites_off{};
                whites_off.whites = 0.0;
                const double density_upper = std::max(0.0, -solve(ev, whites_off).density);
                caps.density_lift = largest(density_upper, [&](const double value) noexcept {
                    LiftCaps trial = caps;
                    trial.density_lift = value;
                    return fits(solve(ev, trial));
                });
                whites_off.density_lift = caps.density_lift;
                const double contrast_upper = std::max(0.0, solve(ev, whites_off).contrast);
                caps.contrast = largest(contrast_upper, [&](const double value) noexcept {
                    LiftCaps trial = caps;
                    trial.contrast = value;
                    return fits(solve(ev, trial));
                });
            }
        }
        LiftCaps whites_free = caps;
        whites_free.whites = std::numeric_limits<double>::infinity();
        const double whites_upper = std::max(0.0, solve(ev, whites_free).whites);
        caps.whites = largest(whites_upper, [&](const double value) noexcept {
            LiftCaps trial = caps;
            trial.whites = value;
            return fits(solve(ev, trial));
        });
        result = solve(ev, caps);
    }
    return result;
}

namespace {

// 확인 렌더에서 새로 날아간 채널이 한도를 넘었을 때: 흰색을 0(이미 음수면 그대로)까지, 그래도 넘치면 노출을
// `auto_tone_channel_exposure_floor` 까지 맞는 만큼만 낮춥니다. 예측은 확인 렌더의 칸별 잰 값으로 바로잡습니다. 둘 다 바닥까지
// 내려도 넘치면 바닥 값입니다(macOS `AutoAdjust.withdrawChannels`).
[[nodiscard]] AutoToneResult withdraw_channels(
    const AutoToneResult& first,
    const AutoAdjustStats& neutral,
    const AutoAdjustStats& measured,
    const double headroom_stops) noexcept {
    const auto fits = [&](const AutoToneResult& candidate) noexcept {
        return channel_headroom::corrected_induced_clipping(
                   neutral.peak_samples, measured.peak_samples, first, candidate, headroom_stops) <=
               channel_headroom::allowance;
    };
    const auto lowered = [&fits](const double from, const double floor, const auto& apply) noexcept {
        if (!(from > floor) || fits(apply(from))) { return from; }
        if (!fits(apply(floor))) { return floor; }
        double high = from;
        double low = floor;
        for (int i = 0; i < 9; ++i) {
            const double mid = 0.5 * (low + high);
            if (fits(apply(mid))) { low = mid; } else { high = mid; }
        }
        return low;
    };
    AutoToneResult result = first;
    result.whites = lowered(first.whites, std::min(first.whites, 0.0), [&result](const double value) noexcept {
        AutoToneResult trial = result;
        trial.whites = value;
        return trial;
    });
    const double exposure_floor = std::min(
        first.exposure, std::max(std::min(first.exposure, 0.0), auto_tone_channel_exposure_floor(neutral, headroom_stops)));
    result.exposure = lowered(first.exposure, exposure_floor, [&result](const double value) noexcept {
        AutoToneResult trial = result;
        trial.exposure = value;
        return trial;
    });
    return result;
}

}  // namespace

double induced_pixel_clipping(
    const std::uint8_t* const neutral, const std::size_t neutral_stride_bytes,
    const std::uint8_t* const measured, const std::size_t measured_stride_bytes,
    const std::uint32_t width, const std::uint32_t height) noexcept {
    if (neutral == nullptr || measured == nullptr || width == 0U || height == 0U ||
        neutral_stride_bytes < static_cast<std::size_t>(width) * 4U ||
        measured_stride_bytes < static_cast<std::size_t>(width) * 4U) {
        return -1.0;
    }
    const auto peak = [](const std::uint8_t* q) noexcept {
        return q[3] == 0U ? std::uint8_t{0} : std::max({q[0], q[1], q[2]});
    };
    std::size_t count = 0U;
    for (std::uint32_t y = 0U; y < height; ++y) {
        const std::uint8_t* a = neutral + static_cast<std::size_t>(y) * neutral_stride_bytes;
        const std::uint8_t* b = measured + static_cast<std::size_t>(y) * measured_stride_bytes;
        for (std::uint32_t x = 0U; x < width; ++x, a += 4, b += 4) {
            if (peak(a) < 255U && peak(b) == 255U &&
                channel_headroom::luma_code(b[0], b[1], b[2]) <= channel_headroom::diffuse_white_code) {
                ++count;
            }
        }
    }
    return static_cast<double>(count) / (static_cast<double>(width) * static_cast<double>(height));
}

namespace {

// 채널 표본을 보지 않고 푼 노출입니다. 화소 표본을 복사하지 않도록 히스토그램만 옮긴 판을 씁니다.
[[nodiscard]] double luminance_only_exposure(const AutoAdjustStats& neutral, const double headroom_stops) noexcept {
    AutoAdjustStats luminance_only{};
    luminance_only.luma_histogram = neutral.luma_histogram;
    luminance_only.clipped_fraction = neutral.clipped_fraction;
    return auto_tone(luminance_only, headroom_stops).exposure;
}

}  // namespace

double auto_tone_channel_exposure_floor(const AutoAdjustStats& neutral, const double headroom_stops) noexcept {
    const double ev = luminance_only_exposure(neutral, headroom_stops);
    return std::max(ev - auto_tone_channel_exposure_budget, std::min(ev, 0.0));
}

double auto_tone_remaining_key_budget(
    const AutoAdjustStats& neutral, const double first_exposure, const double headroom_stops) noexcept {
    const double given = std::max(0.0, luminance_only_exposure(neutral, headroom_stops) - first_exposure);
    return std::max(0.0, auto_tone_channel_exposure_budget - given);
}

double auto_tone_scene_key(const AutoAdjustStats& stats) noexcept { return log_average_luminance(stats); }

double auto_tone_channel_excess(const AutoAdjustStats& neutral, const AutoAdjustStats& measured) noexcept {
    const double induced = channel_headroom::measured_induced_clipping(neutral, measured);
    return induced < 0.0 ? -1.0 : std::max(0.0, induced - channel_headroom::allowance);
}

AutoToneResult refine_auto_tone(
    const AutoToneResult& first,
    const AutoAdjustStats& measured,
    const double headroom_stops,
    const AutoAdjustStats* const neutral) noexcept {
    const double induced = neutral != nullptr ? channel_headroom::measured_induced_clipping(*neutral, measured) : -1.0;
    if (neutral != nullptr && induced > channel_headroom::allowance) {
        return withdraw_channels(first, *neutral, measured, headroom_stops);
    }
    AutoToneResult result = first;
    const auto percentile = [&measured](const double fraction) noexcept {
        return histogram_percentile(measured.luma_histogram, fraction);
    };
    const double p98 = srgb_decode(percentile(0.98));
    double p995_srgb = percentile(0.995);
    const bool clipped =
        std::max(measured.luma_histogram[255], measured.clipped_fraction) >= clip_recovery_threshold;

    // 장면 키: 잰 로그 평균과 키의 차이만큼 노출을 더하거나 뺍니다. 밝힐 때는 명부 여유 안에서,
    // 실질 클리핑이 남아 있으면 더 밝히지 않습니다(macOS `refineTone` 과 같습니다).
    const double measured_key = log_average_luminance(measured);
    double residual = std::log2(
        scene_key(measured_key, srgb_decode(percentile(0.99))) / std::max(measured_key, 1.0e-4));
    if (residual > 0.0) {
        residual = clipped ? 0.0 : std::min(residual, std::max(0.0, std::log2(0.95 / std::max(p98, 1.0e-4))));
    } else if (!clipped) {
        residual = std::max(residual, std::min(0.0,
            std::log2(white_recovery_floor / std::max(srgb_decode(p995_srgb), 1.0e-4))));
    }
    const double refined = clamp_range(result.exposure + residual, -auto_exposure_limit, auto_exposure_limit);
    if (std::abs(refined - result.exposure) > 0.02) {
        // 노출이 바뀌면 백점도 같이 움직입니다 — 같은 연산자로 되돌린 뒤 다시 예측합니다.
        const double unexposed =
            unexposed_luminance(srgb_decode(p995_srgb), result.exposure, headroom_stops);
        p995_srgb = srgb_encode(std::min(
            negaflow::core::exposed_luminance(unexposed, refined, headroom_stops), 1.0));
        result.exposure = refined;
    }

    // 백점: 확산 화이트 목표(linear 0.90)에 남은 오차를 Whites 계수로 메웁니다.
    const double residual_white = srgb_encode(diffuse_white_linear) - p995_srgb;
    if (induced < 0.0 && clipped && result.whites > 0.0) {
        // 첫 제안이 실질 채널 클리핑(≥5%)을 만들었으면 흰색 리프트를 거둡니다 — `auto_tone` 의 "이미
        // 클리핑이면 흰색을 올리지 않는다"를 렌더 결과에 겁니다. 흰색은 휘도 p995 를 보므로 채도 높은
        // 명부의 최대 채널이 먼저 1 에 닿습니다(macOS `refineTone`, 2026-11-08 사용자 카탈로그 실측).
        result.whites = 0.0;
    } else if (std::abs(residual_white) > 0.01 &&
        (std::max(measured.luma_histogram[255], measured.clipped_fraction) <= 0.001 || residual_white < 0.0)) {
        const double mask = std::max(smoothstep(0.68, 0.92, p995_srgb), 0.25);
        result.whites = clamp_range(result.whites + (residual_white / (0.12 * mask)), -1.0, 1.0);
    }

    // 채널(중립 현상본이 없을 때): 더 밝히는 몫(노출 증가·흰색 증가)이 잰 결과에서 새로 1 에 닿게 하는 화소는, 잰
    // 클리핑과 합쳐 channel_headroom::allowance 안이어야 합니다 — 잰 클리핑을 모두 이미 쓴 몫으로 봅니다(원본이 이미
    // 날아간 사진은 폐루프가 더 밝히지 않습니다). 넘치면 두 증가분을 같은 비율로 줄입니다(macOS `refineTone`).
    // 중립 현상본이 있으면 여기서 줄이지 않습니다 — 모형은 스캐너 타깃이 명부를 누르는 몫을 모르고, 첫 제안이 중립과
    // 거의 같으면 확인 렌더로 바로잡을 정보도 없습니다(macOS 사용자 카탈로그: SP-3000 JPEG 노출 0.47 → 0.015, 실제로
    // 새로 날아간 칸은 0.01%). 대신 셸의 폐루프가 후보를 그려 넘치면 첫 제안과 후보 사이를 이분합니다.
    const double raise_exposure = std::max(0.0, result.exposure - first.exposure);
    const double raise_whites = std::max(0.0, result.whites - first.whites);
    if (induced < 0.0 && (raise_exposure > 0.0 || raise_whites > 0.0) && !measured.peak_samples.empty()) {
        const double budget = std::max(0.0, channel_headroom::allowance - measured.clipped_fraction);
        std::vector<AutoAdjustPeakSample> pruned;
        const std::vector<AutoAdjustPeakSample>* pool = &measured.peak_samples;
        try {
            pruned = channel_headroom::candidates(measured.peak_samples, raise_exposure, 0.12 * raise_whites);
            pool = &pruned;
        } catch (...) {
            pool = &measured.peak_samples;
        }
        const std::size_t total = measured.peak_samples.size();
        const auto extra = [&](const double scale) noexcept {
            return channel_headroom::additional_clipping(
                *pool, total, raise_exposure * scale, raise_whites * scale);
        };
        if (extra(1.0) > budget) {
            double low = 0.0;
            double high = 1.0;
            for (int i = 0; i < 9; ++i) {
                const double mid = 0.5 * (low + high);
                if (extra(mid) <= budget) { low = mid; } else { high = mid; }
            }
            if (raise_exposure > 0.0) { result.exposure = first.exposure + (raise_exposure * low); }
            if (raise_whites > 0.0) { result.whites = first.whites + (raise_whites * low); }
        }
    }
    return result;
}

}  // namespace negaflow::imaging

namespace negaflow::imaging {
double auto_tone_score(const AutoAdjustStats& stats, const bool adjust_mid) noexcept {
    const auto p=[&stats](double fraction){return histogram_percentile(stats.luma_histogram,fraction);};
    // 중간 오차는 로그 평균 휘도 대 그 장면의 키입니다(macOS `toneScore`).
    const double white=srgb_decode(p(0.995)),black=srgb_decode(p(0.02));
    const double key=log_average_luminance(stats);
    const double mid_error=adjust_mid?std::abs(std::log2(std::max(key,1e-4)/scene_key(key,srgb_decode(p(0.99))))):0;
    const double white_error=0.25*std::abs(std::log2(std::max(white,1e-4)/diffuse_white_linear));
    const double black_error=0.25*std::max(0.0,std::log2(std::max(black,1e-4)/black_point_linear));
    const double flatness=0.5*std::max(0.0,0.52-(p(0.9)-p(0.1)));
    return mid_error+white_error+black_error+flatness+4*stats.clipped_fraction+2*stats.luma_histogram[0];
}
}
