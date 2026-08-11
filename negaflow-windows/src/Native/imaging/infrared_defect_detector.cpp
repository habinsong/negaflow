#include "negaflow/imaging/infrared_defect_detector.h"

#include "grain_mend_morphology.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <numeric>
#include <optional>
#include <queue>
#include <utility>

namespace negaflow::imaging {
namespace {

constexpr float kPlaneFloor = 1.0e-5F;
constexpr float kCoreCut = 0.5F;
constexpr float kMinimumSignificance = 4.0F;
constexpr std::size_t kMinimumNullSamples = 200U;
constexpr double kPi = 3.14159265358979323846;

struct SignalStatistics final {
    float floor{0.0F};
    float sigma{0.0F};
    float threshold{std::numeric_limits<float>::max()};

    [[nodiscard]] float skirt_floor() const noexcept {
        return floor + 3.0F * sigma;
    }
};

struct RawComponent final {
    std::vector<std::size_t> pixels{};
    std::size_t source_area{0U};
    std::uint32_t min_x{0U};
    std::uint32_t min_y{0U};
    std::uint32_t max_x{0U};
    std::uint32_t max_y{0U};
};

struct ConfirmedDefect final {
    std::int32_t offset_x{0};
    std::int32_t offset_y{0};
    float gain{0.0F};
    float significance{0.0F};
};

struct ConfirmedCandidate final {
    RawComponent component{};
    std::vector<std::size_t> correction_pixels{};
    ConfirmedDefect match{};
};

struct DownsampledPlane final {
    std::vector<float> pixels{};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
};

struct DefectAlignment final {
    std::int32_t offset_x{0};
    std::int32_t offset_y{0};
    double peak{0.0};
    double runner_up{0.0};
    bool at_search_limit{false};
};

[[nodiscard]] bool checked_area(
    const std::uint32_t width,
    const std::uint32_t height,
    std::size_t& area) noexcept {
    if (width == 0U || height == 0U ||
        width > std::numeric_limits<std::size_t>::max() / height) {
        return false;
    }
    area = static_cast<std::size_t>(width) * height;
    return true;
}

[[nodiscard]] float quantile(std::vector<float>& values, const double q) {
    std::sort(values.begin(), values.end());
    const auto index = static_cast<std::size_t>(
        std::clamp(q, 0.0, 1.0) * static_cast<double>(values.size() - 1U));
    return values[index];
}

[[nodiscard]] float percentile(
    const std::span<const float> values,
    const std::vector<std::uint8_t>& excluded,
    const double q) {
    std::vector<float> samples{};
    const std::size_t step = std::max<std::size_t>(1U, values.size() / 100000U);
    samples.reserve(values.size() / step + 1U);
    for (std::size_t index = 0U; index < values.size(); index += step) {
        if (excluded.empty() || excluded[index] == 0U) {
            samples.push_back(values[index]);
        }
    }
    return samples.empty() ? 0.0F : quantile(samples, q);
}

[[nodiscard]] DownsampledPlane block_mean(
    const std::span<const float> source,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t factor) {
    if (factor <= 1U) {
        return DownsampledPlane{
            std::vector<float>(source.begin(), source.end()), width, height};
    }
    DownsampledPlane result{};
    result.width = std::max(1U, width / factor);
    result.height = std::max(1U, height / factor);
    result.pixels.assign(static_cast<std::size_t>(result.width) * result.height, 0.0F);
    const float inverse = 1.0F / static_cast<float>(factor * factor);
    for (std::uint32_t block_y = 0U; block_y < result.height; ++block_y) {
        for (std::uint32_t block_x = 0U; block_x < result.width; ++block_x) {
            float sum = 0.0F;
            for (std::uint32_t y = block_y * factor; y < (block_y + 1U) * factor; ++y) {
                for (std::uint32_t x = block_x * factor; x < (block_x + 1U) * factor; ++x) {
                    sum += source[static_cast<std::size_t>(y) * width + x];
                }
            }
            result.pixels[static_cast<std::size_t>(block_y) * result.width + block_x] =
                sum * inverse;
        }
    }
    return result;
}

[[nodiscard]] double correlation(
    const std::span<const float> first,
    const std::span<const float> second,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::int32_t dx,
    const std::int32_t dy,
    const std::uint32_t stride) noexcept {
    const std::int32_t inset = static_cast<std::int32_t>(stride == 1U ? 4U : 8U) +
        std::max(std::abs(dx), std::abs(dy));
    if (static_cast<std::int32_t>(width) <= 2 * inset ||
        static_cast<std::int32_t>(height) <= 2 * inset) return -1.0;
    double first_sum = 0.0;
    double second_sum = 0.0;
    double first_square = 0.0;
    double second_square = 0.0;
    double product = 0.0;
    double count = 0.0;
    for (std::int32_t y = inset; y < static_cast<std::int32_t>(height) - inset;
         y += static_cast<std::int32_t>(stride)) {
        for (std::int32_t x = inset; x < static_cast<std::int32_t>(width) - inset;
             x += static_cast<std::int32_t>(stride)) {
            const double a = first[static_cast<std::size_t>(y + dy) * width +
                static_cast<std::uint32_t>(x + dx)];
            const double b = second[static_cast<std::size_t>(y) * width +
                static_cast<std::uint32_t>(x)];
            first_sum += a;
            second_sum += b;
            first_square += a * a;
            second_square += b * b;
            product += a * b;
            count += 1.0;
        }
    }
    if (count <= static_cast<double>(stride == 1U ? 16U : 64U)) return -1.0;
    const double first_mean = first_sum / count;
    const double second_mean = second_sum / count;
    const double covariance = product / count - first_mean * second_mean;
    const double first_variance = first_square / count - first_mean * first_mean;
    const double second_variance = second_square / count - second_mean * second_mean;
    if (first_variance <= 1.0e-12 || second_variance <= 1.0e-12) return -1.0;
    return covariance / std::sqrt(first_variance * second_variance);
}

[[nodiscard]] std::optional<DefectAlignment> estimate_defect_alignment(
    const std::span<const float> infrared,
    const std::span<const float> red,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t search_radius) {
    if (search_radius == 0U || width <= 4U * search_radius || height <= 4U * search_radius) {
        return std::nullopt;
    }
    const std::uint32_t inset = std::max(search_radius + 2U, std::min(width, height) / 32U);
    if (width <= 2U * inset || height <= 2U * inset) return std::nullopt;
    std::vector<float> sample{};
    sample.reserve(static_cast<std::size_t>((width - 2U * inset) / 3U + 1U) *
                   ((height - 2U * inset) / 3U + 1U));
    for (std::uint32_t y = inset; y < height - inset; y += 3U) {
        for (std::uint32_t x = inset; x < width - inset; x += 3U) {
            sample.push_back(infrared[static_cast<std::size_t>(y) * width + x]);
        }
    }
    if (sample.size() <= 64U) return std::nullopt;
    std::sort(sample.begin(), sample.end());
    const float base = sample[static_cast<std::size_t>(
        0.90 * static_cast<double>(sample.size() - 1U))];
    const float median = sample[sample.size() / 2U];
    const float spread = base - median;
    if (!(base > 1.0e-4F) || !(spread > base * 1.0e-3F)) return std::nullopt;
    const float cut = base - 4.0F * spread;
    std::vector<std::size_t> points{};
    std::vector<float> weights{};
    for (std::uint32_t y = inset; y < height - inset; ++y) {
        for (std::uint32_t x = inset; x < width - inset; ++x) {
            const std::size_t pixel = static_cast<std::size_t>(y) * width + x;
            if (infrared[pixel] < cut) {
                points.push_back(pixel);
                weights.push_back((base - infrared[pixel]) / base);
            }
        }
    }
    if (points.size() < 16U) return std::nullopt;
    constexpr std::size_t kPointLimit = 20000U;
    if (points.size() > kPointLimit) {
        std::vector<std::size_t> order(points.size(), 0U);
        std::iota(order.begin(), order.end(), 0U);
        std::partial_sort(order.begin(), order.begin() + kPointLimit, order.end(),
            [&](const std::size_t a, const std::size_t b) { return weights[a] > weights[b]; });
        std::vector<std::size_t> limited_points{};
        std::vector<float> limited_weights{};
        limited_points.reserve(kPointLimit);
        limited_weights.reserve(kPointLimit);
        for (std::size_t ordinal = 0U; ordinal < kPointLimit; ++ordinal) {
            limited_points.push_back(points[order[ordinal]]);
            limited_weights.push_back(weights[order[ordinal]]);
        }
        points = std::move(limited_points);
        weights = std::move(limited_weights);
    }
    const std::uint32_t darkness_radius =
        std::max(4U, std::min(24U, std::min(width, height) / 200U));
    const std::vector<float> red_copy(red.begin(), red.end());
    auto darkness = grain_mend_detail::box_mean(red_copy, width, height, darkness_radius);
    for (std::size_t index = 0U; index < darkness.size(); ++index) {
        darkness[index] = std::max(0.0F, darkness[index] - red[index]);
    }
    const double total_weight = std::accumulate(weights.begin(), weights.end(), 0.0);
    if (!(total_weight > 0.0)) return std::nullopt;
    const std::int32_t search = static_cast<std::int32_t>(search_radius);
    const std::int32_t side = 2 * search + 1;
    std::vector<double> scores(static_cast<std::size_t>(side) * side, 0.0);
    double best = -std::numeric_limits<double>::infinity();
    std::int32_t best_x = 0;
    std::int32_t best_y = 0;
    double score_sum = 0.0;
    for (std::int32_t dy = -search; dy <= search; ++dy) {
        for (std::int32_t dx = -search; dx <= search; ++dx) {
            double sum = 0.0;
            for (std::size_t ordinal = 0U; ordinal < points.size(); ++ordinal) {
                const std::size_t pixel = points[ordinal];
                const std::int32_t x = static_cast<std::int32_t>(pixel % width) + dx;
                const std::int32_t y = static_cast<std::int32_t>(pixel / width) + dy;
                if (x >= 0 && y >= 0 && x < static_cast<std::int32_t>(width) &&
                    y < static_cast<std::int32_t>(height)) {
                    sum += static_cast<double>(darkness[static_cast<std::size_t>(y) * width +
                        static_cast<std::uint32_t>(x)]) * weights[ordinal];
                }
            }
            const double score = sum / total_weight;
            scores[static_cast<std::size_t>(dy + search) * side + dx + search] = score;
            score_sum += score;
            if (score > best) {
                best = score;
                best_x = dx;
                best_y = dy;
            }
        }
    }
    if (!(best > 0.0)) return std::nullopt;
    double runner_up = -std::numeric_limits<double>::infinity();
    for (std::int32_t dy = -search; dy <= search; ++dy) {
        for (std::int32_t dx = -search; dx <= search; ++dx) {
            if (std::abs(dx - best_x) <= 2 && std::abs(dy - best_y) <= 2) continue;
            runner_up = std::max(runner_up,
                scores[static_cast<std::size_t>(dy + search) * side + dx + search]);
        }
    }
    const double mean = score_sum / static_cast<double>(scores.size());
    if (!(mean > 0.0) || best < mean * 1.10) return std::nullopt;
    return DefectAlignment{
        -best_x,
        -best_y,
        best,
        std::isfinite(runner_up) ? runner_up : 0.0,
        std::abs(best_x) == search || std::abs(best_y) == search};
}

[[nodiscard]] InfraredAlignmentDiagnostics estimate_alignment(
    const std::span<const float> infrared,
    const std::span<const float> red,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t search_radius) {
    InfraredAlignmentDiagnostics result{};
    result.search_radius = search_radius;
    if (search_radius == 0U) {
        result.status = InfraredAlignmentStatus::not_requested;
        return result;
    }
    if (const auto defect = estimate_defect_alignment(
            infrared, red, width, height, search_radius)) {
        result.status = defect->at_search_limit
            ? InfraredAlignmentStatus::search_limit_reached
            : InfraredAlignmentStatus::aligned;
        result.offset_x = defect->offset_x;
        result.offset_y = defect->offset_y;
        result.peak_correlation = defect->peak;
        result.runner_up_correlation = defect->runner_up;
        return result;
    }
    const std::uint32_t factor = std::max(1U, std::min(width, height) / 384U);
    result.downsample_factor = factor;
    auto infrared_down = block_mean(infrared, width, height, factor);
    auto red_down = block_mean(red, width, height, factor);
    if (infrared_down.width <= 24U || infrared_down.height <= 24U) {
        result.status = InfraredAlignmentStatus::insufficient_texture;
        return result;
    }
    auto ir_low = grain_mend_detail::box_mean(
        infrared_down.pixels, infrared_down.width, infrared_down.height, 4U);
    auto red_low = grain_mend_detail::box_mean(
        red_down.pixels, red_down.width, red_down.height, 4U);
    double ir_square_sum = 0.0;
    for (std::size_t index = 0U; index < infrared_down.pixels.size(); ++index) {
        infrared_down.pixels[index] -= ir_low[index];
        red_down.pixels[index] -= red_low[index];
        ir_square_sum += static_cast<double>(infrared_down.pixels[index]) *
            infrared_down.pixels[index];
    }
    const double ir_rms = std::sqrt(ir_square_sum /
        static_cast<double>(infrared_down.pixels.size()));
    if (ir_rms <= 0.003) {
        result.status = InfraredAlignmentStatus::insufficient_texture;
        return result;
    }
    const std::int32_t radius = static_cast<std::int32_t>(std::max(
        1U,
        std::min(search_radius / factor,
                 std::min(infrared_down.width, infrared_down.height) / 4U)));
    std::int32_t best_x = 0;
    std::int32_t best_y = 0;
    double best = -1.0;
    double runner_up = -1.0;
    for (std::int32_t y = -radius; y <= radius; ++y) {
        for (std::int32_t x = -radius; x <= radius; ++x) {
            const double score = correlation(
                infrared_down.pixels, red_down.pixels,
                infrared_down.width, infrared_down.height, x, y, 1U);
            if (score > best) {
                runner_up = best;
                best = score;
                best_x = x;
                best_y = y;
            } else if (score > runner_up) {
                runner_up = score;
            }
        }
    }
    if (best <= 0.2) {
        result.status = InfraredAlignmentStatus::weak_correlation;
        result.peak_correlation = best;
        result.runner_up_correlation = runner_up;
        return result;
    }
    std::int32_t fine_x = best_x * static_cast<std::int32_t>(factor);
    std::int32_t fine_y = best_y * static_cast<std::int32_t>(factor);
    double fine_best = -1.0;
    double fine_runner_up = -1.0;
    const auto search = static_cast<std::int32_t>(search_radius);
    const std::int32_t minimum_y =
        std::max(-search, fine_y - static_cast<std::int32_t>(factor));
    const std::int32_t maximum_y =
        std::min(search, fine_y + static_cast<std::int32_t>(factor));
    const std::int32_t minimum_x =
        std::max(-search, fine_x - static_cast<std::int32_t>(factor));
    const std::int32_t maximum_x =
        std::min(search, fine_x + static_cast<std::int32_t>(factor));
    for (std::int32_t y = minimum_y; y <= maximum_y; ++y) {
        for (std::int32_t x = minimum_x; x <= maximum_x; ++x) {
            const double score = correlation(
                infrared, red, width, height, x, y, std::max(2U, factor));
            if (score > fine_best) {
                fine_runner_up = fine_best;
                fine_best = score;
                fine_x = x;
                fine_y = y;
            } else if (score > fine_runner_up) {
                fine_runner_up = score;
            }
        }
    }
    result.offset_x = fine_x;
    result.offset_y = fine_y;
    result.peak_correlation = fine_best;
    result.runner_up_correlation = fine_runner_up;
    result.status = std::abs(fine_x) == search || std::abs(fine_y) == search
        ? InfraredAlignmentStatus::search_limit_reached
        : InfraredAlignmentStatus::aligned;
    return result;
}

[[nodiscard]] std::vector<float> shift_plane(
    const std::span<const float> source,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::int32_t dx,
    const std::int32_t dy,
    std::vector<std::uint8_t>& excluded) {
    if (dx == 0 && dy == 0) return std::vector<float>(source.begin(), source.end());
    std::vector<float> output(source.size(), 0.0F);
    for (std::int32_t y = 0; y < static_cast<std::int32_t>(height); ++y) {
        for (std::int32_t x = 0; x < static_cast<std::int32_t>(width); ++x) {
            const std::int32_t source_x = x + dx;
            const std::int32_t source_y = y + dy;
            const std::size_t target = static_cast<std::size_t>(y) * width +
                static_cast<std::uint32_t>(x);
            if (source_x >= 0 && source_y >= 0 && source_x < static_cast<std::int32_t>(width) &&
                source_y < static_cast<std::int32_t>(height)) {
                output[target] = source[static_cast<std::size_t>(source_y) * width +
                    static_cast<std::uint32_t>(source_x)];
            } else {
                excluded[target] = 1U;
            }
        }
    }
    return output;
}

void exclude_border_dark(
    const std::span<const float> plane,
    const std::uint32_t width,
    const std::uint32_t height,
    const float threshold,
    const std::uint32_t rim,
    std::vector<std::uint8_t>& excluded) {
    const auto dark = [&](const std::uint32_t x, const std::uint32_t y) {
        return plane[static_cast<std::size_t>(y) * width + x] < threshold;
    };
    std::vector<std::uint8_t> margin(excluded.size(), 0U);
    std::queue<std::pair<std::uint32_t, std::uint32_t>> pending{};
    const auto seed = [&](const std::uint32_t x, const std::uint32_t y) {
        const std::size_t index = static_cast<std::size_t>(y) * width + x;
        if (margin[index] == 0U && dark(x, y)) {
            margin[index] = 1U;
            pending.emplace(x, y);
        }
    };
    for (std::uint32_t x = 0U; x < width; ++x) {
        seed(x, 0U);
        seed(x, height - 1U);
    }
    for (std::uint32_t y = 0U; y < height; ++y) {
        seed(0U, y);
        seed(width - 1U, y);
    }
    while (!pending.empty()) {
        const auto [x, y] = pending.front();
        pending.pop();
        if (x > 0U) seed(x - 1U, y);
        if (x + 1U < width) seed(x + 1U, y);
        if (y > 0U) seed(x, y - 1U);
        if (y + 1U < height) seed(x, y + 1U);
    }
    if (rim == 0U) {
        for (std::size_t index = 0U; index < excluded.size(); ++index) {
            excluded[index] = excluded[index] != 0U || margin[index] != 0U ? 1U : 0U;
        }
        return;
    }
    std::vector<std::uint8_t> horizontal(margin.size(), 0U);
    for (std::uint32_t y = 0U; y < height; ++y) {
        std::uint32_t active = 0U;
        for (std::uint32_t x = 0U; x <= std::min(rim, width - 1U); ++x) {
            active += margin[static_cast<std::size_t>(y) * width + x];
        }
        for (std::uint32_t x = 0U; x < width; ++x) {
            horizontal[static_cast<std::size_t>(y) * width + x] = active != 0U ? 1U : 0U;
            if (x + rim + 1U < width) {
                active += margin[static_cast<std::size_t>(y) * width + x + rim + 1U];
            }
            if (x >= rim) {
                active -= margin[static_cast<std::size_t>(y) * width + x - rim];
            }
        }
    }
    for (std::uint32_t x = 0U; x < width; ++x) {
        std::uint32_t active = 0U;
        for (std::uint32_t y = 0U; y <= std::min(rim, height - 1U); ++y) {
            active += horizontal[static_cast<std::size_t>(y) * width + x];
        }
        for (std::uint32_t y = 0U; y < height; ++y) {
            const std::size_t index = static_cast<std::size_t>(y) * width + x;
            if (active != 0U) excluded[index] = 1U;
            if (y + rim + 1U < height) {
                active += horizontal[static_cast<std::size_t>(y + rim + 1U) * width + x];
            }
            if (y >= rim) {
                active -= horizontal[static_cast<std::size_t>(y - rim) * width + x];
            }
        }
    }
}

[[nodiscard]] std::vector<float> optical_density(
    const std::span<const float> plane,
    const std::span<const float> baseline) {
    std::vector<float> density(plane.size(), 0.0F);
    for (std::size_t index = 0U; index < plane.size(); ++index) {
        const float value = std::max(plane[index], kPlaneFloor);
        const float base = std::max(baseline[index], kPlaneFloor);
        if (base > value) {
            density[index] = std::log(base / value);
        }
    }
    return density;
}

[[nodiscard]] SignalStatistics signal_statistics(
    const std::span<const float> density,
    const std::vector<std::uint8_t>& excluded,
    const double sensitivity) {
    std::vector<float> samples{};
    const std::size_t step = std::max<std::size_t>(1U, density.size() / 200000U);
    samples.reserve(density.size() / step + 1U);
    for (std::size_t index = 0U; index < density.size(); index += step) {
        if (excluded[index] == 0U) {
            samples.push_back(density[index]);
        }
    }
    if (samples.size() <= 256U) {
        return {};
    }
    std::sort(samples.begin(), samples.end());
    const auto at = [&](const double q) {
        return samples[static_cast<std::size_t>(
            q * static_cast<double>(samples.size() - 1U))];
    };
    const float floor = at(0.5);
    const float sigma = std::max((at(0.75) - floor) / 0.6745F, 0.0F);
    const float multiplier = static_cast<float>(19.0 - 11.0 * sensitivity);
    return SignalStatistics{
        floor,
        sigma,
        std::max(floor + multiplier * sigma, floor + 1.0e-3F)};
}

[[nodiscard]] std::vector<RawComponent> label_components(
    const std::vector<std::uint8_t>& mask,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::size_t minimum_area) {
    std::vector<RawComponent> result{};
    std::vector<std::uint8_t> visited(mask.size(), 0U);
    std::vector<std::size_t> pending{};
    for (std::size_t seed = 0U; seed < mask.size(); ++seed) {
        if (mask[seed] == 0U || visited[seed] != 0U) continue;
        RawComponent component{};
        const auto seed_x = static_cast<std::uint32_t>(seed % width);
        const auto seed_y = static_cast<std::uint32_t>(seed / width);
        component.min_x = component.max_x = seed_x;
        component.min_y = component.max_y = seed_y;
        pending.clear();
        pending.push_back(seed);
        visited[seed] = 1U;
        while (!pending.empty()) {
            const std::size_t pixel = pending.back();
            pending.pop_back();
            component.pixels.push_back(pixel);
            const auto x = static_cast<std::uint32_t>(pixel % width);
            const auto y = static_cast<std::uint32_t>(pixel / width);
            component.min_x = std::min(component.min_x, x);
            component.max_x = std::max(component.max_x, x);
            component.min_y = std::min(component.min_y, y);
            component.max_y = std::max(component.max_y, y);
            const auto visit = [&](const std::size_t next) {
                if (mask[next] != 0U && visited[next] == 0U) {
                    visited[next] = 1U;
                    pending.push_back(next);
                }
            };
            if (x > 0U) visit(pixel - 1U);
            if (x + 1U < width) visit(pixel + 1U);
            if (y > 0U) visit(pixel - width);
            if (y + 1U < height) visit(pixel + width);
            if (x > 0U && y > 0U) visit(pixel - width - 1U);
            if (x + 1U < width && y > 0U) visit(pixel - width + 1U);
            if (x > 0U && y + 1U < height) visit(pixel + width - 1U);
            if (x + 1U < width && y + 1U < height) visit(pixel + width + 1U);
        }
        if (component.pixels.size() >= minimum_area) {
            component.source_area = component.pixels.size();
            result.push_back(std::move(component));
        }
    }
    return result;
}

[[nodiscard]] RawComponent fill_component_holes(
    RawComponent component,
    const std::uint32_t width) {
    const std::uint32_t box_width = component.max_x - component.min_x + 1U;
    const std::uint32_t box_height = component.max_y - component.min_y + 1U;
    const std::size_t box_area = static_cast<std::size_t>(box_width) * box_height;
    if (box_width < 3U || box_height < 3U || box_area > 512U * 512U ||
        box_area > component.pixels.size() * 64U) {
        return component;
    }
    std::vector<std::uint8_t> local(box_area, 0U);
    for (const std::size_t pixel : component.pixels) {
        const std::uint32_t x = static_cast<std::uint32_t>(pixel % width) - component.min_x;
        const std::uint32_t y = static_cast<std::uint32_t>(pixel / width) - component.min_y;
        local[static_cast<std::size_t>(y) * box_width + x] = 1U;
    }
    std::vector<std::uint8_t> outside(box_area, 0U);
    std::vector<std::size_t> pending{};
    const auto push = [&](const std::size_t index) {
        if (local[index] == 0U && outside[index] == 0U) {
            outside[index] = 1U;
            pending.push_back(index);
        }
    };
    for (std::uint32_t x = 0U; x < box_width; ++x) {
        push(x);
        push(static_cast<std::size_t>(box_height - 1U) * box_width + x);
    }
    for (std::uint32_t y = 0U; y < box_height; ++y) {
        push(static_cast<std::size_t>(y) * box_width);
        push(static_cast<std::size_t>(y) * box_width + box_width - 1U);
    }
    while (!pending.empty()) {
        const std::size_t index = pending.back();
        pending.pop_back();
        const std::uint32_t x = static_cast<std::uint32_t>(index % box_width);
        const std::uint32_t y = static_cast<std::uint32_t>(index / box_width);
        if (x > 0U) push(index - 1U);
        if (x + 1U < box_width) push(index + 1U);
        if (y > 0U) push(index - box_width);
        if (y + 1U < box_height) push(index + box_width);
    }
    for (std::size_t index = 0U; index < box_area; ++index) {
        if (local[index] == 0U && outside[index] == 0U) {
            const std::uint32_t x = static_cast<std::uint32_t>(index % box_width) +
                component.min_x;
            const std::uint32_t y = static_cast<std::uint32_t>(index / box_width) +
                component.min_y;
            component.pixels.push_back(static_cast<std::size_t>(y) * width + x);
        }
    }
    return component;
}

[[nodiscard]] double weighted_score(
    const RawComponent& component,
    const std::span<const float> weights,
    const std::span<const float> visible,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::int32_t dx,
    const std::int32_t dy) {
    double score = 0.0;
    for (std::size_t ordinal = 0U; ordinal < component.pixels.size(); ++ordinal) {
        const std::size_t pixel = component.pixels[ordinal];
        const auto x = static_cast<std::int32_t>(pixel % width) + dx;
        const auto y = static_cast<std::int32_t>(pixel / width) + dy;
        if (x >= 0 && y >= 0 && x < static_cast<std::int32_t>(width) &&
            y < static_cast<std::int32_t>(height)) {
            score += static_cast<double>(weights[ordinal]) *
                visible[static_cast<std::size_t>(y) * width +
                    static_cast<std::uint32_t>(x)];
        }
    }
    return score;
}

[[nodiscard]] float selection_bias(const float significance) noexcept {
    const double x = static_cast<double>(kMinimumSignificance - significance);
    const double density = std::exp(-0.5 * x * x) /
        std::sqrt(2.0 * kPi);
    const double tail = 0.5 * std::erfc(x / std::sqrt(2.0));
    return tail > 1.0e-12 ? static_cast<float>(density / tail) : 0.0F;
}

[[nodiscard]] bool confirm_component(
    const RawComponent& component,
    const std::span<const float> density,
    const std::span<const float> visible,
    const std::uint32_t width,
    const std::uint32_t height,
    const float magnitude_floor,
    const std::int32_t search,
    const std::int32_t origin_x,
    const std::int32_t origin_y,
    ConfirmedDefect& confirmed) {
    std::vector<float> weights(component.pixels.size(), 0.0F);
    double square_sum = 0.0;
    for (std::size_t ordinal = 0U; ordinal < component.pixels.size(); ++ordinal) {
        const float weight = std::max(0.0F, density[component.pixels[ordinal]] - magnitude_floor);
        weights[ordinal] = weight;
        square_sum += static_cast<double>(weight) * weight;
    }
    if (!(square_sum > 0.0)) return false;

    double best = -std::numeric_limits<double>::infinity();
    std::int32_t best_x = 0;
    std::int32_t best_y = 0;
    for (std::int32_t dy = -search; dy <= search; ++dy) {
        for (std::int32_t dx = -search; dx <= search; ++dx) {
            const double score = weighted_score(
                component, weights, visible, width, height,
                dx + origin_x, dy + origin_y);
            if (score > best) {
                best = score;
                best_x = dx;
                best_y = dy;
            }
        }
    }
    if (!(best > 0.0)) return false;

    const auto extent = static_cast<std::int32_t>(
        std::min(component.max_x - component.min_x,
                 component.max_y - component.min_y) / 2U + 1U);
    const std::int32_t null_inner = 2 * extent + 2;
    std::vector<double> null_samples{};
    null_samples.reserve(static_cast<std::size_t>(2 * search + 1) *
                         static_cast<std::size_t>(2 * search + 1));
    for (std::int32_t dy = -search; dy <= search; ++dy) {
        for (std::int32_t dx = -search; dx <= search; ++dx) {
            if (std::max(std::abs(dx), std::abs(dy)) >= null_inner) {
                null_samples.push_back(weighted_score(
                    component, weights, visible, width, height,
                    dx + origin_x, dy + origin_y));
            }
        }
    }
    for (std::int32_t radius = std::max(null_inner, search + 1);
         null_samples.size() < kMinimumNullSamples && radius <=
             std::max(null_inner, search + 1) + 2 * extent + 8;
         ++radius) {
        for (std::int32_t dy = -radius; dy <= radius; ++dy) {
            const std::int32_t step = std::abs(dy) == radius ? 1 : 2 * radius;
            for (std::int32_t dx = -radius; dx <= radius; dx += step) {
                null_samples.push_back(weighted_score(
                    component, weights, visible, width, height,
                    dx + origin_x, dy + origin_y));
            }
        }
    }
    if (null_samples.size() < kMinimumNullSamples) return false;
    std::sort(null_samples.begin(), null_samples.end());
    const double center = null_samples[null_samples.size() / 2U];
    std::vector<double> deviations(null_samples.size(), 0.0);
    std::transform(null_samples.begin(), null_samples.end(), deviations.begin(),
                   [center](const double value) { return std::abs(value - center); });
    std::sort(deviations.begin(), deviations.end());
    const double deviation = 1.4826 * deviations[deviations.size() / 2U];
    const float significance = deviation > 0.0
        ? static_cast<float>((best - center) / deviation)
        : std::numeric_limits<float>::max();
    if (significance < kMinimumSignificance) return false;
    const double signal = best - static_cast<double>(selection_bias(significance)) * deviation - center;
    if (!(signal > 0.0)) return false;
    const float gain = static_cast<float>(signal / square_sum);
    if (!std::isfinite(gain) || gain <= 0.0F) return false;
    confirmed = ConfirmedDefect{
        best_x + origin_x,
        best_y + origin_y,
        std::clamp(gain, 0.2F, 4.0F),
        significance};
    return true;
}

[[nodiscard]] InfraredDetectedComponent summarize_component(
    const RawComponent& component,
    const std::span<const std::size_t> correction_pixels,
    const std::span<const float> attenuation,
    const std::uint32_t width) {
    double sum_x = 0.0;
    double sum_y = 0.0;
    double attenuation_sum = 0.0;
    for (const std::size_t pixel : component.pixels) {
        sum_x += static_cast<double>(pixel % width);
        sum_y += static_cast<double>(pixel / width);
        attenuation_sum += attenuation[pixel];
    }
    const double count = static_cast<double>(component.pixels.size());
    const double mean_x = sum_x / count;
    const double mean_y = sum_y / count;
    double covariance_xx = 0.0;
    double covariance_yy = 0.0;
    double covariance_xy = 0.0;
    for (const std::size_t pixel : component.pixels) {
        const double dx = static_cast<double>(pixel % width) - mean_x;
        const double dy = static_cast<double>(pixel / width) - mean_y;
        covariance_xx += dx * dx;
        covariance_yy += dy * dy;
        covariance_xy += dx * dy;
    }
    covariance_xx /= count;
    covariance_yy /= count;
    covariance_xy /= count;
    const double trace = covariance_xx + covariance_yy;
    const double determinant = covariance_xx * covariance_yy - covariance_xy * covariance_xy;
    const double discriminant = std::max(0.0, trace * trace / 4.0 - determinant);
    const double first_eigenvalue = trace / 2.0 + std::sqrt(discriminant);
    const double second_eigenvalue = std::max(1.0e-6, trace / 2.0 - std::sqrt(discriminant));
    const double elongation = std::sqrt(first_eigenvalue / second_eigenvalue);
    const std::uint32_t span = std::max(
        component.max_x - component.min_x,
        component.max_y - component.min_y) + 1U;

    InfraredDetectedComponent summary{};
    if (elongation >= 3.5 && span >= 16U) {
        const double angle = std::abs(0.5 * std::atan2(
            2.0 * covariance_xy, covariance_xx - covariance_yy) * 180.0 / kPi);
        if (angle <= 30.0) summary.classification = InfraredDefectClass::scratch_horizontal;
        else if (angle >= 60.0) summary.classification = InfraredDefectClass::scratch_vertical;
        else summary.classification = InfraredDefectClass::scratch_diagonal;
    }
    summary.confidence = std::clamp(
        attenuation_sum / count / static_cast<double>(kCoreCut), 0.3, 0.98);
    summary.area = component.pixels.size();
    constexpr std::size_t kMaximumPreviewPoints = 240U;
    const std::size_t step = std::max<std::size_t>(
        1U, correction_pixels.size() / kMaximumPreviewPoints);
    for (std::size_t ordinal = 0U; ordinal < correction_pixels.size(); ordinal += step) {
        const std::size_t pixel = correction_pixels[ordinal];
        summary.preview_points.push_back({
            static_cast<std::uint32_t>(pixel % width),
            static_cast<std::uint32_t>(pixel / width)});
    }
    return summary;
}

[[nodiscard]] std::vector<InfraredCorrectionCluster> render_clusters(
    const std::span<const float> attenuation,
    const std::vector<std::size_t>& core_pixels,
    const float threshold,
    const std::uint32_t width,
    const std::uint32_t height,
    const InfraredDetectorParameters& parameters) {
    const std::uint32_t tile = static_cast<std::uint32_t>(parameters.cluster_tile);
    const std::uint32_t padding = static_cast<std::uint32_t>(parameters.cluster_padding);
    const std::uint32_t columns = std::max(1U, (width + tile - 1U) / tile);
    const std::uint32_t rows = std::max(1U, (height + tile - 1U) / tile);
    std::vector<std::uint8_t> touched(static_cast<std::size_t>(columns) * rows, 0U);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            if (attenuation[static_cast<std::size_t>(y) * width + x] >= threshold) {
                touched[static_cast<std::size_t>(y / tile) * columns + x / tile] = 1U;
            }
        }
    }
    std::vector<InfraredCorrectionCluster> clusters{};
    for (std::uint32_t key = 0U; key < touched.size(); ++key) {
        if (touched[key] == 0U) continue;
        const std::uint32_t column = key % columns;
        const std::uint32_t row = key / columns;
        const std::uint32_t x0 = column * tile > padding ? column * tile - padding : 0U;
        const std::uint32_t y0 = row * tile > padding ? row * tile - padding : 0U;
        const std::uint32_t x1 = std::min(width, (column + 1U) * tile + padding);
        const std::uint32_t y1 = std::min(height, (row + 1U) * tile + padding);
        InfraredCorrectionCluster cluster{};
        cluster.roi_x = x0;
        cluster.roi_y_up = height - y1;
        cluster.width = x1 - x0;
        cluster.height = y1 - y0;
        const std::size_t cluster_area = static_cast<std::size_t>(cluster.width) * cluster.height;
        cluster.core_mask.assign(cluster_area * 4U, 0U);
        cluster.attenuation_r16.assign(cluster_area, 0U);
        for (std::uint32_t y = y0; y < y1; ++y) {
            for (std::uint32_t x = x0; x < x1; ++x) {
                const std::size_t source = static_cast<std::size_t>(y) * width + x;
                const std::size_t target = static_cast<std::size_t>(y - y0) * cluster.width + x - x0;
                cluster.attenuation_r16[target] = static_cast<std::uint16_t>(std::lround(
                    std::clamp(attenuation[source], 0.0F, 1.0F) * 65535.0F));
            }
        }
        const auto dilate = static_cast<std::uint32_t>(parameters.dilate_radius);
        for (const std::size_t pixel : core_pixels) {
            const std::uint32_t px = static_cast<std::uint32_t>(pixel % width);
            const std::uint32_t py = static_cast<std::uint32_t>(pixel / width);
            const std::uint32_t sx0 = px > dilate ? px - dilate : 0U;
            const std::uint32_t sy0 = py > dilate ? py - dilate : 0U;
            const std::uint32_t sx1 = std::min(width - 1U, px + dilate);
            const std::uint32_t sy1 = std::min(height - 1U, py + dilate);
            for (std::uint32_t y = std::max(y0, sy0); y <= std::min(y1 - 1U, sy1); ++y) {
                for (std::uint32_t x = std::max(x0, sx0); x <= std::min(x1 - 1U, sx1); ++x) {
                    const std::size_t local = static_cast<std::size_t>(y - y0) * cluster.width + x - x0;
                    std::fill_n(
                        cluster.core_mask.begin() + static_cast<std::ptrdiff_t>(local * 4U),
                        4U,
                        static_cast<std::uint8_t>(255U));
                }
            }
        }
        clusters.push_back(std::move(cluster));
    }
    return clusters;
}

}  // namespace

