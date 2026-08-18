#include "defect_heal_brush_stroke.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <limits>
#include <utility>

namespace negaflow::imaging::heal_brush_detail {

double pixel_distance(
    const DefectBrushPoint first,
    const DefectBrushPoint second,
    const int width,
    const int height) noexcept {
    return std::hypot(
        (first.x - second.x) * width,
        (first.y - second.y) * height);
}

std::vector<BrushChunk> make_chunks(
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
               remaining > tuning::minimum_segment_length) {
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

Rect repair_bounds(
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

double point_segment_distance(
    const double x,
    const double y,
    const PixelPoint first,
    const PixelPoint second) noexcept {
    const double dx = second.x - first.x;
    const double dy = second.y - first.y;
    const double length_squared = dx * dx + dy * dy;
    if (length_squared <= tuning::minimum_segment_length) {
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

std::vector<float> rasterize_mask(
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

std::optional<double> stroke_angle(
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
    double angle = 0.5 * std::atan2(2.0 * xy, xx - yy) * 180.0 / tuning::pi;
    if (angle < 0.0) {
        angle += 180.0;
    }
    if (angle >= 180.0) {
        angle -= 180.0;
    }
    return angle;
}

}  // namespace negaflow::imaging::heal_brush_detail
