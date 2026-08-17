#include "negaflow/imaging/defect_heal_brush.h"

#include "grain_mend_shape.h"

#include "defect_component_repair_detail.h"
#include "grain_mend_morphology.h"

#include "negaflow/color/srgb_transfer.h"
#include "negaflow/core/pixel.h"
#include "negaflow/imaging/coreimage_gaussian.h"
#include "negaflow/imaging/defect_component_repair.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <optional>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

using negaflow::core::Rgba32F;

constexpr double pi = 3.14159265358979323846;
constexpr double minimum_segment_length = 1.0e-6;
constexpr std::size_t maximum_strokes = 100'000U;
constexpr std::size_t maximum_points = 5'000'000U;

struct PixelPoint final {
    double x{0.0};
    double y{0.0};
};

struct Rect final {
    int left{0};
    int top{0};
    int right{0};
    int bottom{0};
};

struct BrushChunk final {
    std::vector<DefectBrushPoint> points{};
    double thickness{0.0};
};

struct StoredPatch final {
    int left{0};
    int top{0};
    int width{0};
    int height{0};
    std::vector<Rgba32F> pixels{};
};


struct Displacement final {
    int dx{0};
    int dy{0};
};

struct ClearRgb final {
    float red{0.0F};
    float green{0.0F};
    float blue{0.0F};
    int distance{0};
};

