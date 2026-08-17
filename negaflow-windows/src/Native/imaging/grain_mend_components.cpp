#include "grain_mend_components.h"

#include "grain_mend_shape.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <unordered_map>
#include <utility>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {
namespace {

constexpr std::size_t maximum_automatic_dust_area = 150U;
constexpr double maximum_automatic_dust_aspect = 4.0;
constexpr double minimum_automatic_scratch_aspect = 2.5;
constexpr double minimum_pca_scratch_length = 12.0;
constexpr double maximum_automatic_scratch_thickness = 12.0;
constexpr double dust_minimum_strong_fraction = 0.08;
constexpr double weak_geometry_minimum_length = 80.0;
constexpr double weak_geometry_maximum_thickness = 3.0;
constexpr double weak_geometry_minimum_aspect = 15.0;
constexpr std::size_t isolation_minimum_structure = 8U;
constexpr std::uint32_t isolation_maximum_ring_padding = 24U;
constexpr double isolation_maximum_ring_density = 0.10;
constexpr std::size_t grain_field_small_component_maximum = 12U;
constexpr int grain_field_radius = 48;
constexpr int grain_field_count = 10;
constexpr std::size_t grid_line_minimum_field = 8U;
constexpr double grid_line_minimum_length = 6.0;
constexpr int grid_line_radius_minimum = 48;
constexpr int grid_line_radius_divisor = 6;
constexpr int grid_line_dense_count = 5;
constexpr double grid_line_orientation_tolerance = 22.0;
constexpr int grid_line_structure_radius_divisor = 4;
constexpr int grid_line_parallel_field = 5;
constexpr int grid_line_minimum_along = 2;
constexpr int grid_line_minimum_perpendicular = 2;
constexpr double grid_line_collinear_offset = 12.0;
constexpr double grid_line_comparable_length_ratio = 2.5;
constexpr int continuation_gap = 16;
constexpr int continuation_minimum_span = 24;
constexpr int continuation_maximum_span = 80;
constexpr double continuation_minimum_length = 12.0;
constexpr double continuation_short_minimum_aspect = 4.0;
constexpr int continuation_step = 2;
constexpr int continuation_perpendicular_tolerance = 2;
constexpr float continuation_level_ratio = 0.5F;
constexpr double continuation_coverage = 0.6;
constexpr double strong_continuation_coverage = 0.8;
constexpr float continuation_minimum_body_response = 1.0e-4F;

struct Component final {
    std::vector<std::size_t> pixels{};
    std::uint32_t minimum_x{0U};
    std::uint32_t maximum_x{0U};
    std::uint32_t minimum_y{0U};
    std::uint32_t maximum_y{0U};
    bool has_strong{false};
    std::size_t strong_count{0U};
};

struct SmallComponent final {
    int center_x{0};
    int center_y{0};
    bool dust{false};
    std::size_t component_index{0U};
};

struct StructureLine final {
    int center_x{0};
    int center_y{0};
    int minimum_x{0};
    int maximum_x{0};
    int minimum_y{0};
    int maximum_y{0};
    double angle{0.0};
    double length{0.0};
    std::size_t component_index{0U};
};

[[nodiscard]] std::int64_t bucket_key(int x, int y) noexcept;

[[nodiscard]] std::vector<Component> collect_components(
    const DetectionImage& image,
    const std::vector<std::uint8_t>& weak,
    const std::vector<std::uint8_t>& strong,
    const std::uint8_t evidence) {
    const std::size_t count =
        static_cast<std::size_t>(image.width) * image.height;
    std::vector<std::uint8_t> visited(count, 0U);
    std::vector<std::size_t> stack{};
    std::vector<Component> result{};
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            const std::size_t seed = static_cast<std::size_t>(y) * image.width + x;
            if (visited[seed] != 0U ||
                (weak[seed] & evidence) == 0U) {
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
                const std::uint32_t current_y =
                    static_cast<std::uint32_t>(index / image.width);
                const std::uint32_t current_x =
                    static_cast<std::uint32_t>(index % image.width);
                component.minimum_x = std::min(component.minimum_x, current_x);
                component.maximum_x = std::max(component.maximum_x, current_x);
                component.minimum_y = std::min(component.minimum_y, current_y);
                component.maximum_y = std::max(component.maximum_y, current_y);
                if ((strong[index] & evidence) != 0U) {
                    component.has_strong = true;
                    ++component.strong_count;
                }

                for (int dy = -1; dy <= 1; ++dy) {
                    for (int dx = -1; dx <= 1; ++dx) {
                        if (dx == 0 && dy == 0) {
                            continue;
                        }
                        const int neighbor_x = static_cast<int>(current_x) + dx;
                        const int neighbor_y = static_cast<int>(current_y) + dy;
                        if (neighbor_x < 0 || neighbor_y < 0 ||
                            neighbor_x >= static_cast<int>(image.width) ||
                            neighbor_y >= static_cast<int>(image.height)) {
                            continue;
                        }
                        const std::size_t neighbor =
                            static_cast<std::size_t>(neighbor_y) * image.width +
                            static_cast<std::size_t>(neighbor_x);
                        if (visited[neighbor] == 0U &&
                            (weak[neighbor] & evidence) != 0U) {
                            visited[neighbor] = 1U;
                            stack.push_back(neighbor);
                        }
                    }
                }
            }
            result.push_back(std::move(component));
        }
    }
    return result;
}

