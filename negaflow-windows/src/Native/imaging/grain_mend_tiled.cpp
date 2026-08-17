#include "grain_mend_tiled.h"

#include "grain_mend_components.h"
#include "grain_mend_detection_image.h"
#include "grain_mend_detector.h"
#include "negaflow/imaging/grain_mend.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <future>
#include <limits>
#include <new>
#include <thread>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {
namespace {

constexpr std::uint32_t automatic_tile_maximum = 1'400U;
// The macOS detector raises the public 48px request to its largest fixed
// context support (80px) before tiling. Keeping the effective halo here avoids
// clipping far-texture statistics at a core boundary.
constexpr std::uint32_t automatic_tile_halo = 80U;
constexpr double base_maximum_dust_area = 150.0;
// macOS `detectComponents` runs at most four tiles at once: every tile holds
// full-size float planes, so starting them all peaks memory and stalls the UI.
constexpr std::size_t maximum_concurrent_tiles = 4U;

[[nodiscard]] std::uint32_t ceil_divide(
    const std::uint32_t value,
    const std::uint32_t divisor) noexcept {
    return value / divisor + (value % divisor == 0U ? 0U : 1U);
}

/// macOS `detectComponents` 의 먼지 면적 상한입니다. **원본 프레임 긴 변**을 기준으로 재므로
/// ROI 를 작게 그리든 크게 그리든 같은 물리 먼지 크기가 됩니다.
[[nodiscard]] double base_dust_area(const WorkingImage& image) noexcept {
    const double long_side = static_cast<double>(
        std::max(image.width, image.height));
    const double ratio =
        long_side / static_cast<double>(grain_mend_maximum_detection_dimension);
    return std::max(
        base_maximum_dust_area,
        std::llround(ratio * ratio * base_maximum_dust_area) * 1.0);
}

/// macOS `detectLabeledWithResponse`: `max(6, max(w, h) / (120 + s * 120))`.
[[nodiscard]] std::uint32_t minimum_scratch_length(
    const DetectionImage& tile,
    const double dust_sensitivity) noexcept {
    const auto divisor = static_cast<std::uint32_t>(
        120.0 + dust_sensitivity * 120.0);
    return std::max(
        6U,
        std::max(tile.width, tile.height) / std::max(1U, divisor));
}

/// 타일 한 장이 쓰는 작업 공간입니다. 배치 안에서 타일마다 하나씩 가집니다.
struct TileWorkspace {
    DetectionImage tile{};
    CandidateMaps candidates{};
    std::vector<std::uint8_t> evidence{};
};

struct TilePlacement {
    std::uint32_t core_x0 = 0U;
    std::uint32_t core_y0 = 0U;
    std::uint32_t core_x1 = 0U;
    std::uint32_t core_y1 = 0U;
    std::uint32_t detect_x0 = 0U;
    std::uint32_t detect_y0 = 0U;
    std::uint32_t detect_x1 = 0U;
    std::uint32_t detect_y1 = 0U;
};

}  // namespace

