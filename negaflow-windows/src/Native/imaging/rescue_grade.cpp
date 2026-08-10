#include "negaflow/imaging/rescue_grade.h"

#include "negaflow/color/srgb_transfer.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <vector>

namespace negaflow::imaging {
namespace {

constexpr std::array<double, 7U> band_edges{
    0.06, 0.20, 0.34, 0.48, 0.62, 0.76, 0.92};
constexpr std::size_t minimum_eligible_band_count = 3U;
constexpr std::size_t minimum_covered_tile_count = 6U;
constexpr double maximum_neutral_chroma = 18.0;
constexpr double minimum_neutral_population_fraction = 0.80;
constexpr double maximum_band_mad = 3.0;
constexpr double maximum_holdout_delta = 2.0;
constexpr double minimum_measured_drift = 1.5;
constexpr double maximum_drift_lab = 12.0;

struct Lab final {
    double lightness;
    double a;
    double b;
};

struct Sample final {
    std::uint32_t x;
    std::uint32_t y;
    double luma;
    double a;
    double b;
    double chroma;
};

struct SampleGrid final {
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::vector<Sample> samples{};
};

struct NeutralBin final {
    double luma;
    double a;
    double b;
};

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

[[nodiscard]] double lab_f(const double value) noexcept {
    constexpr double delta = 6.0 / 29.0;
    return value > delta * delta * delta
        ? std::cbrt(value)
        : (value / (3.0 * delta * delta)) + (4.0 / 29.0);
}

[[nodiscard]] double lab_f_inverse(const double value) noexcept {
    constexpr double delta = 6.0 / 29.0;
    return value > delta
        ? value * value * value
        : 3.0 * delta * delta * (value - (4.0 / 29.0));
}

[[nodiscard]] Lab srgb_to_lab(
    const double red,
    const double green,
    const double blue) noexcept {
    const double linear_red = negaflow::color::srgb_encoded_to_linear(
        static_cast<float>(red));
    const double linear_green = negaflow::color::srgb_encoded_to_linear(
        static_cast<float>(green));
    const double linear_blue = negaflow::color::srgb_encoded_to_linear(
        static_cast<float>(blue));
    const double x = ((0.4124564 * linear_red) + (0.3575761 * linear_green) +
                      (0.1804375 * linear_blue)) / 0.95047;
    const double y = (0.2126729 * linear_red) + (0.7151522 * linear_green) +
                     (0.0721750 * linear_blue);
    const double z = ((0.0193339 * linear_red) + (0.1191920 * linear_green) +
                      (0.9503041 * linear_blue)) / 1.08883;
    const double fx = lab_f(x);
    const double fy = lab_f(y);
    const double fz = lab_f(z);
    return {116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz)};
}

[[nodiscard]] std::array<double, 3U> lab_to_srgb(const Lab lab) noexcept {
    const double fy = (lab.lightness + 16.0) / 116.0;
    const double fx = fy + (lab.a / 500.0);
    const double fz = fy - (lab.b / 200.0);
    const double x = lab_f_inverse(fx) * 0.95047;
    const double y = lab_f_inverse(fy);
    const double z = lab_f_inverse(fz) * 1.08883;
    const double linear_red = (3.2404542 * x) - (1.5371385 * y) - (0.4985314 * z);
    const double linear_green = (-0.9692660 * x) + (1.8760108 * y) + (0.0415560 * z);
    const double linear_blue = (0.0556434 * x) - (0.2040259 * y) + (1.0572252 * z);
    return {
        clamp(negaflow::color::linear_to_srgb_encoded(
                  static_cast<float>(linear_red)), 0.0, 1.0),
        clamp(negaflow::color::linear_to_srgb_encoded(
                  static_cast<float>(linear_green)), 0.0, 1.0),
        clamp(negaflow::color::linear_to_srgb_encoded(
                  static_cast<float>(linear_blue)), 0.0, 1.0),
    };
}

[[nodiscard]] double overlap(
    const double a0,
    const double a1,
    const double b0,
    const double b1) noexcept {
    return std::max(0.0, std::min(a1, b1) - std::max(a0, b0));
}

[[nodiscard]] SampleGrid sample_grid(const negaflow::core::ImageView image) {
    SampleGrid grid{};
    if (image.width <= 8U || image.height <= 8U) {
        return grid;
    }
    grid.width = 192U;
    const double scale = static_cast<double>(grid.width) / image.width;
    const double scaled_height = std::round(static_cast<double>(image.height) * scale);
    if (!std::isfinite(scaled_height) || scaled_height < 1.0 ||
        scaled_height > 65536.0) {
        return {};
    }
    grid.height = static_cast<std::uint32_t>(scaled_height);
    const std::uint64_t target_count =
        static_cast<std::uint64_t>(grid.width) * grid.height;
    if (target_count > 16U * 1024U * 1024U ||
        target_count > std::numeric_limits<std::size_t>::max()) {
        return {};
    }
    grid.samples.reserve(static_cast<std::size_t>(target_count));
    const double inverse_scale = 1.0 / scale;
    for (std::uint32_t target_y = 0U; target_y < grid.height; ++target_y) {
        const double top = target_y * inverse_scale;
        const double bottom = (target_y + 1U) * inverse_scale;
        const std::uint32_t first_y = static_cast<std::uint32_t>(std::floor(top));
        const std::uint32_t last_y = std::min(
            image.height, static_cast<std::uint32_t>(std::ceil(bottom)));
        for (std::uint32_t target_x = 0U; target_x < grid.width; ++target_x) {
            const double left = target_x * inverse_scale;
            const double right = (target_x + 1U) * inverse_scale;
            const std::uint32_t first_x = static_cast<std::uint32_t>(std::floor(left));
            const std::uint32_t last_x = std::min(
                image.width, static_cast<std::uint32_t>(std::ceil(right)));
            std::array<double, 3U> sum{};
            double weight_sum = 0.0;
            for (std::uint32_t y = first_y; y < last_y; ++y) {
                const double y_weight = overlap(
                    top, bottom, static_cast<double>(y), static_cast<double>(y + 1U));
                const std::size_t row = static_cast<std::size_t>(y) * image.stride_pixels;
                for (std::uint32_t x = first_x; x < last_x; ++x) {
                    const double weight = y_weight * overlap(
                        left, right, static_cast<double>(x), static_cast<double>(x + 1U));
                    const negaflow::core::Rgba32F pixel = image.pixels[row + x];
                    sum[0] += pixel.red * weight;
                    sum[1] += pixel.green * weight;
                    sum[2] += pixel.blue * weight;
                    weight_sum += weight;
                }
            }
            if (weight_sum <= 0.0) {
                continue;
            }
            const std::array<double, 3U> linear{
                sum[0] / weight_sum, sum[1] / weight_sum, sum[2] / weight_sum};
            if (!std::isfinite(linear[0]) || !std::isfinite(linear[1]) ||
                !std::isfinite(linear[2]) ||
                std::min({linear[0], linear[1], linear[2]}) <= 0.01 ||
                std::max({linear[0], linear[1], linear[2]}) >= 0.99) {
                continue;
            }
            const std::array<double, 3U> encoded{
                negaflow::color::linear_to_srgb_encoded(static_cast<float>(linear[0])),
                negaflow::color::linear_to_srgb_encoded(static_cast<float>(linear[1])),
                negaflow::color::linear_to_srgb_encoded(static_cast<float>(linear[2])),
            };
            const double luma = (0.2126 * encoded[0]) + (0.7152 * encoded[1]) +
                                (0.0722 * encoded[2]);
            const Lab lab = srgb_to_lab(encoded[0], encoded[1], encoded[2]);
            grid.samples.push_back({
                target_x, target_y, luma, lab.a, lab.b, std::hypot(lab.a, lab.b)});
        }
    }
    return grid;
}

[[nodiscard]] double median(std::vector<double> values) {
    if (values.empty()) {
        return 0.0;
    }
    std::sort(values.begin(), values.end());
    const std::size_t middle = values.size() / 2U;
    return values.size() % 2U == 0U
        ? (values[middle - 1U] + values[middle]) * 0.5
        : values[middle];
}

template <typename Selector>
[[nodiscard]] std::vector<double> select_values(
    const std::vector<const Sample*>& samples,
    Selector selector) {
    std::vector<double> values{};
    values.reserve(samples.size());
    for (const Sample* const sample : samples) {
        values.push_back(selector(*sample));
    }
    return values;
}

[[nodiscard]] bool is_holdout(const Sample& sample) noexcept {
    return ((sample.x * 31U) + (sample.y * 17U)) % 5U == 0U;
}

[[nodiscard]] std::size_t tile_id(
    const Sample& sample,
    const SampleGrid& grid) noexcept {
    const std::size_t tile_x = std::min<std::size_t>(
        3U, static_cast<std::size_t>(sample.x) * 4U / std::max(grid.width, 1U));
    const std::size_t tile_y = std::min<std::size_t>(
        2U, static_cast<std::size_t>(sample.y) * 3U / std::max(grid.height, 1U));
    return (tile_y * 4U) + tile_x;
}

[[nodiscard]] std::size_t sign_change_count(
    const std::vector<NeutralBin>& bins,
    const bool select_a) noexcept {
    int previous = 0;
    std::size_t changes = 0U;
    for (const NeutralBin& bin : bins) {
        const double value = select_a ? bin.a : bin.b;
        if (std::abs(value) < 0.75) {
            continue;
        }
        const int sign = value < 0.0 ? -1 : 1;
        if (previous != 0 && sign != previous) {
            ++changes;
        }
        previous = sign;
    }
    return changes;
}

[[nodiscard]] std::vector<NeutralBin> measure_recovery(
    const SampleGrid& grid,
    RescueGradeInfo& info) {
    std::vector<NeutralBin> bins{};
    if (grid.samples.size() < 512U) {
        return bins;
    }
    const std::size_t minimum_band_samples =
        std::max<std::size_t>(32U, grid.samples.size() / 320U);
    std::array<bool, 12U> accepted_tiles{};
    for (std::size_t band = 0U; band + 1U < band_edges.size(); ++band) {
        std::vector<const Sample*> members{};
        for (const Sample& sample : grid.samples) {
            if (sample.luma >= band_edges[band] && sample.luma < band_edges[band + 1U]) {
                members.push_back(&sample);
            }
        }
        if (members.size() < minimum_band_samples) {
            continue;
        }
        std::vector<double> sorted_chroma = select_values(
            members, [](const Sample& sample) { return sample.chroma; });
        std::sort(sorted_chroma.begin(), sorted_chroma.end());
        const double neutral_ceiling = std::min(
            maximum_neutral_chroma,
            std::max(5.0, sorted_chroma[sorted_chroma.size() / 4U] * 1.35));
        std::vector<const Sample*> neutral{};
        for (const Sample* const sample : members) {
            if (sample->chroma <= neutral_ceiling) {
                neutral.push_back(sample);
            }
        }
        if (neutral.size() < minimum_band_samples ||
            static_cast<double>(neutral.size()) / members.size() <
                minimum_neutral_population_fraction) {
            continue;
        }
        std::vector<const Sample*> training{};
        std::vector<const Sample*> holdout{};
        for (const Sample* const sample : neutral) {
            (is_holdout(*sample) ? holdout : training).push_back(sample);
        }
        if (training.size() < minimum_band_samples * 3U / 4U ||
            holdout.size() < std::max<std::size_t>(8U, minimum_band_samples / 6U)) {
            continue;
        }
        const double training_a = median(select_values(
            training, [](const Sample& sample) { return sample.a; }));
        const double training_b = median(select_values(
            training, [](const Sample& sample) { return sample.b; }));
        if (std::hypot(training_a, training_b) < minimum_measured_drift) {
            continue;
        }
        const double mad_a = median(select_values(
            training, [training_a](const Sample& sample) {
                return std::abs(sample.a - training_a);
            }));
        const double mad_b = median(select_values(
            training, [training_b](const Sample& sample) {
                return std::abs(sample.b - training_b);
            }));
        if (std::max(mad_a, mad_b) > maximum_band_mad) {
            continue;
        }
        const double holdout_a = median(select_values(
            holdout, [](const Sample& sample) { return sample.a; }));
        const double holdout_b = median(select_values(
            holdout, [](const Sample& sample) { return sample.b; }));
        if (std::hypot(holdout_a - training_a, holdout_b - training_b) >
            maximum_holdout_delta) {
            continue;
        }
        const double before = median(select_values(
            holdout, [](const Sample& sample) { return sample.chroma; }));
        const double after = median(select_values(
            holdout, [training_a, training_b](const Sample& sample) {
                return std::hypot(sample.a - training_a, sample.b - training_b);
            }));
        if (after + 0.75 > before || after > before * 0.72) {
            continue;
        }
        std::array<bool, 12U> band_tiles{};
        for (const Sample* const sample : neutral) {
            band_tiles[tile_id(*sample, grid)] = true;
        }
        if (std::count(band_tiles.begin(), band_tiles.end(), true) < 2) {
            continue;
        }
        bins.push_back({
            median(select_values(neutral, [](const Sample& sample) { return sample.luma; })),
            clamp(training_a, -maximum_drift_lab, maximum_drift_lab),
            clamp(training_b, -maximum_drift_lab, maximum_drift_lab),
        });
        for (std::size_t index = 0U; index < accepted_tiles.size(); ++index) {
            accepted_tiles[index] = accepted_tiles[index] || band_tiles[index];
        }
        info.training_sample_count += training.size();
        info.holdout_sample_count += holdout.size();
    }
    std::sort(bins.begin(), bins.end(), [](const NeutralBin& left, const NeutralBin& right) {
        return left.luma < right.luma;
    });
    info.eligible_band_count = bins.size();
    info.covered_tile_count = static_cast<std::size_t>(
        std::count(accepted_tiles.begin(), accepted_tiles.end(), true));
    const bool eligible = bins.size() >= minimum_eligible_band_count &&
        info.covered_tile_count >= minimum_covered_tile_count &&
        info.holdout_sample_count >= 24U && sign_change_count(bins, true) <= 1U &&
        sign_change_count(bins, false) <= 1U;
    if (!eligible) {
        bins.clear();
    }
    return bins;
}

[[nodiscard]] std::array<double, 2U> neutral_drift(
    const double luma,
    const std::vector<NeutralBin>& bins) noexcept {
    if (luma <= bins.front().luma) {
        return {bins.front().a, bins.front().b};
    }
    if (luma >= bins.back().luma) {
        return {bins.back().a, bins.back().b};
    }
    for (std::size_t index = 1U; index < bins.size(); ++index) {
        if (luma <= bins[index].luma) {
            const NeutralBin& low = bins[index - 1U];
            const NeutralBin& high = bins[index];
            const double fraction =
                (luma - low.luma) / std::max(high.luma - low.luma, 1.0e-6);
            return {
                low.a + ((high.a - low.a) * fraction),
                low.b + ((high.b - low.b) * fraction),
            };
        }
    }
    return {bins.back().a, bins.back().b};
}

void apply_recovery(
    const negaflow::core::ImageView image,
    const std::vector<NeutralBin>& bins) noexcept {
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        const std::size_t row = static_cast<std::size_t>(y) * image.stride_pixels;
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            negaflow::core::Rgba32F& pixel = image.pixels[row + x];
            const std::array<double, 3U> encoded{
                negaflow::color::linear_to_srgb_encoded(pixel.red),
                negaflow::color::linear_to_srgb_encoded(pixel.green),
                negaflow::color::linear_to_srgb_encoded(pixel.blue),
            };
            const double domain_weight = smoothstep(
                0.0, 0.02, std::min({encoded[0], encoded[1], encoded[2]})) *
                (1.0 - smoothstep(
                    0.98, 1.0, std::max({encoded[0], encoded[1], encoded[2]})));
            if (domain_weight <= 0.0) {
                continue;
            }
            const double luma = (0.2126 * encoded[0]) + (0.7152 * encoded[1]) +
                                (0.0722 * encoded[2]);
            Lab lab = srgb_to_lab(encoded[0], encoded[1], encoded[2]);
            const std::array<double, 2U> drift = neutral_drift(luma, bins);
            const double endpoint_weight = smoothstep(0.04, 0.12, luma) *
                (1.0 - smoothstep(0.88, 0.96, luma));
            lab.a -= clamp(drift[0], -maximum_drift_lab, maximum_drift_lab) *
                     endpoint_weight;
            lab.b -= clamp(drift[1], -maximum_drift_lab, maximum_drift_lab) *
                     endpoint_weight;
            const std::array<double, 3U> corrected = lab_to_srgb(lab);
            const std::array<double, 3U> corrected_linear{
                negaflow::color::srgb_encoded_to_linear(static_cast<float>(corrected[0])),
                negaflow::color::srgb_encoded_to_linear(static_cast<float>(corrected[1])),
                negaflow::color::srgb_encoded_to_linear(static_cast<float>(corrected[2])),
            };
            pixel.red = static_cast<float>(
                pixel.red + ((corrected_linear[0] - pixel.red) * domain_weight));
            pixel.green = static_cast<float>(
                pixel.green + ((corrected_linear[1] - pixel.green) * domain_weight));
            pixel.blue = static_cast<float>(
                pixel.blue + ((corrected_linear[2] - pixel.blue) * domain_weight));
        }
    }
}

}  // namespace