void discard_pixels(WorkingImage& image) noexcept {
    std::vector<Rgba32F>{}.swap(image.pixels);
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

[[nodiscard]] bool valid_layout(const WorkingImage& image) noexcept {
    if (image.width <= 4U || image.height <= 4U ||
        image.stride_pixels < image.width ||
        image.width > static_cast<std::uint32_t>(
            std::numeric_limits<int>::max()) ||
        image.height > static_cast<std::uint32_t>(
            std::numeric_limits<int>::max())) {
        return false;
    }
    const std::size_t height_minus_one = image.height - 1U;
    if (height_minus_one != 0U &&
        image.stride_pixels >
            (std::numeric_limits<std::size_t>::max() - image.width) /
                height_minus_one) {
        return false;
    }
    return image.pixels.size() >=
        height_minus_one * image.stride_pixels + image.width;
}

[[nodiscard]] bool valid_parameters(
    const DefectHealBrushParameters& parameters) noexcept {
    if (!std::isfinite(parameters.strength) || parameters.strength < 0.0 ||
        parameters.strength > 1.0 || parameters.strokes.size() > maximum_strokes) {
        return false;
    }
    std::size_t point_count = 0U;
    for (const DefectBrushStroke& stroke : parameters.strokes) {
        if (!std::isfinite(stroke.thickness) || stroke.thickness < 0.0 ||
            stroke.thickness > 1.0 ||
            stroke.points.size() > maximum_points - point_count) {
            return false;
        }
        point_count += stroke.points.size();
        for (const DefectBrushPoint point : stroke.points) {
            if (!std::isfinite(point.x) || !std::isfinite(point.y) ||
                point.x < 0.0 || point.x > 1.0 ||
                point.y < 0.0 || point.y > 1.0) {
                return false;
            }
        }
    }
    return true;
}

[[nodiscard]] bool contains(
    const StoredPatch& patch,
    const int x,
    const int y) noexcept {
    return x >= patch.left && y >= patch.top &&
        x - patch.left < patch.width && y - patch.top < patch.height;
}

[[nodiscard]] Rgba32F full_strength_pixel(
    const WorkingImage& base,
    const std::vector<StoredPatch>& patches,
    const int x,
    const int y) noexcept {
    for (auto patch = patches.rbegin(); patch != patches.rend(); ++patch) {
        if (contains(*patch, x, y)) {
            return patch->pixels[
                static_cast<std::size_t>(y - patch->top) * patch->width +
                static_cast<std::size_t>(x - patch->left)];
        }
    }
    return base.pixels[
        static_cast<std::size_t>(y) * base.stride_pixels +
        static_cast<std::size_t>(x)];
}

[[nodiscard]] double pixel_distance(
    const DefectBrushPoint first,
    const DefectBrushPoint second,
    const int width,
    const int height) noexcept {
    return std::hypot(
        (first.x - second.x) * width,
        (first.y - second.y) * height);
}

[[nodiscard]] std::vector<BrushChunk> make_chunks(
    const DefectBrushStroke& stroke,
    const int width,
    const int height) {
    if (stroke.points.empty()) {
        return {};
    }
    if (stroke.points.size() == 1U) {
        return {{{stroke.points.front()}, stroke.thickness}};
    }
    const double minimum_dimension = static_cast<double>(std::min(width, height));
    const double maximum_length = std::max(
        240.0,
        std::min(minimum_dimension * 0.16, 640.0));
    std::vector<BrushChunk> chunks{};
    BrushChunk current{};
    current.thickness = stroke.thickness;
    current.points.push_back(stroke.points.front());
    double current_length = 0.0;
    DefectBrushPoint start = stroke.points.front();
    for (std::size_t index = 1U; index < stroke.points.size(); ++index) {
        const DefectBrushPoint target = stroke.points[index];
        DefectBrushPoint segment_start = start;
        double remaining = pixel_distance(
            segment_start, target, width, height);
        while (current_length + remaining > maximum_length &&
               remaining > minimum_segment_length) {
            const double take = std::max(1.0, maximum_length - current_length);
            const double ratio = std::min(1.0, take / remaining);
            const DefectBrushPoint split{
                segment_start.x + (target.x - segment_start.x) * ratio,
                segment_start.y + (target.y - segment_start.y) * ratio,
            };
            current.points.push_back(split);
            chunks.push_back(std::move(current));
            current = {};
            current.thickness = stroke.thickness;
            current.points.push_back(split);
            current_length = 0.0;
            segment_start = split;
            remaining = pixel_distance(segment_start, target, width, height);
        }
        current.points.push_back(target);
        current_length += remaining;
        start = target;
    }
    if (current.points.size() > 1U) {
        chunks.push_back(std::move(current));
    }
    return chunks;
}

[[nodiscard]] Rect repair_bounds(
    const BrushChunk& chunk,
    const int width,
    const int height) noexcept {
    const double minimum_dimension = static_cast<double>(std::min(width, height));
    const double line_width = std::max(1.0, chunk.thickness * minimum_dimension);
    double minimum_x = std::numeric_limits<double>::max();
    double minimum_y = std::numeric_limits<double>::max();
    double maximum_x = -std::numeric_limits<double>::max();
    double maximum_y = -std::numeric_limits<double>::max();
    for (const DefectBrushPoint point : chunk.points) {
        const double x = point.x * width;
        const double y = point.y * height;
        minimum_x = std::min(minimum_x, x - line_width * 0.5);
        minimum_y = std::min(minimum_y, y - line_width * 0.5);
        maximum_x = std::max(maximum_x, x + line_width * 0.5);
        maximum_y = std::max(maximum_y, y + line_width * 0.5);
    }
    const double halo = std::max(
        96.0,
        std::max(minimum_dimension * 0.025, line_width * 3.2));
    return {
        std::clamp(static_cast<int>(std::floor(minimum_x - halo)), 0, width),
        std::clamp(static_cast<int>(std::floor(minimum_y - halo)), 0, height),
        std::clamp(static_cast<int>(std::ceil(maximum_x + halo)), 0, width),
        std::clamp(static_cast<int>(std::ceil(maximum_y + halo)), 0, height),
    };
}

[[nodiscard]] double point_segment_distance(
    const double x,
    const double y,
    const PixelPoint first,
    const PixelPoint second) noexcept {
    const double dx = second.x - first.x;
    const double dy = second.y - first.y;
    const double length_squared = dx * dx + dy * dy;
    if (length_squared <= minimum_segment_length) {
        return std::hypot(x - first.x, y - first.y);
    }
    const double position = std::clamp(
        ((x - first.x) * dx + (y - first.y) * dy) / length_squared,
        0.0,
        1.0);
    return std::hypot(
        x - (first.x + position * dx),
        y - (first.y + position * dy));
}

[[nodiscard]] std::vector<float> rasterize_mask(
    const BrushChunk& chunk,
    const Rect bounds,
    const int image_width,
    const int image_height) {
    const int width = bounds.right - bounds.left;
    const int height = bounds.bottom - bounds.top;
    std::vector<float> mask(
        static_cast<std::size_t>(width) * height, 0.0F);
    std::vector<PixelPoint> points{};
    points.reserve(chunk.points.size());
    for (const DefectBrushPoint point : chunk.points) {
        points.push_back({point.x * image_width, point.y * image_height});
    }
    const double radius = std::max(
        0.5,
        chunk.thickness * static_cast<double>(
            std::min(image_width, image_height)) * 0.5);
    for (int y = 0; y < height; ++y) {
        const double pixel_y = static_cast<double>(bounds.top + y) + 0.5;
        for (int x = 0; x < width; ++x) {
            const double pixel_x = static_cast<double>(bounds.left + x) + 0.5;
            double distance = std::hypot(
                pixel_x - points.front().x,
                pixel_y - points.front().y);
            for (std::size_t point = 1U; point < points.size(); ++point) {
                distance = std::min(
                    distance,
                    point_segment_distance(
                        pixel_x,
                        pixel_y,
                        points[point - 1U],
                        points[point]));
            }
            mask[static_cast<std::size_t>(y) * width + x] =
                static_cast<float>(std::clamp(radius + 0.5 - distance, 0.0, 1.0));
        }
    }
    return mask;
}

[[nodiscard]] std::vector<float> gaussian_radius_one(
    const std::vector<float>& source,
    const int width,
    const int height) {
    constexpr float radius = 1.0F;
    const float sigma = coreimage_gaussian_effective_sigma(radius);
    const int support_radius = coreimage_gaussian_support_radius(radius);
    std::vector<float> weights(
        static_cast<std::size_t>(support_radius * 2 + 1));
    float total = 0.0F;
    for (int offset = -support_radius; offset <= support_radius; ++offset) {
        const float value = std::exp(
            -static_cast<float>(offset * offset) / (2.0F * sigma * sigma));
        weights[static_cast<std::size_t>(offset + support_radius)] = value;
        total += value;
    }
    for (float& weight : weights) {
        weight /= total;
    }
    std::vector<float> horizontal(source.size(), 0.0F);
    std::vector<float> output(source.size(), 0.0F);
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            float value = 0.0F;
            for (int offset = -support_radius;
                 offset <= support_radius;
                 ++offset) {
                const int sample_x = x + offset;
                if (sample_x >= 0 && sample_x < width) {
                    value += source[
                        static_cast<std::size_t>(y) * width + sample_x] *
                        weights[static_cast<std::size_t>(offset + support_radius)];
                }
            }
            horizontal[static_cast<std::size_t>(y) * width + x] = value;
        }
    }
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            float value = 0.0F;
            for (int offset = -support_radius;
                 offset <= support_radius;
                 ++offset) {
                const int sample_y = y + offset;
                if (sample_y >= 0 && sample_y < height) {
                    value += horizontal[
                        static_cast<std::size_t>(sample_y) * width + x] *
                        weights[static_cast<std::size_t>(offset + support_radius)];
                }
            }
            output[static_cast<std::size_t>(y) * width + x] = value;
        }
    }
    return output;
}

