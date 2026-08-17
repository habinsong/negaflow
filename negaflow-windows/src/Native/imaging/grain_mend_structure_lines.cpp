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

// macOS `medianResponse` — 컴포넌트 본체의 대표 응답(중앙값)이며 비율 판정의 분모입니다.
// 평균은 밝은 교차점 하나에 끌려갑니다. `sampler` 는 macOS 의 `responseAt` 클로저 자리이며,
// 타일 로컬 배열과 프레임 전역 저해상도 맵을 같은 판정으로 씁니다.
template <typename Sampler>
[[nodiscard]] float median_response(
    const Component& component,
    const std::uint32_t width,
    const Sampler& sampler) {
    std::vector<float> values{};
    values.reserve(component.pixels.size());
    for (const std::size_t pixel : component.pixels) {
        const int y = static_cast<int>(pixel / width);
        const int x = static_cast<int>(pixel - static_cast<std::size_t>(y) * width);
        float value = 0.0F;
        if (sampler(x, y, value)) {
            values.push_back(value);
        }
    }
    if (values.empty()) {
        return 0.0F;
    }
    const auto middle = values.begin() +
        static_cast<std::ptrdiff_t>(values.size() / 2U);
    std::nth_element(values.begin(), middle, values.end());
    return *middle;
}

// macOS `continuationCoverageOf` — 끝점에서 (dx,dy) 방향으로 연장하며 응답이 level 이상으로
// 이어지는 샘플 비율(0~1)입니다. 샘플 경로가 판정 범위 밖으로 나가면 판정 불가를 뜻하는
// 음수를 돌려줍니다.
template <typename Sampler>
[[nodiscard]] double continuation_coverage_from(
    const double start_x,
    const double start_y,
    const double dx,
    const double dy,
    const int span,
    const float level,
    const Sampler& sampler) {
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
            float value = 0.0F;
            if (!sampler(x, y, value)) {
                continue;
            }
            inside = true;
            strongest = std::max(strongest, value);
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

// macOS `continuationDrops(scratch:width:responseAt:)` — 양 끝 연장선에 같은 선이 계속되는
// 스크래치 컴포넌트를 고릅니다.
template <typename Sampler>
[[nodiscard]] std::vector<std::uint8_t> continuation_drops_with(
    const std::vector<Component>& scratch,
    const std::uint32_t width,
    const Sampler& sampler) {
    std::vector<std::uint8_t> drop(scratch.size(), 0U);
    if (width == 0U) {
        return drop;
    }
    for (std::size_t index = 0U; index < scratch.size(); ++index) {
        const Component& component = scratch[index];
        const PcaMetrics metrics = pca_metrics(component, width);
        if (metrics.length < continuation_minimum_length ||
            (metrics.length < static_cast<double>(continuation_minimum_span) &&
             metrics.aspect < continuation_short_minimum_aspect)) {
            continue;
        }
        const float body = median_response(component, width, sampler);
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
            const double x = static_cast<double>(pixel % width);
            const double y = static_cast<double>(pixel / width);
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
            maximum_x, maximum_y, axis_x, axis_y, span, level, sampler);
        const double backward = continuation_coverage_from(
            minimum_x, minimum_y, -axis_x, -axis_y, span, level, sampler);
        if (forward >= strong_continuation_coverage ||
            backward >= strong_continuation_coverage ||
            (forward >= continuation_coverage &&
             backward >= continuation_coverage)) {
            drop[index] = 1U;
        }
    }
    return drop;
}

// macOS `continuationDrops(scratch:response:width:height:)` — 타일 로컬 응답 배열용
// 편의 진입점입니다.
std::vector<std::uint8_t> continuation_drops(
    const std::vector<Component>& scratch,
    const DetectionImage& image,
    const std::vector<float>& response) {
    const std::size_t expected =
        static_cast<std::size_t>(image.width) * image.height;
    if (image.width == 0U || image.height == 0U || response.size() != expected) {
        return std::vector<std::uint8_t>(scratch.size(), 0U);
    }
    const std::uint32_t width = image.width;
    const std::uint32_t height = image.height;
    return continuation_drops_with(
        scratch,
        width,
        [&](const int x, const int y, float& value) {
            if (x < 0 || y < 0 || x >= static_cast<int>(width) ||
                y >= static_cast<int>(height)) {
                return false;
            }
            value = response[static_cast<std::size_t>(y) * width +
                             static_cast<std::size_t>(x)];
            return true;
        });
}

// macOS `rejectingGlobalStructureLines` 가 쓰는 진입점입니다 — 전역 저해상도 응답 맵을
// 같은 판정에 넘깁니다(`responseAt: { x, y in responseMap.value(atX: x, y: y) }`).
std::vector<std::uint8_t> continuation_drops(
    const std::vector<Component>& scratch,
    const std::uint32_t width,
    const ScratchResponseMap& response) {
    return continuation_drops_with(
        scratch,
        width,
        [&](const int x, const int y, float& value) {
            if (x < 0 || y < 0) {
                return false;
            }
            return response.value(
                static_cast<std::uint32_t>(x),
                static_cast<std::uint32_t>(y),
                value);
        });
}

}  // namespace negaflow::imaging::grain_mend_detail