negaflow::core::KernelStatus apply_rescue_grade(
    const negaflow::core::ImageView image,
    const bool color_film,
    RescueGradeInfo& info) noexcept {
    info = {};
    const negaflow::core::KernelStatus view_status =
        negaflow::core::validate_image_view(image);
    if (view_status != negaflow::core::KernelStatus::ok) {
        return view_status;
    }
    const negaflow::core::KernelStatus input_status =
        negaflow::core::validate_finite_pixels({
            image.pixels, image.pixel_capacity, image.width, image.height,
            image.stride_pixels});
    if (input_status != negaflow::core::KernelStatus::ok) {
        return input_status;
    }
    if (!color_film) {
        return negaflow::core::KernelStatus::ok;
    }
    try {
        const SampleGrid grid = sample_grid(image);
        const std::vector<NeutralBin> bins = measure_recovery(grid, info);
        if (bins.empty()) {
            return negaflow::core::KernelStatus::ok;
        }
        apply_recovery(image, bins);
        info.applied = true;
        return negaflow::core::validate_finite_pixels({
            image.pixels, image.pixel_capacity, image.width, image.height,
            image.stride_pixels});
    } catch (const std::bad_alloc&) {
        return negaflow::core::KernelStatus::buffer_too_small;
    } catch (...) {
        return negaflow::core::KernelStatus::invalid_argument;
    }
}

}  // namespace negaflow::imaging