[[nodiscard]] double bounding_aspect(const Component& component) noexcept {
    const std::uint32_t width =
        component.maximum_x - component.minimum_x + 1U;
    const std::uint32_t height =
        component.maximum_y - component.minimum_y + 1U;
    return static_cast<double>(std::max(width, height)) /
           static_cast<double>(std::max(1U, std::min(width, height)));
}

[[nodiscard]] bool passes_dust_gate(
    const Component& component,
    const std::size_t maximum_area,
    const double maximum_aspect,
    const double minimum_thickness,
    const double maximum_thickness) noexcept {
    if (component.pixels.size() <= maximum_area &&
        bounding_aspect(component) <= maximum_aspect) {
        return true;
    }
    const std::uint32_t width =
        component.maximum_x - component.minimum_x + 1U;
    const std::uint32_t height =
        component.maximum_y - component.minimum_y + 1U;
    const double average_thickness =
        static_cast<double>(component.pixels.size()) /
        static_cast<double>(std::max(width, height));
    return average_thickness >= minimum_thickness &&
           average_thickness <= maximum_thickness;
}

// 채택된 컴포넌트를 분류해 담습니다. 게이트가 이미 끝난 뒤이므로 채택 여부는 바뀌지 않고
// 메타데이터만 붙습니다 — macOS `DefectClassifier.classify` 가 서는 자리와 같습니다.
//
// pinhole/emulsion 경계는 macOS 와 같은 식입니다:
//   pinholeMaxArea  = max(16, 분류면적/25)
//   emulsionMinArea = max(200, 분류면적/3)
void collect_classified(
    const std::vector<Component>& dust,
    const std::vector<std::uint8_t>& drop_dust,
    const std::vector<Component>& scratch,
    const std::vector<std::uint8_t>& drop_scratch,
    const DetectionImage& image,
    const CandidateMaps* const candidates,
    const std::size_t maximum_dust_area,
    std::vector<ClassifiedComponent>& result) {
    const std::size_t count =
        static_cast<std::size_t>(image.width) * image.height;
    result.clear();
    result.reserve(dust.size() + scratch.size());
    auto append = [&result](const Component& component, const bool is_scratch) {
        ClassifiedComponent entry{};
        entry.pixels = component.pixels;
        entry.minimum_x = component.minimum_x;
        entry.maximum_x = component.maximum_x;
        entry.minimum_y = component.minimum_y;
        entry.maximum_y = component.maximum_y;
        entry.is_scratch = is_scratch;
        result.push_back(std::move(entry));
    };
    for (std::size_t index = 0U; index < dust.size(); ++index) {
        if (drop_dust[index] == 0U) {
            append(dust[index], false);
        }
    }
    for (std::size_t index = 0U; index < scratch.size(); ++index) {
        if (drop_scratch[index] == 0U) {
            append(scratch[index], true);
        }
    }
    if (candidates == nullptr || result.empty() ||
        candidates->dust_magnitude.size() != count) {
        return;
    }

    // 극성은 "컴포넌트 평균 밝기 − 주변 링 평균"이고, 링에서 라벨된 화소를 뺍니다.
    std::vector<std::int32_t> labels(count, -1);
    for (std::size_t index = 0U; index < result.size(); ++index) {
        for (const std::size_t pixel : result[index].pixels) {
            labels[pixel] = static_cast<std::int32_t>(index);
        }
    }
    ClassifierField field{};
    field.width = image.width;
    field.height = image.height;
    field.dust_magnitude = &candidates->dust_magnitude;
    field.thin_magnitude = &candidates->thin_magnitude;
    field.noise_scale = &candidates->noise_scale;
    field.bright = &image.brightest_channel;
    field.strong = &candidates->strong;
    field.labels = &labels;
    classify_components(
        result,
        field,
        std::max<std::size_t>(16U, maximum_dust_area / 25U),
        std::max<std::size_t>(200U, maximum_dust_area / 3U));
}