// 형태 측정은 grain_mend_shape 하나만 씁니다. 두께와 각도만 쓰지만 같은 셈이어야
// 브러시가 보는 획 방향과 검출 게이트가 보는 방향이 갈리지 않습니다.
[[nodiscard]] grain_mend_detail::PcaMetrics pca_metrics(
    const std::vector<int>& component,
    const int width) noexcept {
    return grain_mend_detail::pca_metrics(component, width);
}

[[nodiscard]] std::optional<double> stroke_angle(
    const BrushChunk& chunk,
    const int width,
    const int height) noexcept {
    if (chunk.points.size() < 2U) {
        return std::nullopt;
    }
    const double count = static_cast<double>(chunk.points.size());
    double mean_x = 0.0;
    double mean_y = 0.0;
    for (const DefectBrushPoint point : chunk.points) {
        mean_x += point.x * width;
        mean_y += point.y * height;
    }
    mean_x /= count;
    mean_y /= count;
    double xx = 0.0;
    double yy = 0.0;
    double xy = 0.0;
    for (const DefectBrushPoint point : chunk.points) {
        const double dx = point.x * width - mean_x;
        const double dy = point.y * height - mean_y;
        xx += dx * dx;
        yy += dy * dy;
        xy += dx * dy;
    }
    const double rms = std::sqrt((xx + yy) / count);
    if (rms < static_cast<double>(std::min(width, height)) * 0.01) {
        return std::nullopt;
    }
    const double anisotropy = std::sqrt(
        (xx - yy) * (xx - yy) + 4.0 * xy * xy) /
        std::max(1.0e-6, xx + yy);
    if (anisotropy <= 0.3) {
        return std::nullopt;
    }
    double angle = 0.5 * std::atan2(2.0 * xy, xx - yy) * 180.0 / pi;
    if (angle < 0.0) {
        angle += 180.0;
    }
    if (angle >= 180.0) {
        angle -= 180.0;
    }
    return angle;
}

