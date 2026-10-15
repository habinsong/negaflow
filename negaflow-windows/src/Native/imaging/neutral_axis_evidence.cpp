#include "negaflow/imaging/neutral_axis_evidence.h"

#include <algorithm>
#include <cmath>
#include <map>

namespace negaflow::imaging {
namespace {

// 중립 후보의 첫 창(ln, ≈0.5 스톱)과 좁힌 창(≈0.25 스톱)입니다.
constexpr double initial_window = 0.35;
constexpr double refined_window = 0.17;
// 화소가 의미 있는 색을 가지려면 모든 채널이 이 값을 넘어야 합니다(인화 토우 0.001 의 4배 —
// 그 아래는 양자화·잡음이 비율을 지배합니다). 위쪽은 클리핑 근처를 뺍니다.
constexpr double minimum_channel = 0.004;
constexpr double maximum_luminance = 0.90;
const double band_width = std::log(2.0);

struct LogSample final {
    double luminance{0.0};
    std::array<double, 3> cast{};
};

// macOS `medianCast` 안의 `sorted[sorted.count / 2]` — 짝수면 위쪽입니다.
[[nodiscard]] double upper_median(std::vector<double> values) {
    if (values.empty()) {
        return 0.0;
    }
    std::sort(values.begin(), values.end());
    return values[values.size() / 2U];
}

[[nodiscard]] std::array<double, 3> median_cast_of(
    const std::vector<LogSample>& samples,
    const std::vector<std::size_t>& indices) {
    std::array<double, 3> result{};
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        std::vector<double> values;
        values.reserve(indices.size());
        for (const std::size_t index : indices) {
            values.push_back(samples[index].cast[channel]);
        }
        result[channel] = upper_median(std::move(values));
    }
    return result;
}

[[nodiscard]] std::vector<std::size_t> select_around(
    const std::vector<LogSample>& samples,
    const std::array<double, 3>& center,
    const double window) {
    std::vector<std::size_t> selected;
    for (std::size_t index = 0U; index < samples.size(); ++index) {
        const auto& cast = samples[index].cast;
        const double distance = std::max(
            std::abs(cast[0] - center[0]),
            std::max(std::abs(cast[1] - center[1]), std::abs(cast[2] - center[2])));
        if (distance < window) {
            selected.push_back(index);
        }
    }
    return selected;
}

}  // namespace

std::array<double, 3> neutral_axis_median_cast(const NeutralAxisEvidence& evidence) {
    std::array<double, 3> result{};
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        std::vector<double> values;
        values.reserve(evidence.bands.size());
        for (const NeutralAxisBand& band : evidence.bands) {
            values.push_back(band.cast[channel]);
        }
        if (values.empty()) {
            continue;
        }
        std::sort(values.begin(), values.end());
        const std::size_t middle = values.size() / 2U;
        result[channel] = values.size() % 2U == 0U
            ? 0.5 * (values[middle - 1U] + values[middle])
            : values[middle];
    }
    return result;
}

std::optional<NeutralAxisEvidence> measure_neutral_axis(
    const std::vector<std::array<double, 3>>& pixels) {
    std::vector<LogSample> samples;
    samples.reserve(pixels.size());
    for (const auto& pixel : pixels) {
        if (!(pixel[0] > minimum_channel && pixel[1] > minimum_channel &&
              pixel[2] > minimum_channel) ||
            !((0.2126 * pixel[0]) + (0.7152 * pixel[1]) + (0.0722 * pixel[2]) <
              maximum_luminance)) {
            continue;
        }
        const std::array<double, 3> logs{std::log(pixel[0]), std::log(pixel[1]), std::log(pixel[2])};
        const double mean = (logs[0] + logs[1] + logs[2]) / 3.0;
        samples.push_back({mean, {logs[0] - mean, logs[1] - mean, logs[2] - mean}});
    }
    if (samples.size() < 64U) {
        return std::nullopt;
    }

    std::vector<std::size_t> selected = select_around(samples, {0.0, 0.0, 0.0}, initial_window);
    bool is_fallback = false;
    if (selected.size() < std::max<std::size_t>(32U, samples.size() / 20U)) {
        // 중립 근처 후보가 5% 미만 — 캐스트가 0.5 스톱보다 크거나 장면이 한 색입니다.
        std::vector<std::size_t> all(samples.size());
        for (std::size_t index = 0U; index < all.size(); ++index) {
            all[index] = index;
        }
        selected = select_around(samples, median_cast_of(samples, all), initial_window);
        is_fallback = true;
    }
    if (selected.size() < 32U) {
        return std::nullopt;
    }
    for (int pass = 0; pass < 2; ++pass) {
        selected = select_around(samples, median_cast_of(samples, selected), refined_window);
        if (selected.size() < 32U) {
            return std::nullopt;
        }
    }

    // 휘도대(1 스톱)별 중앙값입니다. 표본이 너무 적은 대역은 버립니다.
    const std::size_t minimum_band_count = std::max<std::size_t>(8U, selected.size() / 200U);
    std::map<long long, std::vector<std::size_t>> by_band;
    for (const std::size_t index : selected) {
        by_band[static_cast<long long>(std::floor(samples[index].luminance / band_width))].push_back(index);
    }
    NeutralAxisEvidence evidence{};
    for (const auto& [key, members] : by_band) {
        (void)key;
        if (members.size() < minimum_band_count) {
            continue;
        }
        std::vector<double> luminances;
        luminances.reserve(members.size());
        for (const std::size_t index : members) {
            luminances.push_back(samples[index].luminance);
        }
        std::sort(luminances.begin(), luminances.end());
        evidence.bands.push_back(
            {luminances[luminances.size() / 2U], median_cast_of(samples, members), members.size()});
    }
    if (evidence.bands.empty()) {
        return std::nullopt;
    }
    evidence.selected_fraction =
        static_cast<double>(selected.size()) / static_cast<double>(pixels.size());
    evidence.is_fallback = is_fallback;
    return evidence;
}

}  // namespace negaflow::imaging
