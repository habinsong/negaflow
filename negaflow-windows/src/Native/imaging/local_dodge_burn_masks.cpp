#include "local_dodge_burn_masks.h"

#include "local_dodge_burn_blur.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <new>

namespace negaflow::imaging::local_dodge_burn_detail {

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

}  // namespace negaflow::imaging::local_dodge_burn_detail
