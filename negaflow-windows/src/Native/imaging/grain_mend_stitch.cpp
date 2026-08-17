#include "grain_mend_stitch.h"

#include <algorithm>
#include <cstddef>
#include <utility>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {
namespace {

struct ComponentUnion final {
    std::vector<int> parent;

    explicit ComponentUnion(const int count) : parent(static_cast<std::size_t>(count)) {
        for (int index = 0; index < count; ++index) {
            parent[static_cast<std::size_t>(index)] = index;
        }
    }

    [[nodiscard]] int root_of(int value) noexcept {
        while (parent[static_cast<std::size_t>(value)] != value) {
            const int parent_index = parent[static_cast<std::size_t>(value)];
            parent[static_cast<std::size_t>(value)] =
                parent[static_cast<std::size_t>(parent_index)];
            value = parent[static_cast<std::size_t>(value)];
        }
        return value;
    }

    void merge(const int lhs, const int rhs) noexcept {
        const int first = root_of(lhs);
        const int second = root_of(rhs);
        if (first != second) {
            parent[static_cast<std::size_t>(std::max(first, second))] =
                std::min(first, second);
        }
    }
};

void stitch_kind(
    const std::vector<ClassifiedComponent>& same_kind,
    const std::uint32_t width,
    const std::uint32_t height,
    std::vector<ClassifiedComponent>& out) {
    if (same_kind.empty() || width == 0U || height == 0U) {
        return;
    }
    const std::size_t count = static_cast<std::size_t>(width) * height;
    ComponentUnion unions{static_cast<int>(same_kind.size())};
    std::vector<std::int32_t> owner(count, -1);
    for (std::size_t index = 0U; index < same_kind.size(); ++index) {
        for (const std::size_t pixel : same_kind[index].pixels) {
            if (pixel >= count) {
                continue;
            }
            if (owner[pixel] >= 0) {
                unions.merge(static_cast<int>(index), owner[pixel]);
            } else {
                owner[pixel] = static_cast<std::int32_t>(index);
            }
        }
    }

    // macOS: 비중첩 core 조각은 공통 화소가 없다. 전역 8-연결로 다시 잇는다.
    // 전방 이웃만 보면 전체 8-연결과 같은 쌍을 본다.
    constexpr int neighbor_x[] = {1, 0, 1, -1};
    constexpr int neighbor_y[] = {0, 1, 1, 1};
    const int image_width = static_cast<int>(width);
    const int image_height = static_cast<int>(height);
    for (const ClassifiedComponent& component : same_kind) {
        for (const std::size_t pixel : component.pixels) {
            if (pixel >= count || owner[pixel] < 0) {
                continue;
            }
            const int y = static_cast<int>(pixel / width);
            const int x = static_cast<int>(pixel % width);
            for (int step = 0; step < 4; ++step) {
                const int next_x = x + neighbor_x[step];
                const int next_y = y + neighbor_y[step];
                if (next_x < 0 || next_y < 0 || next_x >= image_width ||
                    next_y >= image_height) {
                    continue;
                }
                const std::size_t next =
                    static_cast<std::size_t>(next_y) * width +
                    static_cast<std::size_t>(next_x);
                if (owner[next] >= 0 && owner[next] != owner[pixel]) {
                    unions.merge(owner[pixel], owner[next]);
                }
            }
        }
    }

    std::vector<std::vector<std::size_t>> pixels_by_root(same_kind.size());
    for (std::size_t index = 0U; index < same_kind.size(); ++index) {
        const int root = unions.root_of(static_cast<int>(index));
        for (const std::size_t pixel : same_kind[index].pixels) {
            if (pixel < count && owner[pixel] == static_cast<std::int32_t>(index)) {
                pixels_by_root[static_cast<std::size_t>(root)].push_back(pixel);
            }
        }
    }
    for (auto& pixels : pixels_by_root) {
        if (pixels.size() > 1U) {
            std::sort(pixels.begin(), pixels.end());
        }
    }

    std::vector<const ClassifiedComponent*> metadata(same_kind.size(), nullptr);
    for (std::size_t index = 0U; index < same_kind.size(); ++index) {
        const int root = unions.root_of(static_cast<int>(index));
        const ClassifiedComponent& component = same_kind[index];
        const ClassifiedComponent*& slot =
            metadata[static_cast<std::size_t>(root)];
        if (slot == nullptr || component.confidence > slot->confidence) {
            slot = &component;
        }
    }

    for (std::size_t root = 0U; root < pixels_by_root.size(); ++root) {
        if (pixels_by_root[root].empty() || metadata[root] == nullptr) {
            continue;
        }
        ClassifiedComponent entry = *metadata[root];
        entry.pixels = std::move(pixels_by_root[root]);
        std::uint32_t minimum_x = width;
        std::uint32_t minimum_y = height;
        std::uint32_t maximum_x = 0U;
        std::uint32_t maximum_y = 0U;
        for (const std::size_t pixel : entry.pixels) {
            const std::uint32_t x = static_cast<std::uint32_t>(pixel % width);
            const std::uint32_t y = static_cast<std::uint32_t>(pixel / width);
            minimum_x = std::min(minimum_x, x);
            minimum_y = std::min(minimum_y, y);
            maximum_x = std::max(maximum_x, x);
            maximum_y = std::max(maximum_y, y);
        }
        entry.minimum_x = minimum_x;
        entry.minimum_y = minimum_y;
        entry.maximum_x = maximum_x;
        entry.maximum_y = maximum_y;
        out.push_back(std::move(entry));
    }
}

}  // namespace

std::vector<ClassifiedComponent> stitch_region_defect_tiles(
    const std::vector<ClassifiedComponent>& mapped,
    const std::uint32_t width,
    const std::uint32_t height) {
    std::vector<ClassifiedComponent> result{};
    std::vector<ClassifiedComponent> dust{};
    std::vector<ClassifiedComponent> scratch{};
    dust.reserve(mapped.size());
    scratch.reserve(mapped.size());
    for (const ClassifiedComponent& component : mapped) {
        if (component.pixels.empty()) {
            continue;
        }
        if (component.is_scratch) {
            scratch.push_back(component);
        } else {
            dust.push_back(component);
        }
    }
    stitch_kind(dust, width, height, result);
    stitch_kind(scratch, width, height, result);
    return result;
}

}  // namespace negaflow::imaging::grain_mend_detail
