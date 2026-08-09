#include "negaflow/imaging/auto_negative_base_resolver.h"

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

[[nodiscard]] float percentile(std::vector<float>& values, const double fraction) noexcept {
    if (values.empty()) {
        return 0.0F;
    }
    std::sort(values.begin(), values.end());
    const std::size_t index = std::min(
        values.size() - 1U,
        static_cast<std::size_t>(static_cast<double>(values.size() - 1U) * fraction));
    return values[index];
}

[[nodiscard]] bool finite_rgb(const negaflow::core::Rgba32F& pixel) noexcept {
    return std::isfinite(pixel.red) && std::isfinite(pixel.green) && std::isfinite(pixel.blue);
}

[[nodiscard]] std::array<float, 3> fallback_for(const NegativeFilmType film_type) noexcept {
    return film_type == NegativeFilmType::black_and_white ? monochrome_fallback : color_fallback;
}

[[nodiscard]] float luma_of(const negaflow::core::Rgba32F& pixel) noexcept {
    return (pixel.red + pixel.green + pixel.blue) / 3.0F;
}

[[nodiscard]] bool is_component_candidate(
    const negaflow::core::Rgba32F& pixel,
    const NegativeFilmType film_type) noexcept {
    if (!finite_rgb(pixel)) {
        return false;
    }
    const float luma = luma_of(pixel);
    const float peak = std::max(pixel.red, std::max(pixel.green, pixel.blue));
    if (film_type == NegativeFilmType::black_and_white) {
        const float tolerance = peak * 0.12F + 0.01F;
        return luma >= 0.012F && luma <= 0.92F &&
            std::abs(pixel.red - pixel.green) <= tolerance &&
            std::abs(pixel.green - pixel.blue) <= tolerance;
    }
    return luma >= 0.012F && luma <= 0.85F && peak > 0.0F &&
        pixel.red >= pixel.green - 0.01F && pixel.green >= pixel.blue - 0.01F &&
        pixel.red - pixel.blue >= std::max(0.004F, peak * 0.10F);
}

