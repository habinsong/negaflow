#include "grain_mend_speck_detector.h"

#include "grain_mend_morphology.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <utility>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {
namespace {

constexpr std::array<std::uint32_t, 2U> speck_radii{1U, 3U};
constexpr std::uint32_t speck_cell_size = 32U;
constexpr double speck_floor_quantile = 0.90;
constexpr float speck_minimum_channel_balance = 0.30F;
constexpr double speck_maximum_candidate_fraction = 0.015;
constexpr std::size_t speck_minimum_area = 2U;
constexpr std::size_t speck_maximum_area = 64U;
constexpr double speck_maximum_aspect = 3.0;
constexpr double speck_minimum_fill_ratio = 0.25;
constexpr float clip_high = 0.985F;
constexpr float clip_low = 0.020F;

struct Component final {
    std::vector<std::size_t> pixels{};
    std::uint32_t minimum_x{0U};
    std::uint32_t maximum_x{0U};
    std::uint32_t minimum_y{0U};
    std::uint32_t maximum_y{0U};
};

[[nodiscard]] std::vector<std::uint8_t> make_valid_mask(
    const DetectionImage& image) {
    const std::size_t count = image.luminance.size();
    std::vector<std::uint8_t> valid(count, 0U);
    const std::vector<float> luma_open =
        opening(image.luminance, image.width, image.height, 4U);
    const std::vector<float> luma_close =
        closing(image.luminance, image.width, image.height, 4U);
    for (std::size_t index = 0U; index < count; ++index) {
        valid[index] = luma_open[index] < clip_high && luma_close[index] > clip_low
            ? 1U
            : 0U;
    }
    return valid;
}

[[nodiscard]] std::vector<float> robust_floor(
    const std::vector<float>& coherence,
    const std::uint32_t width,
    const std::uint32_t height,
    const negaflow::core::CancelFlag cancel,
    bool& completed) {
    const std::uint32_t cells_x = (width + speck_cell_size - 1U) / speck_cell_size;
    const std::uint32_t cells_y = (height + speck_cell_size - 1U) / speck_cell_size;
    std::vector<float> grid(static_cast<std::size_t>(cells_x) * cells_y, 0.0F);
    std::vector<float> bucket{};
    bucket.reserve(static_cast<std::size_t>(speck_cell_size) * speck_cell_size);
    for (std::uint32_t cell_y = 0U; cell_y < cells_y; ++cell_y) {
        if (cancel.requested()) {
            completed = false;
            return {};
        }
        const std::uint32_t y0 = cell_y * speck_cell_size;
        const std::uint32_t y1 = std::min(height, y0 + speck_cell_size);
        for (std::uint32_t cell_x = 0U; cell_x < cells_x; ++cell_x) {
            const std::uint32_t x0 = cell_x * speck_cell_size;
            const std::uint32_t x1 = std::min(width, x0 + speck_cell_size);
            bucket.clear();
            for (std::uint32_t y = y0; y < y1; ++y) {
                const std::size_t row = static_cast<std::size_t>(y) * width;
                for (std::uint32_t x = x0; x < x1; ++x) {
                    bucket.push_back(coherence[row + x]);
                }
            }
            std::sort(bucket.begin(), bucket.end());
            const std::size_t quantile = static_cast<std::size_t>(
                static_cast<double>(bucket.size() - 1U) * speck_floor_quantile);
            grid[static_cast<std::size_t>(cell_y) * cells_x + cell_x] = bucket[quantile];
        }
    }

    std::vector<float> smoothed = grid;
    for (std::uint32_t cell_y = 0U; cell_y < cells_y; ++cell_y) {
        for (std::uint32_t cell_x = 0U; cell_x < cells_x; ++cell_x) {
            float sum = 0.0F;
            std::uint32_t samples = 0U;
            for (int delta_y = -1; delta_y <= 1; ++delta_y) {
                const int neighbor_y = static_cast<int>(cell_y) + delta_y;
                if (neighbor_y < 0 || neighbor_y >= static_cast<int>(cells_y)) {
                    continue;
                }
                for (int delta_x = -1; delta_x <= 1; ++delta_x) {
                    const int neighbor_x = static_cast<int>(cell_x) + delta_x;
                    if (neighbor_x < 0 || neighbor_x >= static_cast<int>(cells_x)) {
                        continue;
                    }
                    sum += grid[static_cast<std::size_t>(neighbor_y) * cells_x +
                                static_cast<std::size_t>(neighbor_x)];
                    ++samples;
                }
            }
            smoothed[static_cast<std::size_t>(cell_y) * cells_x + cell_x] =
                sum / static_cast<float>(samples);
        }
    }
    return smoothed;
}

[[nodiscard]] std::vector<Component> collect_components(
    const std::vector<std::uint8_t>& candidates,
    const std::uint32_t width,
    const std::uint32_t height) {
    std::vector<std::uint8_t> visited(candidates.size(), 0U);
    std::vector<std::size_t> stack{};
    std::vector<Component> components{};
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::size_t seed = static_cast<std::size_t>(y) * width + x;
            if (visited[seed] != 0U || candidates[seed] == 0U) {
                continue;
            }
            Component component{};
            component.minimum_x = x;
            component.maximum_x = x;
            component.minimum_y = y;
            component.maximum_y = y;
            stack.clear();
            stack.push_back(seed);
            visited[seed] = 1U;
            while (!stack.empty()) {
                const std::size_t index = stack.back();
                stack.pop_back();
                component.pixels.push_back(index);
                const std::uint32_t current_x = static_cast<std::uint32_t>(index % width);
                const std::uint32_t current_y = static_cast<std::uint32_t>(index / width);
                component.minimum_x = std::min(component.minimum_x, current_x);
                component.maximum_x = std::max(component.maximum_x, current_x);
                component.minimum_y = std::min(component.minimum_y, current_y);
                component.maximum_y = std::max(component.maximum_y, current_y);
                for (int delta_y = -1; delta_y <= 1; ++delta_y) {
                    for (int delta_x = -1; delta_x <= 1; ++delta_x) {
                        if (delta_x == 0 && delta_y == 0) {
                            continue;
                        }
                        const int neighbor_x = static_cast<int>(current_x) + delta_x;
                        const int neighbor_y = static_cast<int>(current_y) + delta_y;
                        if (neighbor_x < 0 || neighbor_y < 0 ||
                            neighbor_x >= static_cast<int>(width) ||
                            neighbor_y >= static_cast<int>(height)) {
                            continue;
                        }
                        const std::size_t neighbor =
                            static_cast<std::size_t>(neighbor_y) * width +
                            static_cast<std::size_t>(neighbor_x);
                        if (visited[neighbor] == 0U && candidates[neighbor] != 0U) {
                            visited[neighbor] = 1U;
                            stack.push_back(neighbor);
                        }
                    }
                }
            }
            components.push_back(std::move(component));
        }
    }
    return components;
}

