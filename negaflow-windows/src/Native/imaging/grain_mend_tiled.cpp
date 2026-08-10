#include "grain_mend_tiled.h"

#include "grain_mend_components.h"
#include "grain_mend_detector.h"
#include "negaflow/imaging/grain_mend.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {
namespace {

constexpr std::uint32_t automatic_tile_maximum = 1'400U;
// The macOS detector raises the public 48px request to its largest fixed
// context support (80px) before tiling. Keeping the effective halo here avoids
// clipping far-texture statistics at a core boundary.
constexpr std::uint32_t automatic_tile_halo = 80U;
constexpr std::size_t base_maximum_dust_area = 150U;

[[nodiscard]] std::size_t checked_pixel_count(
    const std::uint32_t width,
    const std::uint32_t height) {
    if (width == 0U || height == 0U ||
        static_cast<std::size_t>(width) >
            std::numeric_limits<std::size_t>::max() /
                static_cast<std::size_t>(height)) {
        throw std::bad_alloc{};
    }
    return static_cast<std::size_t>(width) * static_cast<std::size_t>(height);
}

[[nodiscard]] std::uint32_t ceil_divide(
    const std::uint32_t value,
    const std::uint32_t divisor) noexcept {
    return value / divisor + (value % divisor == 0U ? 0U : 1U);
}

[[nodiscard]] std::size_t maximum_dust_area(
    const WorkingImage& image,
    const double sensitivity) noexcept {
    const double long_side = static_cast<double>(
        std::max(image.width, image.height));
    const double ratio =
        long_side / static_cast<double>(grain_mend_maximum_detection_dimension);
    const double physical = std::max(
        static_cast<double>(base_maximum_dust_area),
        ratio * ratio * static_cast<double>(base_maximum_dust_area));
    return static_cast<std::size_t>(std::llround(
        physical * (1.0 + sensitivity * 5.0)));
}

[[nodiscard]] std::uint32_t minimum_scratch_length(
    const DetectionImage& tile,
    const double dust_sensitivity) noexcept {
    const std::uint32_t divisor = static_cast<std::uint32_t>(
        120.0 + dust_sensitivity * 120.0);
    return std::max(
        6U,
        std::max(tile.width, tile.height) / std::max(1U, divisor));
}

}  // namespace

std::vector<std::uint8_t> build_tiled_automatic_mask(
    const WorkingImage& image,
    const double dust_sensitivity,
    const double scratch_sensitivity,
    const double protect_detail,
    std::size_t& accepted_pixels,
    const negaflow::core::CancelFlag cancel) {
    const std::size_t count = checked_pixel_count(image.width, image.height);
    std::vector<std::uint8_t> frame_evidence(count, 0U);
    std::vector<float> frame_scratch_response(count, 0.0F);

    const std::uint32_t columns = ceil_divide(
        image.width, automatic_tile_maximum);
    const std::uint32_t rows = ceil_divide(
        image.height, automatic_tile_maximum);
    const std::uint32_t core_width = ceil_divide(image.width, columns);
    const std::uint32_t core_height = ceil_divide(image.height, rows);
    const std::size_t dust_area = maximum_dust_area(
        image, dust_sensitivity);
    DetectionImage tile{};
    CandidateMaps candidates{};
    std::vector<std::uint8_t> evidence{};

    for (std::uint32_t tile_y = 0U; tile_y < rows; ++tile_y) {
        if (cancel.requested()) {
            return {};
        }
        const std::uint32_t core_y0 = tile_y * core_height;
        const std::uint32_t core_y1 = std::min(
            image.height, core_y0 + core_height);
        for (std::uint32_t tile_x = 0U; tile_x < columns; ++tile_x) {
            const std::uint32_t core_x0 = tile_x * core_width;
            const std::uint32_t core_x1 = std::min(
                image.width, core_x0 + core_width);
            const std::uint32_t detect_x0 = core_x0 > automatic_tile_halo
                ? core_x0 - automatic_tile_halo
                : 0U;
            const std::uint32_t detect_y0 = core_y0 > automatic_tile_halo
                ? core_y0 - automatic_tile_halo
                : 0U;
            const std::uint32_t detect_x1 = std::min(
                image.width, core_x1 + automatic_tile_halo);
            const std::uint32_t detect_y1 = std::min(
                image.height, core_y1 + automatic_tile_halo);

            make_detection_image_region(
                image,
                detect_x0,
                detect_y0,
                detect_x1 - detect_x0,
                detect_y1 - detect_y0,
                tile);
            find_candidates(
                tile,
                dust_sensitivity,
                scratch_sensitivity,
                protect_detail,
                true,
                candidates,
                cancel);
            if (cancel.requested()) {
                return {};
            }
            build_automatic_evidence(
                tile,
                candidates,
                dust_area,
                minimum_scratch_length(tile, dust_sensitivity),
                dust_sensitivity,
                true,
                evidence);

            for (std::uint32_t y = core_y0; y < core_y1; ++y) {
                const std::size_t frame_row =
                    static_cast<std::size_t>(y) * image.width;
                const std::size_t tile_row =
                    static_cast<std::size_t>(y - detect_y0) * tile.width;
                for (std::uint32_t x = core_x0; x < core_x1; ++x) {
                    const std::size_t frame_index = frame_row + x;
                    const std::size_t tile_index =
                        tile_row + static_cast<std::size_t>(x - detect_x0);
                    frame_evidence[frame_index] = evidence[tile_index];
                    frame_scratch_response[frame_index] =
                        candidates.scratch_response[tile_index];
                }
            }
        }
    }

    DetectionImage frame{};
    frame.width = image.width;
    frame.height = image.height;
    return build_automatic_mask_from_evidence(
        frame,
        frame_evidence,
        frame_scratch_response,
        dust_area,
        static_cast<int>(std::min(core_width, core_height)),
        true,
        accepted_pixels);
}

}  // namespace negaflow::imaging::grain_mend_detail
