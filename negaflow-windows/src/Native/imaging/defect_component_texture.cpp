#include "defect_component_repair_detail.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <optional>
#include <utility>
#include <vector>

namespace negaflow::imaging::defect_component_repair_detail {
namespace {

using negaflow::core::Rgba32F;

struct Displacement final {
    int dx{0};
    int dy{0};
};

struct CandidateScore final {
    Displacement displacement{};
    double valid_fraction{0.0};
    double context_ssd{std::numeric_limits<double>::max()};
};

[[nodiscard]] float clamp_unit(const float value) noexcept {
    return std::clamp(value, 0.0F, 1.0F);
}

[[nodiscard]] std::optional<Rgba32F> local_mean_rgb(
    const std::vector<Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    const int width,
    const int x,
    const int y) noexcept {
    Rgba32F sum{0.0F, 0.0F, 0.0F, 0.0F};
    float count = 0.0F;
    for (int sample_y = y - 1; sample_y <= y + 1; ++sample_y) {
        for (int sample_x = x - 1; sample_x <= x + 1; ++sample_x) {
            const std::size_t index =
                static_cast<std::size_t>(sample_y) * width + sample_x;
            if (damaged[index] != 0U) {
                continue;
            }
            const Rgba32F sample = source[index];
            sum.red += sample.red;
            sum.green += sample.green;
            sum.blue += sample.blue;
            count += 1.0F;
        }
    }
    if (count == 0.0F) {
        return std::nullopt;
    }
    return Rgba32F{
        sum.red / count,
        sum.green / count,
        sum.blue / count,
        1.0F,
    };
}

[[nodiscard]] std::vector<int> context_samples(
    const std::vector<std::uint8_t>& damaged,
    const int width,
    const int height,
    const ComponentBounds& bounds) {
    std::vector<int> ring{};
    const int x0 = std::max(0, bounds.min_x - 5);
    const int x1 = std::min(width - 1, bounds.max_x + 5);
    const int y0 = std::max(0, bounds.min_y - 5);
    const int y1 = std::min(height - 1, bounds.max_y + 5);
    for (int y = y0; y <= y1; ++y) {
        const bool in_core_y =
            y >= bounds.min_y - 1 && y <= bounds.max_y + 1;
        for (int x = x0; x <= x1; ++x) {
            if (in_core_y && x >= bounds.min_x - 1 &&
                x <= bounds.max_x + 1) {
                continue;
            }
            const int index = y * width + x;
            if (damaged[static_cast<std::size_t>(index)] == 0U) {
                ring.push_back(index);
            }
        }
    }
    if (ring.size() <= 96U) {
        return ring;
    }
    const std::size_t stride = ring.size() / 96U;
    std::vector<int> sampled{};
    sampled.reserve(97U);
    for (std::size_t index = 0U; index < ring.size(); index += stride) {
        sampled.push_back(ring[index]);
    }
    return sampled;
}

[[nodiscard]] double context_ssd(
    const std::vector<int>& context,
    const Displacement displacement,
    const std::vector<Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    const int width,
    const int height) noexcept {
    if (context.empty()) {
        return std::numeric_limits<double>::max();
    }
    double sum = 0.0;
    std::size_t count = 0U;
    for (const int pixel : context) {
        const int y = pixel / width;
        const int x = pixel - y * width;
        const int sample_x = x + displacement.dx;
        const int sample_y = y + displacement.dy;
        if (sample_x < 0 || sample_y < 0 || sample_x >= width ||
            sample_y >= height) {
            continue;
        }
        const std::size_t sample_index =
            static_cast<std::size_t>(sample_y) * width + sample_x;
        if (damaged[sample_index] != 0U) {
            continue;
        }
        const Rgba32F current = source[static_cast<std::size_t>(pixel)];
        const Rgba32F sample = source[sample_index];
        const double dr = static_cast<double>(current.red - sample.red);
        const double dg = static_cast<double>(current.green - sample.green);
        const double db = static_cast<double>(current.blue - sample.blue);
        sum += dr * dr + dg * dg + db * db;
        ++count;
    }
    if (count * 2U < context.size()) {
        return std::numeric_limits<double>::max();
    }
    return sum / static_cast<double>(count);
}

[[nodiscard]] std::optional<Displacement> select_displacement(
    const std::vector<Displacement>& candidates,
    const std::vector<int>& filled,
    const std::vector<int>& context,
    const std::vector<Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    const int width,
    const int height) noexcept {
    const std::size_t stride = std::max<std::size_t>(1U, filled.size() / 64U);
    std::optional<CandidateScore> best{};
    for (const Displacement candidate : candidates) {
        std::size_t valid_count = 0U;
        std::size_t total = 0U;
        for (std::size_t index = 0U; index < filled.size(); index += stride) {
            const int pixel = filled[index];
            const int y = pixel / width;
            const int x = pixel - y * width;
            const int sample_x = x + candidate.dx;
            const int sample_y = y + candidate.dy;
            ++total;
            if (sample_x >= 1 && sample_y >= 1 && sample_x < width - 1 &&
                sample_y < height - 1 &&
                damaged[static_cast<std::size_t>(sample_y) * width + sample_x] ==
                    0U) {
                ++valid_count;
            }
        }
        const double valid = total == 0U
            ? 0.0
            : static_cast<double>(valid_count) / static_cast<double>(total);
        if (valid <= 0.25) {
            continue;
        }
        const double ssd = context_ssd(
            context,
            candidate,
            source,
            damaged,
            width,
            height);
        if (!best.has_value() || valid > best->valid_fraction + 0.15 ||
            (valid > best->valid_fraction - 0.15 &&
             ssd < best->context_ssd)) {
            best = CandidateScore{candidate, valid, ssd};
        }
    }
    return best.has_value()
        ? std::optional<Displacement>{best->displacement}
        : std::nullopt;
}

[[nodiscard]] bool apply_texture_residual(
    std::vector<Rgba32F>& repaired,
    const std::vector<Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    const int width,
    const int x,
    const int y,
    const int sample_x,
    const int sample_y,
    const TextureSigma cap,
    const float clone_mix) noexcept {
    Rgba32F mean{0.0F, 0.0F, 0.0F, 0.0F};
    float count = 0.0F;
    for (int ny = sample_y - 1; ny <= sample_y + 1; ++ny) {
        for (int nx = sample_x - 1; nx <= sample_x + 1; ++nx) {
            const std::size_t index = static_cast<std::size_t>(ny) * width + nx;
            if (damaged[index] != 0U) {
                continue;
            }
            const Rgba32F sample = source[index];
            mean.red += sample.red;
            mean.green += sample.green;
            mean.blue += sample.blue;
            count += 1.0F;
        }
    }
    if (count < 4.0F) {
        return false;
    }
    const std::size_t output_index = static_cast<std::size_t>(y) * width + x;
    const std::size_t source_index =
        static_cast<std::size_t>(sample_y) * width + sample_x;
    const Rgba32F sample = source[source_index];
    Rgba32F& output = repaired[output_index];
    const float keep = 1.0F - clone_mix;
    const float red = output.red * keep + sample.red * clone_mix;
    const float green = output.green * keep + sample.green * clone_mix;
    const float blue = output.blue * keep + sample.blue * clone_mix;
    output.red = clamp_unit(
        red + std::clamp((sample.red - mean.red / count) * 0.8F,
                         -cap.red,
                         cap.red));
    output.green = clamp_unit(
        green + std::clamp((sample.green - mean.green / count) * 0.8F,
                           -cap.green,
                           cap.green));
    output.blue = clamp_unit(
        blue + std::clamp((sample.blue - mean.blue / count) * 0.8F,
                          -cap.blue,
                          cap.blue));
    return true;
}

[[nodiscard]] float next_noise(std::uint64_t& state) noexcept {
    state = state * 6364136223846793005ULL + 1442695040888963407ULL;
    return (static_cast<float>(state >> 40U) /
                static_cast<float>(1U << 24U) *
            2.0F -
            1.0F) *
        1.23F;
}

}  // namespace

TextureSigma grain_sigma_rgb(
    const std::vector<Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    const int width,
    const int height,
    const ComponentBounds& bounds) noexcept {
    constexpr int pad = 4;
    const int x0 = std::max(1, bounds.min_x - pad);
    const int x1 = std::min(width - 2, bounds.max_x + pad);
    const int y0 = std::max(1, bounds.min_y - pad);
    const int y1 = std::min(height - 2, bounds.max_y + pad);
    if (x1 < x0 || y1 < y0) {
        return {};
    }
    TextureSigma sum{};
    float count = 0.0F;
    for (int y = y0; y <= y1; ++y) {
        for (int x = x0; x <= x1; ++x) {
            const std::size_t index = static_cast<std::size_t>(y) * width + x;
            if (damaged[index] != 0U) {
                continue;
            }
            const auto mean = local_mean_rgb(source, damaged, width, x, y);
            if (!mean.has_value()) {
                continue;
            }
            const Rgba32F sample = source[index];
            sum.red += std::abs(sample.red - mean->red);
            sum.green += std::abs(sample.green - mean->green);
            sum.blue += std::abs(sample.blue - mean->blue);
            count += 1.0F;
        }
    }
    if (count <= 8.0F) {
        return {};
    }
    return {
        std::min(0.05F, sum.red / count * 1.25F),
        std::min(0.05F, sum.green / count * 1.25F),
        std::min(0.05F, sum.blue / count * 1.25F),
    };
}

void transfer_component_texture(
    std::vector<Rgba32F>& repaired,
    const std::vector<Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged_original,
    const int width,
    const int height,
    const std::vector<int>& filled,
    const std::size_t component_count,
    const ComponentBounds& bounds,
    const std::optional<double> cross_angle,
    const TextureSigma sigma,
    std::uint64_t& seed) {
    if (filled.empty()) {
        return;
    }
    const int maximum_side =
        std::max(bounds.max_x - bounds.min_x, bounds.max_y - bounds.min_y) + 1;
    const double average_thickness = static_cast<double>(component_count) /
        static_cast<double>(std::max(1, maximum_side));
    const int displacement = std::min(
        128,
        std::max(6, static_cast<int>(std::round(average_thickness * 2.0)) + 8));
    const float clone_mix = static_cast<float>(
        std::clamp((average_thickness - 10.0) / 120.0, 0.0, 0.42));

    std::vector<Displacement> candidates{};
    candidates.reserve(cross_angle.has_value() ? 20U : 16U);
    if (cross_angle.has_value()) {
        const double radians = *cross_angle * 3.14159265358979323846 / 180.0;
        for (const int radius : {displacement, 2 * displacement}) {
            const int dx = static_cast<int>(
                std::round(std::cos(radians) * static_cast<double>(radius)));
            const int dy = static_cast<int>(
                std::round(std::sin(radians) * static_cast<double>(radius)));
            candidates.push_back({dx, dy});
            candidates.push_back({-dx, -dy});
        }
    }
    for (const int radius : {displacement, 2 * displacement}) {
        candidates.insert(
            candidates.end(),
            {{radius, 0},
             {-radius, 0},
             {0, radius},
             {0, -radius},
             {radius, radius},
             {-radius, -radius},
             {radius, -radius},
             {-radius, radius}});
    }

    const std::vector<int> context =
        context_samples(damaged_original, width, height, bounds);
    const std::optional<Displacement> best = select_displacement(
        candidates,
        filled,
        context,
        source,
        damaged_original,
        width,
        height);
    const TextureSigma cap{
        std::max(1.0e-4F, 3.0F * sigma.red),
        std::max(1.0e-4F, 3.0F * sigma.green),
        std::max(1.0e-4F, 3.0F * sigma.blue),
    };
    for (const int pixel : filled) {
        const int y = pixel / width;
        const int x = pixel - y * width;
        const std::size_t index = static_cast<std::size_t>(pixel);
        bool applied = false;
        if (best.has_value()) {
            const int sample_x = x + best->dx;
            const int sample_y = y + best->dy;
            if (sample_x >= 1 && sample_y >= 1 && sample_x < width - 1 &&
                sample_y < height - 1 &&
                damaged_original[
                    static_cast<std::size_t>(sample_y) * width + sample_x] == 0U) {
                applied = apply_texture_residual(
                    repaired,
                    source,
                    damaged_original,
                    width,
                    x,
                    y,
                    sample_x,
                    sample_y,
                    cap,
                    clone_mix);
            }
        }
        if (!applied) {
            Rgba32F& output = repaired[index];
            output.red = clamp_unit(
                output.red +
                (sigma.red > 0.0F ? sigma.red * next_noise(seed) : 0.0F));
            output.green = clamp_unit(
                output.green +
                (sigma.green > 0.0F ? sigma.green * next_noise(seed) : 0.0F));
            output.blue = clamp_unit(
                output.blue +
                (sigma.blue > 0.0F ? sigma.blue * next_noise(seed) : 0.0F));
        }
    }
}

}  // namespace negaflow::imaging::defect_component_repair_detail