void add_displacement(
    std::vector<Displacement>& values,
    const double angle,
    const double distance) {
    const int dx = static_cast<int>(std::llround(std::cos(angle) * distance));
    const int dy = static_cast<int>(std::llround(std::sin(angle) * distance));
    if (dx != 0 || dy != 0) {
        values.push_back({dx, dy});
        values.push_back({-dx, -dy});
    }
}

[[nodiscard]] std::vector<int> context_ring(
    const std::vector<std::uint8_t>& damaged,
    const int width,
    const int height,
    const defect_component_repair_detail::ComponentBounds& bounds) {
    std::vector<int> ring{};
    const int x0 = std::max(0, bounds.min_x - 5);
    const int x1 = std::min(width - 1, bounds.max_x + 5);
    const int y0 = std::max(0, bounds.min_y - 5);
    const int y1 = std::min(height - 1, bounds.max_y + 5);
    for (int y = y0; y <= y1; ++y) {
        for (int x = x0; x <= x1; ++x) {
            const int pixel = y * width + x;
            if (damaged[static_cast<std::size_t>(pixel)] == 0U) {
                ring.push_back(pixel);
            }
        }
    }
    if (ring.size() <= 96U) {
        return ring;
    }
    const std::size_t step = ring.size() / 96U;
    std::vector<int> sampled{};
    for (std::size_t index = 0U; index < ring.size(); index += step) {
        sampled.push_back(ring[index]);
    }
    return sampled;
}

[[nodiscard]] double context_ssd(
    const std::vector<int>& ring,
    const Displacement displacement,
    const std::vector<Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    const int width,
    const int height) noexcept {
    if (ring.empty()) {
        return std::numeric_limits<double>::max();
    }
    double sum = 0.0;
    std::size_t count = 0U;
    for (const int pixel : ring) {
        const int y = pixel / width;
        const int x = pixel - y * width;
        const int sx = x + displacement.dx;
        const int sy = y + displacement.dy;
        if (sx < 0 || sy < 0 || sx >= width || sy >= height) {
            continue;
        }
        const int other = sy * width + sx;
        if (damaged[static_cast<std::size_t>(other)] != 0U) {
            continue;
        }
        const Rgba32F first = source[static_cast<std::size_t>(pixel)];
        const Rgba32F second = source[static_cast<std::size_t>(other)];
        const double dr = first.red - second.red;
        const double dg = first.green - second.green;
        const double db = first.blue - second.blue;
        sum += dr * dr + dg * dg + db * db;
        ++count;
    }
    return count * 2U >= ring.size()
        ? sum / static_cast<double>(count)
        : std::numeric_limits<double>::max();
}