// 형태 측정은 grain_mend_shape 하나만 씁니다 — 게이트와 분류기가 같은 모양을 봐야 합니다.
[[nodiscard]] PcaMetrics pca_metrics(
    const Component& component,
    const std::uint32_t image_width) noexcept {
    return grain_mend_detail::pca_metrics(component.pixels, image_width);
}

[[nodiscard]] bool passes_scratch_gate(
    const Component& component,
    const std::uint32_t image_width,
    const std::uint32_t minimum_length,
    const double minimum_aspect) noexcept {
    const std::uint32_t box_width =
        component.maximum_x - component.minimum_x + 1U;
    const std::uint32_t box_height =
        component.maximum_y - component.minimum_y + 1U;
    const std::uint32_t long_side = std::max(box_width, box_height);
    const std::uint32_t short_side =
        std::max(1U, std::min(box_width, box_height));
    const double box_aspect =
        static_cast<double>(long_side) / static_cast<double>(short_side);

    const PcaMetrics pca = pca_metrics(component, image_width);
    if (pca.thickness > maximum_automatic_scratch_thickness) {
        return false;
    }
    const bool box_pass =
        long_side >= minimum_length &&
        box_aspect >= minimum_aspect;
    const bool pca_pass =
        pca.length >= std::max(
            static_cast<double>(minimum_length),
            minimum_pca_scratch_length) &&
        pca.aspect >= minimum_aspect;
    return box_pass || pca_pass;
}

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

[[nodiscard]] std::vector<std::uint8_t> make_chunky_map(
    const std::vector<Component>& components,
    const std::size_t count) {
    std::vector<std::uint8_t> result(count, 0U);
    for (const Component& component : components) {
        if (component.pixels.size() < isolation_minimum_structure) {
            continue;
        }
        for (const std::size_t index : component.pixels) {
            result[index] = 1U;
        }
    }
    return result;
}