[[nodiscard]] std::optional<std::array<float, 3>> connected_component_base(
    const WorkingImage& image,
    const NegativeFilmType film_type) {
    const std::uint32_t width = std::clamp(image.width, 32U, 256U);
    const std::uint32_t height = std::max(1U, static_cast<std::uint32_t>(
        (static_cast<std::uint64_t>(image.height) * width) / image.width));
    const std::size_t count = static_cast<std::size_t>(width) * height;
    std::vector<negaflow::core::Rgba32F> pixels(count);
    std::vector<float> lumas(count);
    std::vector<float> candidate_lumas;
    candidate_lumas.reserve(count);
    for (std::uint32_t y = 0; y < height; ++y) {
        const std::uint32_t source_y = std::min(image.height - 1U,
            static_cast<std::uint32_t>((static_cast<std::uint64_t>(y) * image.height) / height));
        for (std::uint32_t x = 0; x < width; ++x) {
            const std::uint32_t source_x = std::min(image.width - 1U,
                static_cast<std::uint32_t>((static_cast<std::uint64_t>(x) * image.width) / width));
            const std::size_t index = static_cast<std::size_t>(y) * width + x;
            pixels[index] = image.pixels[static_cast<std::size_t>(source_y) * image.stride_pixels + source_x];
            lumas[index] = luma_of(pixels[index]);
            if (is_component_candidate(pixels[index], film_type)) {
                candidate_lumas.push_back(lumas[index]);
            }
        }
    }
    if (candidate_lumas.empty()) {
        return std::nullopt;
    }
    const float floor = percentile(candidate_lumas, 0.99) * 0.10F;
    std::vector<bool> excluded(count, false);
    for (std::uint32_t y = 0; y < height; ++y) {
        for (std::uint32_t x = 0; x < width; ++x) {
            const std::size_t index = static_cast<std::size_t>(y) * width + x;
            if (!std::isfinite(lumas[index]) || lumas[index] < 0.88F) {
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
            if (excluded[index] || lumas[index] < floor || !is_component_candidate(pixels[index], film_type)) {
                continue;
            }
            bool boundary = false;
            const float ceiling = lumas[index] * 1.15F;
            for (std::uint32_t ny = y > 2U ? y - 2U : 0U; ny <= std::min(height - 1U, y + 2U) && !boundary; ++ny) {
                for (std::uint32_t nx = x > 2U ? x - 2U : 0U; nx <= std::min(width - 1U, x + 2U); ++nx) {
                    if (lumas[static_cast<std::size_t>(ny) * width + nx] > ceiling) {
                        boundary = true;
                        break;
                    }
                }
            }
            interior[index] = !boundary;
        }
    }
    struct Component { std::vector<std::size_t> cells; float p75; };
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
            std::vector<float> values; values.reserve(cells.size());
            for (const std::size_t cell : cells) { values.push_back(lumas[cell]); }
            components.push_back({std::move(cells), percentile(values, 0.75)});
        }
    }
    if (components.empty()) { return std::nullopt; }
    std::sort(components.begin(), components.end(), [](const Component& left, const Component& right) {
        return left.p75 > right.p75;
    });
    std::size_t selected_index = 0U;
    if (film_type == NegativeFilmType::color && components.front().p75 >= 0.60F) {
        const auto median_red_minus_blue = [&pixels](const Component& component) {
            std::vector<float> values;
            values.reserve(component.cells.size());
            for (const std::size_t cell : component.cells) {
                values.push_back(pixels[cell].red - pixels[cell].blue);
            }
            return percentile(values, 0.50);
        };
        const float brightest_red_minus_blue = median_red_minus_blue(components.front());
        for (std::size_t index = 1U; index < components.size(); ++index) {
            const float brightness_ratio = components[index].p75 / components.front().p75;
            if (brightness_ratio >= 0.12F && brightness_ratio <= 0.87F &&
                brightest_red_minus_blue < median_red_minus_blue(components[index]) * 0.75F) {
                selected_index = index;
                break;
            }
        }
    }
    const float selected_p75 = components[selected_index].p75;
    std::vector<std::size_t> members;
    for (const Component& component : components) {
        if (component.p75 >= selected_p75 * 0.90F && component.p75 <= selected_p75 / 0.90F) {
            members.insert(members.end(), component.cells.begin(), component.cells.end());
        }
    }
    std::sort(members.begin(), members.end(), [&lumas](const std::size_t left, const std::size_t right) {
        return lumas[left] > lumas[right];
    });
    members.resize(std::max(members.size() / 2U, std::min(members.size(), std::size_t{24U})));
    std::vector<float> red, green, blue;
    red.reserve(members.size()); green.reserve(members.size()); blue.reserve(members.size());
    for (const std::size_t cell : members) { red.push_back(pixels[cell].red); green.push_back(pixels[cell].green); blue.push_back(pixels[cell].blue); }
    return std::array<float, 3>{
        std::clamp(percentile(red, 0.50), minimum_manual_dmin, maximum_manual_dmin),
        std::clamp(percentile(green, 0.50), minimum_manual_dmin, maximum_manual_dmin),
        std::clamp(percentile(blue, 0.50), minimum_manual_dmin, maximum_manual_dmin)};
}

struct SampleGrid final {
    std::uint32_t width{};
    std::uint32_t height{};
    std::vector<negaflow::core::Rgba32F> pixels;
    std::vector<float> lumas;
};

[[nodiscard]] std::optional<SampleGrid> make_sample_grid(const WorkingImage& image) {
    const std::uint32_t width = std::clamp(image.width, 32U, 256U);
    const std::uint32_t height = std::max(1U, static_cast<std::uint32_t>(
        (static_cast<std::uint64_t>(image.height) * width) / image.width));
    SampleGrid grid{};
    grid.width = width;
    grid.height = height;
    const std::size_t count = static_cast<std::size_t>(width) * height;
    grid.pixels.resize(count);
    grid.lumas.resize(count);
    for (std::uint32_t y = 0U; y < height; ++y) {
        const std::uint32_t source_y = std::min(image.height - 1U,
            static_cast<std::uint32_t>((static_cast<std::uint64_t>(y) * image.height) / height));
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::uint32_t source_x = std::min(image.width - 1U,
                static_cast<std::uint32_t>((static_cast<std::uint64_t>(x) * image.width) / width));
            const std::size_t index = static_cast<std::size_t>(y) * width + x;
            grid.pixels[index] = image.pixels[
                static_cast<std::size_t>(source_y) * image.stride_pixels + source_x];
            grid.lumas[index] = luma_of(grid.pixels[index]);
        }
    }
    return grid;
}

