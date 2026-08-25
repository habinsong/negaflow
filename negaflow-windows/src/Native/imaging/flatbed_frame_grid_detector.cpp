#include "negaflow/imaging/flatbed_frame_grid_detector.h"

#include "flatbed_frame_bands.h"
#include "flatbed_frame_grid_fit.h"
#include "flatbed_frame_grid_types.h"
#include "flatbed_frame_profiles.h"
#include "flatbed_frame_signal.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <numbers>
#include <numeric>
#include <optional>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

using namespace negaflow::imaging::flatbed_detail;

[[nodiscard]] bool valid_preview(const FlatbedFramePreview& preview) noexcept {
    if (preview.width <= 32U || preview.height <= 32U ||
        !std::isfinite(preview.physical_width_mm) || !std::isfinite(preview.physical_height_mm) ||
        preview.physical_width_mm <= 0.0 || preview.physical_height_mm <= 0.0 ||
        preview.luminance.size() != static_cast<std::size_t>(preview.width) * preview.height) {
        return false;
    }
    return std::all_of(preview.luminance.begin(), preview.luminance.end(), [](const float value) {
        return std::isfinite(value) && value >= 0.0F && value <= 1.0F;
    });
}

struct EdgeImage final {
    std::vector<std::uint8_t> pixels{};
    int width{0};
    int height{0};
};

struct IntRange final {
    int first{0};
    int last{0};  // exclusive

    [[nodiscard]] int count() const noexcept { return last - first; }
};

struct EdgeStrip final {
    IntRange aperture{};
    std::vector<int> boundaries{};
    double angle{0.0};
    double confidence{0.0};
};

struct EdgeRect final {
    int x{0};
    int y{0};
    int width{0};
    int height{0};
};

[[nodiscard]] std::optional<double> robust_slope(
    const std::vector<std::pair<double, double>>& samples);

[[nodiscard]] bool valid_edge_preview(const FlatbedFramePreview& preview) noexcept {
    if (preview.width < 48U || preview.height < 48U ||
        preview.width > static_cast<std::uint32_t>(std::numeric_limits<int>::max()) ||
        preview.height > static_cast<std::uint32_t>(std::numeric_limits<int>::max()) ||
        preview.luminance.size() != static_cast<std::size_t>(preview.width) * preview.height) {
        return false;
    }
    return std::all_of(preview.luminance.begin(), preview.luminance.end(), [](const float value) {
        return std::isfinite(value) && value >= 0.0F && value <= 1.0F;
    });
}

[[nodiscard]] EdgeImage make_edge_image(const FlatbedFramePreview& preview) {
    EdgeImage image{};
    image.width = static_cast<int>(preview.width);
    image.height = static_cast<int>(preview.height);
    image.pixels.resize(preview.luminance.size());
    std::transform(
        preview.luminance.begin(), preview.luminance.end(), image.pixels.begin(),
        [](const float value) {
            return static_cast<std::uint8_t>(std::clamp(
                std::lround(static_cast<double>(value) * 255.0), 0L, 255L));
        });
    return image;
}

[[nodiscard]] double median(std::vector<double> values) {
    if (values.empty()) return 0.0;
    std::sort(values.begin(), values.end());
    const std::size_t middle = values.size() / 2U;
    return values.size() % 2U == 0U
        ? (values[middle - 1U] + values[middle]) * 0.5
        : values[middle];
}

[[nodiscard]] std::uint8_t border_background(const EdgeImage& image) {
    const int stride = std::max(1, std::min(image.width, image.height) / 128);
    std::vector<double> values{};
    values.reserve(static_cast<std::size_t>((image.width + image.height) / stride) * 2U);
    for (int x = 0; x < image.width; x += stride) {
        values.push_back(image.pixels[static_cast<std::size_t>(x)]);
        values.push_back(image.pixels[
            static_cast<std::size_t>(image.height - 1) * image.width + x]);
    }
    for (int y = stride; y < image.height - 1; y += stride) {
        values.push_back(image.pixels[static_cast<std::size_t>(y) * image.width]);
        values.push_back(image.pixels[
            static_cast<std::size_t>(y) * image.width + image.width - 1]);
    }
    return static_cast<std::uint8_t>(std::clamp(std::lround(median(values)), 0L, 255L));
}

[[nodiscard]] double background_threshold(
    const EdgeImage& image,
    const std::uint8_t background) {
    const int stride = std::max(1, std::min(image.width, image.height) / 128);
    std::vector<double> distances{};
    for (int x = 0; x < image.width; x += stride) {
        distances.push_back(std::abs(static_cast<int>(image.pixels[x]) - background));
        distances.push_back(std::abs(static_cast<int>(image.pixels[
            static_cast<std::size_t>(image.height - 1) * image.width + x])) - background);
    }
    for (int y = stride; y < image.height - 1; y += stride) {
        distances.push_back(std::abs(static_cast<int>(image.pixels[
            static_cast<std::size_t>(y) * image.width]) - background));
        distances.push_back(std::abs(static_cast<int>(image.pixels[
            static_cast<std::size_t>(y) * image.width + image.width - 1]) - background));
    }
    return std::max(12.0, median(std::move(distances)) * 3.0 + 6.0);
}