[[nodiscard]] bool is_isolated(
    const Component& component,
    const std::vector<std::uint8_t>& chunky,
    const DetectionImage& image) noexcept {
    const std::uint32_t box_width =
        component.maximum_x - component.minimum_x + 1U;
    const std::uint32_t box_height =
        component.maximum_y - component.minimum_y + 1U;
    const std::uint32_t padding = std::max(
        8U,
        std::min(
            isolation_maximum_ring_padding,
            2U * std::min(box_width, box_height)));
    const std::uint32_t x0 =
        component.minimum_x > padding ? component.minimum_x - padding : 0U;
    const std::uint32_t y0 =
        component.minimum_y > padding ? component.minimum_y - padding : 0U;
    const std::uint32_t x1 = std::min(
        image.width - 1U,
        component.maximum_x + padding);
    const std::uint32_t y1 = std::min(
        image.height - 1U,
        component.maximum_y + padding);
    std::size_t total = 0U;
    std::size_t hits = 0U;
    for (std::uint32_t y = y0; y <= y1; ++y) {
        const bool within_y =
            y >= component.minimum_y && y <= component.maximum_y;
        for (std::uint32_t x = x0; x <= x1; ++x) {
            if (within_y &&
                x >= component.minimum_x && x <= component.maximum_x) {
                continue;
            }
            ++total;
            if (chunky[static_cast<std::size_t>(y) * image.width + x] != 0U) {
                ++hits;
            }
        }
    }
    return total == 0U ||
           static_cast<double>(hits) / static_cast<double>(total) <=
               isolation_maximum_ring_density;
}

[[nodiscard]] std::int64_t bucket_key(const int x, const int y) noexcept {
    return static_cast<std::int64_t>(x) * 1'000'003LL +
           static_cast<std::int64_t>(y);
}

void mark_grain_field_drops(
    const std::vector<Component>& dust,
    const std::vector<Component>& scratch,
    const std::uint32_t width,
    std::vector<std::uint8_t>& drop_dust,
    std::vector<std::uint8_t>& drop_scratch) {
    std::vector<SmallComponent> small{};
    const auto add_small = [&](const std::vector<Component>& components,
                               const bool dust_kind) {
        for (std::size_t component_index = 0U;
             component_index < components.size();
             ++component_index) {
            const Component& component = components[component_index];
            if (component.pixels.size() > grain_field_small_component_maximum) {
                continue;
            }
            std::size_t sum_x = 0U;
            std::size_t sum_y = 0U;
            for (const std::size_t pixel : component.pixels) {
                sum_x += pixel % width;
                sum_y += pixel / width;
            }
            small.push_back({
                static_cast<int>(sum_x / component.pixels.size()),
                static_cast<int>(sum_y / component.pixels.size()),
                dust_kind,
                component_index,
            });
        }
    };
    add_small(dust, true);
    add_small(scratch, false);
    if (small.size() < static_cast<std::size_t>(grain_field_count)) {
        return;
    }

    std::unordered_map<std::int64_t, std::vector<std::size_t>> buckets{};
    for (std::size_t index = 0U; index < small.size(); ++index) {
        const SmallComponent& component = small[index];
        buckets[bucket_key(
            component.center_x / grain_field_radius,
            component.center_y / grain_field_radius)].push_back(index);
    }
    for (const SmallComponent& component : small) {
        const int bucket_x = component.center_x / grain_field_radius;
        const int bucket_y = component.center_y / grain_field_radius;
        int nearby = 0;
        for (int neighbor_x = bucket_x - 1;
             neighbor_x <= bucket_x + 1 && nearby < grain_field_count;
             ++neighbor_x) {
            for (int neighbor_y = std::max(0, bucket_y - 1);
                 neighbor_y <= bucket_y + 1 && nearby < grain_field_count;
                 ++neighbor_y) {
                const auto found = buckets.find(bucket_key(neighbor_x, neighbor_y));
                if (found == buckets.end()) {
                    continue;
                }
                for (const std::size_t index : found->second) {
                    const SmallComponent& other = small[index];
                    if (std::abs(other.center_x - component.center_x) <=
                            grain_field_radius &&
                        std::abs(other.center_y - component.center_y) <=
                            grain_field_radius) {
                        ++nearby;
                        if (nearby >= grain_field_count) {
                            break;
                        }
                    }
                }
            }
        }
        if (nearby >= grain_field_count) {
            if (component.dust) {
                drop_dust[component.component_index] = 1U;
            } else {
                drop_scratch[component.component_index] = 1U;
            }
        }
    }
}