[[nodiscard]] float median(std::vector<float> values) {
    if (values.empty()) {
        return 0.0F;
    }
    std::sort(values.begin(), values.end());
    const std::size_t middle = values.size() / 2U;
    return values.size() % 2U == 0U ? (values[middle - 1U] + values[middle]) * 0.5F : values[middle];
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

[[nodiscard]] float candidate_luma_peak(
    const SampleGrid& grid,
    const NegativeFilmType film_type) {
    const std::vector<std::size_t> candidates = candidate_indices(grid, film_type);
    std::vector<float> lumas;
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

[[nodiscard]] std::optional<float> brightest_coherent_mode(
    const SampleGrid& grid,
    const NegativeFilmType film_type) {
    const std::vector<std::size_t> candidates = candidate_indices(grid, film_type);
    if (candidates.empty()) {
        return std::nullopt;
    }
    std::vector<std::size_t> sorted = candidates;
    std::sort(sorted.begin(), sorted.end(), [&grid](const std::size_t left, const std::size_t right) {
        return grid.lumas[left] > grid.lumas[right];
    });
    const std::size_t coherent_count = std::max<std::size_t>(24U, grid.pixels.size() * 4U / 1000U);
    const auto mode_center = [&grid, &sorted, coherent_count](const float upper) -> std::optional<float> {
        std::size_t low = 0U;
        std::size_t high = 0U;
        for (std::size_t index = 0U; index < sorted.size(); ++index) {
            const float center = grid.lumas[sorted[index]];
            if (center >= upper) {
                continue;
            }
            while (low < sorted.size() && grid.lumas[sorted[low]] > center + 0.03F) {
                ++low;
            }
            high = std::max(high, low);
            while (high < sorted.size() && grid.lumas[sorted[high]] >= center - 0.03F) {
                ++high;
            }
            if (high - low >= coherent_count) {
                return center;
            }
        }
        return std::nullopt;
    };
    const std::optional<float> top = mode_center(std::numeric_limits<float>::infinity());
    if (!top.has_value() || film_type == NegativeFilmType::black_and_white || *top < 0.60F) {
        return top;
    }
    const std::optional<float> second = mode_center(*top * 0.87F);
    if (!second.has_value() || *second / *top < 0.12F || *second / *top > 0.87F) {
        return top;
    }
    const float gap_low = *second + 0.045F;
    const float gap_high = *top - 0.045F;
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
    const auto median_red_minus_blue = [&grid, &sorted](const float center) {
        std::vector<float> values;
        for (const std::size_t index : sorted) {
            if (std::abs(grid.lumas[index] - center) <= 0.03F) {
                values.push_back(grid.pixels[index].red - grid.pixels[index].blue);
            }
        }
        return median(std::move(values));
    };
    return median_red_minus_blue(*top) < median_red_minus_blue(*second) * 0.75F ? second : top;
}

[[nodiscard]] std::optional<std::vector<bool>> non_film_exclusion(
    const SampleGrid& grid,
    const NegativeFilmType film_type) {
    const std::optional<float> base_mode = brightest_coherent_mode(grid, film_type);
    const float cut = std::min(0.88F, base_mode.has_value() ? *base_mode * 1.12F : 0.88F);
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

[[nodiscard]] std::optional<std::array<float, 3>> coherent_measurement(
    const SampleGrid& grid,
    const std::vector<std::size_t>& selected) {
    if (selected.empty()) {
        return std::nullopt;
    }
    std::vector<float> lumas;
    lumas.reserve(selected.size());
    for (const std::size_t index : selected) {
        lumas.push_back(grid.lumas[index]);
    }
    const float middle = median(lumas);
    std::vector<float> deviations;
    deviations.reserve(lumas.size());
    for (const float value : lumas) {
        deviations.push_back(std::abs(value - middle));
    }
    const float tolerance = std::max(median(std::move(deviations)) * 1.4826F * 3.0F, 1.0e-4F);
    std::vector<std::size_t> retained;
    retained.reserve(selected.size());
    for (const std::size_t index : selected) {
        if (std::abs(grid.lumas[index] - middle) <= tolerance) {
            retained.push_back(index);
        }
    }
    if (retained.size() < std::max<std::size_t>(4U, selected.size() / 4U)) {
        retained = selected;
    }
    std::vector<float> red, green, blue;
    red.reserve(retained.size()); green.reserve(retained.size()); blue.reserve(retained.size());
    for (const std::size_t index : retained) {
        red.push_back(grid.pixels[index].red);
        green.push_back(grid.pixels[index].green);
        blue.push_back(grid.pixels[index].blue);
    }
    return std::array<float, 3>{
        std::clamp(median(std::move(red)), minimum_manual_dmin, maximum_manual_dmin),
        std::clamp(median(std::move(green)), minimum_manual_dmin, maximum_manual_dmin),
        std::clamp(median(std::move(blue)), minimum_manual_dmin, maximum_manual_dmin)};
}

[[nodiscard]] std::optional<std::array<float, 3>> continuous_border_base(
    const SampleGrid& grid,
    const NegativeFilmType film_type,
    const std::vector<bool>* excluded) {
    const float floor = candidate_luma_peak(grid, film_type) * 0.10F;
    std::vector<std::size_t> all = candidate_indices(grid, film_type, excluded);
    all.erase(std::remove_if(all.begin(), all.end(), [&grid, floor](const std::size_t index) {
        return grid.lumas[index] < floor;
    }), all.end());
    const std::uint32_t edge_x = std::max(1U, static_cast<std::uint32_t>(grid.width * 0.06F));
    const std::uint32_t edge_y = std::max(1U, static_cast<std::uint32_t>(grid.height * 0.06F));
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
    std::vector<float> lumas;
    lumas.reserve(candidates.size());
    for (const std::size_t index : candidates) { lumas.push_back(grid.lumas[index]); }
    const float cut = percentile(lumas, 0.95);
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
    const std::size_t horizontal = static_cast<std::size_t>(grid.width * 0.65F);
    const std::size_t vertical = static_cast<std::size_t>(grid.height * 0.65F);
    bool continuous = false;
    for (std::uint32_t y = 0U; y < grid.height; ++y) {
        continuous = continuous || ((y < edge_y || y >= grid.height - edge_y) && row_counts[y] >= horizontal);
    }
    for (std::uint32_t x = 0U; x < grid.width; ++x) {
        continuous = continuous || ((x < edge_x || x >= grid.width - edge_x) && column_counts[x] >= vertical);
    }
    return continuous ? coherent_measurement(grid, bright) : std::nullopt;
}

[[nodiscard]] std::optional<std::array<float, 3>> distributed_base(
    const SampleGrid& grid,
    const NegativeFilmType film_type,
    const std::vector<bool>* excluded) {
    const float floor = candidate_luma_peak(grid, film_type) * 0.10F;
    std::vector<std::size_t> candidates = candidate_indices(grid, film_type, excluded);
    candidates.erase(std::remove_if(candidates.begin(), candidates.end(), [&grid, floor](const std::size_t index) {
        return grid.lumas[index] < floor;
    }), candidates.end());
    if (candidates.size() < 32U) {
        return std::nullopt;
    }
    std::vector<float> lumas;
    lumas.reserve(candidates.size());
    for (const std::size_t index : candidates) { lumas.push_back(grid.lumas[index]); }
    const float cut = percentile(lumas, 0.95);
    if (cut - median(lumas) < 0.02F) {
        return std::nullopt;
    }
    std::vector<std::size_t> bright;
    for (const std::size_t index : candidates) {
        if (grid.lumas[index] >= cut) { bright.push_back(index); }
    }
    const std::size_t minimum = std::max<std::size_t>(32U, candidates.size() * 2U / 100U);
    return bright.size() >= minimum ? coherent_measurement(grid, bright) : std::nullopt;
}

[[nodiscard]] std::optional<std::array<float, 3>> strip_fallback_base(
    const SampleGrid& grid,
    const NegativeFilmType film_type,
    const std::vector<bool>* excluded) {
    const std::uint32_t edge_x = std::max(1U, static_cast<std::uint32_t>(grid.width * 0.06F));
    const std::uint32_t edge_y = std::max(1U, static_cast<std::uint32_t>(grid.height * 0.06F));
    const auto strip_mean = [&grid, excluded](const auto contains) -> std::optional<negaflow::core::Rgba32F> {
        negaflow::core::Rgba32F total{};
        std::size_t count = 0U;
        for (std::uint32_t y = 0U; y < grid.height; ++y) {
            for (std::uint32_t x = 0U; x < grid.width; ++x) {
                const std::size_t index = static_cast<std::size_t>(y) * grid.width + x;
                if (!contains(x, y) || (excluded != nullptr && (*excluded)[index]) ||
                    !finite_rgb(grid.pixels[index])) { continue; }
                total.red += grid.pixels[index].red;
                total.green += grid.pixels[index].green;
                total.blue += grid.pixels[index].blue;
                ++count;
            }
        }
        if (count == 0U) { return std::nullopt; }
        const float inverse = 1.0F / static_cast<float>(count);
        return negaflow::core::Rgba32F{total.red * inverse, total.green * inverse, total.blue * inverse, 1.0F};
    };
    std::vector<negaflow::core::Rgba32F> strips;
    for (const auto& mean : {
             strip_mean([edge_y](const std::uint32_t, const std::uint32_t y) { return y < edge_y; }),
             strip_mean([&grid, edge_y](const std::uint32_t, const std::uint32_t y) { return y >= grid.height - edge_y; }),
             strip_mean([edge_x](const std::uint32_t x, const std::uint32_t) { return x < edge_x; }),
             strip_mean([&grid, edge_x](const std::uint32_t x, const std::uint32_t) { return x >= grid.width - edge_x; })}) {
        if (mean.has_value()) { strips.push_back(*mean); }
    }
    if (strips.empty()) { return std::nullopt; }
    float brightest = 0.0F;
    for (const auto& strip : strips) {
        const float luma = luma_of(strip);
        if (luma < 0.97F) { brightest = std::max(brightest, luma); }
    }
    if (brightest <= 0.0F) { return std::nullopt; }
    const float base_level = candidate_luma_peak(grid, film_type);
    std::vector<float> red, green, blue;
    for (const auto& strip : strips) {
        if (luma_of(strip) >= brightest * 0.55F && luma_of(strip) >= base_level * 0.50F) {
            red.push_back(strip.red); green.push_back(strip.green); blue.push_back(strip.blue);
        }
    }
    if (red.empty()) { return std::nullopt; }
    return std::array<float, 3>{
        std::clamp(median(std::move(red)), minimum_manual_dmin, maximum_manual_dmin),
        std::clamp(median(std::move(green)), minimum_manual_dmin, maximum_manual_dmin),
        std::clamp(median(std::move(blue)), minimum_manual_dmin, maximum_manual_dmin)};
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
        const float maximum = std::max(resolved.dmin[0], std::max(resolved.dmin[1], resolved.dmin[2]));
        const float minimum = std::min(resolved.dmin[0], std::min(resolved.dmin[1], resolved.dmin[2]));
        if (minimum <= 1.0e-6F || maximum / minimum <= 1.25F) {
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
        if (const std::optional<std::array<float, 3>> component =
                connected_component_base(image, film_type)) {
            result.dmin = *component;
            result.source = AutoNegativeBaseSource::connected_component;
            return with_chromogenic_fallback(result);
        }
        const std::optional<SampleGrid> grid = make_sample_grid(image);
        if (!grid.has_value()) {
            return result;
        }
        const std::optional<std::vector<bool>> exclusion = non_film_exclusion(*grid, film_type);
        const std::vector<bool>* excluded = exclusion.has_value() ? &*exclusion : nullptr;
        const std::optional<std::array<float, 3>> edge = continuous_border_base(*grid, film_type, excluded);
        const std::optional<std::array<float, 3>> distributed = distributed_base(*grid, film_type, excluded);
        if (edge.has_value() && distributed.has_value()) {
            const float edge_luma = ((*edge)[0] + (*edge)[1] + (*edge)[2]) / 3.0F;
            const float distributed_luma = ((*distributed)[0] + (*distributed)[1] + (*distributed)[2]) / 3.0F;
            result.dmin = edge_luma >= distributed_luma * 0.85F ? *edge : *distributed;
            result.source = edge_luma >= distributed_luma * 0.85F
                ? AutoNegativeBaseSource::continuous_border
                : AutoNegativeBaseSource::distributed_mask;
            return with_chromogenic_fallback(result);
        }
        if (edge.has_value()) {
            result.dmin = *edge;
            result.source = AutoNegativeBaseSource::continuous_border;
            return with_chromogenic_fallback(result);
        }
        if (distributed.has_value()) {
            result.dmin = *distributed;
            result.source = AutoNegativeBaseSource::distributed_mask;
            return with_chromogenic_fallback(result);
        }
        if (const std::optional<std::array<float, 3>> strip = strip_fallback_base(*grid, film_type, excluded)) {
            result.dmin = *strip;
            result.source = AutoNegativeBaseSource::strip_fallback;
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
