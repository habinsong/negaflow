#include "negaflow/imaging/local_dodge_burn.h"

#include "negaflow/core/parallel_rows.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

constexpr float adjustment_identity_threshold = 1.0e-4F;
constexpr float mask_blur_identity_threshold = 0.25F;
constexpr float direct_gaussian_maximum_sigma = 32.0F;

struct PixelPoint final {
    float x;
    float y;
};

struct MaskResult final {
    std::vector<float> weights{};
    std::size_t scratch_peak_bytes{0U};
};

void discard_pixels(WorkingImage& image) noexcept {
    std::vector<negaflow::core::Rgba32F>{}.swap(image.pixels);
}

[[nodiscard]] negaflow::core::ConstImageView const_view(
    const WorkingImage& image) noexcept {
    return {
        image.pixels.data(),
        image.pixels.size(),
        image.width,
        image.height,
        image.stride_pixels,
    };
}

[[nodiscard]] std::size_t pixel_count(const WorkingImage& image) {
    if (image.width == 0U || image.height == 0U ||
        static_cast<std::size_t>(image.width) >
            std::numeric_limits<std::size_t>::max() /
                static_cast<std::size_t>(image.height)) {
        throw std::bad_alloc{};
    }
    return static_cast<std::size_t>(image.width) * image.height;
}

[[nodiscard]] std::size_t index_of(
    const std::uint32_t x,
    const std::uint32_t y,
    const std::uint32_t width) noexcept {
    return static_cast<std::size_t>(y) * width + x;
}

[[nodiscard]] float clamp_unit(const float value) noexcept {
    return std::clamp(value, 0.0F, 1.0F);
}

[[nodiscard]] PixelPoint pixel_point(
    const LocalDodgeBurnPoint point,
    const WorkingImage& image) noexcept {
    return {
        clamp_unit(point.x) * static_cast<float>(image.width),
        clamp_unit(point.y) * static_cast<float>(image.height),
    };
}

[[nodiscard]] std::vector<float> box_blur(
    const std::vector<float>& source,
    const std::uint32_t width,
    const std::uint32_t height,
    const int radius) {
    if (radius <= 0) {
        return source;
    }
    std::vector<float> horizontal(source.size());
    std::vector<float> result(source.size());
    const float inverse = 1.0F / static_cast<float>(radius * 2 + 1);
    // Each sweep carries a running sum along its own line and touches no other, so the
    // horizontal pass splits by row and the vertical one by column. Same arithmetic in
    // the same order within a line, so the totals are identical.
    const std::uint64_t work_units =
        static_cast<std::uint64_t>(width) * static_cast<std::uint64_t>(height);
    negaflow::core::for_each_row_block(
        height,
        work_units,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
      for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
        float sum = 0.0F;
        for (int offset = -radius; offset <= radius; ++offset) {
            const auto sample_x = static_cast<std::uint32_t>(std::clamp(
                offset,
                0,
                static_cast<int>(width) - 1));
            sum += source[index_of(sample_x, y, width)];
        }
        for (std::uint32_t x = 0U; x < width; ++x) {
            horizontal[index_of(x, y, width)] = sum * inverse;
            const auto remove_x = static_cast<std::uint32_t>(std::clamp(
                static_cast<int>(x) - radius,
                0,
                static_cast<int>(width) - 1));
            const auto add_x = static_cast<std::uint32_t>(std::clamp(
                static_cast<int>(x) + radius + 1,
                0,
                static_cast<int>(width) - 1));
            sum += source[index_of(add_x, y, width)] -
                   source[index_of(remove_x, y, width)];
        }
      }
        });
    negaflow::core::for_each_row_block(
        width,
        work_units,
        [&](const std::uint32_t first_column, const std::uint32_t column_count) noexcept {
      for (std::uint32_t x = first_column; x < first_column + column_count; ++x) {
        float sum = 0.0F;
        for (int offset = -radius; offset <= radius; ++offset) {
            const auto sample_y = static_cast<std::uint32_t>(std::clamp(
                offset,
                0,
                static_cast<int>(height) - 1));
            sum += horizontal[index_of(x, sample_y, width)];
        }
        for (std::uint32_t y = 0U; y < height; ++y) {
            result[index_of(x, y, width)] = sum * inverse;
            const auto remove_y = static_cast<std::uint32_t>(std::clamp(
                static_cast<int>(y) - radius,
                0,
                static_cast<int>(height) - 1));
            const auto add_y = static_cast<std::uint32_t>(std::clamp(
                static_cast<int>(y) + radius + 1,
                0,
                static_cast<int>(height) - 1));
            sum += horizontal[index_of(x, add_y, width)] -
                   horizontal[index_of(x, remove_y, width)];
        }
      }
        });
    return result;
}

