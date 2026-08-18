#include "grain_mend_tiled.h"

#include "grain_mend_component_classification.h"
#include "grain_mend_component_gates.h"
#include "grain_mend_component_types.h"
#include "grain_mend_components.h"
#include "grain_mend_detection_image.h"
#include "grain_mend_detector.h"
#include "grain_mend_mask_paint.h"
#include "grain_mend_speck_detector.h"
#include "grain_mend_stitch.h"
#include "grain_mend_structure_lines.h"
#include "grain_mend_tile_plan.h"
#include "negaflow/imaging/grain_mend.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <future>
#include <limits>
#include <new>
#include <thread>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {

std::vector<std::uint8_t> build_tiled_automatic_mask(
    const WorkingImage& image,
    const AutomaticDetection& request,
    std::size_t& accepted_pixels,
    std::vector<ClassifiedComponent>* const components,
    GrainMendTimings* const timings,
    const negaflow::core::CancelFlag cancel) {
    const auto started = std::chrono::steady_clock::now();
    GrainMendTimings measured{};
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
    // macOS `detectComponents`: `extendedDustScales: constrainedRegion`. 전체 프레임 자동은
    // FILM-R no-regression 기준의 보수 계약을 유지하고, 사용자가 부분 ROI 를 그려 범위를
    // 지정한 가이드에서만 미세·대형 이물 확장 규칙을 켭니다.
    const bool extended_dust_scales = request.constrained_region;

    std::vector<ClassifiedComponent> mapped_components{};
    std::vector<std::uint8_t> frame_evidence(count, 0U);
    std::vector<std::uint8_t> frame_specks{};
    std::vector<float> frame_speck_confidence{};
    if (request.detect_micro_specks) {
        frame_specks.assign(count, 0U);
        frame_speck_confidence.assign(count, 0.0F);
    }
    // macOS `detectComponents` 는 타일 응답을 `DefectScratchResponseMap`(2배 다운샘플
    // max-pooling)에 **타일 전체(halo 포함)** 로 병합하고, stitch 뒤 전역 판정에 그 맵을
    // 넘깁니다. core 화소만 풀해상도로 옮기면 판정이 보는 값이 달라집니다.
    ScratchResponseMap frame_scratch_response(region_width, region_height);
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
                 dust_area, extended_dust_scales, cancel] {
                    const auto image_started = std::chrono::steady_clock::now();
                    make_detection_image_region(
                        image,
                        request.origin_x + placement.detect_x0,
                        request.origin_y + placement.detect_y0,
                        placement.detect_x1 - placement.detect_x0,
                        placement.detect_y1 - placement.detect_y0,
                        workspace.tile);
                    const auto candidates_started = std::chrono::steady_clock::now();
                    workspace.image_microseconds = static_cast<std::uint64_t>(
                        std::chrono::duration_cast<std::chrono::microseconds>(
                            candidates_started - image_started).count());
                    // macOS `detectLabeled` 계약입니다 — strong/weak 히스테리시스와 가는
                    // 결함(thin) 합치기가 여기서만 돕니다. 브러시 경로(false)와 다릅니다.
                    find_candidates(
                        workspace.tile,
                        request.dust_sensitivity,
                        request.scratch_sensitivity,
                        request.protect_detail,
                        true,
                        extended_dust_scales,
                        workspace.candidates,
                        cancel);
                    if (cancel.requested()) {
                        return;
                    }
                    const auto evidence_started = std::chrono::steady_clock::now();
                    build_automatic_evidence(
                        workspace.tile,
                        workspace.candidates,
                        dust_area,
                        minimum_scratch_length(workspace.tile, sensitivity),
                        sensitivity,
                        true,
                        extended_dust_scales,
                        workspace.evidence);
                    const auto speck_started = std::chrono::steady_clock::now();
                    workspace.evidence_microseconds = static_cast<std::uint64_t>(
                        std::chrono::duration_cast<std::chrono::microseconds>(
                            speck_started - evidence_started).count());
                    workspace.speck_microseconds = 0U;
                    if (!request.detect_micro_specks) {
                        workspace.specks.clear();
                        return;
                    }
                    // 같은 타일 화소를 다시 씁니다. 겹치는 입자는 기존 검출이 임자입니다.
                    workspace.specks.assign(workspace.evidence.size(), 0U);
                    workspace.speck_confidence.assign(
                        workspace.evidence.size(), 0.0F);
                    std::size_t added = 0U;
                    static_cast<void>(merge_micro_speck_mask(
                        workspace.tile,
                        request.dust_sensitivity,
                        workspace.specks,
                        added,
                        cancel,
                        &workspace.candidates.valid,
                        &workspace.speck_confidence));
                    workspace.speck_microseconds = static_cast<std::uint64_t>(
                        std::chrono::duration_cast<std::chrono::microseconds>(
                            std::chrono::steady_clock::now() - speck_started).count());
                }));
        }
        for (std::size_t slot = 0U; slot < futures.size(); ++slot) {
            futures[slot].get();
        }
        if (cancel.requested()) {
            return {};
        }
        const auto stitch_started = std::chrono::steady_clock::now();
        for (std::size_t slot = 0U; slot < futures.size(); ++slot) {
            const TileWorkspace& workspace = workspaces[slot];
            const TilePlacement placement = placements[first + slot];
            // 배치는 병렬로 돌므로 타일 시간을 더하면 벽시계보다 큽니다. 어느 단계가 무거운지
            // 비교하는 것이 목적이므로 합계 그대로 냅니다.
            measured.dust_morphology_microseconds +=
                workspace.candidates.dust_morphology_microseconds;
            measured.scratch_angles_microseconds +=
                workspace.candidates.scratch_angles_microseconds;
            measured.detection_image_microseconds += workspace.image_microseconds;
            measured.evidence_microseconds += workspace.evidence_microseconds;
            measured.speck_microseconds += workspace.speck_microseconds;
            measured.dust_components_collected +=
                workspace.candidates.dust_components_collected;
            measured.dust_dropped_no_strong +=
                workspace.candidates.dust_dropped_no_strong;
            measured.dust_dropped_strong_fraction +=
                workspace.candidates.dust_dropped_strong_fraction;
            measured.dust_dropped_gate +=
                workspace.candidates.dust_dropped_gate;
            measured.dust_dropped_isolation +=
                workspace.candidates.dust_dropped_isolation;
            measured.dust_kept += workspace.candidates.dust_kept;
            measured.dust_pixels_above_weak_abs +=
                workspace.candidates.dust_pixels_above_weak_abs;
            measured.dust_pixels_above_abs +=
                workspace.candidates.dust_pixels_above_abs;
            measured.valid_pixels += workspace.candidates.valid_pixels;
            measured.dust_magnitude_sum +=
                workspace.candidates.dust_magnitude_sum;
            measured.dust_noise_sum += workspace.candidates.dust_noise_sum;
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
                    if (!frame_specks.empty() && !workspace.specks.empty()) {
                        frame_specks[frame_index] = workspace.specks[tile_index];
                        if (tile_index < workspace.speck_confidence.size()) {
                            frame_speck_confidence[frame_index] =
                                workspace.speck_confidence[tile_index];
                        }
                    }
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
                    if (tile_index < workspace.candidates.strong.size() &&
                        (workspace.candidates.strong[tile_index] & 1U) != 0U) {
                        ++measured.dust_strong_pixels;
                    }
                    if (tile_index < workspace.candidates.weak.size() &&
                        (workspace.candidates.weak[tile_index] & 1U) != 0U) {
                        ++measured.dust_raw_weak_pixels;
                    }
                }
            }
            // macOS: `responseMap.merge(tile: tile.scratchResponse, tileWidth: tile.dw,
            // tileHeight: tileHeight, originX: tile.dx0, originY: tile.fieldY0)` —
            // core 가 아니라 검출 사각형 전체를 그 원점에 병합합니다.
            if (reject_line_grid) {
                frame_scratch_response.merge(
                    workspace.candidates.scratch_response,
                    workspace.tile.width,
                    workspace.tile.height,
                    placement.detect_x0,
                    placement.detect_y0);
            }
            append_mapped_core_components(
                workspace,
                placement,
                region_width,
                classification_dust_area,
                mapped_components);
        }
        measured.stitch_microseconds +=
            static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(
                std::chrono::steady_clock::now() - stitch_started).count());
    }

    // macOS `stitchRegionDefectTiles` 후 `rejectingGlobalStructureLines`.
    // 타일에서 이미 분류된 성분을 union 하고, 합친 덩어리를 다시 분류하지 않는다.
    const auto components_started = std::chrono::steady_clock::now();
    std::vector<ClassifiedComponent> stitched = stitch_region_defect_tiles(
        mapped_components, region_width, region_height);
    std::vector<std::uint8_t> drop(stitched.size(), 0U);
    if (reject_line_grid) {
        std::vector<Component> scratch{};
        std::vector<std::size_t> scratch_index{};
        scratch.reserve(stitched.size());
        scratch_index.reserve(stitched.size());
        for (std::size_t index = 0U; index < stitched.size(); ++index) {
            if (stitched[index].is_scratch) {
                scratch.push_back(to_raw_component(stitched[index]));
                scratch_index.push_back(index);
            }
        }
        if (scratch.size() >= tuning::grid_line_minimum_field) {
            const std::vector<std::uint8_t> grid_drops = structure_grid_drops(
                scratch,
                frame,
                static_cast<int>(std::min(core_width, core_height)));
            const std::vector<std::uint8_t> line_drops = continuation_drops(
                scratch, region_width, frame_scratch_response);
            for (std::size_t index = 0U; index < scratch.size(); ++index) {
                if (grid_drops[index] != 0U || line_drops[index] != 0U) {
                    drop[scratch_index[index]] = 1U;
                }
            }
        }
    }

    std::vector<std::uint8_t> mask(count, 0U);
    if (components != nullptr) {
        components->clear();
        components->reserve(stitched.size());
    }
    for (std::size_t index = 0U; index < stitched.size(); ++index) {
        if (drop[index] != 0U) {
            continue;
        }
        ClassifiedComponent& component = stitched[index];
        const Component raw = to_raw_component(component);
        if (component.is_scratch) {
            paint_component(raw, 1, frame, mask);
        } else {
            paint_component(raw, 0, frame, mask);
            fill_interior_holes(raw, frame, dust_area, mask);
        }
        if (components != nullptr) {
            components->push_back(std::move(component));
        }
    }
    accepted_pixels = static_cast<std::size_t>(std::count(
        mask.begin(), mask.end(), static_cast<std::uint8_t>(1U)));
    if (!frame_specks.empty()) {
        measured.speck_mask_pixels = static_cast<std::uint64_t>(
            std::count(frame_specks.begin(), frame_specks.end(),
                       static_cast<std::uint8_t>(1U)));
    }
    for (const std::uint8_t bit : frame_evidence) {
        if ((bit & 1U) != 0U) {
            ++measured.dust_weak_pixels;
        }
    }
    const auto finished = std::chrono::steady_clock::now();
    measured.components_microseconds =
        static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(
            finished - components_started).count());
    measured.total_microseconds =
        static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(
            finished - started).count());
    measured.tile_count = static_cast<std::uint32_t>(placements.size());
    measured.worker_count = static_cast<std::uint32_t>(workers);
    if (timings != nullptr) {
        *timings = measured;
    }
    return mask;
}


}  // namespace negaflow::imaging::grain_mend_detail