std::vector<std::uint8_t> build_tiled_automatic_mask(
    const WorkingImage& image,
    const AutomaticDetection& request,
    std::size_t& accepted_pixels,
    std::vector<ClassifiedComponent>* const components,
    const negaflow::core::CancelFlag cancel) {
    const std::uint32_t region_width = request.width;
    const std::uint32_t region_height = request.height;
    const std::size_t count = checked_pixel_count(region_width, region_height);

    // macOS 게이트 계약. 자동과 가이드가 나뉘는 유일한 자리입니다.
    const double sensitivity = std::clamp(request.dust_sensitivity, 0.0, 1.0);
    const double base = base_dust_area(image);
    const double area_scale = request.constrained_region ? 48.0 : 5.0;
    const auto dust_area = static_cast<std::size_t>(std::llround(
        base * (1.0 + sensitivity * area_scale)));
    const auto classification_dust_area = static_cast<std::size_t>(std::llround(
        base * (1.0 + sensitivity * 5.0)));
    // 사용자가 ROI 로 결함을 지목한 가이드에서는 대상 스크래치를 격자로 오인해 지우지
    // 않도록 끕니다 — macOS `rejectLineGrid = !constrainedRegion`.
    const bool reject_line_grid = !request.constrained_region;

    std::vector<std::uint8_t> frame_evidence(count, 0U);
    std::vector<float> frame_scratch_response(count, 0.0F);
    // 분류기가 읽는 국소 통계입니다. 타일이 낸 것을 core 만 프레임으로 옮깁니다 — 분류를
    // 타일 안에서 하면 타일 경계에서 잘린 한 결함이 조각마다 다른 종류가 됩니다.
    CandidateMaps frame_candidates{};
    frame_candidates.dust_magnitude.assign(count, 0.0F);
    frame_candidates.thin_magnitude.assign(count, 0.0F);
    frame_candidates.noise_scale.assign(count, 0.0F);
    DetectionImage frame{};
    frame.width = region_width;
    frame.height = region_height;
    frame.brightest_channel.assign(count, 0.0F);

    const std::uint32_t columns = ceil_divide(
        region_width, automatic_tile_maximum);
    const std::uint32_t rows = ceil_divide(
        region_height, automatic_tile_maximum);
    const std::uint32_t core_width = ceil_divide(region_width, columns);
    const std::uint32_t core_height = ceil_divide(region_height, rows);
    const std::size_t tile_count =
        static_cast<std::size_t>(columns) * static_cast<std::size_t>(rows);

    std::vector<TilePlacement> placements{};
    placements.reserve(tile_count);
    for (std::uint32_t row = 0U; row < rows; ++row) {
        const std::uint32_t core_y0 = row * core_height;
        const std::uint32_t core_y1 = std::min(
            region_height, core_y0 + core_height);
        for (std::uint32_t column = 0U; column < columns; ++column) {
            const std::uint32_t core_x0 = column * core_width;
            const std::uint32_t core_x1 = std::min(
                region_width, core_x0 + core_width);
            if (core_x1 <= core_x0 || core_y1 <= core_y0) {
                continue;
            }
            placements.push_back({
                core_x0,
                core_y0,
                core_x1,
                core_y1,
                core_x0 > automatic_tile_halo ? core_x0 - automatic_tile_halo : 0U,
                core_y0 > automatic_tile_halo ? core_y0 - automatic_tile_halo : 0U,
                std::min(region_width, core_x1 + automatic_tile_halo),
                std::min(region_height, core_y1 + automatic_tile_halo),
            });
        }
    }

    const unsigned int hardware_threads = std::thread::hardware_concurrency();
    const std::size_t workers = std::clamp<std::size_t>(
        hardware_threads == 0U ? 1U : hardware_threads / 2U,
        1U,
        maximum_concurrent_tiles);
    std::vector<TileWorkspace> workspaces(workers);

    for (std::size_t first = 0U; first < placements.size(); first += workers) {
        if (cancel.requested()) {
            return {};
        }
        const std::size_t last = std::min(placements.size(), first + workers);
        std::vector<std::future<void>> futures{};
        futures.reserve(last - first);
        for (std::size_t index = first; index < last; ++index) {
            TileWorkspace& workspace = workspaces[index - first];
            const TilePlacement placement = placements[index];
            futures.push_back(std::async(
                std::launch::async,
                [&image, &request, &workspace, placement, sensitivity,
                 dust_area, cancel] {
                    make_detection_image_region(
                        image,
                        request.origin_x + placement.detect_x0,
                        request.origin_y + placement.detect_y0,
                        placement.detect_x1 - placement.detect_x0,
                        placement.detect_y1 - placement.detect_y0,
                        workspace.tile);
                    // macOS `detectLabeled` 계약입니다 — strong/weak 히스테리시스와 가는
                    // 결함(thin) 합치기가 여기서만 돕니다. 브러시 경로(false)와 다릅니다.
                    find_candidates(
                        workspace.tile,
                        request.dust_sensitivity,
                        request.scratch_sensitivity,
                        request.protect_detail,
                        true,
                        workspace.candidates,
                        cancel);
                    if (cancel.requested()) {
                        return;
                    }
                    build_automatic_evidence(
                        workspace.tile,
                        workspace.candidates,
                        dust_area,
                        minimum_scratch_length(workspace.tile, sensitivity),
                        sensitivity,
                        true,
                        workspace.evidence);
                }));
        }
        for (std::size_t slot = 0U; slot < futures.size(); ++slot) {
            futures[slot].get();
        }
        if (cancel.requested()) {
            return {};
        }
        for (std::size_t slot = 0U; slot < futures.size(); ++slot) {
            const TileWorkspace& workspace = workspaces[slot];
            const TilePlacement placement = placements[first + slot];
            const bool has_statistics =
                workspace.candidates.dust_magnitude.size() ==
                    workspace.evidence.size() &&
                workspace.candidates.thin_magnitude.size() ==
                    workspace.evidence.size() &&
                workspace.candidates.noise_scale.size() ==
                    workspace.evidence.size();
            for (std::uint32_t y = placement.core_y0; y < placement.core_y1; ++y) {
                const std::size_t frame_row =
                    static_cast<std::size_t>(y) * region_width;
                const std::size_t tile_row =
                    static_cast<std::size_t>(y - placement.detect_y0) *
                    workspace.tile.width;
                for (std::uint32_t x = placement.core_x0;
                     x < placement.core_x1;
                     ++x) {
                    const std::size_t frame_index = frame_row + x;
                    const std::size_t tile_index =
                        tile_row + static_cast<std::size_t>(x - placement.detect_x0);
                    frame_evidence[frame_index] = workspace.evidence[tile_index];
                    frame_scratch_response[frame_index] =
                        workspace.candidates.scratch_response[tile_index];
                    frame.brightest_channel[frame_index] =
                        workspace.tile.brightest_channel[tile_index];
                    if (has_statistics) {
                        frame_candidates.dust_magnitude[frame_index] =
                            workspace.candidates.dust_magnitude[tile_index];
                        frame_candidates.thin_magnitude[frame_index] =
                            workspace.candidates.thin_magnitude[tile_index];
                        frame_candidates.noise_scale[frame_index] =
                            workspace.candidates.noise_scale[tile_index];
                    }
                }
            }
        }
    }

    // 구조선 배제는 프레임 전체에서 한 번에 판정합니다. 타일 안에서는 프레임에 퍼진 구조가
    // 판정 최소 선 개수에 못 미치고, 연장 증거는 halo 밖을 볼 수 없습니다.
    return build_automatic_mask_from_evidence(
        frame,
        frame_evidence,
        frame_scratch_response,
        dust_area,
        classification_dust_area,
        static_cast<int>(std::min(core_width, core_height)),
        reject_line_grid,
        accepted_pixels,
        &frame_candidates,
        components);
}

}  // namespace negaflow::imaging::grain_mend_detail