void paint_component(
    const Component& component,
    const int radius,
    const DetectionImage& image,
    std::vector<std::uint8_t>& mask) noexcept {
    for (const std::size_t pixel : component.pixels) {
        const int y = static_cast<int>(pixel / image.width);
        const int x = static_cast<int>(pixel % image.width);
        for (int dy = -radius; dy <= radius; ++dy) {
            for (int dx = -radius; dx <= radius; ++dx) {
                const int mask_x = x + dx;
                const int mask_y = y + dy;
                if (mask_x >= 0 && mask_y >= 0 &&
                    mask_x < static_cast<int>(image.width) &&
                    mask_y < static_cast<int>(image.height)) {
                    mask[static_cast<std::size_t>(mask_y) * image.width +
                         static_cast<std::size_t>(mask_x)] = 1U;
                }
            }
        }
    }
}

void fill_interior_holes(
    const Component& component,
    const DetectionImage& image,
    const std::size_t maximum_dust_area,
    std::vector<std::uint8_t>& mask) {
    const std::uint32_t x0 = component.minimum_x == 0U
        ? 0U
        : component.minimum_x - 1U;
    const std::uint32_t y0 = component.minimum_y == 0U
        ? 0U
        : component.minimum_y - 1U;
    const std::uint32_t x1 = std::min(
        image.width - 1U,
        component.maximum_x + 1U);
    const std::uint32_t y1 = std::min(
        image.height - 1U,
        component.maximum_y + 1U);
    const std::uint32_t box_width = x1 - x0 + 1U;
    const std::uint32_t box_height = y1 - y0 + 1U;
    if (box_width <= 2U || box_height <= 2U) {
        return;
    }
    const std::size_t local_count =
        static_cast<std::size_t>(box_width) * box_height;
    std::vector<std::uint8_t> outside(local_count, 0U);
    std::vector<std::size_t> stack{};
    const auto local_index = [&](const std::uint32_t x,
                                 const std::uint32_t y) noexcept {
        return static_cast<std::size_t>(y - y0) * box_width + (x - x0);
    };
    const auto defect = [&](const std::uint32_t x,
                            const std::uint32_t y) noexcept {
        return mask[static_cast<std::size_t>(y) * image.width + x] != 0U;
    };
    const auto seed = [&](const std::uint32_t x, const std::uint32_t y) {
        const std::size_t index = local_index(x, y);
        if (!defect(x, y) && outside[index] == 0U) {
            outside[index] = 1U;
            stack.push_back(index);
        }
    };
    for (std::uint32_t x = x0; x <= x1; ++x) {
        seed(x, y0);
        seed(x, y1);
    }
    for (std::uint32_t y = y0; y <= y1; ++y) {
        seed(x0, y);
        seed(x1, y);
    }
    constexpr std::array<std::pair<int, int>, 4U> neighbors{{
        {1, 0}, {-1, 0}, {0, 1}, {0, -1},
    }};
    while (!stack.empty()) {
        const std::size_t current = stack.back();
        stack.pop_back();
        const int x = static_cast<int>(current % box_width + x0);
        const int y = static_cast<int>(current / box_width + y0);
        for (const auto [dx, dy] : neighbors) {
            const int neighbor_x = x + dx;
            const int neighbor_y = y + dy;
            if (neighbor_x < static_cast<int>(x0) ||
                neighbor_y < static_cast<int>(y0) ||
                neighbor_x > static_cast<int>(x1) ||
                neighbor_y > static_cast<int>(y1)) {
                continue;
            }
            const auto nx = static_cast<std::uint32_t>(neighbor_x);
            const auto ny = static_cast<std::uint32_t>(neighbor_y);
            const std::size_t next = local_index(nx, ny);
            if (outside[next] == 0U && !defect(nx, ny)) {
                outside[next] = 1U;
                stack.push_back(next);
            }
        }
    }

    std::vector<std::size_t> holes{};
    for (std::uint32_t y = y0; y <= y1; ++y) {
        for (std::uint32_t x = x0; x <= x1; ++x) {
            if (!defect(x, y) && outside[local_index(x, y)] == 0U) {
                holes.push_back(static_cast<std::size_t>(y) * image.width + x);
            }
        }
    }
    const std::size_t maximum_hole_area = std::min(
        maximum_dust_area,
        component.pixels.size() * 2U);
    if (holes.empty() || holes.size() > maximum_hole_area) {
        return;
    }
    for (const std::size_t pixel : holes) {
        mask[pixel] = 1U;
    }
}

}  // namespace