[[nodiscard]] std::vector<float> direct_gaussian_blur(
    const std::vector<float>& source,
    const std::uint32_t width,
    const std::uint32_t height,
    const float sigma) {
    const int radius = std::max(1, static_cast<int>(std::ceil(3.0F * sigma)));
    std::vector<float> weights(static_cast<std::size_t>(radius * 2 + 1));
    float total = 0.0F;
    for (int offset = -radius; offset <= radius; ++offset) {
        const float weight = std::exp(
            -static_cast<float>(offset * offset) / (2.0F * sigma * sigma));
        weights[static_cast<std::size_t>(offset + radius)] = weight;
        total += weight;
    }
    for (float& weight : weights) {
        weight /= total;
    }

    std::vector<float> horizontal(source.size());
    std::vector<float> result(source.size());
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            float value = 0.0F;
            for (int offset = -radius; offset <= radius; ++offset) {
                const auto sample_x = static_cast<std::uint32_t>(std::clamp(
                    static_cast<int>(x) + offset,
                    0,
                    static_cast<int>(width) - 1));
                value += source[index_of(sample_x, y, width)] *
                         weights[static_cast<std::size_t>(offset + radius)];
            }
            horizontal[index_of(x, y, width)] = value;
        }
    }
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            float value = 0.0F;
            for (int offset = -radius; offset <= radius; ++offset) {
                const auto sample_y = static_cast<std::uint32_t>(std::clamp(
                    static_cast<int>(y) + offset,
                    0,
                    static_cast<int>(height) - 1));
                value += horizontal[index_of(x, sample_y, width)] *
                         weights[static_cast<std::size_t>(offset + radius)];
            }
            result[index_of(x, y, width)] = value;
        }
    }
    return result;
}

[[nodiscard]] std::vector<float> scalable_gaussian_blur(
    const std::vector<float>& source,
    const std::uint32_t width,
    const std::uint32_t height,
    const float sigma) {
    constexpr int passes = 3;
    const float ideal_width = std::sqrt(
        12.0F * sigma * sigma / static_cast<float>(passes) + 1.0F);
    int lower_width = static_cast<int>(std::floor(ideal_width));
    if ((lower_width & 1) == 0) {
        --lower_width;
    }
    lower_width = std::max(1, lower_width);
    const int upper_width = lower_width + 2;
    const float numerator =
        12.0F * sigma * sigma -
        static_cast<float>(passes * lower_width * lower_width +
                           4 * passes * lower_width + 3 * passes);
    const int lower_passes = std::clamp(
        static_cast<int>(std::lround(
            numerator / static_cast<float>(-4 * lower_width - 4))),
        0,
        passes);

    std::vector<float> result = source;
    for (int pass = 0; pass < passes; ++pass) {
        const int width_for_pass =
            pass < lower_passes ? lower_width : upper_width;
        result = box_blur(
            result,
            width,
            height,
            (width_for_pass - 1) / 2);
    }
    return result;
}

void soften_mask(
    MaskResult& mask,
    const WorkingImage& image,
    const float sigma) {
    if (sigma <= mask_blur_identity_threshold) {
        return;
    }
    const std::size_t bytes = mask.weights.size() * sizeof(float);
    mask.scratch_peak_bytes = std::max(mask.scratch_peak_bytes, bytes * 3U);
    mask.weights = sigma <= direct_gaussian_maximum_sigma
        ? direct_gaussian_blur(mask.weights, image.width, image.height, sigma)
        : scalable_gaussian_blur(mask.weights, image.width, image.height, sigma);
    for (float& weight : mask.weights) {
        weight = clamp_unit(weight);
    }
}