[[nodiscard]] double component_aspect(
    const Component& component,
    const std::uint32_t width) noexcept {
    const double count = static_cast<double>(component.pixels.size());
    double mean_x = 0.0;
    double mean_y = 0.0;
    for (const std::size_t index : component.pixels) {
        mean_x += static_cast<double>(index % width);
        mean_y += static_cast<double>(index / width);
    }
    mean_x /= count;
    mean_y /= count;
    double covariance_xx = 0.0;
    double covariance_yy = 0.0;
    double covariance_xy = 0.0;
    for (const std::size_t index : component.pixels) {
        const double delta_x = static_cast<double>(index % width) - mean_x;
        const double delta_y = static_cast<double>(index / width) - mean_y;
        covariance_xx += delta_x * delta_x;
        covariance_yy += delta_y * delta_y;
        covariance_xy += delta_x * delta_y;
    }
    covariance_xx /= count;
    covariance_yy /= count;
    covariance_xy /= count;
    const double half_trace = (covariance_xx + covariance_yy) * 0.5;
    const double determinant = covariance_xx * covariance_yy - covariance_xy * covariance_xy;
    const double major = half_trace +
        std::sqrt(std::max(0.0, half_trace * half_trace - determinant));
    const double length = std::max(1.0, std::floor(std::sqrt(12.0 * major)) + 1.0);
    return length / std::max(1.0, count / length);
}

}  // namespace

