#include "grain_mend_structure_lines.h"

#include "grain_mend_component_gates.h"
#include "grain_mend_shape.h"

#include <algorithm>
#include <cmath>
#include <unordered_map>
#include <utility>

namespace negaflow::imaging::grain_mend_detail {

// 조율값은 grain_mend_component_types.h 의 한 표에서만 옵니다.
using namespace tuning;

[[nodiscard]] double orientation_difference(
    const double first,
    const double second) noexcept {
    const double difference = std::fmod(std::abs(first - second), 180.0);
    return std::min(difference, 180.0 - difference);
}

[[nodiscard]] std::vector<std::uint8_t> structure_grid_drops(
    const std::vector<Component>& scratch,
    const DetectionImage& image,
    const int radius_reference) {
    std::vector<std::uint8_t> drop(scratch.size(), 0U);
    if (scratch.size() < grid_line_minimum_field) {
        return drop;
    }
    std::vector<StructureLine> lines{};
    lines.reserve(scratch.size());
    for (std::size_t index = 0U; index < scratch.size(); ++index) {
        const Component& component = scratch[index];
        const PcaMetrics metrics = pca_metrics(component, image.width);
        if (metrics.length < grid_line_minimum_length) {
            continue;
        }
        std::size_t sum_x = 0U;
        std::size_t sum_y = 0U;
        for (const std::size_t pixel : component.pixels) {
            sum_x += pixel % image.width;
            sum_y += pixel / image.width;
        }
        lines.push_back({
            static_cast<int>(sum_x / component.pixels.size()),
            static_cast<int>(sum_y / component.pixels.size()),
            static_cast<int>(component.minimum_x),
            static_cast<int>(component.maximum_x),
            static_cast<int>(component.minimum_y),
            static_cast<int>(component.maximum_y),
            metrics.angle_degrees,
            metrics.length,
            index,
        });
    }
    if (lines.size() < grid_line_minimum_field) {
        return drop;
    }

    const auto same_fragment = [&](const StructureLine& first,
                                   const StructureLine& second) noexcept {
        if (orientation_difference(first.angle, second.angle) >
            grid_line_orientation_tolerance) {
            return false;
        }
        const double radians =
            first.angle * 3.14159265358979323846 / 180.0;
        const double offset = std::abs(
            static_cast<double>(second.center_y - first.center_y) *
                std::cos(radians) -
            static_cast<double>(second.center_x - first.center_x) *
                std::sin(radians));
        return offset <= grid_line_collinear_offset;
    };
    const auto votes = [&](const std::size_t subject,
                           const std::size_t other) noexcept {
        if (subject == other) {
            return true;
        }
        if (same_fragment(lines[subject], lines[other])) {
            return false;
        }
        const double longer =
            std::max(lines[subject].length, lines[other].length);
        const double shorter = std::max(
            1.0,
            std::min(lines[subject].length, lines[other].length));
        return longer / shorter <= grid_line_comparable_length_ratio;
    };

    const int reference = radius_reference > 0
        ? radius_reference
        : static_cast<int>(std::min(image.width, image.height));
    const int dense_radius = std::max(
        grid_line_radius_minimum,
        reference / grid_line_radius_divisor);
    std::unordered_map<std::int64_t, std::vector<std::size_t>> buckets{};
    for (std::size_t index = 0U; index < lines.size(); ++index) {
        buckets[bucket_key(
            lines[index].center_x / dense_radius,
            lines[index].center_y / dense_radius)].push_back(index);
    }
    for (std::size_t index = 0U; index < lines.size(); ++index) {
        const StructureLine& line = lines[index];
        const int bucket_x = line.center_x / dense_radius;
        const int bucket_y = line.center_y / dense_radius;
        int nearby = 0;
        for (int x = bucket_x - 1;
             x <= bucket_x + 1 && nearby < grid_line_dense_count;
             ++x) {
            for (int y = bucket_y - 1;
                 y <= bucket_y + 1 && nearby < grid_line_dense_count;
                 ++y) {
                const auto found = buckets.find(bucket_key(x, y));
                if (found == buckets.end()) {
                    continue;
                }
                for (const std::size_t other : found->second) {
                    if (std::abs(lines[other].center_x - line.center_x) <= dense_radius &&
                        std::abs(lines[other].center_y - line.center_y) <= dense_radius &&
                        votes(index, other)) {
                        ++nearby;
                        if (nearby >= grid_line_dense_count) {
                            break;
                        }
                    }
                }
            }
        }
        if (nearby >= grid_line_dense_count) {
            drop[line.component_index] = 1U;
        }
    }

    const int structure_radius = std::max(
        grid_line_radius_minimum,
        reference / grid_line_structure_radius_divisor);
    const auto near_box = [&](const StructureLine& first,
                              const StructureLine& second) noexcept {
        return first.minimum_x - structure_radius <= second.maximum_x &&
               second.minimum_x - structure_radius <= first.maximum_x &&
               first.minimum_y - structure_radius <= second.maximum_y &&
               second.minimum_y - structure_radius <= first.maximum_y;
    };
    std::vector<std::uint8_t> core(lines.size(), 0U);
    for (std::size_t index = 0U; index < lines.size(); ++index) {
        int along = 0;
        int perpendicular = 0;
        for (std::size_t other = 0U; other < lines.size(); ++other) {
            if (!near_box(lines[index], lines[other])) {
                continue;
            }
            const double difference = orientation_difference(
                lines[other].angle,
                lines[index].angle);
            if (difference <= grid_line_orientation_tolerance &&
                votes(index, other)) {
                ++along;
            } else if (std::abs(difference - 90.0) <=
                           grid_line_orientation_tolerance &&
                       votes(index, other)) {
                ++perpendicular;
            }
        }
        core[index] =
            along >= grid_line_parallel_field ||
                    (along >= grid_line_minimum_along &&
                     perpendicular >= grid_line_minimum_perpendicular)
                ? 1U
                : 0U;
    }
    for (std::size_t index = 0U; index < lines.size(); ++index) {
        if (drop[lines[index].component_index] != 0U) {
            continue;
        }
        if (core[index] != 0U) {
            drop[lines[index].component_index] = 1U;
            continue;
        }
        for (std::size_t other = 0U; other < lines.size(); ++other) {
            if (core[other] != 0U &&
                near_box(lines[index], lines[other]) &&
                orientation_difference(lines[other].angle, lines[index].angle) <=
                    grid_line_orientation_tolerance &&
                votes(index, other)) {
                drop[lines[index].component_index] = 1U;
                break;
            }
        }
    }
    return drop;
}

[[nodiscard]] float median_response(
    const Component& component,
    const std::vector<float>& response) {
    std::vector<float> values{};
    values.reserve(component.pixels.size());
    for (const std::size_t pixel : component.pixels) {
        values.push_back(response[pixel]);
    }
    if (values.empty()) {
        return 0.0F;
    }
    const auto middle = values.begin() +
        static_cast<std::ptrdiff_t>(values.size() / 2U);
    std::nth_element(values.begin(), middle, values.end());
    return *middle;
}

[[nodiscard]] double continuation_coverage_from(
    const double start_x,
    const double start_y,
    const double dx,
    const double dy,
    const int span,
    const float level,
    const DetectionImage& image,
    const std::vector<float>& response) noexcept {
    const double perpendicular_x = -dy;
    const double perpendicular_y = dx;
    int samples = 0;
    int hits = 0;
    for (int distance = continuation_gap;
         distance <= continuation_gap + span;
         distance += continuation_step) {
        const double center_x = start_x + dx * static_cast<double>(distance);
        const double center_y = start_y + dy * static_cast<double>(distance);
        float strongest = 0.0F;
        bool inside = false;
        for (int offset = -continuation_perpendicular_tolerance;
             offset <= continuation_perpendicular_tolerance;
             ++offset) {
            const int x = static_cast<int>(std::lround(
                center_x + perpendicular_x * static_cast<double>(offset)));
            const int y = static_cast<int>(std::lround(
                center_y + perpendicular_y * static_cast<double>(offset)));
            if (x < 0 || y < 0 ||
                x >= static_cast<int>(image.width) ||
                y >= static_cast<int>(image.height)) {
                continue;
            }
            inside = true;
            strongest = std::max(
                strongest,
                response[static_cast<std::size_t>(y) * image.width +
                         static_cast<std::size_t>(x)]);
        }
        if (!inside) {
            return -1.0;
        }
        ++samples;
        if (strongest >= level) {
            ++hits;
        }
    }
    return samples > 0
        ? static_cast<double>(hits) / static_cast<double>(samples)
        : -1.0;
}

[[nodiscard]] std::vector<std::uint8_t> continuation_drops(
    const std::vector<Component>& scratch,
    const DetectionImage& image,
    const std::vector<float>& response) {
    std::vector<std::uint8_t> drop(scratch.size(), 0U);
    const std::size_t expected =
        static_cast<std::size_t>(image.width) * image.height;
    if (response.size() != expected) {
        return drop;
    }
    for (std::size_t index = 0U; index < scratch.size(); ++index) {
        const Component& component = scratch[index];
        const PcaMetrics metrics = pca_metrics(component, image.width);
        if (metrics.length < continuation_minimum_length ||
            (metrics.length < static_cast<double>(continuation_minimum_span) &&
             metrics.aspect < continuation_short_minimum_aspect)) {
            continue;
        }
        const float body = median_response(component, response);
        if (body < continuation_minimum_body_response) {
            continue;
        }
        const double radians =
            metrics.angle_degrees * 3.14159265358979323846 / 180.0;
        const double axis_x = std::cos(radians);
        const double axis_y = std::sin(radians);
        double minimum_projection = std::numeric_limits<double>::max();
        double maximum_projection = std::numeric_limits<double>::lowest();
        double minimum_x = 0.0;
        double minimum_y = 0.0;
        double maximum_x = 0.0;
        double maximum_y = 0.0;
        for (const std::size_t pixel : component.pixels) {
            const double x = static_cast<double>(pixel % image.width);
            const double y = static_cast<double>(pixel / image.width);
            const double projection = x * axis_x + y * axis_y;
            if (projection < minimum_projection) {
                minimum_projection = projection;
                minimum_x = x;
                minimum_y = y;
            }
            if (projection > maximum_projection) {
                maximum_projection = projection;
                maximum_x = x;
                maximum_y = y;
            }
        }
        const int span = std::min(
            continuation_maximum_span,
            std::max(
                continuation_minimum_span,
                static_cast<int>(metrics.length)));
        const float level = body * continuation_level_ratio;
        const double forward = continuation_coverage_from(
            maximum_x,
            maximum_y,
            axis_x,
            axis_y,
            span,
            level,
            image,
            response);
        const double backward = continuation_coverage_from(
            minimum_x,
            minimum_y,
            -axis_x,
            -axis_y,
            span,
            level,
            image,
            response);
        if (forward >= strong_continuation_coverage ||
            backward >= strong_continuation_coverage ||
            (forward >= continuation_coverage &&
             backward >= continuation_coverage)) {
            drop[index] = 1U;
        }
    }
    return drop;
}


}  // namespace negaflow::imaging::grain_mend_detail
