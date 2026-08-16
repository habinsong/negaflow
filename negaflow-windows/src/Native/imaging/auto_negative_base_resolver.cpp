#include "negaflow/imaging/auto_negative_base_resolver.h"

#include "bilinear_rgb_sampler.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <optional>
#include <vector>

namespace negaflow::imaging {
namespace {

constexpr std::array<float, 3> color_fallback{0.86F, 0.68F, 0.50F};
constexpr std::array<float, 3> monochrome_fallback{0.80F, 0.80F, 0.80F};
using BaseMeasurement = std::array<double, 3>;

[[nodiscard]] bool has_compatible_layout(const WorkingImage& image) noexcept {
    if (image.width == 0U || image.height == 0U || image.stride_pixels < image.width) {
        return false;
    }
    const std::size_t stride = image.stride_pixels;
    if (image.height > std::numeric_limits<std::size_t>::max() / stride) {
        return false;
    }
    return image.pixels.size() >= stride * image.height;
}

[[nodiscard]] double percentile(std::vector<double>& values, const double fraction) noexcept {
    if (values.empty()) {
        return 0.0;
    }
    std::sort(values.begin(), values.end());
    const std::size_t index = std::min(
        values.size() - 1U,
        static_cast<std::size_t>(static_cast<double>(values.size() - 1U) * fraction));
    return values[index];
}

[[nodiscard]] double median(std::vector<double> values) {
    if (values.empty()) {
        return 0.0;
    }
    std::sort(values.begin(), values.end());
    const std::size_t middle = values.size() / 2U;
    return values.size() % 2U == 0U
        ? (values[middle - 1U] + values[middle]) * 0.5
        : values[middle];
}

[[nodiscard]] double upper_median(std::vector<double> values) {
    if (values.empty()) {
        return 0.0;
    }
    std::sort(values.begin(), values.end());
    return values[values.size() / 2U];
}

[[nodiscard]] bool finite_rgb(const negaflow::core::Rgba32F& pixel) noexcept {
    return std::isfinite(pixel.red) && std::isfinite(pixel.green) && std::isfinite(pixel.blue);
}

[[nodiscard]] std::array<float, 3> fallback_for(const NegativeFilmType film_type) noexcept {
    return film_type == NegativeFilmType::black_and_white ? monochrome_fallback : color_fallback;
}

[[nodiscard]] double luma_of(const negaflow::core::Rgba32F& pixel) noexcept {
    return (static_cast<double>(pixel.red) + static_cast<double>(pixel.green) +
            static_cast<double>(pixel.blue)) /
        3.0;
}

[[nodiscard]] std::array<float, 3> narrow_measurement(const BaseMeasurement& measurement) noexcept {
    return {
        static_cast<float>(measurement[0]),
        static_cast<float>(measurement[1]),
        static_cast<float>(measurement[2]),
    };
}

[[nodiscard]] std::optional<BaseMeasurement> coherent_measurement(
    const std::vector<negaflow::core::Rgba32F>& pixels,
    const std::vector<std::size_t>& selected) {
    if (selected.empty()) {
        return std::nullopt;
    }
    std::vector<double> lumas;
    lumas.reserve(selected.size());
    for (const std::size_t index : selected) {
        lumas.push_back(luma_of(pixels[index]));
    }
    const double middle = median(lumas);
    std::vector<double> deviations;
    deviations.reserve(lumas.size());
    for (const double value : lumas) {
        deviations.push_back(std::abs(value - middle));
    }
    const double tolerance = std::max(
        median(std::move(deviations)) * 1.4826 * 3.0,
        1.0e-4);
    std::vector<std::size_t> retained;
    retained.reserve(selected.size());
    for (std::size_t index = 0U; index < selected.size(); ++index) {
        if (std::abs(lumas[index] - middle) <= tolerance) {
            retained.push_back(selected[index]);
        }
    }
    if (retained.size() < std::max<std::size_t>(4U, selected.size() / 4U)) {
        retained = selected;
    }
    std::vector<double> red;
    std::vector<double> green;
    std::vector<double> blue;
    red.reserve(retained.size());
    green.reserve(retained.size());
    blue.reserve(retained.size());
    for (const std::size_t index : retained) {
        red.push_back(static_cast<double>(pixels[index].red));
        green.push_back(static_cast<double>(pixels[index].green));
        blue.push_back(static_cast<double>(pixels[index].blue));
    }
    return BaseMeasurement{
        std::clamp(
            median(std::move(red)),
            static_cast<double>(minimum_manual_dmin),
            static_cast<double>(maximum_manual_dmin)),
        std::clamp(
            median(std::move(green)),
            static_cast<double>(minimum_manual_dmin),
            static_cast<double>(maximum_manual_dmin)),
        std::clamp(
            median(std::move(blue)),
            static_cast<double>(minimum_manual_dmin),
            static_cast<double>(maximum_manual_dmin))};
}

[[nodiscard]] bool is_component_candidate(
    const negaflow::core::Rgba32F& pixel,
    const NegativeFilmType film_type) noexcept {
    if (!finite_rgb(pixel)) {
        return false;
    }
    const double red = static_cast<double>(pixel.red);
    const double green = static_cast<double>(pixel.green);
    const double blue = static_cast<double>(pixel.blue);
    const double luma = luma_of(pixel);
    const double peak = std::max(red, std::max(green, blue));
    if (film_type == NegativeFilmType::black_and_white) {
        const double tolerance = peak * 0.12 + 0.01;
        return luma >= 0.012 && luma <= 0.92 &&
            std::abs(red - green) <= tolerance &&
            std::abs(green - blue) <= tolerance;
    }
    return luma >= 0.012 && luma <= 0.85 && peak > 0.0 &&
        red >= green - 0.01 && green >= blue - 0.01 &&
        red - blue >= std::max(0.004, peak * 0.10);
}

struct SampleGrid final {
    std::uint32_t width{};
    std::uint32_t height{};
    std::vector<negaflow::core::Rgba32F> pixels;
    std::vector<double> lumas;
};

struct SampleGridGeometry final {
    std::uint32_t width{};
    std::uint32_t height{};
    double uniform_scale{};
};

[[nodiscard]] std::optional<SampleGridGeometry> make_sample_grid_geometry(
    const WorkingImage& image,
    const std::uint32_t minimum_width,
    const std::uint32_t maximum_width) noexcept {
    const std::uint32_t width = std::clamp(image.width, minimum_width, maximum_width);
    const double uniform_scale =
        static_cast<double>(width) / static_cast<double>(image.width);
    const double scaled_height = static_cast<double>(image.height) * uniform_scale;
    if (!std::isfinite(scaled_height) ||
        scaled_height > static_cast<double>(std::numeric_limits<std::uint32_t>::max())) {
        return std::nullopt;
    }
    return SampleGridGeometry{
        width,
        std::max(1U, static_cast<std::uint32_t>(scaled_height)),
        uniform_scale,
    };
}

[[nodiscard]] std::optional<BaseMeasurement> connected_component_base(
    const SampleGrid& grid,
    const NegativeFilmType film_type) {
    const std::uint32_t width = grid.width;
    const std::uint32_t height = grid.height;
    const std::size_t count = grid.pixels.size();
    std::vector<double> candidate_lumas;
    candidate_lumas.reserve(count);
    for (std::size_t index = 0U; index < count; ++index) {
        if (is_component_candidate(grid.pixels[index], film_type)) {
            candidate_lumas.push_back(grid.lumas[index]);
        }
    }
    if (candidate_lumas.empty()) {
        return std::nullopt;
    }
    const double floor = percentile(candidate_lumas, 0.99) * 0.10;
    std::vector<bool> excluded(count, false);
    for (std::uint32_t y = 0; y < height; ++y) {
        for (std::uint32_t x = 0; x < width; ++x) {
            const std::size_t index = static_cast<std::size_t>(y) * width + x;
            if (!std::isfinite(grid.lumas[index]) || grid.lumas[index] < 0.88) {
                continue;
            }
            for (std::uint32_t ny = y > 2U ? y - 2U : 0U; ny <= std::min(height - 1U, y + 2U); ++ny) {
                for (std::uint32_t nx = x > 2U ? x - 2U : 0U; nx <= std::min(width - 1U, x + 2U); ++nx) {
                    excluded[static_cast<std::size_t>(ny) * width + nx] = true;
                }
            }
        }
    }
    std::vector<bool> interior(count, false);
    for (std::uint32_t y = 0; y < height; ++y) {
        for (std::uint32_t x = 0; x < width; ++x) {
            const std::size_t index = static_cast<std::size_t>(y) * width + x;
            if (excluded[index] || grid.lumas[index] < floor ||
                !is_component_candidate(grid.pixels[index], film_type)) {
                continue;
            }
            bool boundary = false;
            const double ceiling = grid.lumas[index] * 1.15;
            for (std::uint32_t ny = y > 2U ? y - 2U : 0U; ny <= std::min(height - 1U, y + 2U) && !boundary; ++ny) {
                for (std::uint32_t nx = x > 2U ? x - 2U : 0U; nx <= std::min(width - 1U, x + 2U); ++nx) {
                    if (grid.lumas[static_cast<std::size_t>(ny) * width + nx] > ceiling) {
                        boundary = true;
                        break;
                    }
                }
            }
            interior[index] = !boundary;
        }
    }
    struct Component { std::vector<std::size_t> cells; double p75; };
    std::vector<std::int32_t> labels(count, -1);
    std::vector<Component> components;
    std::vector<std::size_t> queue;
    const std::size_t minimum_size = std::max<std::size_t>(24U, count * 4U / 1000U);
    for (std::size_t start = 0; start < count; ++start) {
        if (!interior[start] || labels[start] >= 0) { continue; }
        queue.clear();
        std::vector<std::size_t> cells;
        queue.push_back(start);
        labels[start] = static_cast<std::int32_t>(components.size());
        while (!queue.empty()) {
            const std::size_t cell = queue.back(); queue.pop_back(); cells.push_back(cell);
            const std::uint32_t x = static_cast<std::uint32_t>(cell % width);
            const std::uint32_t y = static_cast<std::uint32_t>(cell / width);
            const std::array<std::pair<std::uint32_t, std::uint32_t>, 4> neighbors{{
                {x > 0 ? x - 1U : x, y}, {std::min(width - 1U, x + 1U), y},
                {x, y > 0 ? y - 1U : y}, {x, std::min(height - 1U, y + 1U)}}};
            for (const auto [nx, ny] : neighbors) {
                const std::size_t next = static_cast<std::size_t>(ny) * width + nx;
                if (next != cell && interior[next] && labels[next] < 0) {
                    labels[next] = labels[cell]; queue.push_back(next);
                }
            }
        }
        if (cells.size() >= minimum_size) {
            std::vector<double> values; values.reserve(cells.size());
            for (const std::size_t cell : cells) { values.push_back(grid.lumas[cell]); }
            components.push_back({std::move(cells), percentile(values, 0.75)});
        }
    }
    if (components.empty()) { return std::nullopt; }
    std::sort(components.begin(), components.end(), [](const Component& left, const Component& right) {
        return left.p75 > right.p75;
    });
    std::size_t selected_index = 0U;
    if (film_type == NegativeFilmType::color && components.front().p75 >= 0.60) {
        const auto median_red_minus_blue = [&grid](const Component& component) {
            std::vector<double> values;
            values.reserve(component.cells.size());
            for (const std::size_t cell : component.cells) {
                values.push_back(
                    static_cast<double>(grid.pixels[cell].red) -
                    static_cast<double>(grid.pixels[cell].blue));
            }
            return upper_median(std::move(values));
        };
        const double brightest_red_minus_blue = median_red_minus_blue(components.front());
        const auto second = std::find_if(
            components.begin() + 1,
            components.end(),
            [&components](const Component& component) {
                return component.p75 < components.front().p75 * 0.87;
            });
        if (second != components.end()) {
            const double brightness_ratio = second->p75 / components.front().p75;
            if (brightness_ratio >= 0.12 && brightness_ratio <= 0.87 &&
                brightest_red_minus_blue < median_red_minus_blue(*second) * 0.75) {
                selected_index = static_cast<std::size_t>(second - components.begin());
            }
        }
    }
    const double selected_p75 = components[selected_index].p75;

    // 고른 성분이 후보 밝기 봉우리에 한참 못 미치면 이것은 필름 베이스가 아니다.
    //
    // 베이스는 오렌지 마스크 후보들 가운데 **가장 밝은** 결맞은 구조다. 후보 분포의
    // 봉우리보다 훨씬 어두운 성분을 베이스로 채택하면, 실제 베이스는 성분을 이루지
    // 못했고 어두운 덩어리 하나만 남았다는 뜻이다. 그 값을 Dmin 으로 쓰면 대부분
    // 화소의 밀도가 음수가 되어 사진이 통째로 검게 눌린다(OpticFilm 8100 실기: 성분
    // 하나, p75 0.0168, 후보 봉우리 0.122 — 결과 median 19).
    //
    // 여기서 포기하면 호출부의 다음 전략(경계·분산 마스크)이 받는다. 같은 프레임에서
    // 그 전략은 0.1764/0.0929/0.0703 을 내며 macOS 의 0.1913/0.0939/0.0711 에 가깝다.
    // 정상 프레임(V700)은 고른 성분이 후보 봉우리와 사실상 같아 이 관문에 걸리지 않는다.
    // 강등이 일어났다면 더 어두운 성분을 **일부러** 고른 것이므로 이 관문을 적용하지 않는다.
    // 웜 백라이트 강등은 밝은 쪽이 광원이라고 판단한 결과이지 증거가 약한 것이 아니다.
    const double candidate_peak = floor * 10.0;
    if (selected_index == 0U && candidate_peak > 0.0 &&
        selected_p75 < candidate_peak * 0.5) {
        return std::nullopt;
    }

    std::vector<std::size_t> members;
    for (const Component& component : components) {
        if (component.p75 >= selected_p75 * 0.90 && component.p75 <= selected_p75 / 0.90) {
            members.insert(members.end(), component.cells.begin(), component.cells.end());
        }
    }
    std::sort(members.begin(), members.end(), [&grid](const std::size_t left, const std::size_t right) {
        return grid.lumas[left] > grid.lumas[right];
    });
    members.resize(std::max(members.size() / 2U, std::min(members.size(), std::size_t{24U})));
    return coherent_measurement(grid.pixels, members);
}

[[nodiscard]] std::optional<SampleGrid> make_sample_grid(const WorkingImage& image) {
    const std::optional<SampleGridGeometry> geometry =
        make_sample_grid_geometry(image, 32U, 256U);
    if (!geometry.has_value()) {
        return std::nullopt;
    }
    SampleGrid grid{};
    grid.width = geometry->width;
    grid.height = geometry->height;
    const std::size_t count = static_cast<std::size_t>(grid.width) * grid.height;
    grid.pixels.resize(count);
    grid.lumas.resize(count);
    const negaflow::core::ConstImageView source{
        image.pixels.data(),
        image.pixels.size(),
        image.width,
        image.height,
        image.stride_pixels,
    };
    for (std::uint32_t y = 0U; y < grid.height; ++y) {
        const double source_y =
            (static_cast<double>(y) + 0.5) / geometry->uniform_scale - 0.5;
        for (std::uint32_t x = 0U; x < grid.width; ++x) {
            const double source_x =
                (static_cast<double>(x) + 0.5) / geometry->uniform_scale - 0.5;
            const std::size_t index = static_cast<std::size_t>(y) * grid.width + x;
            const detail::BilinearRgb sampled =
                detail::sample_bilinear_rgb_transparent(source, source_x, source_y);
            grid.pixels[index] = {
                static_cast<float>(sampled.red),
                static_cast<float>(sampled.green),
                static_cast<float>(sampled.blue),
                1.0F,
            };
            grid.lumas[index] = luma_of(grid.pixels[index]);
        }
    }
    return grid;
}

[[nodiscard]] std::vector<std::size_t> candidate_indices(
    const SampleGrid& grid,
    const NegativeFilmType film_type,
    const std::vector<bool>* excluded = nullptr) {
    std::vector<std::size_t> result;
    result.reserve(grid.pixels.size());
    for (std::size_t index = 0U; index < grid.pixels.size(); ++index) {
        if ((excluded != nullptr && (*excluded)[index]) ||
            !is_component_candidate(grid.pixels[index], film_type)) {
            continue;
        }
        result.push_back(index);
    }
    return result;
}

[[nodiscard]] double candidate_luma_peak(
    const SampleGrid& grid,
    const NegativeFilmType film_type) {
    const std::vector<std::size_t> candidates = candidate_indices(grid, film_type);
    std::vector<double> lumas;
    lumas.reserve(candidates.size());
    for (const std::size_t index : candidates) {
        lumas.push_back(grid.lumas[index]);
    }
    return percentile(lumas, 0.99);
}

[[nodiscard]] std::vector<bool> dilate(
    const std::vector<bool>& selected,
    const SampleGrid& grid) {
    std::vector<bool> result = selected;
    for (std::uint32_t y = 0U; y < grid.height; ++y) {
        for (std::uint32_t x = 0U; x < grid.width; ++x) {
            if (!selected[static_cast<std::size_t>(y) * grid.width + x]) {
                continue;
            }
            for (std::uint32_t ny = y > 2U ? y - 2U : 0U;
                 ny <= std::min(grid.height - 1U, y + 2U); ++ny) {
                for (std::uint32_t nx = x > 2U ? x - 2U : 0U;
                     nx <= std::min(grid.width - 1U, x + 2U); ++nx) {
                    result[static_cast<std::size_t>(ny) * grid.width + nx] = true;
                }
            }
        }
    }
    return result;
}

[[nodiscard]] std::optional<double> brightest_coherent_mode(
    const SampleGrid& grid,
    const NegativeFilmType film_type) {
    std::vector<std::size_t> candidates = candidate_indices(grid, film_type);
    const double floor = candidate_luma_peak(grid, film_type) * 0.10;
    candidates.erase(
        std::remove_if(
            candidates.begin(),
            candidates.end(),
            [&grid, floor](const std::size_t index) {
                return grid.lumas[index] < floor;
            }),
        candidates.end());
    if (candidates.empty()) {
        return std::nullopt;
    }
    std::vector<std::size_t> sorted = candidates;
    std::sort(sorted.begin(), sorted.end(), [&grid](const std::size_t left, const std::size_t right) {
        return grid.lumas[left] > grid.lumas[right];
    });
    const std::size_t coherent_count = std::max<std::size_t>(24U, grid.pixels.size() * 4U / 1000U);
    const auto mode_center = [&grid, &sorted, coherent_count](const double upper) -> std::optional<double> {
        std::size_t low = 0U;
        std::size_t high = 0U;
        for (std::size_t index = 0U; index < sorted.size(); ++index) {
            const double center = grid.lumas[sorted[index]];
            if (center >= upper) {
                continue;
            }
            while (low < sorted.size() && grid.lumas[sorted[low]] > center + 0.03) {
                ++low;
            }
            high = std::max(high, low);
            while (high < sorted.size() && grid.lumas[sorted[high]] >= center - 0.03) {
                ++high;
            }
            if (high - low >= coherent_count) {
                return center;
            }
        }
        return std::nullopt;
    };
    const std::optional<double> top = mode_center(std::numeric_limits<double>::infinity());
    if (!top.has_value() || film_type == NegativeFilmType::black_and_white || *top < 0.60) {
        return top;
    }
    const std::optional<double> second = mode_center(*top * 0.87);
    if (!second.has_value() || *second / *top < 0.12 || *second / *top > 0.87) {
        return top;
    }
    const double gap_low = *second + 0.045;
    const double gap_high = *top - 0.045;
    if (gap_high <= gap_low) {
        return top;
    }
    std::vector<bool> top_cells(grid.pixels.size(), false);
    for (std::size_t index = 0U; index < grid.pixels.size(); ++index) {
        top_cells[index] = grid.lumas[index] >= gap_high;
    }
    const std::vector<bool> halo = dilate(top_cells, grid);
    std::size_t gap_count = 0U;
    for (std::size_t index = 0U; index < grid.pixels.size(); ++index) {
        if (grid.lumas[index] > gap_low && grid.lumas[index] < gap_high && !halo[index]) {
            ++gap_count;
        }
    }
    if (static_cast<double>(gap_count) > static_cast<double>(grid.pixels.size()) * 0.002) {
        return top;
    }
    const auto median_red_minus_blue = [&grid, &sorted](const double center) {
        std::vector<double> values;
        for (const std::size_t index : sorted) {
            if (std::abs(grid.lumas[index] - center) <= 0.03) {
                values.push_back(
                    static_cast<double>(grid.pixels[index].red) -
                    static_cast<double>(grid.pixels[index].blue));
            }
        }
        return upper_median(std::move(values));
    };
    return median_red_minus_blue(*top) < median_red_minus_blue(*second) * 0.75 ? second : top;
}

[[nodiscard]] std::optional<std::vector<bool>> non_film_exclusion(
    const SampleGrid& grid,
    const NegativeFilmType film_type) {
    const std::optional<double> base_mode = brightest_coherent_mode(grid, film_type);
    const double cut = std::min(0.88, base_mode.has_value() ? *base_mode * 1.12 : 0.88);
    std::vector<bool> bright(grid.pixels.size(), false);
    bool has_bright = false;
    for (std::size_t index = 0U; index < grid.pixels.size(); ++index) {
        if (grid.lumas[index] >= cut) {
            bright[index] = true;
            has_bright = true;
        }
    }
    if (!has_bright) {
        return std::nullopt;
    }
    std::vector<bool> excluded = dilate(bright, grid);
    if (candidate_indices(grid, film_type, &excluded).size() < 24U) {
        return std::nullopt;
    }
    return excluded;
}

[[nodiscard]] std::optional<BaseMeasurement> coherent_measurement(
    const SampleGrid& grid,
    const std::vector<std::size_t>& selected) {
    return coherent_measurement(grid.pixels, selected);
}

[[nodiscard]] std::optional<BaseMeasurement> continuous_border_base(
    const SampleGrid& grid,
    const NegativeFilmType film_type,
    const std::vector<bool>* excluded) {
    const double floor = candidate_luma_peak(grid, film_type) * 0.10;
    std::vector<std::size_t> all = candidate_indices(grid, film_type, excluded);
    all.erase(std::remove_if(all.begin(), all.end(), [&grid, floor](const std::size_t index) {
        return grid.lumas[index] < floor;
    }), all.end());
    const std::uint32_t edge_x = std::max(
        1U, static_cast<std::uint32_t>(static_cast<double>(grid.width) * 0.06));
    const std::uint32_t edge_y = std::max(
        1U, static_cast<std::uint32_t>(static_cast<double>(grid.height) * 0.06));
    std::vector<std::size_t> border;
    for (const std::size_t index : all) {
        const std::uint32_t x = static_cast<std::uint32_t>(index % grid.width);
        const std::uint32_t y = static_cast<std::uint32_t>(index / grid.width);
        if (x < edge_x || x >= grid.width - edge_x || y < edge_y || y >= grid.height - edge_y) {
            border.push_back(index);
        }
    }
    const std::vector<std::size_t>& candidates = border.size() >= 16U ? border : all;
    if (candidates.size() < 8U) {
        return std::nullopt;
    }
    std::vector<double> lumas;
    lumas.reserve(candidates.size());
    for (const std::size_t index : candidates) { lumas.push_back(grid.lumas[index]); }
    const double cut = percentile(lumas, 0.95);
    std::vector<std::size_t> bright;
    std::vector<std::size_t> row_counts(grid.height, 0U), column_counts(grid.width, 0U);
    for (const std::size_t index : candidates) {
        if (grid.lumas[index] < cut) { continue; }
        bright.push_back(index);
        ++row_counts[index / grid.width];
        ++column_counts[index % grid.width];
    }
    if (bright.size() < 4U) {
        return std::nullopt;
    }
    const std::size_t horizontal =
        static_cast<std::size_t>(static_cast<double>(grid.width) * 0.65);
    const std::size_t vertical =
        static_cast<std::size_t>(static_cast<double>(grid.height) * 0.65);
    bool continuous = false;
    for (std::uint32_t y = 0U; y < grid.height; ++y) {
        continuous = continuous || ((y < edge_y || y >= grid.height - edge_y) && row_counts[y] >= horizontal);
    }
    for (std::uint32_t x = 0U; x < grid.width; ++x) {
        continuous = continuous || ((x < edge_x || x >= grid.width - edge_x) && column_counts[x] >= vertical);
    }
    return continuous ? coherent_measurement(grid, bright) : std::nullopt;
}

[[nodiscard]] std::optional<BaseMeasurement> distributed_base(
    const SampleGrid& grid,
    const NegativeFilmType film_type,
    const std::vector<bool>* excluded) {
    const double floor = candidate_luma_peak(grid, film_type) * 0.10;
    std::vector<std::size_t> candidates = candidate_indices(grid, film_type, excluded);
    candidates.erase(std::remove_if(candidates.begin(), candidates.end(), [&grid, floor](const std::size_t index) {
        return grid.lumas[index] < floor;
    }), candidates.end());
    if (candidates.size() < 32U) {
        return std::nullopt;
    }
    std::vector<double> lumas;
    lumas.reserve(candidates.size());
    for (const std::size_t index : candidates) { lumas.push_back(grid.lumas[index]); }
    const double cut = percentile(lumas, 0.95);
    if (cut - median(lumas) < 0.02) {
        return std::nullopt;
    }
    std::vector<std::size_t> bright;
    for (const std::size_t index : candidates) {
        if (grid.lumas[index] >= cut) { bright.push_back(index); }
    }
    const std::size_t minimum = std::max<std::size_t>(32U, candidates.size() * 2U / 100U);
    return bright.size() >= minimum ? coherent_measurement(grid, bright) : std::nullopt;
}

[[nodiscard]] std::optional<BaseMeasurement> strip_fallback_base(
    const SampleGrid& grid,
    const NegativeFilmType film_type,
    const std::vector<bool>* excluded) {
    const std::uint32_t edge_x = std::max(
        1U, static_cast<std::uint32_t>(static_cast<double>(grid.width) * 0.06));
    const std::uint32_t edge_y = std::max(
        1U, static_cast<std::uint32_t>(static_cast<double>(grid.height) * 0.06));
    const auto strip_mean = [&grid, excluded](const auto contains) -> std::optional<BaseMeasurement> {
        std::array<double, 3> total{};
        std::size_t count = 0U;
        for (std::uint32_t y = 0U; y < grid.height; ++y) {
            for (std::uint32_t x = 0U; x < grid.width; ++x) {
                const std::size_t index = static_cast<std::size_t>(y) * grid.width + x;
                if (!contains(x, y) || (excluded != nullptr && (*excluded)[index])) { continue; }
                total[0] += grid.pixels[index].red;
                total[1] += grid.pixels[index].green;
                total[2] += grid.pixels[index].blue;
                ++count;
            }
        }
        if (count == 0U) { return std::nullopt; }
        const double inverse = 1.0 / static_cast<double>(count);
        return BaseMeasurement{
            total[0] * inverse,
            total[1] * inverse,
            total[2] * inverse};
    };
    std::vector<BaseMeasurement> strips;
    for (const auto& mean : {
             strip_mean([edge_y](const std::uint32_t, const std::uint32_t y) { return y < edge_y; }),
             strip_mean([&grid, edge_y](const std::uint32_t, const std::uint32_t y) { return y >= grid.height - edge_y; }),
             strip_mean([edge_x](const std::uint32_t x, const std::uint32_t) { return x < edge_x; }),
             strip_mean([&grid, edge_x](const std::uint32_t x, const std::uint32_t) { return x >= grid.width - edge_x; })}) {
        if (mean.has_value()) { strips.push_back(*mean); }
    }
    if (strips.empty()) { return std::nullopt; }
    const auto strip_luma = [](const BaseMeasurement& strip) noexcept {
        return (strip[0] + strip[1] + strip[2]) / 3.0;
    };
    double brightest = 0.0;
    for (const auto& strip : strips) {
        const double luma = strip_luma(strip);
        if (luma < 0.97) { brightest = std::max(brightest, luma); }
    }
    if (brightest <= 0.0) { return std::nullopt; }
    const double base_level = candidate_luma_peak(grid, film_type);
    std::vector<double> red, green, blue;
    for (const auto& strip : strips) {
        const double luma = strip_luma(strip);
        if (luma >= brightest * 0.55 && luma >= base_level * 0.50) {
            red.push_back(strip[0]); green.push_back(strip[1]); blue.push_back(strip[2]);
        }
    }
    if (red.empty()) { return std::nullopt; }
    return BaseMeasurement{
        std::clamp(
            median(std::move(red)),
            static_cast<double>(minimum_manual_dmin),
            static_cast<double>(maximum_manual_dmin)),
        std::clamp(
            median(std::move(green)),
            static_cast<double>(minimum_manual_dmin),
            static_cast<double>(maximum_manual_dmin)),
        std::clamp(
            median(std::move(blue)),
            static_cast<double>(minimum_manual_dmin),
            static_cast<double>(maximum_manual_dmin))};
}

[[nodiscard]] std::optional<BaseMeasurement> scene_edge_fallback_base(
    const WorkingImage& image,
    const NegativeFilmType film_type) {
    const std::optional<SampleGridGeometry> geometry =
        make_sample_grid_geometry(image, 64U, 320U);
    if (!geometry.has_value()) {
        return std::nullopt;
    }
    const std::uint32_t edge_x = std::max(
        1U, static_cast<std::uint32_t>(static_cast<double>(geometry->width) * 0.06));
    const std::uint32_t edge_y = std::max(
        1U, static_cast<std::uint32_t>(static_cast<double>(geometry->height) * 0.06));

    std::vector<negaflow::core::Rgba32F> edge_pixels;
    edge_pixels.reserve(static_cast<std::size_t>(geometry->width) * edge_y * 2U +
                        static_cast<std::size_t>(geometry->height) * edge_x * 2U);
    const negaflow::core::ConstImageView source{
        image.pixels.data(),
        image.pixels.size(),
        image.width,
        image.height,
        image.stride_pixels,
    };
    for (std::uint32_t y = 0U; y < geometry->height; ++y) {
        const double source_y =
            (static_cast<double>(y) + 0.5) / geometry->uniform_scale - 0.5;
        for (std::uint32_t x = 0U; x < geometry->width; ++x) {
            if (x >= edge_x && x < geometry->width - edge_x &&
                y >= edge_y && y < geometry->height - edge_y) {
                continue;
            }
            const double source_x =
                (static_cast<double>(x) + 0.5) / geometry->uniform_scale - 0.5;
            const detail::BilinearRgb sampled =
                detail::sample_bilinear_rgb_transparent(source, source_x, source_y);
            edge_pixels.push_back({
                static_cast<float>(sampled.red),
                static_cast<float>(sampled.green),
                static_cast<float>(sampled.blue),
                1.0F,
            });
        }
    }

    std::vector<double> edge_lumas;
    edge_lumas.reserve(edge_pixels.size());
    for (const negaflow::core::Rgba32F& pixel : edge_pixels) {
        const double luma = luma_of(pixel);
        if (std::isfinite(luma) && luma < 0.92) {
            edge_lumas.push_back(luma);
        }
    }
    if (edge_lumas.empty()) {
        return std::nullopt;
    }
    const double edge_peak = percentile(edge_lumas, 0.99);
    const double luma_floor = std::max(0.02, edge_peak * 0.45);
    std::vector<double> red;
    std::vector<double> green;
    std::vector<double> blue;
    red.reserve(edge_pixels.size());
    green.reserve(edge_pixels.size());
    blue.reserve(edge_pixels.size());
    for (const negaflow::core::Rgba32F& pixel : edge_pixels) {
        if (!finite_rgb(pixel)) {
            continue;
        }
        const double luma = luma_of(pixel);
        if (luma < luma_floor || luma >= 0.92) {
            continue;
        }
        const double red_value = static_cast<double>(pixel.red);
        const double green_value = static_cast<double>(pixel.green);
        const double blue_value = static_cast<double>(pixel.blue);
        const double peak = std::max(red_value, std::max(green_value, blue_value));
        if (film_type == NegativeFilmType::black_and_white) {
            const double tolerance = peak * 0.12 + 0.01;
            if (std::abs(red_value - green_value) > tolerance ||
                std::abs(green_value - blue_value) > tolerance) {
                continue;
            }
        } else if (red_value < green_value - 0.01 ||
                   green_value < blue_value - 0.01 || peak <= 0.0 ||
                   red_value - blue_value < std::max(0.003, peak * 0.10)) {
            continue;
        }
        red.push_back(red_value);
        green.push_back(green_value);
        blue.push_back(blue_value);
    }
    if (red.size() < 32U) {
        return std::nullopt;
    }
    return BaseMeasurement{
        percentile(red, 0.90), percentile(green, 0.90), percentile(blue, 0.90)};
}

}  // namespace

AutoNegativeBaseResult resolve_auto_negative_base(
    const WorkingImage& image,
    const NegativeFilmType film_type) noexcept {
    AutoNegativeBaseResult result{};
    if (!has_compatible_layout(image)) {
        return result;
    }

    result.status = AutoNegativeBaseStatus::ok;
    result.dmin = fallback_for(film_type);
    const auto with_chromogenic_fallback = [&image, film_type](const AutoNegativeBaseResult resolved) {
        if (film_type != NegativeFilmType::black_and_white ||
            resolved.status != AutoNegativeBaseStatus::ok) {
            return resolved;
        }
        const double maximum = std::max(
            static_cast<double>(resolved.dmin[0]),
            std::max(
                static_cast<double>(resolved.dmin[1]),
                static_cast<double>(resolved.dmin[2])));
        const double minimum = std::min(
            static_cast<double>(resolved.dmin[0]),
            std::min(
                static_cast<double>(resolved.dmin[1]),
                static_cast<double>(resolved.dmin[2])));
        if (minimum <= 1.0e-6 || maximum / minimum <= 1.25) {
            return resolved;
        }
        const AutoNegativeBaseResult chromogenic = resolve_auto_negative_base(image, NegativeFilmType::color);
        return chromogenic.status == AutoNegativeBaseStatus::ok &&
                chromogenic.source != AutoNegativeBaseSource::fallback
            ? chromogenic
            : resolved;
    };
    if (image.width <= 4U || image.height <= 4U) {
        return result;
    }

    try {
        const std::optional<SampleGrid> grid = make_sample_grid(image);
        if (!grid.has_value()) {
            return result;
        }
        if (const std::optional<BaseMeasurement> component =
                connected_component_base(*grid, film_type)) {
            result.dmin = narrow_measurement(*component);
            result.source = AutoNegativeBaseSource::connected_component;
            return with_chromogenic_fallback(result);
        }
        const std::optional<std::vector<bool>> exclusion = non_film_exclusion(*grid, film_type);
        const std::vector<bool>* excluded = exclusion.has_value() ? &*exclusion : nullptr;
        const std::optional<BaseMeasurement> edge =
            continuous_border_base(*grid, film_type, excluded);
        const std::optional<BaseMeasurement> distributed =
            distributed_base(*grid, film_type, excluded);
        if (edge.has_value() && distributed.has_value()) {
            const double edge_luma = ((*edge)[0] + (*edge)[1] + (*edge)[2]) / 3.0;
            const double distributed_luma =
                ((*distributed)[0] + (*distributed)[1] + (*distributed)[2]) / 3.0;
            const bool use_edge = edge_luma >= distributed_luma * 0.85;
            result.dmin = narrow_measurement(use_edge ? *edge : *distributed);
            result.source = use_edge
                ? AutoNegativeBaseSource::continuous_border
                : AutoNegativeBaseSource::distributed_mask;
            return with_chromogenic_fallback(result);
        }
        if (edge.has_value()) {
            result.dmin = narrow_measurement(*edge);
            result.source = AutoNegativeBaseSource::continuous_border;
            return with_chromogenic_fallback(result);
        }
        if (distributed.has_value()) {
            result.dmin = narrow_measurement(*distributed);
            result.source = AutoNegativeBaseSource::distributed_mask;
            return with_chromogenic_fallback(result);
        }
        if (const std::optional<BaseMeasurement> strip =
                strip_fallback_base(*grid, film_type, excluded)) {
            result.dmin = narrow_measurement(*strip);
            result.source = AutoNegativeBaseSource::strip_fallback;
            return with_chromogenic_fallback(result);
        }
        if (const std::optional<BaseMeasurement> scene_edge =
                scene_edge_fallback_base(image, film_type)) {
            result.dmin = narrow_measurement(*scene_edge);
            result.source = AutoNegativeBaseSource::scene_edge;
        }
    } catch (...) {
        // The documented fallback is preferable to allowing an allocation failure to cross a
        // noexcept ABI boundary. It remains distinguishable from a manual base in request mode.
    }
    return with_chromogenic_fallback(result);
}

const char* auto_negative_base_status_name(const AutoNegativeBaseStatus status) noexcept {
    switch (status) {
        case AutoNegativeBaseStatus::ok:
            return "ok";
        case AutoNegativeBaseStatus::invalid_image:
            return "invalid_image";
    }
    return "unknown_auto_negative_base_status";
}

}  // namespace negaflow::imaging