void rasterize_segment(
    std::vector<float>& mask,
    const WorkingImage& image,
    const PixelPoint first,
    const PixelPoint second,
    const float radius) noexcept {
    const float minimum_x = std::min(first.x, second.x) - radius;
    const float maximum_x = std::max(first.x, second.x) + radius;
    const float minimum_y = std::min(first.y, second.y) - radius;
    const float maximum_y = std::max(first.y, second.y) + radius;
    const std::uint32_t x0 = static_cast<std::uint32_t>(std::max(
        0.0F,
        std::floor(minimum_x)));
    const std::uint32_t x1 = static_cast<std::uint32_t>(std::min(
        static_cast<float>(image.width),
        std::ceil(maximum_x)));
    const std::uint32_t y0 = static_cast<std::uint32_t>(std::max(
        0.0F,
        std::floor(minimum_y)));
    const std::uint32_t y1 = static_cast<std::uint32_t>(std::min(
        static_cast<float>(image.height),
        std::ceil(maximum_y)));
    const float dx = second.x - first.x;
    const float dy = second.y - first.y;
    const float length_squared = dx * dx + dy * dy;
    const float radius_squared = radius * radius;
    for (std::uint32_t y = y0; y < y1; ++y) {
        for (std::uint32_t x = x0; x < x1; ++x) {
            const float sample_x = static_cast<float>(x) + 0.5F;
            const float sample_y = static_cast<float>(y) + 0.5F;
            const float projection = length_squared > 0.0F
                ? std::clamp(
                      ((sample_x - first.x) * dx +
                       (sample_y - first.y) * dy) /
                          length_squared,
                      0.0F,
                      1.0F)
                : 0.0F;
            const float nearest_x = first.x + projection * dx;
            const float nearest_y = first.y + projection * dy;
            const float distance_x = sample_x - nearest_x;
            const float distance_y = sample_y - nearest_y;
            if (distance_x * distance_x + distance_y * distance_y <=
                radius_squared) {
                mask[index_of(x, y, image.width)] = 1.0F;
            }
        }
    }
}

[[nodiscard]] MaskResult brush_mask(
    const LocalDodgeBurnMask& source,
    const WorkingImage& image) {
    MaskResult result{};
    result.weights.assign(pixel_count(image), 0.0F);
    result.scratch_peak_bytes = result.weights.size() * sizeof(float);
    const float minimum_dimension =
        static_cast<float>(std::min(image.width, image.height));
    float maximum_feather = 0.0F;
    bool drew = false;
    for (const LocalDodgeBurnStroke& stroke : source.strokes) {
        if (stroke.points.empty()) {
            continue;
        }
        const float line_width = std::max(
            1.0F,
            std::clamp(stroke.thickness, 0.001F, 0.25F) *
                minimum_dimension);
        maximum_feather = std::max(
            maximum_feather,
            std::clamp(stroke.feather, 0.0F, 0.25F) * minimum_dimension);
        if (stroke.points.size() == 1U) {
            const PixelPoint point = pixel_point(stroke.points.front(), image);
            rasterize_segment(
                result.weights,
                image,
                point,
                point,
                line_width * 0.5F);
            drew = true;
            continue;
        }
        for (std::size_t index = 1U; index < stroke.points.size(); ++index) {
            rasterize_segment(
                result.weights,
                image,
                pixel_point(stroke.points[index - 1U], image),
                pixel_point(stroke.points[index], image),
                line_width * 0.5F);
            drew = true;
        }
    }
    if (!drew) {
        result.weights.clear();
        return result;
    }
    soften_mask(result, image, maximum_feather);
    return result;
}

[[nodiscard]] MaskResult radial_mask(
    const LocalDodgeBurnMask& source,
    const WorkingImage& image) {
    MaskResult result{};
    result.weights.resize(pixel_count(image));
    result.scratch_peak_bytes = result.weights.size() * sizeof(float);
    const PixelPoint center = pixel_point(source.center, image);
    const float radius = std::max(
        1.0F,
        std::clamp(source.radius, 0.001F, 2.0F) *
            static_cast<float>(std::min(image.width, image.height)));
    const float feather = std::clamp(source.feather, 0.0F, 1.0F);
    const float inner = radius * (1.0F - feather);
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            const float dx = static_cast<float>(x) + 0.5F - center.x;
            const float dy = static_cast<float>(y) + 0.5F - center.y;
            const float distance = std::sqrt(dx * dx + dy * dy);
            float weight = 0.0F;
            if (distance <= inner) {
                weight = 1.0F;
            } else if (distance < radius && radius > inner) {
                weight = (radius - distance) / (radius - inner);
            }
            result.weights[index_of(x, y, image.width)] = weight;
        }
    }
    return result;
}