bool merge_micro_speck_mask(
    const DetectionImage& image,
    const double dust_sensitivity,
    std::vector<std::uint8_t>& mask,
    std::size_t& added_pixels,
    const negaflow::core::CancelFlag cancel) {
    added_pixels = 0U;
    const std::size_t count = image.luminance.size();
    if (image.width == 0U || image.height == 0U ||
        count != static_cast<std::size_t>(image.width) * image.height ||
        mask.size() != count) {
        return true;
    }
    for (const auto& channel : image.channels) {
        if (channel.size() != count) {
            return true;
        }
    }

    const std::vector<std::uint8_t> valid = make_valid_mask(image);
    std::vector<float> coherence(count, 0.0F);
    std::vector<float> balance(count, 0.0F);
    for (const std::uint32_t radius : speck_radii) {
        if (cancel.requested()) {
            return false;
        }
        std::vector<float> minimum_response(count, std::numeric_limits<float>::max());
        std::vector<float> maximum_response(count, 0.0F);
        for (const auto& channel : image.channels) {
            const std::vector<float> closed = closing(channel, image.width, image.height, radius);
            const std::vector<float> background = opening(closed, image.width, image.height, radius);
            for (std::size_t index = 0U; index < count; ++index) {
                const float response = std::max(0.0F, background[index] - channel[index]);
                minimum_response[index] = std::min(minimum_response[index], response);
                maximum_response[index] = std::max(maximum_response[index], response);
            }
        }
        for (std::size_t index = 0U; index < count; ++index) {
            if (minimum_response[index] > coherence[index]) {
                coherence[index] = minimum_response[index];
                balance[index] = maximum_response[index] > 0.0F
                    ? minimum_response[index] / maximum_response[index]
                    : 0.0F;
            }
        }
    }

    bool floor_completed = true;
    const std::vector<float> floor = robust_floor(
        coherence, image.width, image.height, cancel, floor_completed);
    if (!floor_completed) {
        return false;
    }
    const std::uint32_t cells_x = (image.width + speck_cell_size - 1U) / speck_cell_size;
    const double sensitivity = std::clamp(dust_sensitivity, 0.0, 1.0);
    const float absolute_floor = static_cast<float>(0.05 - sensitivity * 0.02);
    const float noise_multiple = static_cast<float>(4.5 - sensitivity * 1.5);
    std::vector<std::uint8_t> candidates(count, 0U);
    std::size_t candidate_count = 0U;
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        if (cancel.requested()) {
            return false;
        }
        const std::uint32_t cell_y = y / speck_cell_size;
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            const std::size_t index = static_cast<std::size_t>(y) * image.width + x;
            const std::uint32_t cell_x = x / speck_cell_size;
            const float threshold = std::max(
                absolute_floor,
                noise_multiple * floor[static_cast<std::size_t>(cell_y) * cells_x + cell_x]);
            if (valid[index] != 0U && coherence[index] > threshold &&
                balance[index] >= speck_minimum_channel_balance) {
                candidates[index] = 1U;
                ++candidate_count;
            }
        }
    }
    if (candidate_count == 0U ||
        static_cast<double>(candidate_count) >
            static_cast<double>(count) * speck_maximum_candidate_fraction) {
        return true;
    }

    for (const Component& component : collect_components(candidates, image.width, image.height)) {
        if (component.pixels.size() < speck_minimum_area ||
            component.pixels.size() > speck_maximum_area) {
            continue;
        }
        const std::uint32_t box_width = component.maximum_x - component.minimum_x + 1U;
        const std::uint32_t box_height = component.maximum_y - component.minimum_y + 1U;
        const double fill_ratio = static_cast<double>(component.pixels.size()) /
            static_cast<double>(box_width * box_height);
        if (fill_ratio < speck_minimum_fill_ratio ||
            component_aspect(component, image.width) > speck_maximum_aspect) {
            continue;
        }
        if (std::any_of(component.pixels.begin(), component.pixels.end(),
                        [&mask](const std::size_t index) { return mask[index] != 0U; })) {
            continue;
        }
        for (const std::size_t index : component.pixels) {
            mask[index] = 1U;
            ++added_pixels;
        }
    }
    return true;
}

}  // namespace negaflow::imaging::grain_mend_detail