InfraredDetectorParameters sanitize_infrared_detector_parameters(
    const InfraredDetectorParameters& parameters,
    const std::uint32_t width,
    const std::uint32_t height) noexcept {
    const auto maximum = static_cast<std::int32_t>(
        std::min<std::uint32_t>(std::max(width, height),
                                static_cast<std::uint32_t>(std::numeric_limits<std::int32_t>::max())));
    InfraredDetectorParameters result{};
    result.sensitivity = std::isfinite(parameters.sensitivity)
        ? std::clamp(parameters.sensitivity, 0.0, 1.0) : 0.5;
    result.dilate_radius = std::clamp(parameters.dilate_radius, 0, maximum);
    result.minimum_area = std::max(parameters.minimum_area, 1);
    result.maximum_coverage = std::isfinite(parameters.maximum_coverage)
        ? std::clamp(parameters.maximum_coverage, 0.0, 1.0) : 0.05;
    result.alignment_search_radius = std::clamp(parameters.alignment_search_radius, 0, maximum);
    result.cluster_tile = std::clamp(parameters.cluster_tile, 1, std::max(maximum, 1));
    result.cluster_padding = std::clamp(parameters.cluster_padding, 0, maximum);
    return result;
}

InfraredDetectionResult detect_infrared_defects(
    const std::span<const float> infrared,
    const std::span<const float> red,
    const std::uint32_t width,
    const std::uint32_t height,
    const InfraredDetectorParameters& raw_parameters,
    const negaflow::core::CancelFlag cancel) noexcept {
    InfraredDetectionResult result{};
    try {
        std::size_t area = 0U;
        if (!checked_area(width, height, area) || infrared.size() != area || red.size() != area ||
            !std::all_of(infrared.begin(), infrared.end(), [](float value) { return std::isfinite(value); }) ||
            !std::all_of(red.begin(), red.end(), [](float value) { return std::isfinite(value); })) {
            result.status = InfraredDetectionStatus::unreadable;
            return result;
        }
        if (width < 64U || height < 64U) {
            result.status = InfraredDetectionStatus::too_small;
            return result;
        }
        if (cancel.requested()) {
            result.status = InfraredDetectionStatus::cancelled;
            return result;
        }
        const InfraredDetectorParameters parameters =
            sanitize_infrared_detector_parameters(raw_parameters, width, height);
        result.detection.width = width;
        result.detection.height = height;
        std::vector<std::uint8_t> excluded(area, 0U);
        result.detection.alignment = estimate_alignment(
            infrared, red, width, height,
            static_cast<std::uint32_t>(parameters.alignment_search_radius));
        const bool seed_trusted =
            result.detection.alignment.status == InfraredAlignmentStatus::not_requested ||
            result.detection.alignment.status == InfraredAlignmentStatus::aligned;
        const std::int32_t seed_x = seed_trusted ? result.detection.alignment.offset_x : 0;
        const std::int32_t seed_y = seed_trusted ? result.detection.alignment.offset_y : 0;
        result.detection.offset_x = seed_x;
        result.detection.offset_y = seed_y;
        auto aligned_infrared = shift_plane(
            infrared, width, height, seed_x, seed_y, excluded);
        const float p95 = percentile(aligned_infrared, excluded, 0.95);
        if (!(p95 > 1.0e-4F)) {
            result.status = InfraredDetectionStatus::unreadable;
            return result;
        }
        const std::uint32_t rim = std::max(4U, std::min(24U, std::min(width, height) / 200U));
        exclude_border_dark(aligned_infrared, width, height, p95 * 0.2F, rim, excluded);
        if (cancel.requested()) {
            result.status = InfraredDetectionStatus::cancelled;
            return result;
        }

        const std::uint32_t radius = std::max(4U, std::min(96U, std::min(width, height) / 100U));
        auto ir_baseline = grain_mend_detail::closing(aligned_infrared, width, height, radius);
        auto density = optical_density(aligned_infrared, ir_baseline);
        ir_baseline.clear();
        const SignalStatistics statistics = signal_statistics(density, excluded, parameters.sensitivity);
        const float excess = statistics.threshold - statistics.floor;
        std::vector<std::uint8_t> candidate_mask(area, 0U);
        for (std::size_t index = 0U; index < area; ++index) {
            if (excluded[index] == 0U && density[index] >= statistics.floor + 0.5F * excess) {
                candidate_mask[index] = 1U;
            }
        }
        auto candidates = label_components(
            candidate_mask, width, height, static_cast<std::size_t>(parameters.minimum_area));
        candidates.erase(
            std::remove_if(candidates.begin(), candidates.end(), [&](const RawComponent& component) {
                double sum = 0.0;
                for (const std::size_t pixel : component.pixels) {
                    sum += static_cast<double>(density[pixel] - statistics.floor);
                }
                return sum < static_cast<double>(excess) *
                    std::sqrt(static_cast<double>(component.pixels.size()));
            }),
            candidates.end());
        result.detection.candidate_count = candidates.size();
        if (candidates.empty()) {
            result.status = InfraredDetectionStatus::no_defects;
            return result;
        }

        const std::vector<float> red_copy(red.begin(), red.end());
        auto visible_baseline = grain_mend_detail::closing(red_copy, width, height, radius);
        auto visible = optical_density(red, visible_baseline);
        visible_baseline.clear();
        const float visible_floor = signal_statistics(visible, excluded, parameters.sensitivity).floor;
        for (float& value : visible) value -= visible_floor;

        std::vector<ConfirmedCandidate> confirmed{};
        std::int32_t consensus_x = 0;
        std::int32_t consensus_y = 0;
        const std::int32_t coarse_search =
            std::max(4, std::min(20, parameters.alignment_search_radius));
        if (!seed_trusted && coarse_search > 4) {
            std::vector<std::size_t> order(candidates.size(), 0U);
            std::iota(order.begin(), order.end(), 0U);
            std::sort(order.begin(), order.end(), [&](const std::size_t a, const std::size_t b) {
                return candidates[a].source_area > candidates[b].source_area;
            });
            std::vector<std::int32_t> votes_x{};
            std::vector<std::int32_t> votes_y{};
            const std::size_t vote_count = std::min<std::size_t>(64U, order.size());
            votes_x.reserve(vote_count);
            votes_y.reserve(vote_count);
            for (std::size_t ordinal = 0U; ordinal < vote_count; ++ordinal) {
                RawComponent candidate = fill_component_holes(candidates[order[ordinal]], width);
                const auto extent = static_cast<std::int32_t>(
                    std::min(candidate.max_x - candidate.min_x,
                             candidate.max_y - candidate.min_y) / 2U + 1U);
                ConfirmedDefect vote{};
                if (confirm_component(candidate, density, visible, width, height,
                                      statistics.floor, coarse_search + extent, 0, 0, vote)) {
                    votes_x.push_back(vote.offset_x);
                    votes_y.push_back(vote.offset_y);
                }
            }
            if (votes_x.size() >= 8U) {
                std::sort(votes_x.begin(), votes_x.end());
                std::sort(votes_y.begin(), votes_y.end());
                consensus_x = votes_x[votes_x.size() / 2U];
                consensus_y = votes_y[votes_y.size() / 2U];
            }
            if (cancel.requested()) {
                result.status = InfraredDetectionStatus::cancelled;
                return result;
            }
        }
        result.detection.offset_x = seed_x + consensus_x;
        result.detection.offset_y = seed_y + consensus_y;
        const std::int32_t residual = std::max(4, std::min(8, parameters.alignment_search_radius));
        for (RawComponent& component : candidates) {
            if (cancel.requested()) {
                result.status = InfraredDetectionStatus::cancelled;
                return result;
            }
            RawComponent filled = fill_component_holes(component, width);
            const auto extent = static_cast<std::int32_t>(
                std::min(component.max_x - component.min_x,
                         component.max_y - component.min_y) / 2U + 1U);
            ConfirmedDefect match{};
            if (confirm_component(filled, density, visible, width, height,
                                  statistics.floor, std::min<int>(radius + residual, residual + extent + 3),
                                  consensus_x, consensus_y, match)) {
                confirmed.push_back(ConfirmedCandidate{
                    std::move(component), std::move(filled.pixels), match});
            }
        }
        result.detection.confirmed_count = confirmed.size();
        if (confirmed.empty()) {
            result.status = InfraredDetectionStatus::no_defects;
            return result;
        }

        std::vector<float> gains{};
        gains.reserve(confirmed.size());
        for (const auto& item : confirmed) gains.push_back(item.match.gain);
        std::sort(gains.begin(), gains.end());
        const float median_gain = gains[gains.size() / 2U];
        std::vector<float> deviations(gains.size(), 0.0F);
        std::transform(gains.begin(), gains.end(), deviations.begin(),
                       [median_gain](float gain) { return std::abs(gain - median_gain); });
        std::sort(deviations.begin(), deviations.end());
        const float gain_ceiling = median_gain + 2.0F * deviations[deviations.size() / 2U];
        result.detection.median_gain = median_gain;

        std::vector<float> attenuation(area, 0.0F);
        std::vector<std::size_t> core_pixels{};
        std::vector<std::uint8_t> visited(area, 0U);
        std::vector<std::size_t> frontier{};
        std::vector<std::size_t> reached{};
        for (const ConfirmedCandidate& candidate : confirmed) {
            const RawComponent& component = candidate.component;
            const ConfirmedDefect& match = candidate.match;
            const float gain = std::min(match.gain, gain_ceiling);
            const std::uint32_t x0 = component.min_x > radius ? component.min_x - radius : 0U;
            const std::uint32_t y0 = component.min_y > radius ? component.min_y - radius : 0U;
            const std::uint32_t x1 = std::min(width - 1U, component.max_x + radius);
            const std::uint32_t y1 = std::min(height - 1U, component.max_y + radius);
            frontier = candidate.correction_pixels;
            reached = candidate.correction_pixels;
            for (const std::size_t pixel : candidate.correction_pixels) visited[pixel] = 1U;
            while (!frontier.empty()) {
                const std::size_t pixel = frontier.back();
                frontier.pop_back();
                const std::uint32_t x = static_cast<std::uint32_t>(pixel % width);
                const std::uint32_t y = static_cast<std::uint32_t>(pixel / width);
                const auto visit = [&](const std::uint32_t next_x, const std::uint32_t next_y) {
                    if (next_x < x0 || next_x > x1 || next_y < y0 || next_y > y1) return;
                    const std::size_t next = static_cast<std::size_t>(next_y) * width + next_x;
                    if (visited[next] == 0U && density[next] > statistics.skirt_floor()) {
                        visited[next] = 1U;
                        frontier.push_back(next);
                        reached.push_back(next);
                    }
                };
                if (x > x0) visit(x - 1U, y);
                if (x < x1) visit(x + 1U, y);
                if (y > y0) visit(x, y - 1U);
                if (y < y1) visit(x, y + 1U);
            }
            for (const std::size_t pixel : reached) {
                visited[pixel] = 0U;
                const float value = density[pixel] - statistics.floor;
                if (!(value > 0.0F)) continue;
                const auto target_x = static_cast<std::int32_t>(pixel % width) + match.offset_x;
                const auto target_y = static_cast<std::int32_t>(pixel / width) + match.offset_y;
                if (target_x < 0 || target_y < 0 || target_x >= static_cast<std::int32_t>(width) ||
                    target_y >= static_cast<std::int32_t>(height)) continue;
                const float occlusion = std::min(0.98F, 1.0F - std::exp(-gain * value));
                const std::size_t target = static_cast<std::size_t>(target_y) * width +
                    static_cast<std::uint32_t>(target_x);
                attenuation[target] = std::max(attenuation[target], occlusion);
            }
        }
        const float significant_cut = std::max(
            1.0F - std::exp(-3.0F * statistics.sigma), 0.002F);
        std::size_t significant = 0U;
        for (std::size_t index = 0U; index < attenuation.size(); ++index) {
            if (attenuation[index] >= significant_cut) ++significant;
            if (attenuation[index] >= kCoreCut) core_pixels.push_back(index);
        }
        const std::size_t excluded_count = std::accumulate(
            excluded.begin(), excluded.end(), std::size_t{0U});
        const std::size_t valid_area = std::max<std::size_t>(1U, area - excluded_count);
        result.detection.coverage = static_cast<double>(significant) /
            static_cast<double>(valid_area);
        if (result.detection.coverage > parameters.maximum_coverage) {
            result.status = InfraredDetectionStatus::coverage_too_high;
            return result;
        }
        result.detection.components.reserve(confirmed.size());
        for (const ConfirmedCandidate& candidate : confirmed) {
            result.detection.components.push_back(summarize_component(
                candidate.component,
                candidate.correction_pixels,
                attenuation,
                width));
        }
        result.detection.clusters = render_clusters(
            attenuation, core_pixels, significant_cut, width, height, parameters);
        if (result.detection.clusters.empty()) {
            result.status = InfraredDetectionStatus::no_defects;
            return result;
        }
        result.status = InfraredDetectionStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.status = InfraredDetectionStatus::allocation_failed;
        return result;
    } catch (...) {
        result.status = InfraredDetectionStatus::unreadable;
        return result;
    }
}

const char* infrared_detection_status_name(const InfraredDetectionStatus status) noexcept {
    switch (status) {
        case InfraredDetectionStatus::ok: return "ok";
        case InfraredDetectionStatus::unreadable: return "unreadable";
        case InfraredDetectionStatus::too_small: return "too_small";
        case InfraredDetectionStatus::no_defects: return "no_defects";
        case InfraredDetectionStatus::coverage_too_high: return "coverage_too_high";
        case InfraredDetectionStatus::cancelled: return "cancelled";
        case InfraredDetectionStatus::allocation_failed: return "allocation_failed";
    }
    return "unknown";
}

}  // namespace negaflow::imaging