[[nodiscard]] MaskResult linear_mask(
    const LocalDodgeBurnMask& source,
    const WorkingImage& image) {
    const PixelPoint start = pixel_point(source.start, image);
    const PixelPoint end = pixel_point(source.end, image);
    const float dx = end.x - start.x;
    const float dy = end.y - start.y;
    const float length_squared = dx * dx + dy * dy;
    if (length_squared <= 1.0F) {
        return {};
    }
    MaskResult result{};
    result.weights.resize(pixel_count(image));
    result.scratch_peak_bytes = result.weights.size() * sizeof(float);
    const float feather = std::clamp(source.feather, 0.0F, 1.0F);
    const float plateau_end = 1.0F - feather;
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            const float sample_x = static_cast<float>(x) + 0.5F;
            const float sample_y = static_cast<float>(y) + 0.5F;
            const float position =
                ((sample_x - start.x) * dx + (sample_y - start.y) * dy) /
                length_squared;
            float weight = 0.0F;
            if (position <= plateau_end) {
                weight = 1.0F;
            } else if (position < 1.0F && feather > 0.0F) {
                weight = (1.0F - position) / feather;
            }
            result.weights[index_of(x, y, image.width)] = clamp_unit(weight);
        }
    }
    return result;
}

[[nodiscard]] bool point_inside_polygon(
    const float sample_x,
    const float sample_y,
    const std::vector<PixelPoint>& points) noexcept {
    bool inside = false;
    std::size_t previous = points.size() - 1U;
    for (std::size_t current = 0U; current < points.size(); ++current) {
        const PixelPoint first = points[current];
        const PixelPoint second = points[previous];
        const bool crosses = (first.y > sample_y) != (second.y > sample_y);
        if (crosses) {
            const float crossing_x =
                (second.x - first.x) * (sample_y - first.y) /
                    (second.y - first.y) +
                first.x;
            if (sample_x < crossing_x) {
                inside = !inside;
            }
        }
        previous = current;
    }
    return inside;
}

[[nodiscard]] MaskResult polygon_mask(
    const LocalDodgeBurnMask& source,
    const WorkingImage& image) {
    if (source.points.size() < 3U) {
        return {};
    }
    std::vector<PixelPoint> points{};
    points.reserve(source.points.size());
    for (const LocalDodgeBurnPoint point : source.points) {
        points.push_back(pixel_point(point, image));
    }
    MaskResult result{};
    result.weights.resize(pixel_count(image));
    result.scratch_peak_bytes =
        result.weights.size() * sizeof(float) +
        points.size() * sizeof(PixelPoint);
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            result.weights[index_of(x, y, image.width)] =
                point_inside_polygon(
                    static_cast<float>(x) + 0.5F,
                    static_cast<float>(y) + 0.5F,
                    points)
                    ? 1.0F
                    : 0.0F;
        }
    }
    const float sigma = std::clamp(source.feather, 0.0F, 0.25F) *
                        static_cast<float>(std::min(image.width, image.height));
    soften_mask(result, image, sigma);
    return result;
}

[[nodiscard]] MaskResult make_mask(
    const LocalDodgeBurnMask& mask,
    const WorkingImage& image) {
    switch (mask.kind) {
        case LocalDodgeBurnMaskKind::brush:
            return brush_mask(mask, image);
        case LocalDodgeBurnMaskKind::radial:
            return radial_mask(mask, image);
        case LocalDodgeBurnMaskKind::linear:
            return linear_mask(mask, image);
        case LocalDodgeBurnMaskKind::polygon:
            return polygon_mask(mask, image);
    }
    return {};
}

[[nodiscard]] bool mask_has_weight(
    const std::vector<float>& mask) noexcept {
    return std::any_of(mask.begin(), mask.end(), [](const float weight) {
        return weight > 0.0F;
    });
}

void apply_adjustment(
    WorkingImage& image,
    const LocalDodgeBurnAdjustment& adjustment,
    const std::vector<float>& mask) noexcept {
    const float amount = clamp_unit(adjustment.amount);
    const float stops = adjustment.mode == LocalDodgeBurnMode::dodge
        ? amount
        : -amount;
    const float exposure = std::exp2(stops);
    negaflow::core::for_each_row_block(
        image.height,
        static_cast<std::uint64_t>(image.width) *
            static_cast<std::uint64_t>(image.height),
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
      for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
        auto* const row = image.pixels.data() +
            static_cast<std::size_t>(y) * image.stride_pixels;
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            const float weight = mask[index_of(x, y, image.width)];
            if (weight <= 0.0F) {
                continue;
            }
            const float scale = 1.0F + (exposure - 1.0F) * weight;
            row[x].red *= scale;
            row[x].green *= scale;
            row[x].blue *= scale;
        }
      }
        });
}

