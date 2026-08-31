#include "film_base_sampling.h"

#include "negaflow/imaging/mipmap_downsampler.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <limits>
#include <utility>

namespace negaflow::imaging::film_base_detail {

using negaflow::imaging::FilmBaseMeasurement;
using negaflow::imaging::FilmBaseMeasurementMethod;
using negaflow::imaging::FilmBaseSample;
using negaflow::imaging::build_film_base_measurement;

namespace {

// NEGA_DEBUG 진단입니다. macOS 와 성분 목록을 그대로 대조하기 위한 opt-in 출력이며 반전
// 수식에는 들어가지 않습니다.
[[nodiscard]] bool base_debug_enabled() noexcept {
    std::size_t length = 0U;
    return getenv_s(&length, nullptr, 0U, "NEGA_DEBUG") == 0 && length > 0U;
}

}  // namespace

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

[[nodiscard]] double luma_of(const negaflow::core::Rgba32F& pixel) noexcept {
    return (static_cast<double>(pixel.red) + static_cast<double>(pixel.green) +
            static_cast<double>(pixel.blue)) /
        3.0;
}

[[nodiscard]] FilmBaseSample sample_at(const SampleGrid& grid, const std::size_t index) {
    return FilmBaseSample{
        static_cast<int>(index % grid.width),
        static_cast<int>(index / grid.width),
        {
            static_cast<double>(grid.pixels[index].red),
            static_cast<double>(grid.pixels[index].green),
            static_cast<double>(grid.pixels[index].blue),
        },
    };
}

[[nodiscard]] std::vector<FilmBaseSample> samples_from_indices(
    const SampleGrid& grid,
    const std::vector<std::size_t>& selected) {
    std::vector<FilmBaseSample> samples;
    samples.reserve(selected.size());
    for (const std::size_t index : selected) {
        samples.push_back(sample_at(grid, index));
    }
    return samples;
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


// 성분의 **상위 절반 luma** 채널 중앙값 — 최종 선택이 쓰는 통계와 같습니다.
// 맥의 베이스와 어느 성분이 맞는지 이 값으로 바로 댈 수 있습니다(진단 전용).
[[nodiscard]] double component_channel_median(
    const SampleGrid& grid,
    const std::vector<std::size_t>& cells,
    const int channel) {
    std::vector<std::size_t> ordered = cells;
    std::sort(ordered.begin(), ordered.end(),
              [&grid](const std::size_t left, const std::size_t right) {
                  return grid.lumas[left] > grid.lumas[right];
              });
    ordered.resize(std::max(ordered.size() / 2U, std::min(ordered.size(), std::size_t{24U})));
    std::vector<double> values;
    values.reserve(ordered.size());
    for (const std::size_t cell : ordered) {
        const negaflow::core::Rgba32F& pixel = grid.pixels[cell];
        values.push_back(static_cast<double>(
            channel == 0 ? pixel.red : (channel == 1 ? pixel.green : pixel.blue)));
    }
    return median(std::move(values));
}

[[nodiscard]] std::optional<FilmBaseMeasurement> connected_component_base(
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
    // 성분 목록 진단(NEGA_DEBUG opt-in). macOS 는 `components.sort { $0.p75 > $1.p75 }` 뒤에
    // 곧바로 강등·형제 병합으로 갑니다 — 어느 성분이 몇 개 셀로 어떤 p75 를 냈는지가 갈리면
    // 베이스가 통째로 달라지므로, 값이 어긋날 때 여기부터 봅니다.
    if (base_debug_enabled()) {
        std::size_t interior_cells = 0U;
        for (std::size_t index = 0U; index < count; ++index) {
            if (interior[index]) {
                ++interior_cells;
            }
        }
        std::fprintf(
            stderr,
            "[base-cc] grid=%ux%u count=%zu floor=%.6f peak=%.6f minSize=%zu "
            "interior=%zu components=%zu\n",
            width, height, count, floor, floor * 10.0, minimum_size, interior_cells,
            components.size());
        // 격자에서 **가장 밝은 칸들**이 후보 판정을 지나는지입니다. 베이스는 필름에서 가장
        // 밝은 자리이므로, 여기 있는 칸이 후보가 아니라면 그 판정이 진짜 베이스를 밀어낸
        // 것입니다 — 카메라 스캔처럼 마스크가 우리 가정과 다른 원본에서 그 자리를 봅니다.
        std::vector<std::size_t> brightest(count);
        for (std::size_t index = 0U; index < count; ++index) {
            brightest[index] = index;
        }
        const std::size_t shown = std::min<std::size_t>(10U, count);
        std::partial_sort(
            brightest.begin(), brightest.begin() + static_cast<std::ptrdiff_t>(shown),
            brightest.end(),
            [&grid](const std::size_t left, const std::size_t right) {
                return grid.lumas[left] > grid.lumas[right];
            });
        for (std::size_t rank = 0U; rank < shown; ++rank) {
            const std::size_t index = brightest[rank];
            const negaflow::core::Rgba32F& pixel = grid.pixels[index];
            const double peak_channel = std::max(
                static_cast<double>(pixel.red),
                std::max(static_cast<double>(pixel.green),
                         static_cast<double>(pixel.blue)));
            std::fprintf(
                stderr,
                "[base-top] #%zu luma=%.4f rgb=(%.4f,%.4f,%.4f) r-b=%.4f need=%.4f "
                "candidate=%d\n",
                rank, grid.lumas[index],
                static_cast<double>(pixel.red),
                static_cast<double>(pixel.green),
                static_cast<double>(pixel.blue),
                static_cast<double>(pixel.red) - static_cast<double>(pixel.blue),
                std::max(0.004, peak_channel * 0.10),
                is_component_candidate(pixel, film_type) ? 1 : 0);
        }
        for (std::size_t index = 0U; index < components.size() && index < 8U; ++index) {
            std::fprintf(
                stderr,
                "[base-cc]   #%zu cells=%zu p75=%.6f topHalf=(%.5f,%.5f,%.5f)\n",
                index,
                components[index].cells.size(),
                components[index].p75,
                component_channel_median(grid, components[index].cells, 0),
                component_channel_median(grid, components[index].cells, 1),
                component_channel_median(grid, components[index].cells, 2));
        }
    }
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

    std::vector<std::size_t> members;
    for (const Component& component : components) {
        if (component.p75 >= selected_p75 * 0.90 && component.p75 <= selected_p75 / 0.90) {
            members.insert(members.end(), component.cells.begin(), component.cells.end());
        }
    }
    std::sort(members.begin(), members.end(), [&grid](const std::size_t left, const std::size_t right) {
        return grid.lumas[left] > grid.lumas[right];
    });
    const std::size_t member_count = members.size();
    members.resize(std::max(members.size() / 2U, std::min(members.size(), std::size_t{24U})));
    return build_film_base_measurement(
        FilmBaseMeasurementMethod::connected_component,
        static_cast<int>(count),
        static_cast<int>(member_count),
        samples_from_indices(grid, members),
        static_cast<int>(width),
        static_cast<int>(height));
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
    const DownsampledProxy proxy =
        downsample_for_statistics(source, grid.width, grid.height);
    if (proxy.pixels.empty()) {
        return std::nullopt;
    }
    for (std::size_t index = 0U; index < count; ++index) {
        grid.pixels[index] = proxy.pixels[index];
        grid.lumas[index] = luma_of(grid.pixels[index]);
    }
    return grid;
}

[[nodiscard]] std::vector<std::size_t> candidate_indices(
    const SampleGrid& grid,
    const NegativeFilmType film_type,
    const std::vector<bool>* excluded) {
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

}  // namespace negaflow::imaging::film_base_detail