[[nodiscard]] std::optional<ClearRgb> find_clear(
    const std::vector<Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    const int width,
    const int height,
    const int x,
    const int y,
    const double dx,
    const double dy,
    const double sign) noexcept {
    for (int step = 1; step <= 160; ++step) {
        const int sx = x + static_cast<int>(std::llround(
            dx * sign * static_cast<double>(step)));
        const int sy = y + static_cast<int>(std::llround(
            dy * sign * static_cast<double>(step)));
        if (sx < 0 || sy < 0 || sx >= width || sy >= height) {
            break;
        }
        const std::size_t pixel =
            static_cast<std::size_t>(sy) * width + sx;
        if (damaged[pixel] == 0U) {
            const Rgba32F value = source[pixel];
            return ClearRgb{value.red, value.green, value.blue, step};
        }
    }
    return std::nullopt;
}

[[nodiscard]] std::optional<Rgba32F> cross_fill(
    const std::vector<Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    const int width,
    const int height,
    const int x,
    const int y,
    const double axis) noexcept {
    const std::array<double, 2U> directions{{axis + pi * 0.5, axis}};
    for (const double direction : directions) {
        const double dx = std::cos(direction);
        const double dy = std::sin(direction);
        const auto first = find_clear(
            source, damaged, width, height, x, y, dx, dy, 1.0);
        const auto second = find_clear(
            source, damaged, width, height, x, y, dx, dy, -1.0);
        if (first.has_value() && second.has_value()) {
            const float position = static_cast<float>(first->distance) /
                static_cast<float>(first->distance + second->distance);
            return Rgba32F{
                first->red + (second->red - first->red) * position,
                first->green + (second->green - first->green) * position,
                first->blue + (second->blue - first->blue) * position,
                1.0F,
            };
        }
        const auto& only = first.has_value() ? first : second;
        if (only.has_value()) {
            return Rgba32F{only->red, only->green, only->blue, 1.0F};
        }
    }
    return std::nullopt;
}