[[nodiscard]] bool finite_point(const LocalDodgeBurnPoint point) noexcept {
    return std::isfinite(point.x) && std::isfinite(point.y);
}

}  // namespace

bool valid_local_dodge_burn_parameters(
    const LocalDodgeBurnParameters& parameters) noexcept {
    if (parameters.adjustments.size() >
        local_dodge_burn_maximum_adjustments) {
        return false;
    }
    std::size_t total_points = 0U;
    for (const LocalDodgeBurnAdjustment& adjustment : parameters.adjustments) {
        if (!std::isfinite(adjustment.amount) ||
            static_cast<std::uint8_t>(adjustment.mode) >
                static_cast<std::uint8_t>(LocalDodgeBurnMode::burn) ||
            static_cast<std::uint8_t>(adjustment.mask.kind) >
                static_cast<std::uint8_t>(LocalDodgeBurnMaskKind::polygon) ||
            !finite_point(adjustment.mask.center) ||
            !finite_point(adjustment.mask.start) ||
            !finite_point(adjustment.mask.end) ||
            !std::isfinite(adjustment.mask.radius) ||
            !std::isfinite(adjustment.mask.feather) ||
            adjustment.mask.strokes.size() >
                local_dodge_burn_maximum_strokes_per_mask) {
            return false;
        }
        if (adjustment.mask.points.size() >
            local_dodge_burn_maximum_points - total_points) {
            return false;
        }
        total_points += adjustment.mask.points.size();
        for (const LocalDodgeBurnPoint point : adjustment.mask.points) {
            if (!finite_point(point)) {
                return false;
            }
        }
        for (const LocalDodgeBurnStroke& stroke : adjustment.mask.strokes) {
            if (!std::isfinite(stroke.thickness) ||
                !std::isfinite(stroke.feather) ||
                stroke.points.size() >
                    local_dodge_burn_maximum_points - total_points) {
                return false;
            }
            total_points += stroke.points.size();
            for (const LocalDodgeBurnPoint point : stroke.points) {
                if (!finite_point(point)) {
                    return false;
                }
            }
        }
    }
    return true;
}

LocalDodgeBurnResult apply_local_dodge_burn(
    WorkingImage image,
    const LocalDodgeBurnParameters& parameters) noexcept {
    LocalDodgeBurnResult result{};
    result.image = std::move(image);
    if (!valid_local_dodge_burn_parameters(parameters)) {
        discard_pixels(result.image);
        return result;
    }
    result.info.kernel_status =
        negaflow::core::validate_finite_pixels(const_view(result.image));
    if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
        result.status = LocalDodgeBurnStatus::kernel_failed;
        discard_pixels(result.image);
        return result;
    }
    if (parameters.adjustments.empty()) {
        result.status = LocalDodgeBurnStatus::ok;
        return result;
    }

    try {
        for (const LocalDodgeBurnAdjustment& adjustment :
             parameters.adjustments) {
            if (!adjustment.enabled ||
                clamp_unit(adjustment.amount) <=
                    adjustment_identity_threshold) {
                continue;
            }
            MaskResult mask = make_mask(adjustment.mask, result.image);
            result.info.mask_scratch_peak_bytes = std::max(
                result.info.mask_scratch_peak_bytes,
                mask.scratch_peak_bytes);
            if (mask.weights.empty() || !mask_has_weight(mask.weights)) {
                continue;
            }
            apply_adjustment(result.image, adjustment, mask.weights);
            ++result.info.adjustments_applied;
        }
        result.info.applied = result.info.adjustments_applied != 0U;
        result.status = LocalDodgeBurnStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.status = LocalDodgeBurnStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    } catch (...) {
        result.status = LocalDodgeBurnStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    }
}

const char* local_dodge_burn_status_name(
    const LocalDodgeBurnStatus status) noexcept {
    switch (status) {
        case LocalDodgeBurnStatus::ok:
            return "ok";
        case LocalDodgeBurnStatus::invalid_parameter:
            return "invalid_parameter";
        case LocalDodgeBurnStatus::kernel_failed:
            return "kernel_failed";
        case LocalDodgeBurnStatus::allocation_failed:
            return "allocation_failed";
    }
    return "unknown";
}

}  // namespace negaflow::imaging
