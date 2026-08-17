#include "grain_mend_component_gates.h"

#include "grain_mend_shape.h"

#include <algorithm>
#include <utility>

namespace negaflow::imaging::grain_mend_detail {

// 조율값은 grain_mend_component_types.h 의 한 표에서만 옵니다.
using namespace tuning;

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


}  // namespace negaflow::imaging::grain_mend_detail