[[nodiscard]] bool heal_component(
    const std::vector<int>& component,
    const defect_component_repair_detail::ComponentBounds& bounds,
    const std::vector<Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    const int width,
    const int height,
    const std::optional<double> preferred_angle,
    std::vector<Rgba32F>& healed) {
    const grain_mend_detail::PcaMetrics pca = pca_metrics(component, width);
    const double angle_degrees = preferred_angle.value_or(pca.angle_degrees);
    const double axis = angle_degrees * pi / 180.0;
    const double thickness = std::max(4.0, pca.thickness);
    const int base = static_cast<int>(std::llround(thickness + 6.0));
    std::vector<Displacement> candidates{};
    const double perpendicular = axis + pi * 0.5;
    for (const double multiple : {1.4, 2.0, 2.8}) {
        add_displacement(candidates, perpendicular, base * multiple);
    }
    for (const double multiple : {1.6, 2.4}) {
        add_displacement(candidates, axis, base * multiple);
    }
    for (const double multiple : {1.7, 2.5}) {
        add_displacement(
            candidates, perpendicular + pi * 0.25, base * multiple);
        add_displacement(
            candidates, perpendicular - pi * 0.25, base * multiple);
    }
    const std::vector<int> ring = context_ring(
        damaged, width, height, bounds);
    std::optional<Displacement> best{};
    double best_ssd = std::numeric_limits<double>::max();
    for (const Displacement candidate : candidates) {
        bool valid = true;
        for (const int pixel : component) {
            const int y = pixel / width;
            const int x = pixel - y * width;
            const int sx = x + candidate.dx;
            const int sy = y + candidate.dy;
            if (sx < 0 || sy < 0 || sx >= width || sy >= height ||
                damaged[static_cast<std::size_t>(sy) * width + sx] != 0U) {
                valid = false;
                break;
            }
        }
        if (!valid) {
            continue;
        }
        const double ssd = context_ssd(
            ring, candidate, source, damaged, width, height);
        if (!best.has_value() || ssd < best_ssd) {
            best = candidate;
            best_ssd = ssd;
        }
    }
    if (!best.has_value()) {
        return false;
    }

    std::vector<Rgba32F> filled = source;
    for (const int pixel : component) {
        const int y = pixel / width;
        const int x = pixel - y * width;
        const auto value = cross_fill(
            source, damaged, width, height, x, y, axis);
        if (value.has_value()) {
            filled[static_cast<std::size_t>(pixel)].red = value->red;
            filled[static_cast<std::size_t>(pixel)].green = value->green;
            filled[static_cast<std::size_t>(pixel)].blue = value->blue;
        }
    }
    const std::uint32_t radius = static_cast<std::uint32_t>(std::max(
        4,
        std::min(16, static_cast<int>(std::llround(thickness * 0.5)))));
    std::array<std::vector<float>, 3U> low{};
    for (std::size_t channel = 0U; channel < low.size(); ++channel) {
        std::vector<float> values(filled.size());
        for (std::size_t pixel = 0U; pixel < filled.size(); ++pixel) {
            values[pixel] = channel == 0U
                ? filled[pixel].red
                : channel == 1U ? filled[pixel].green : filled[pixel].blue;
        }
        low[channel] = grain_mend_detail::box_mean(
            values,
            static_cast<std::uint32_t>(width),
            static_cast<std::uint32_t>(height),
            radius);
    }
    for (const int pixel : component) {
        const int y = pixel / width;
        const int x = pixel - y * width;
        const int sample =
            (y + best->dy) * width + (x + best->dx);
        const std::size_t destination = static_cast<std::size_t>(pixel);
        const std::size_t source_pixel = static_cast<std::size_t>(sample);
        healed[destination].red = std::clamp(
            source[source_pixel].red + low[0][destination] - low[0][source_pixel],
            0.0F,
            1.0F);
        healed[destination].green = std::clamp(
            source[source_pixel].green + low[1][destination] - low[1][source_pixel],
            0.0F,
            1.0F);
        healed[destination].blue = std::clamp(
            source[source_pixel].blue + low[2][destination] - low[2][source_pixel],
            0.0F,
            1.0F);
    }
    return true;
}

[[nodiscard]] StoredPatch fallback_patch(
    const std::vector<Rgba32F>& linear,
    const std::vector<float>& mask,
    const Rect bounds,
    const std::optional<double> angle) {
    const int width = bounds.right - bounds.left;
    const int height = bounds.bottom - bounds.top;
    WorkingImage roi{};
    roi.width = static_cast<std::uint32_t>(width);
    roi.height = static_cast<std::uint32_t>(height);
    roi.stride_pixels = static_cast<std::uint32_t>(width);
    roi.pixels = linear;
    std::vector<std::uint8_t> weights(mask.size());
    for (std::size_t pixel = 0U; pixel < mask.size(); ++pixel) {
        weights[pixel] = static_cast<std::uint8_t>(std::clamp(
            std::floor(static_cast<double>(mask[pixel]) * 255.0 + 0.5),
            0.0,
            255.0));
    }
    DefectComponentRepairParameters parameters{};
    parameters.has_preferred_angle = angle.has_value();
    parameters.preferred_angle_degrees = angle.value_or(0.0);
    auto repaired = repair_defect_components(
        std::move(roi), weights, static_cast<std::size_t>(width), parameters);
    if (repaired.status != DefectComponentRepairStatus::ok) {
        throw std::bad_alloc{};
    }
    return {
        bounds.left,
        bounds.top,
        width,
        height,
        std::move(repaired.image.pixels),
    };
}