std::vector<std::uint8_t> build_automatic_evidence(
    const DetectionImage& image,
    const CandidateMaps& candidates,
    const std::size_t maximum_dust_area,
    const std::uint32_t minimum_scratch_length,
    const double dust_sensitivity,
    const bool labeled_detection) {
    std::vector<std::uint8_t> evidence{};
    build_automatic_evidence(
        image,
        candidates,
        maximum_dust_area,
        minimum_scratch_length,
        dust_sensitivity,
        labeled_detection,
        evidence);
    return evidence;
}

void build_automatic_evidence(
    const DetectionImage& image,
    const CandidateMaps& candidates,
    const std::size_t maximum_dust_area,
    const std::uint32_t minimum_scratch_length,
    const double dust_sensitivity,
    const bool labeled_detection,
    std::vector<std::uint8_t>& evidence) {
    const std::size_t count =
        static_cast<std::size_t>(image.width) * image.height;
    std::vector<Component> dust = collect_components(
        image, candidates.weak, candidates.strong, 1U);
    std::vector<Component> scratch = collect_components(
        image, candidates.weak, candidates.strong, 2U);
    const std::vector<std::uint8_t> chunky = make_chunky_map(dust, count);
    const double maximum_dust_aspect = labeled_detection
        ? 4.0 + dust_sensitivity * 4.0
        : maximum_automatic_dust_aspect;
    const double minimum_scratch_aspect = labeled_detection
        ? 2.5 - dust_sensitivity * 0.7
        : minimum_automatic_scratch_aspect;
    const double minimum_thick_defect = labeled_detection ? 4.0 : 1.0;
    const double maximum_thick_defect = labeled_detection
        ? 12.0 + dust_sensitivity * 12.0
        : 0.0;

    dust.erase(
        std::remove_if(
            dust.begin(),
            dust.end(),
            [&](const Component& component) {
                return !component.has_strong ||
                       (labeled_detection &&
                        static_cast<double>(component.strong_count) /
                                static_cast<double>(component.pixels.size()) <
                            dust_minimum_strong_fraction) ||
                       !passes_dust_gate(
                           component,
                           maximum_dust_area,
                           maximum_dust_aspect,
                           minimum_thick_defect,
                           maximum_thick_defect) ||
                       !is_isolated(component, chunky, image);
            }),
        dust.end());
    scratch.erase(
        std::remove_if(
            scratch.begin(),
            scratch.end(),
            [&](const Component& component) {
                if (!passes_scratch_gate(
                        component,
                        image.width,
                        minimum_scratch_length,
                        minimum_scratch_aspect)) {
                    return true;
                }
                if (!labeled_detection || component.has_strong) {
                    return false;
                }
                const PcaMetrics metrics = pca_metrics(
                    component, image.width);
                return metrics.length < weak_geometry_minimum_length ||
                       metrics.thickness > weak_geometry_maximum_thickness ||
                       metrics.aspect < weak_geometry_minimum_aspect;
            }),
        scratch.end());

    std::vector<std::uint8_t> drop_dust(dust.size(), 0U);
    std::vector<std::uint8_t> drop_scratch(scratch.size(), 0U);
    mark_grain_field_drops(
        dust,
        scratch,
        image.width,
        drop_dust,
        drop_scratch);

    evidence.resize(count);
    std::fill(
        evidence.begin(),
        evidence.end(),
        static_cast<std::uint8_t>(0U));
    for (std::size_t index = 0U; index < dust.size(); ++index) {
        if (drop_dust[index] == 0U) {
            for (const std::size_t pixel : dust[index].pixels) {
                evidence[pixel] |= 1U;
            }
        }
    }
    for (std::size_t index = 0U; index < scratch.size(); ++index) {
        if (drop_scratch[index] == 0U) {
            for (const std::size_t pixel : scratch[index].pixels) {
                evidence[pixel] |= 2U;
            }
        }
    }
}