[[nodiscard]] std::optional<EdgeRect> foreground_bounds(const EdgeImage& image) {
    const std::uint8_t background = border_background(image);
    const double threshold = background_threshold(image, background);
    const int block = std::max(2, std::max(image.width, image.height) / 512);
    int minimum_x = image.width;
    int minimum_y = image.height;
    int maximum_x = 0;
    int maximum_y = 0;
    int active_blocks = 0;
    for (int block_y = 0; block_y < image.height; block_y += block) {
        const int block_maximum_y = std::min(image.height, block_y + block);
        for (int block_x = 0; block_x < image.width; block_x += block) {
            const int block_maximum_x = std::min(image.width, block_x + block);
            const int sample_count =
                (block_maximum_x - block_x) * (block_maximum_y - block_y);
            int different = 0;
            for (int y = block_y; y < block_maximum_y; ++y) {
                for (int x = block_x; x < block_maximum_x; ++x) {
                    const int value = image.pixels[
                        static_cast<std::size_t>(y) * image.width + x];
                    if (std::abs(value - background) >= threshold) ++different;
                }
            }
            if (different * 4 < sample_count) continue;
            ++active_blocks;
            minimum_x = std::min(minimum_x, block_x);
            minimum_y = std::min(minimum_y, block_y);
            maximum_x = std::max(maximum_x, block_maximum_x);
            maximum_y = std::max(maximum_y, block_maximum_y);
        }
    }
    const int divisor = std::max(block * block * 2'000, 1);
    const int minimum_blocks = std::max(4, image.width * image.height / divisor);
    if (active_blocks < minimum_blocks || maximum_x <= minimum_x || maximum_y <= minimum_y) {
        return std::nullopt;
    }
    return EdgeRect{minimum_x, minimum_y, maximum_x - minimum_x, maximum_y - minimum_y};
}

[[nodiscard]] EdgeImage cropped(const EdgeImage& image, const EdgeRect rect) {
    EdgeImage result{};
    result.width = rect.width;
    result.height = rect.height;
    result.pixels.resize(static_cast<std::size_t>(rect.width) * rect.height);
    for (int y = 0; y < rect.height; ++y) {
        const auto source = image.pixels.begin() +
            static_cast<std::ptrdiff_t>((rect.y + y) * image.width + rect.x);
        std::copy_n(
            source, rect.width,
            result.pixels.begin() + static_cast<std::ptrdiff_t>(y * rect.width));
    }
    return result;
}

[[nodiscard]] EdgeImage resized(const EdgeImage& image, const int maximum_dimension) {
    if (std::max(image.width, image.height) <= maximum_dimension) return image;
    const double scale = static_cast<double>(maximum_dimension) /
        std::max(image.width, image.height);
    EdgeImage result{};
    result.width = std::max(1, static_cast<int>(std::lround(image.width * scale)));
    result.height = std::max(1, static_cast<int>(std::lround(image.height * scale)));
    result.pixels.resize(static_cast<std::size_t>(result.width) * result.height);
    for (int y = 0; y < result.height; ++y) {
        const int source_y = std::min(
            image.height - 1,
            static_cast<int>(static_cast<double>(y) / result.height * image.height));
        for (int x = 0; x < result.width; ++x) {
            const int source_x = std::min(
                image.width - 1,
                static_cast<int>(static_cast<double>(x) / result.width * image.width));
            result.pixels[static_cast<std::size_t>(y) * result.width + x] =
                image.pixels[static_cast<std::size_t>(source_y) * image.width + source_x];
        }
    }
    return result;
}

[[nodiscard]] EdgeImage rotated_counter_clockwise(const EdgeImage& image) {
    EdgeImage result{};
    result.width = image.height;
    result.height = image.width;
    result.pixels.resize(image.pixels.size());
    for (int y = 0; y < image.height; ++y) {
        for (int x = 0; x < image.width; ++x) {
            const int target_x = y;
            const int target_y = image.width - 1 - x;
            result.pixels[static_cast<std::size_t>(target_y) * result.width + target_x] =
                image.pixels[static_cast<std::size_t>(y) * image.width + x];
        }
    }
    return result;
}

[[nodiscard]] EdgeImage rotated(const EdgeImage& image, const double degrees) {
    const double radians = degrees * std::numbers::pi / 180.0;
    const double cosine = std::cos(radians);
    const double sine = std::sin(radians);
    const double center_x = static_cast<double>(image.width - 1) * 0.5;
    const double center_y = static_cast<double>(image.height - 1) * 0.5;
    const std::uint8_t background = border_background(image);
    EdgeImage result{};
    result.width = image.width;
    result.height = image.height;
    result.pixels.assign(image.pixels.size(), background);
    for (int y = 0; y < image.height; ++y) {
        const double centered_y = y - center_y;
        for (int x = 0; x < image.width; ++x) {
            const double centered_x = x - center_x;
            const int source_x = static_cast<int>(std::lround(
                cosine * centered_x + sine * centered_y + center_x));
            const int source_y = static_cast<int>(std::lround(
                -sine * centered_x + cosine * centered_y + center_y));
            if (source_x < 0 || source_y < 0 ||
                source_x >= image.width || source_y >= image.height) continue;
            result.pixels[static_cast<std::size_t>(y) * image.width + x] =
                image.pixels[static_cast<std::size_t>(source_y) * image.width + source_x];
        }
    }
    return result;
}

[[nodiscard]] std::optional<double> estimated_deskew_angle(const EdgeImage& image) {
    const std::uint8_t background = border_background(image);
    const double threshold = background_threshold(image, background);
    const int step = std::max(4, image.width / 96);
    std::vector<std::pair<double, double>> top{};
    std::vector<std::pair<double, double>> bottom{};
    for (int x = step / 2; x < image.width; x += step) {
        for (int y = 0; y < image.height; ++y) {
            if (std::abs(static_cast<int>(image.pixels[
                    static_cast<std::size_t>(y) * image.width + x]) - background) >= threshold) {
                top.emplace_back(x, y);
                break;
            }
        }
        for (int y = image.height - 1; y >= 0; --y) {
            if (std::abs(static_cast<int>(image.pixels[
                    static_cast<std::size_t>(y) * image.width + x]) - background) >= threshold) {
                bottom.emplace_back(x, y);
                break;
            }
        }
    }
    std::vector<double> slopes{};
    for (const auto* samples : {&top, &bottom}) {
        if (samples->size() < 12U) continue;
        const auto [minimum, maximum] = std::minmax_element(
            samples->begin(), samples->end(), [](const auto first, const auto second) {
                return first.first < second.first;
            });
        if (maximum->first - minimum->first < image.width * 0.55) continue;
        if (const auto slope = robust_slope(*samples)) slopes.push_back(*slope);
    }
    if (slopes.empty()) return std::nullopt;
    const double correction = -std::atan(median(slopes)) * 180.0 / std::numbers::pi;
    return std::isfinite(correction) && std::abs(correction) >= 0.25 &&
        std::abs(correction) <= 5.5 ? std::optional<double>{correction} : std::nullopt;
}

[[nodiscard]] std::vector<double> moving_average(
    const std::vector<double>& values,
    const int radius) {
    if (values.empty() || radius <= 0) return values;
    std::vector<double> prefix(values.size() + 1U, 0.0);
    for (std::size_t index = 0U; index < values.size(); ++index) {
        prefix[index + 1U] = prefix[index] + values[index];
    }
    std::vector<double> result(values.size(), 0.0);
    for (std::size_t index = 0U; index < values.size(); ++index) {
        const std::size_t lower = index > static_cast<std::size_t>(radius)
            ? index - static_cast<std::size_t>(radius) : 0U;
        const std::size_t upper = std::min(
            values.size(), index + static_cast<std::size_t>(radius) + 1U);
        result[index] = (prefix[upper] - prefix[lower]) /
            static_cast<double>(upper - lower);
    }
    return result;
}

[[nodiscard]] std::array<std::uint8_t, 256U> equalization_lut(
    const EdgeImage& image) {
    std::array<std::uint32_t, 256U> histogram{};
    for (const std::uint8_t value : image.pixels) ++histogram[value];
    std::uint64_t cumulative = 0U;
    std::uint64_t minimum = 0U;
    for (const std::uint32_t count : histogram) {
        cumulative += count;
        if (minimum == 0U && cumulative != 0U) minimum = cumulative;
    }
    std::array<std::uint8_t, 256U> lut{};
    const std::uint64_t total = image.pixels.size();
    if (total <= minimum) {
        std::iota(lut.begin(), lut.end(), static_cast<std::uint8_t>(0U));
        return lut;
    }
    cumulative = 0U;
    for (std::size_t value = 0U; value < histogram.size(); ++value) {
        cumulative += histogram[value];
        const double mapped = static_cast<double>(cumulative - minimum) * 255.0 /
            static_cast<double>(total - minimum);
        lut[value] = static_cast<std::uint8_t>(std::clamp(std::lround(mapped), 0L, 255L));
    }
    return lut;
}

[[nodiscard]] int quantile_from_histogram(
    const std::array<int, 256U>& histogram,
    const int samples,
    const double quantile) noexcept {
    const int target = std::clamp(
        static_cast<int>(std::ceil(static_cast<double>(samples) * quantile)), 1, samples);
    int cumulative = 0;
    for (int value = 0; value < 256; ++value) {
        cumulative += histogram[static_cast<std::size_t>(value)];
        if (cumulative >= target) return value;
    }
    return 255;
}

[[nodiscard]] std::vector<double> horizontal_gradient_row_means(
    const EdgeImage& image) {
    const auto lut = equalization_lut(image);
    std::vector<double> result(static_cast<std::size_t>(image.height), 0.0);
    for (int y = 0; y < image.height; ++y) {
        std::uint64_t sum = 0U;
        const std::size_t row = static_cast<std::size_t>(y) * image.width;
        for (int x = 0; x < image.width - 1; ++x) {
            const int left = lut[image.pixels[row + static_cast<std::size_t>(x)]];
            const int right = lut[image.pixels[row + static_cast<std::size_t>(x + 1)]];
            sum += static_cast<std::uint64_t>(std::abs(right - left));
        }
        result[static_cast<std::size_t>(y)] = static_cast<double>(sum) /
            static_cast<double>((image.width - 1) * 255);
    }
    return result;
}

[[nodiscard]] std::vector<double> vertical_gradient_row_quantiles(
    const EdgeImage& image) {
    std::vector<double> result(static_cast<std::size_t>(image.height), 0.0);
    std::array<int, 256U> histogram{};
    for (int y = 0; y < image.height - 1; ++y) {
        histogram.fill(0);
        const std::size_t top = static_cast<std::size_t>(y) * image.width;
        const std::size_t bottom = top + static_cast<std::size_t>(image.width);
        for (int x = 0; x < image.width; ++x) {
            const int difference = std::abs(
                static_cast<int>(image.pixels[top + static_cast<std::size_t>(x)]) -
                static_cast<int>(image.pixels[bottom + static_cast<std::size_t>(x)]));
            ++histogram[static_cast<std::size_t>(difference)];
        }
        result[static_cast<std::size_t>(y)] =
            static_cast<double>(quantile_from_histogram(histogram, image.width, 0.75)) / 255.0;
    }
    result.back() = result[result.size() - 2U];
    return result;
}

[[nodiscard]] std::vector<double> horizontal_gradient_column_quantiles(
    const EdgeImage& image,
    const IntRange rows) {
    std::vector<double> result(static_cast<std::size_t>(image.width - 1), 0.0);
    std::array<int, 256U> histogram{};
    for (int x = 0; x < image.width - 1; ++x) {
        histogram.fill(0);
        for (int y = rows.first; y < rows.last; ++y) {
            const std::size_t offset = static_cast<std::size_t>(y) * image.width + x;
            const int difference = std::abs(
                static_cast<int>(image.pixels[offset]) -
                static_cast<int>(image.pixels[offset + 1U]));
            ++histogram[static_cast<std::size_t>(difference)];
        }
        result[static_cast<std::size_t>(x)] =
            static_cast<double>(quantile_from_histogram(histogram, rows.count(), 0.75)) / 255.0;
    }
    return result;
}

[[nodiscard]] std::vector<IntRange> inferred_strip_ranges(
    const EdgeImage& image,
    const std::vector<double>& row_energy) {
    const int radius = std::max(2, static_cast<int>(std::lround(image.height * 0.005)));
    const std::vector<double> smoothed = moving_average(row_energy, radius);
    const int center_start = std::min(radius, image.height);
    const int center_end = std::max(center_start, image.height - radius);
    const double baseline = median(std::vector<double>(
        smoothed.begin() + center_start, smoothed.begin() + center_end));
    if (baseline <= 0.0) return {};

    std::vector<IntRange> low_runs{};
    std::optional<int> start{};
    for (int index = 0; index < image.height; ++index) {
        const bool low = smoothed[static_cast<std::size_t>(index)] < baseline * 0.45;
        if (low && !start) start = index;
        if (!low && start) {
            low_runs.push_back({*start, index});
            start.reset();
        }
    }
    if (start) low_runs.push_back({*start, image.height});

    const int interior_minimum = std::max(4, image.height / 40);
    const int edge_minimum = std::max(3, image.height / 100);
    std::vector<IntRange> accepted{};
    for (const IntRange run : low_runs) {
        const bool edge = run.first <= radius || run.last >= image.height - radius;
        if (run.count() >= (edge ? edge_minimum : interior_minimum)) accepted.push_back(run);
    }
    std::optional<IntRange> leading{};
    std::optional<IntRange> trailing{};
    std::vector<IntRange> interior{};
    for (const IntRange run : accepted) {
        if (!leading && run.first <= radius) leading = run;
        if (run.last >= image.height - radius) trailing = run;
        if (run.first > radius && run.last < image.height - radius) interior.push_back(run);
    }
    if (interior.empty()) return {{0, image.height}};
    int longest = 0;
    for (const IntRange gap : interior) longest = std::max(longest, gap.count());
    std::erase_if(interior, [longest](const IntRange gap) {
        return static_cast<double>(gap.count()) < static_cast<double>(longest) * 0.75;
    });

    const int lower_limit = leading ? leading->last : 0;
    const int upper_limit = trailing ? trailing->first : image.height;
    const int minimum_height = std::max(32, image.height / 12);
    if (upper_limit - lower_limit < minimum_height) return {};
    std::vector<IntRange> ranges{};
    int lower = lower_limit;
    for (const IntRange gap : interior) {
        if (gap.first - lower < minimum_height) return {};
        ranges.push_back({lower, gap.first});
        lower = gap.last;
    }
    if (upper_limit - lower < minimum_height) return {};
    ranges.push_back({lower, upper_limit});
    return ranges;
}

[[nodiscard]] std::optional<int> weighted_maximum(
    const IntRange range,
    const std::vector<double>& values,
    const double target,
    const double sigma) noexcept {
    if (range.count() <= 0 || range.first < 0 ||
        range.last > static_cast<int>(values.size()) || sigma <= 0.0) return std::nullopt;
    int best = range.first;
    double best_score = -1.0;
    for (int index = range.first; index < range.last; ++index) {
        const double distance = (static_cast<double>(index) - target) / sigma;
        const double score = values[static_cast<std::size_t>(index)] *
            std::exp(-0.5 * distance * distance);
        if (score > best_score) {
            best_score = score;
            best = index;
        }
    }
    return best;
}

[[nodiscard]] bool distinct_peak(
    const int index,
    const IntRange range,
    const std::vector<double>& values) {
    if (index < range.first || index >= range.last) return false;
    const double baseline = std::max(
        median(std::vector<double>(
            values.begin() + range.first, values.begin() + range.last)), 1.0 / 255.0);
    return values[static_cast<std::size_t>(index)] >= std::max(2.0 / 255.0, baseline * 2.0);
}

[[nodiscard]] std::optional<IntRange> aperture_range(
    const IntRange partition,
    const std::vector<double>& scores,
    const bool inner) {
    if (partition.count() < 32) return std::nullopt;
    const int height = partition.count();
    const int limit = static_cast<int>(scores.size());
    const auto bounded = [limit](const int first, const int last) {
        const int lower = std::clamp(first, 0, limit);
        return IntRange{lower, std::clamp(last, lower, limit)};
    };
    const IntRange top = inner
        ? bounded(partition.first + static_cast<int>(height * 0.08),
                  partition.first + static_cast<int>(height * 0.32))
        : bounded(partition.first, partition.first + std::max(3, static_cast<int>(height * 0.20)));
    const IntRange bottom = inner
        ? bounded(partition.first + static_cast<int>(height * 0.68),
                  partition.first + static_cast<int>(height * 0.92))
        : bounded(partition.last - std::max(3, static_cast<int>(height * 0.20)), partition.last);
    const double top_target = partition.first + height * (inner ? 0.165 : 0.05);
    const double bottom_target = partition.first + height * (inner ? 0.86 : 0.95);
    const double sigma = std::max(2.0, height * (inner ? 0.03 : 0.06));
    const auto top_edge = weighted_maximum(top, scores, top_target, sigma);
    const auto bottom_edge = weighted_maximum(bottom, scores, bottom_target, sigma);
    if (!top_edge || !bottom_edge) return std::nullopt;
    const int aperture = *bottom_edge - *top_edge;
    if (aperture < static_cast<int>(height * (inner ? 0.60 : 0.70)) ||
        (inner && aperture > static_cast<int>(height * 0.78)) ||
        !distinct_peak(*top_edge, top, scores) ||
        !distinct_peak(*bottom_edge, bottom, scores)) return std::nullopt;
    return IntRange{std::max(partition.first, *top_edge + 1),
                    std::min(partition.last, *bottom_edge + 1)};
}

[[nodiscard]] std::optional<double> least_squares_slope(
    const std::vector<std::pair<double, double>>& samples) noexcept {
    if (samples.size() < 2U) return std::nullopt;
    double mean_x = 0.0;
    double mean_y = 0.0;
    for (const auto [x, y] : samples) { mean_x += x; mean_y += y; }
    mean_x /= samples.size();
    mean_y /= samples.size();
    double numerator = 0.0;
    double denominator = 0.0;
    for (const auto [x, y] : samples) {
        const double dx = x - mean_x;
        numerator += dx * (y - mean_y);
        denominator += dx * dx;
    }
    return denominator > 1.0e-9 ? std::optional<double>{numerator / denominator} : std::nullopt;
}

[[nodiscard]] std::optional<double> robust_slope(
    const std::vector<std::pair<double, double>>& samples) {
    if (samples.size() < 8U) return std::nullopt;
    const auto initial = least_squares_slope(samples);
    if (!initial) return std::nullopt;
    double center_x = 0.0;
    double center_y = 0.0;
    for (const auto [x, y] : samples) { center_x += x; center_y += y; }
    center_x /= samples.size();
    center_y /= samples.size();
    std::vector<double> residuals{};
    residuals.reserve(samples.size());
    for (const auto [x, y] : samples) {
        residuals.push_back(std::abs(y - (center_y + *initial * (x - center_x))));
    }
    const double cutoff = std::max(1.0, median(residuals) * 2.5);
    std::vector<std::pair<double, double>> filtered{};
    for (std::size_t index = 0U; index < samples.size(); ++index) {
        if (residuals[index] <= cutoff) filtered.push_back(samples[index]);
    }
    return filtered.size() >= 8U ? least_squares_slope(filtered) : initial;
}

[[nodiscard]] std::vector<std::pair<double, double>> trace_horizontal_edge(
    const EdgeImage& image,
    const int expected_y,
    const int radius) {
    const int step = std::max(8, image.width / 64);
    const int x_radius = std::max(1, step / 8);
    std::vector<std::pair<double, double>> samples{};
    for (int x = step / 2; x < image.width; x += step) {
        const int first_y = std::max(0, expected_y - radius);
        const int last_y = std::min(image.height - 1, expected_y + radius + 1);
        if (first_y >= last_y) continue;
        int best_y = first_y;
        int best_score = -1;
        for (int y = first_y; y < last_y; ++y) {
            int score = 0;
            for (int sx = std::max(0, x - x_radius);
                 sx < std::min(image.width, x + x_radius + 1); ++sx) {
                const std::size_t top = static_cast<std::size_t>(y) * image.width + sx;
                score += std::abs(static_cast<int>(image.pixels[top]) -
                                  static_cast<int>(image.pixels[top + image.width]));
            }
            if (score > best_score) { best_score = score; best_y = y; }
        }
        samples.emplace_back(x, best_y);
    }
    return samples;
}

[[nodiscard]] std::vector<std::pair<double, double>> trace_vertical_edge(
    const EdgeImage& image,
    const int expected_x,
    const IntRange rows,
    const int radius) {
    const int step = std::max(6, rows.count() / 32);
    const int y_radius = std::max(1, step / 8);
    std::vector<std::pair<double, double>> samples{};
    for (int y = rows.first + step / 2; y < rows.last; y += step) {
        const int first_x = std::max(0, expected_x - radius);
        const int last_x = std::min(image.width - 1, expected_x + radius + 1);
        if (first_x >= last_x) continue;
        int best_x = first_x;
        int best_score = -1;
        for (int x = first_x; x < last_x; ++x) {
            int score = 0;
            for (int sy = std::max(rows.first, y - y_radius);
                 sy < std::min(rows.last, y + y_radius + 1); ++sy) {
                const std::size_t offset = static_cast<std::size_t>(sy) * image.width + x;
                score += std::abs(static_cast<int>(image.pixels[offset]) -
                                  static_cast<int>(image.pixels[offset + 1U]));
            }
            if (score > best_score) { best_score = score; best_x = x; }
        }
        samples.emplace_back(best_x, y);
    }
    return samples;
}

[[nodiscard]] double strip_angle(
    const EdgeImage& image,
    const IntRange aperture,
    const IntRange partition,
    const std::vector<int>& boundaries,
    const double pitch) {
    const int partition_height = partition.count();
    if (aperture.first > partition.first + static_cast<int>(partition_height * 0.05) &&
        aperture.last < partition.last - static_cast<int>(partition_height * 0.05)) {
        const int radius = std::max(2, aperture.count() / 35);
        std::vector<double> slopes{};
        for (const int edge : {aperture.first, aperture.last - 1}) {
            if (const auto slope = robust_slope(trace_horizontal_edge(image, edge, radius))) {
                slopes.push_back(*slope);
            }
        }
        if (!slopes.empty()) {
            const double slope = std::accumulate(slopes.begin(), slopes.end(), 0.0) /
                static_cast<double>(slopes.size());
            const double correction = -std::atan(slope) * 180.0 / std::numbers::pi;
            if (std::isfinite(correction) && std::abs(correction) <= 5.0) return correction;
        }
    }
    std::vector<double> corrections{};
    const int radius = std::max(3, static_cast<int>(std::lround(pitch * 0.035)));
    for (std::size_t index = 1U; index + 1U < boundaries.size(); ++index) {
        const auto traced = trace_vertical_edge(image, boundaries[index], aperture, radius);
        std::vector<std::pair<double, double>> swapped{};
        swapped.reserve(traced.size());
        for (const auto [x, y] : traced) swapped.emplace_back(y, x);
        if (const auto slope = robust_slope(swapped)) {
            const double correction = std::atan(*slope) * 180.0 / std::numbers::pi;
            if (std::isfinite(correction) && std::abs(correction) <= 5.0) {
                corrections.push_back(correction);
            }
        }
    }
    return corrections.size() >= std::max<std::size_t>(1U, (boundaries.size() - 2U) / 2U)
        ? median(corrections) : 0.0;
}

[[nodiscard]] std::optional<EdgeStrip> detect_edge_strip(
    const EdgeImage& image,
    const IntRange aperture,
    const IntRange partition,
    const std::vector<double>& vertical_scores,
    const double aspect) {
    const double raw_count = static_cast<double>(image.width) /
        (static_cast<double>(aperture.count()) * aspect);
    const int columns = static_cast<int>(std::lround(raw_count));
    if (columns < 1 || columns > 48) return std::nullopt;
    const double pitch = static_cast<double>(image.width) / columns;
    const double inferred = pitch / aperture.count();
    if (inferred < aspect * 0.90 || inferred > aspect * 1.10 ||
        vertical_scores.size() != static_cast<std::size_t>(image.width - 1)) return std::nullopt;
    const double floor = std::max(median(vertical_scores), 1.0 / 255.0);
    const double threshold = floor * 5.0;
    if (columns > 1 && *std::max_element(vertical_scores.begin(), vertical_scores.end()) < threshold) {
        return std::nullopt;
    }
    std::vector<int> boundaries(static_cast<std::size_t>(columns + 1), 0);
    boundaries.back() = image.width;
    std::vector<std::pair<int, int>> measured{};
    int strong = 0;
    for (int boundary = 1; boundary < columns; ++boundary) {
        const double target = boundary * pitch;
        const int half = std::max(4, static_cast<int>(std::lround(pitch * 0.12)));
        const int first = std::max(0, static_cast<int>(std::lround(target)) - half);
        const int last = std::min(image.width - 1, static_cast<int>(std::lround(target)) + half + 1);
        const double sigma = std::max(2.0, pitch * 0.08);
        int best = first;
        double best_score = -1.0;
        for (int x = first; x < last; ++x) {
            const double distance = (x - target) / sigma;
            const double score = vertical_scores[static_cast<std::size_t>(x)] *
                std::exp(-0.5 * distance * distance);
            if (score > best_score) { best_score = score; best = x; }
        }
        if (vertical_scores[static_cast<std::size_t>(best)] >= threshold) {
            ++strong;
            measured.emplace_back(boundary, best);
            boundaries[static_cast<std::size_t>(boundary)] = best;
        } else {
            boundaries[static_cast<std::size_t>(boundary)] = static_cast<int>(std::lround(target));
        }
    }
    const int required = columns <= 2 ? columns - 1 : columns - 2;
    if (strong < std::max(0, required)) return std::nullopt;
    for (int boundary = 1; boundary < columns; ++boundary) {
        if (std::any_of(measured.begin(), measured.end(), [boundary](const auto pair) {
                return pair.first == boundary;
            })) continue;
        int left = boundary - 1;
        while (left > 0 && !std::any_of(measured.begin(), measured.end(), [left](const auto pair) {
            return pair.first == left;
        })) --left;
        int right = boundary + 1;
        while (right < columns && !std::any_of(measured.begin(), measured.end(), [right](const auto pair) {
            return pair.first == right;
        })) ++right;
        const double fraction = static_cast<double>(boundary - left) / (right - left);
        boundaries[static_cast<std::size_t>(boundary)] = static_cast<int>(std::lround(
            boundaries[static_cast<std::size_t>(left)] +
            (boundaries[static_cast<std::size_t>(right)] -
             boundaries[static_cast<std::size_t>(left)]) * fraction));
    }
    for (int boundary = 0; boundary < columns; ++boundary) {
        const double spacing = boundaries[static_cast<std::size_t>(boundary + 1)] -
            boundaries[static_cast<std::size_t>(boundary)];
        if (spacing < pitch * 0.68 || spacing > pitch * 1.32) return std::nullopt;
    }
    const double angle = strip_angle(image, aperture, partition, boundaries, pitch);
    const double evidence = columns > 1
        ? static_cast<double>(strong) / (columns - 1) : 0.5;
    return EdgeStrip{aperture, std::move(boundaries), std::clamp(angle, -5.0, 5.0),
                     std::clamp(0.55 + evidence * 0.4, 0.0, 1.0)};
}

[[nodiscard]] bool frame_has_evidence(
    const EdgeImage& image,
    const IntRange columns,
    const IntRange rows) noexcept {
    const int x_step = std::max(1, columns.count() / 32);
    const int y_step = std::max(1, rows.count() / 24);
    int minimum = 255;
    int maximum = 0;
    double interior = 0.0;
    int count = 0;
    for (int y = rows.first; y < rows.last; y += y_step) {
        for (int x = columns.first; x < columns.last; x += x_step) {
            const int value = image.pixels[static_cast<std::size_t>(y) * image.width + x];
            minimum = std::min(minimum, value);
            maximum = std::max(maximum, value);
            interior += value;
            ++count;
        }
    }
    if (count == 0) return false;
    if (maximum - minimum >= 8) return true;
    const int outside[2] = {
        std::max(0, rows.first - std::max(2, rows.count() / 16)),
        std::min(image.height - 1, rows.last + std::max(1, rows.count() / 16))};
    double exterior = 0.0;
    int exterior_count = 0;
    for (const int y : outside) {
        if (y >= rows.first && y < rows.last) continue;
        for (int x = columns.first; x < columns.last; x += x_step) {
            exterior += image.pixels[static_cast<std::size_t>(y) * image.width + x];
            ++exterior_count;
        }
    }
    return exterior_count == 0 ||
        std::abs(interior / count - exterior / exterior_count) >= 6.0;
}

[[nodiscard]] std::pair<double, double> aperture_dimensions(
    const FlatbedFrameFormat format) noexcept {
    switch (format) {
        case FlatbedFrameFormat::full_frame_35mm: return {36.0, 24.0};
        case FlatbedFrameFormat::square_35mm: return {24.0, 24.0};
        case FlatbedFrameFormat::half_frame_35mm: return {18.0, 24.0};
        case FlatbedFrameFormat::medium_645: return {41.5, 56.0};
        case FlatbedFrameFormat::medium_66: return {56.0, 56.0};
        case FlatbedFrameFormat::medium_67: return {69.0, 55.0};
        case FlatbedFrameFormat::medium_68: return {76.0, 56.0};
        case FlatbedFrameFormat::medium_69: return {84.0, 56.0};
        case FlatbedFrameFormat::medium_612: return {112.0, 56.0};
        case FlatbedFrameFormat::medium_617: return {168.0, 56.0};
    }
    return {36.0, 24.0};
}

[[nodiscard]] std::vector<FlatbedFrameDetection> detect_edges_horizontal(
    const EdgeImage& image,
    const FlatbedFrameFormat format,
    const negaflow::core::CancelFlag cancel) {
    const std::vector<double> row_energy = horizontal_gradient_row_means(image);
    const std::vector<IntRange> partitions = inferred_strip_ranges(image, row_energy);
    if (partitions.empty() || partitions.size() > 12U) return {};
    const std::vector<double> horizontal_scores = moving_average(
        vertical_gradient_row_quantiles(image), 1);
    const auto [aperture_width, aperture_height] = aperture_dimensions(format);
    const double aspects[2] = {aperture_width / aperture_height,
                               aperture_height / aperture_width};
    std::vector<FlatbedFrameDetection> preferred{};
    for (const double aspect : aspects) {
        if (cancel.requested()) return {};
        std::vector<FlatbedFrameDetection> detections{};
        std::uint32_t row = 0U;
        for (const IntRange partition : partitions) {
            const auto aperture = aperture_range(
                partition, horizontal_scores, partitions.size() > 1U);
            if (!aperture) continue;
            const auto strip = detect_edge_strip(
                image, *aperture, partition,
                horizontal_gradient_column_quantiles(image, *aperture), aspect);
            if (!strip) continue;
            std::uint32_t output_column = 0U;
            for (std::size_t column = 0U; column + 1U < strip->boundaries.size(); ++column) {
                const IntRange x{strip->boundaries[column], strip->boundaries[column + 1U]};
                if (!frame_has_evidence(image, x, strip->aperture)) continue;
                detections.push_back({
                    static_cast<double>(x.first) / image.width,
                    static_cast<double>(strip->aperture.first) / image.height,
                    static_cast<double>(x.count()) / image.width,
                    static_cast<double>(strip->aperture.count()) / image.height,
                    strip->angle,
                    strip->confidence,
                    row,
                    output_column++,
                });
            }
            ++row;
        }
        if (detections.size() > preferred.size()) preferred = std::move(detections);
        if (std::abs(aspects[0] - aspects[1]) < 1.0e-9) break;
    }
    return preferred;
}

// ABI 계약: 검출은 단위 사각형 안이고 유한해야 합니다. 여기서 한 번 맞춥니다.
//
// 경로마다 자기 나눗셈을 합니다 - 격자는 `snapped.first / preview.width` 와
// `snapped.count() / preview.width` 로 짓고, `map_from_crop` 은 crop 좌표를 원본 크기로
// 되돌리며, 회전 되돌림만 min/max 를 clamp 합니다. 그래서 정수 구간이 폭을 꽉 채우거나
// 부동소수 나머지가 남으면 `x + width` 가 1.0 을 아주 조금 넘습니다. 관리 쪽 검사는 그것을
// 계약 위반으로 보고 예외를 던지고, 그 예외가 평판 프리뷰의 프레임 찾기를 통째로 끊었습니다
// (실기: "The flatbed detector returned an invalid frame rectangle").
//
// 자르는 것이 맞습니다 - 화면 밖은 볼 수 없는 자리이고, macOS 도 경계에 걸친 컷을 프리뷰와
// 교차시켜 남깁니다. 넓이가 0 이 된 것만 버립니다.
void constrain_to_unit_square(std::vector<FlatbedFrameDetection>& detections) noexcept {
    std::size_t kept = 0U;
    for (std::size_t index = 0U; index < detections.size(); ++index) {
        FlatbedFrameDetection detection = detections[index];
        if (!std::isfinite(detection.x) || !std::isfinite(detection.y) ||
            !std::isfinite(detection.width) || !std::isfinite(detection.height) ||
            !std::isfinite(detection.confidence) ||
            !std::isfinite(detection.straighten_angle)) {
            continue;
        }
        const double left = std::clamp(detection.x, 0.0, 1.0);
        const double top = std::clamp(detection.y, 0.0, 1.0);
        const double right = std::clamp(detection.x + detection.width, left, 1.0);
        const double bottom = std::clamp(detection.y + detection.height, top, 1.0);
        if (!(right > left) || !(bottom > top)) {
            continue;
        }
        detection.x = left;
        detection.y = top;
        detection.width = right - left;
        detection.height = bottom - top;
        detection.confidence = std::clamp(detection.confidence, 0.0, 1.0);
        detection.straighten_angle = std::clamp(detection.straighten_angle, -45.0, 45.0);
        detections[kept] = detection;
        ++kept;
    }
    detections.resize(kept);
}

[[nodiscard]] std::vector<FlatbedFrameDetection> normalized_topology(
    std::vector<FlatbedFrameDetection> detections) {
    std::sort(detections.begin(), detections.end(), [](const auto& first, const auto& second) {
        const double first_mid_y = first.y + first.height * 0.5;
        const double second_mid_y = second.y + second.height * 0.5;
        return std::abs(first_mid_y - second_mid_y) > 0.001
            ? first_mid_y < second_mid_y : first.x < second.x;
    });
    std::vector<std::vector<FlatbedFrameDetection>> rows{};
    for (const auto& detection : detections) {
        auto matching = rows.end();
        for (auto row = rows.begin(); row != rows.end(); ++row) {
            const auto& reference = row->front();
            const double minimum_height = std::min(reference.height, detection.height);
            const double overlap = std::min(reference.y + reference.height,
                                            detection.y + detection.height) -
                std::max(reference.y, detection.y);
            if (minimum_height > 0.0 && overlap / minimum_height >= 0.5) matching = row;
        }
        if (matching == rows.end()) rows.push_back({detection});
        else matching->push_back(detection);
    }
    std::vector<FlatbedFrameDetection> result{};
    for (std::size_t row = 0U; row < rows.size(); ++row) {
        std::sort(rows[row].begin(), rows[row].end(), [](const auto& first, const auto& second) {
            return first.x < second.x;
        });
        for (std::size_t column = 0U; column < rows[row].size(); ++column) {
            auto detection = rows[row][column];
            detection.row = static_cast<std::uint32_t>(row);
            detection.column = static_cast<std::uint32_t>(column);
            result.push_back(detection);
        }
    }
    return result;
}

[[nodiscard]] std::vector<FlatbedFrameDetection> detect_edges_aligned(
    const EdgeImage& image,
    const FlatbedFrameFormat format,
    const negaflow::core::CancelFlag cancel) {
    auto direct = detect_edges_horizontal(image, format, cancel);
    if (!direct.empty() || cancel.requested()) return normalized_topology(std::move(direct));
    const EdgeImage counter_clockwise = rotated_counter_clockwise(image);
    auto rotated_detections = detect_edges_horizontal(counter_clockwise, format, cancel);
    for (auto& detection : rotated_detections) {
        const double x = 1.0 - detection.y - detection.height;
        const double y = detection.x;
        const double width = detection.height;
        const double height = detection.width;
        detection.x = x;
        detection.y = y;
        detection.width = width;
        detection.height = height;
    }
    return normalized_topology(std::move(rotated_detections));
}

[[nodiscard]] std::vector<FlatbedFrameDetection> map_from_rotated_canvas(
    std::vector<FlatbedFrameDetection> detections,
    const double angle,
    const int width,
    const int height) {
    const double radians = angle * std::numbers::pi / 180.0;
    const double cosine = std::cos(radians);
    const double sine = std::sin(radians);
    const double center_x = static_cast<double>(width - 1) * 0.5;
    const double center_y = static_cast<double>(height - 1) * 0.5;
    for (auto& detection : detections) {
        const double minimum_x = width * detection.x;
        const double maximum_x = width * (detection.x + detection.width);
        const double minimum_y = height * detection.y;
        const double maximum_y = height * (detection.y + detection.height);
        const std::array<std::pair<double, double>, 4U> corners{{
            {minimum_x, minimum_y}, {maximum_x, minimum_y},
            {minimum_x, maximum_y}, {maximum_x, maximum_y}}};
        double mapped_minimum_x = static_cast<double>(width);
        double mapped_maximum_x = 0.0;
        double mapped_minimum_y = static_cast<double>(height);
        double mapped_maximum_y = 0.0;
        for (const auto [x, y] : corners) {
            const double centered_x = x - center_x;
            const double centered_y = y - center_y;
            const double mapped_x = cosine * centered_x + sine * centered_y + center_x;
            const double mapped_y = -sine * centered_x + cosine * centered_y + center_y;
            mapped_minimum_x = std::min(mapped_minimum_x, mapped_x);
            mapped_maximum_x = std::max(mapped_maximum_x, mapped_x);
            mapped_minimum_y = std::min(mapped_minimum_y, mapped_y);
            mapped_maximum_y = std::max(mapped_maximum_y, mapped_y);
        }
        mapped_minimum_x = std::clamp(mapped_minimum_x, 0.0, static_cast<double>(width));
        mapped_maximum_x = std::clamp(mapped_maximum_x, 0.0, static_cast<double>(width));
        mapped_minimum_y = std::clamp(mapped_minimum_y, 0.0, static_cast<double>(height));
        mapped_maximum_y = std::clamp(mapped_maximum_y, 0.0, static_cast<double>(height));
        detection.x = mapped_minimum_x / width;
        detection.y = mapped_minimum_y / height;
        detection.width = std::max(0.0, mapped_maximum_x - mapped_minimum_x) / width;
        detection.height = std::max(0.0, mapped_maximum_y - mapped_minimum_y) / height;
        detection.straighten_angle = std::clamp(
            detection.straighten_angle + angle, -5.0, 5.0);
        detection.confidence *= 0.95;
    }
    return detections;
}

[[nodiscard]] std::vector<FlatbedFrameDetection> map_from_crop(
    std::vector<FlatbedFrameDetection> detections,
    const EdgeRect crop,
    const int source_width,
    const int source_height) {
    for (auto& detection : detections) {
        detection.x = (crop.x + detection.x * crop.width) / source_width;
        detection.y = (crop.y + detection.y * crop.height) / source_height;
        detection.width = detection.width * crop.width / source_width;
        detection.height = detection.height * crop.height / source_height;
    }
    return detections;
}

[[nodiscard]] std::vector<FlatbedFrameDetection> detect_edges(
    const EdgeImage& image,
    const FlatbedFrameFormat format,
    const negaflow::core::CancelFlag cancel) {
    auto aligned = detect_edges_aligned(image, format, cancel);
    if (!aligned.empty() || cancel.requested()) return aligned;
    const auto foreground = foreground_bounds(image);
    if (!foreground) return {};
    const int padding = std::max(4, std::min(image.width, image.height) / 100);
    const int minimum_x = std::max(0, foreground->x - padding);
    const int minimum_y = std::max(0, foreground->y - padding);
    const int maximum_x = std::min(image.width, foreground->x + foreground->width + padding);
    const int maximum_y = std::min(image.height, foreground->y + foreground->height + padding);
    const EdgeRect crop{minimum_x, minimum_y, maximum_x - minimum_x, maximum_y - minimum_y};
    if ((crop.width >= static_cast<int>(image.width * 0.98) &&
         crop.height >= static_cast<int>(image.height * 0.98)) ||
        crop.width < 48 || crop.height < 48) return {};
    const EdgeImage fallback = resized(cropped(image, crop), 1'024);
    const auto estimated = estimated_deskew_angle(fallback);
    if (!estimated) {
        auto cropped_aligned = detect_edges_aligned(fallback, format, cancel);
        if (!cropped_aligned.empty()) {
            return normalized_topology(map_from_crop(
                std::move(cropped_aligned), crop, image.width, image.height));
        }
    }
    std::vector<double> angles{};
    if (estimated) angles.push_back(*estimated);
    for (const double angle : {-1.0, 1.0, -2.0, 2.0, -3.0, 3.0, -4.0, 4.0, -5.0, 5.0}) {
        if (std::none_of(angles.begin(), angles.end(), [angle](const double existing) {
                return std::abs(existing - angle) < 0.35;
            })) angles.push_back(angle);
    }
    for (const double angle : angles) {
        if (cancel.requested()) return {};
        auto detections = detect_edges_aligned(rotated(fallback, angle), format, cancel);
        if (detections.empty()) continue;
        detections = map_from_rotated_canvas(
            std::move(detections), angle, fallback.width, fallback.height);
        return normalized_topology(map_from_crop(
            std::move(detections), crop, image.width, image.height));
    }
    return {};
}

}  // namespace

FlatbedFrameGridResult detect_flatbed_frame_grid(
    const FlatbedFramePreview& preview,
    const FlatbedFrameFormat format,
    const negaflow::core::CancelFlag cancel) noexcept {
    FlatbedFrameGridResult result{};
    if (!valid_preview(preview)) {
        result.status = FlatbedFrameGridStatus::invalid_input;
        return result;
    }
    if (cancel.requested()) {
        result.status = FlatbedFrameGridStatus::cancelled;
        return result;
    }
    try {
        const auto geometry = make_geometry(preview, format);
        if (!geometry || geometry->along_pixels_y() < 8.0 || geometry->across_pixels_x() < 8.0) {
            result.status = FlatbedFrameGridStatus::invalid_input;
            return result;
        }
        const ColumnProfiles columns = column_profiles(preview);
        const std::vector<Slot> detected_slots = slots(preview, columns, *geometry);
        if (cancel.requested()) {
            result.status = FlatbedFrameGridStatus::cancelled;
            return result;
        }
        const double floor = noise_floor(columns, detected_slots);
        for (std::size_t row = 0U; row < detected_slots.size(); ++row) {
            const RowProfiles rows = row_profiles(preview, detected_slots[row].measured);
            const std::vector<flatbed_detail::IntRange> bands =
                film_bands(preview, rows, *geometry);
            std::uint32_t column = 0U;
            for (const flatbed_detail::IntRange band : bands) {
                if (cancel.requested()) {
                    result.detections.clear();
                    result.status = FlatbedFrameGridStatus::cancelled;
                    return result;
                }
                const auto grid = fit_grid(gap_evidence(rows, band, *geometry), *geometry, cancel);
                if (cancel.requested()) {
                    result.detections.clear();
                    result.status = FlatbedFrameGridStatus::cancelled;
                    return result;
                }
                if (!grid) continue;
                for (const DoubleRange span : occupied(frame_spans(*grid, band, *geometry), rows, floor, preview.height)) {
                    result.detections.push_back({
                        static_cast<double>(detected_slots[row].snapped.first) / preview.width,
                        span.first / preview.height,
                        static_cast<double>(detected_slots[row].snapped.count()) / preview.width,
                        (span.last - span.first) / preview.height,
                        0.0,
                        grid->confidence,
                        static_cast<std::uint32_t>(row),
                        column++,
                    });
                }
            }
        }
        constrain_to_unit_square(result.detections);
        result.status = FlatbedFrameGridStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.detections.clear();
        result.status = FlatbedFrameGridStatus::allocation_failed;
        return result;
    } catch (...) {
        result.detections.clear();
        result.status = FlatbedFrameGridStatus::invalid_input;
        return result;
    }
}

FlatbedFrameGridResult detect_flatbed_frame_edges(
    const FlatbedFramePreview& preview,
    const FlatbedFrameFormat format,
    const negaflow::core::CancelFlag cancel) noexcept {
    FlatbedFrameGridResult result{};
    if (!valid_edge_preview(preview)) {
        result.status = FlatbedFrameGridStatus::invalid_input;
        return result;
    }
    if (cancel.requested()) {
        result.status = FlatbedFrameGridStatus::cancelled;
        return result;
    }
    try {
        result.detections = detect_edges(make_edge_image(preview), format, cancel);
        if (cancel.requested()) {
            result.detections.clear();
            result.status = FlatbedFrameGridStatus::cancelled;
            return result;
        }
        constrain_to_unit_square(result.detections);
        result.status = FlatbedFrameGridStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.detections.clear();
        result.status = FlatbedFrameGridStatus::allocation_failed;
        return result;
    } catch (...) {
        result.detections.clear();
        result.status = FlatbedFrameGridStatus::invalid_input;
        return result;
    }
}

const char* flatbed_frame_grid_status_name(const FlatbedFrameGridStatus status) noexcept {
    switch (status) {
        case FlatbedFrameGridStatus::ok: return "ok";
        case FlatbedFrameGridStatus::invalid_input: return "invalid_input";
        case FlatbedFrameGridStatus::cancelled: return "cancelled";
        case FlatbedFrameGridStatus::allocation_failed: return "allocation_failed";
    }
    return "unknown";
}


}  // namespace negaflow::imaging