[[nodiscard]] StoredPatch make_patch(
    const WorkingImage& base,
    const std::vector<StoredPatch>& preceding,
    const BrushChunk& chunk,
    bool& used_fallback,
    std::size_t& component_count,
    std::size_t& healed_pixels) {
    const int image_width = static_cast<int>(base.width);
    const int image_height = static_cast<int>(base.height);
    const Rect bounds = repair_bounds(
        chunk, image_width, image_height);
    const int width = bounds.right - bounds.left;
    const int height = bounds.bottom - bounds.top;
    if (width <= 4 || height <= 4) {
        return {};
    }
    const std::size_t count = static_cast<std::size_t>(width) * height;
    if (count > defect_heal_brush_maximum_patch_bytes / sizeof(Rgba32F)) {
        throw std::bad_alloc{};
    }
    std::vector<Rgba32F> linear(count);
    std::vector<Rgba32F> encoded(count);
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const std::size_t pixel = static_cast<std::size_t>(y) * width + x;
            linear[pixel] = full_strength_pixel(
                base, preceding, bounds.left + x, bounds.top + y);
            encoded[pixel] = {
                negaflow::color::linear_to_srgb_encoded(linear[pixel].red),
                negaflow::color::linear_to_srgb_encoded(linear[pixel].green),
                negaflow::color::linear_to_srgb_encoded(linear[pixel].blue),
                linear[pixel].alpha,
            };
        }
    }
    const std::vector<float> mask = rasterize_mask(
        chunk, bounds, image_width, image_height);
    std::vector<std::uint8_t> damaged(count, 0U);
    for (std::size_t pixel = 0U; pixel < count; ++pixel) {
        if (mask[pixel] * 255.0F > 8.0F) {
            damaged[pixel] = 1U;
            ++healed_pixels;
        }
    }
    const auto angle = stroke_angle(chunk, image_width, image_height);
    std::vector<Rgba32F> healed = encoded;
    bool all_healed = true;
    defect_component_repair_detail::for_each_component(
        damaged,
        width,
        height,
        [&](const std::vector<int>& component,
            const defect_component_repair_detail::ComponentBounds& component_bounds) {
            if (!all_healed) {
                return;
            }
            ++component_count;
            all_healed = heal_component(
                component,
                component_bounds,
                encoded,
                damaged,
                width,
                height,
                angle,
                healed);
        });
    if (!all_healed) {
        used_fallback = true;
        return fallback_patch(linear, mask, bounds, angle);
    }

    const std::vector<float> feathered = gaussian_radius_one(mask, width, height);
    StoredPatch patch{};
    patch.left = bounds.left;
    patch.top = bounds.top;
    patch.width = width;
    patch.height = height;
    patch.pixels.resize(count);
    for (std::size_t pixel = 0U; pixel < count; ++pixel) {
        const float blend = std::clamp(feathered[pixel], 0.0F, 1.0F);
        const float keep = 1.0F - blend;
        const Rgba32F repaired_linear{
            negaflow::color::srgb_encoded_to_linear(healed[pixel].red),
            negaflow::color::srgb_encoded_to_linear(healed[pixel].green),
            negaflow::color::srgb_encoded_to_linear(healed[pixel].blue),
            linear[pixel].alpha,
        };
        patch.pixels[pixel] = {
            linear[pixel].red * keep + repaired_linear.red * blend,
            linear[pixel].green * keep + repaired_linear.green * blend,
            linear[pixel].blue * keep + repaired_linear.blue * blend,
            linear[pixel].alpha,
        };
    }
    return patch;
}

