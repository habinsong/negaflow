#include "scanner_target_measure.h"

#include "scanner_target_color.h"
#include "scanner_target_profile.h"

#include "negaflow/imaging/kernel_accelerator.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <vector>

namespace negaflow::imaging::scanner_target_detail {
namespace {

// 점 표본 격자입니다. 칸 (x, y) 는 원본의 (min(w-1, x*w/sw), min(h-1, y*h/sh)) 화소입니다.
// 안쪽 사각형은 `sh` 로 정하지만, `sh` 가 1 인 극단 비율에서는 한 줄 아래(y = 1)를 읽으므로
// 격자는 최소 두 줄을 담습니다.
struct SampleGrid final {
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::uint32_t rows{0U};
    std::vector<negaflow::core::Rgba32F> pixels{};
};

[[nodiscard]] SampleGrid sample_grid(const negaflow::core::ImageView image) {
    SampleGrid grid{};
    grid.width = std::min(160U, image.width);
    grid.height = std::max(
        1U, static_cast<std::uint32_t>(std::round(
            static_cast<double>(image.height) * grid.width / image.width)));
    grid.rows = std::max(grid.height, 2U);
    grid.pixels.resize(static_cast<std::size_t>(grid.width) * grid.rows);
    // 화상이 GPU 에 머물러 있으면 호스트 화소는 낡았습니다. 거기서 같은 점을 뽑아 옵니다 -
    // 전체를 내리는 대신 격자만 내립니다. 못 뽑으면 가속기가 호스트를 최신으로 만들어 둡니다.
    if (const KernelAccelerator* const table = kernel_accelerator();
        table != nullptr && table->resident_point_samples != nullptr &&
        table->resident_point_samples(
            reinterpret_cast<const float*>(image.pixels),
            image.width,
            image.height,
            grid.width,
            grid.height,
            reinterpret_cast<float*>(grid.pixels.data()))) {
        return grid;
    }
    for (std::uint32_t y = 0U; y < grid.rows; ++y) {
        const std::uint32_t source_y = std::min(
            image.height - 1U,
            static_cast<std::uint32_t>((static_cast<std::uint64_t>(y) * image.height) / grid.height));
        for (std::uint32_t x = 0U; x < grid.width; ++x) {
            const std::uint32_t source_x = std::min(
                image.width - 1U,
                static_cast<std::uint32_t>((static_cast<std::uint64_t>(x) * image.width) / grid.width));
            grid.pixels[static_cast<std::size_t>(y) * grid.width + x] =
                image.pixels[static_cast<std::size_t>(source_y) * image.stride_pixels + source_x];
        }
    }
    return grid;
}

[[nodiscard]] bool measure_grid_inset(
    const SampleGrid& grid,
    const double fraction,
    InsetStats& stats) {
    const std::uint32_t inset_x = std::max(1U, static_cast<std::uint32_t>(grid.width * fraction));
    const std::uint32_t inset_y = std::max(1U, static_cast<std::uint32_t>(grid.height * fraction));
    std::vector<double> values;
    values.reserve(static_cast<std::size_t>(grid.width) * grid.height);
    for (std::uint32_t y = inset_y; y < std::max(inset_y + 1U, grid.height - inset_y); ++y) {
        for (std::uint32_t x = inset_x; x < std::max(inset_x + 1U, grid.width - inset_x); ++x) {
            const negaflow::core::Rgba32F pixel =
                grid.pixels[static_cast<std::size_t>(y) * grid.width + x];
            values.push_back(luma({
                srgb_encode(clamp(pixel.red, 0.0, 1.0)),
                srgb_encode(clamp(pixel.green, 0.0, 1.0)),
                srgb_encode(clamp(pixel.blue, 0.0, 1.0)),
            }));
        }
    }
    if (values.size() < 64U) return false;
    auto copy = values;
    stats.median = percentile(copy, 0.50);
    copy = values;
    stats.p05 = percentile(copy, 0.05);
    copy = std::move(values);
    stats.p95 = percentile(copy, 0.95);
    return true;
}

}  // namespace

bool measure_inset(
    const negaflow::core::ImageView image,
    const double fraction,
    InsetStats& stats) {
    return measure_grid_inset(sample_grid(image), fraction, stats);
}

[[nodiscard]] double scene_anchor_weight(
    const negaflow::core::ImageView image,
    double& median) {
    if (image.width <= 8U || image.height <= 8U) {
        median = 0.5;
        return 0.0;
    }
    // 두 안쪽 사각형은 같은 격자에서 잽니다. 격자 크기가 원본 치수로만 정해지기 때문입니다.
    const SampleGrid grid = sample_grid(image);
    InsetStats outer{};
    if (!measure_grid_inset(grid, 0.06, outer)) {
        median = 0.5;
        return 0.0;
    }
    InsetStats chosen = outer;
    InsetStats inner{};
    if (measure_grid_inset(grid, 0.15, inner) &&
        outer.p95 - inner.p95 < 0.05 &&
        inner.p05 - outer.p05 > 0.30) {
        chosen = inner;
    }
    median = chosen.median;
    return 1.0 - smoothstep(0.45, 0.66, chosen.p95 - chosen.p05);
}

}  // namespace negaflow::imaging::scanner_target_detail