std::vector<std::uint8_t> build_automatic_mask_from_evidence(
    const DetectionImage& image,
    const std::vector<std::uint8_t>& evidence,
    const std::vector<float>& scratch_response,
    const std::size_t maximum_dust_area,
    const int structure_radius_reference,
    const bool reject_structure_lines,
    std::size_t& accepted_pixels,
    const CandidateMaps* const candidates,
    std::vector<ClassifiedComponent>* const components) {
    const std::size_t count =
        static_cast<std::size_t>(image.width) * image.height;
    if (evidence.size() != count) {
        throw std::bad_alloc{};
    }
    std::vector<Component> dust = collect_components(
        image, evidence, evidence, 1U);
    std::vector<Component> scratch = collect_components(
        image, evidence, evidence, 2U);

    std::vector<std::uint8_t> drop_dust(dust.size(), 0U);
    std::vector<std::uint8_t> drop_scratch(scratch.size(), 0U);
    mark_grain_field_drops(
        dust,
        scratch,
        image.width,
        drop_dust,
        drop_scratch);
    if (reject_structure_lines) {
        const std::vector<std::uint8_t> grid_drops =
            structure_grid_drops(scratch, image, structure_radius_reference);
        const std::vector<std::uint8_t> line_drops = continuation_drops(
            scratch,
            image,
            scratch_response);
        for (std::size_t index = 0U; index < drop_scratch.size(); ++index) {
            drop_scratch[index] = static_cast<std::uint8_t>(
                drop_scratch[index] | grid_drops[index] | line_drops[index]);
        }
    }

    std::vector<std::uint8_t> mask(count, 0U);
    for (std::size_t index = 0U; index < dust.size(); ++index) {
        if (drop_dust[index] != 0U) {
            continue;
        }
        paint_component(dust[index], 0, image, mask);
        fill_interior_holes(
            dust[index], image, maximum_dust_area, mask);
    }
    for (std::size_t index = 0U; index < scratch.size(); ++index) {
        if (drop_scratch[index] == 0U) {
            paint_component(scratch[index], 1, image, mask);
        }
    }
    accepted_pixels = static_cast<std::size_t>(std::count(
        mask.begin(), mask.end(), static_cast<std::uint8_t>(1U)));
    if (components != nullptr) {
        collect_classified(
            dust,
            drop_dust,
            scratch,
            drop_scratch,
            image,
            candidates,
            maximum_dust_area,
            *components);
    }
    return mask;
}

std::vector<std::uint8_t> build_automatic_mask(
    const DetectionImage& image,
    const CandidateMaps& candidates,
    const bool reject_structure_lines,
    std::size_t& accepted_pixels) {
    const std::uint32_t minimum_scratch_length =
        std::max(10U, image.width / 120U);
    const std::vector<std::uint8_t> evidence = build_automatic_evidence(
        image,
        candidates,
        maximum_automatic_dust_area,
        minimum_scratch_length,
        0.0,
        false);
    return build_automatic_mask_from_evidence(
        image,
        evidence,
        candidates.scratch_response,
        maximum_automatic_dust_area,
        static_cast<int>(std::min(image.width, image.height)),
        reject_structure_lines,
        accepted_pixels);
}

}  // namespace negaflow::imaging::grain_mend_detail