[[nodiscard]] float quantize_linear16(const float value) noexcept {
    const double encoded = std::floor(
        static_cast<double>(std::clamp(value, 0.0F, 1.0F)) * 65'535.0 + 0.5);
    return static_cast<float>(encoded / 65'535.0);
}

void composite_patches(
    WorkingImage& image,
    const std::vector<StoredPatch>& patches,
    const float strength) {
    std::vector<std::uint8_t> covered(
        static_cast<std::size_t>(image.width) * image.height,
        0U);
    for (auto current = patches.rbegin(); current != patches.rend(); ++current) {
        const StoredPatch& patch = *current;
        for (int y = 0; y < patch.height; ++y) {
            for (int x = 0; x < patch.width; ++x) {
                const std::size_t patch_pixel =
                    static_cast<std::size_t>(y) * patch.width + x;
                const std::size_t image_pixel =
                    static_cast<std::size_t>(patch.top + y) *
                        image.stride_pixels +
                    static_cast<std::size_t>(patch.left + x);
                const std::size_t packed_pixel =
                    static_cast<std::size_t>(patch.top + y) * image.width +
                    static_cast<std::size_t>(patch.left + x);
                if (covered[packed_pixel] != 0U) {
                    continue;
                }
                covered[packed_pixel] = 1U;
                Rgba32F& destination = image.pixels[image_pixel];
                const Rgba32F full = patch.pixels[patch_pixel];
                const float keep = 1.0F - strength;
                destination.red = destination.red * keep +
                    quantize_linear16(full.red) * strength;
                destination.green = destination.green * keep +
                    quantize_linear16(full.green) * strength;
                destination.blue = destination.blue * keep +
                    quantize_linear16(full.blue) * strength;
            }
        }
    }
}

}  // namespace

DefectHealBrushResult apply_defect_heal_brush(
    WorkingImage image,
    const DefectHealBrushParameters& parameters) noexcept {
    DefectHealBrushResult result{};
    result.image = std::move(image);
    if (!valid_layout(result.image) || !valid_parameters(parameters)) {
        discard_pixels(result.image);
        return result;
    }
    const auto kernel_status = negaflow::core::validate_finite_pixels(
        const_view(result.image));
    if (kernel_status != negaflow::core::KernelStatus::ok) {
        result.status = DefectHealBrushStatus::kernel_failed;
        discard_pixels(result.image);
        return result;
    }
    if (parameters.strength <= 1.0e-3 || parameters.strokes.empty()) {
        result.status = DefectHealBrushStatus::ok;
        return result;
    }
    try {
        std::vector<BrushChunk> chunks{};
        for (const DefectBrushStroke& stroke : parameters.strokes) {
            auto stroke_chunks = make_chunks(
                stroke,
                static_cast<int>(result.image.width),
                static_cast<int>(result.image.height));
            for (BrushChunk& chunk : stroke_chunks) {
                chunks.push_back(std::move(chunk));
            }
        }
        std::vector<StoredPatch> patches{};
        patches.reserve(chunks.size());
        std::size_t patch_bytes = 0U;
        for (const BrushChunk& chunk : chunks) {
            bool fallback = false;
            std::size_t components = 0U;
            std::size_t pixels = 0U;
            StoredPatch patch = make_patch(
                result.image,
                patches,
                chunk,
                fallback,
                components,
                pixels);
            if (patch.pixels.empty()) {
                continue;
            }
            const std::size_t bytes = patch.pixels.size() * sizeof(Rgba32F);
            if (bytes > defect_heal_brush_maximum_patch_bytes - patch_bytes) {
                throw std::bad_alloc{};
            }
            patch_bytes += bytes;
            result.info.peak_patch_bytes = std::max(
                result.info.peak_patch_bytes,
                bytes);
            ++result.info.applied_chunk_count;
            result.info.healed_component_count += components;
            result.info.healed_pixels += pixels;
            result.info.fallback_chunk_count += fallback ? 1U : 0U;
            patches.push_back(std::move(patch));
        }
        composite_patches(
            result.image,
            patches,
            static_cast<float>(parameters.strength));
        result.info.applied = !patches.empty();
        result.status = DefectHealBrushStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.status = DefectHealBrushStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    } catch (...) {
        result.status = DefectHealBrushStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    }
}

const char* defect_heal_brush_status_name(
    const DefectHealBrushStatus status) noexcept {
    switch (status) {
        case DefectHealBrushStatus::ok:
            return "ok";
        case DefectHealBrushStatus::invalid_argument:
            return "invalid_argument";
        case DefectHealBrushStatus::kernel_failed:
            return "kernel_failed";
        case DefectHealBrushStatus::allocation_failed:
            return "allocation_failed";
    }
    return "unknown";
}

}  // namespace negaflow::imaging
