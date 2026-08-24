#include "grain_mend_memory_probe.h"

#include "negaflow/pipeline/develop_export.h"
#include "export/stages/decode.h"
#include "export/support/preview_raw_store.h"

#include <array>
#include <cstdint>
#include <iostream>
#include <span>
#include <string>
#include <vector>

#include <windows.h>
#include <psapi.h>

namespace negaflow::test_probes {
namespace {

// macOS `DevelopFrameRenderer.fullMaxDimension`.
constexpr std::uint32_t settled_box = 3600U;

[[nodiscard]] negaflow::pipeline::DevelopExportRequest base_request(
    const std::filesystem::path& source) {
    negaflow::pipeline::DevelopExportRequest request{};
    request.source = source;
    request.film_polarity = negaflow::pipeline::FilmPolarity::negative;
    request.base_estimation_mode = negaflow::pipeline::NegativeBaseEstimationMode::manual;
    request.negative.dmin = {0.18F, 0.11F, 0.08F};
    request.tone.exposure_stops = 0.25F;
    request.retain_preview_raw = false;
    return request;
}

/// recipe 안의 span 은 **벡터가 최종 크기에 도달한 뒤에** 묶어야 합니다. 먼저 묶으면
/// `push_back` 의 재할당이 앞서 묶어 둔 span 을 매답니다.
struct RecipeBuffers final {
    std::vector<std::uint8_t> mask{};
};

/// Auto·Guided 가 만드는 region edit 입니다. 둘의 차이는 마스크 한 변의 크기뿐입니다 —
/// Auto 는 검출이 찾은 작은 결함들, Guided 는 사용자가 친 넓은 영역입니다.
void add_region_edit(
    negaflow::pipeline::DevelopExportRequest& request,
    RecipeBuffers& buffers,
    const std::uint32_t side) {
    buffers.mask.assign(static_cast<std::size_t>(side) * side, 0U);
    for (std::uint32_t row = side / 4U; row < side - side / 4U; ++row) {
        for (std::uint32_t column = side / 4U; column < side - side / 4U; ++column) {
            buffers.mask[static_cast<std::size_t>(row) * side + column] = 255U;
        }
    }
    negaflow::pipeline::DefectRegionEdit edit{};
    edit.roi_x = 64U;
    edit.roi_y = 64U;
    edit.width = side;
    edit.height = side;
    edit.mask = buffers.mask;
    edit.mask_stride_bytes = side;
    edit.repair.strength = 1.0;
    request.defect_recipe.regions.edits.push_back(edit);
    request.defect_recipe.order.push_back(
        {negaflow::pipeline::DefectRecipeEditKind::region, 0U});
}

void add_brush_edit(negaflow::pipeline::DevelopExportRequest& request) {
    auto& recipe = request.defect_recipe;
    recipe.brush_points_storage = {{0.32, 0.44}, {0.38, 0.47}, {0.44, 0.50}};
    negaflow::imaging::DefectBrushStroke stroke{};
    stroke.points = recipe.brush_points_storage;
    stroke.thickness = 0.03;
    recipe.brush_strokes_storage.push_back(stroke);
    negaflow::pipeline::DefectBrushEdit edit{};
    edit.parameters.strokes = recipe.brush_strokes_storage;
    edit.parameters.strength = 1.0;
    recipe.brushes.push_back(edit);
    recipe.order.push_back({negaflow::pipeline::DefectRecipeEditKind::brush, 0U});
}

void add_clone_edit(negaflow::pipeline::DevelopExportRequest& request) {
    auto& recipe = request.defect_recipe;
    recipe.clone_points_storage = {{0.40, 0.48}, {0.48, 0.48}};
    for (std::size_t index = 0U; index < recipe.clone_points_storage.size(); ++index) {
        negaflow::imaging::DefectCloneStroke stroke{};
        stroke.points = std::span{&recipe.clone_points_storage[index], 1U};
        stroke.offset_x = index == 0U ? 0.07 : -0.05;
        stroke.offset_y = index == 0U ? -0.03 : 0.06;
        stroke.diameter_pixels = 34.0;
        stroke.hardness = 0.65;
        recipe.clone_strokes_storage.push_back(stroke);
    }
    for (std::size_t index = 0U; index < recipe.clone_strokes_storage.size(); ++index) {
        negaflow::pipeline::DefectCloneEdit edit{};
        edit.parameters.strokes = std::span{&recipe.clone_strokes_storage[index], 1U};
        recipe.clones.push_back(edit);
        recipe.order.push_back({negaflow::pipeline::DefectRecipeEditKind::clone, index});
    }
}

void add_infrared_edit(
    negaflow::pipeline::DevelopExportRequest& request,
    RecipeBuffers& buffers) {
    constexpr std::uint32_t side = 96U;
    buffers.mask.assign(static_cast<std::size_t>(side) * side, 0U);
    for (std::uint32_t row = 16U; row < side - 16U; ++row) {
        for (std::uint32_t column = 16U; column < side - 16U; ++column) {
            buffers.mask[static_cast<std::size_t>(row) * side + column] = 255U;
        }
    }
    negaflow::pipeline::DefectInfraredEdit cluster{};
    cluster.roi_x = 128U;
    cluster.roi_y = 128U;
    cluster.width = side;
    cluster.height = side;
    cluster.core_mask = buffers.mask;
    cluster.core_mask_stride_bytes = side;
    cluster.strength = 1.0;
    negaflow::pipeline::DefectInfraredItem item{};
    item.strength = 1.0;
    item.clusters.push_back(cluster);
    request.defect_recipe.infrared.push_back(item);
    request.defect_recipe.order.push_back(
        {negaflow::pipeline::DefectRecipeEditKind::infrared, 0U});
}

[[nodiscard]] bool build_request(
    const std::string_view feature,
    const std::filesystem::path& source,
    negaflow::pipeline::DevelopExportRequest& request,
    RecipeBuffers& buffers) {
    request = base_request(source);
    if (feature == "switch") {
        return true;
    }
    if (feature == "auto") {
        add_region_edit(request, buffers, 48U);
    } else if (feature == "guided") {
        add_region_edit(request, buffers, 192U);
    } else if (feature == "brush") {
        add_brush_edit(request);
    } else if (feature == "clone") {
        add_clone_edit(request);
    } else if (feature == "infrared") {
        add_infrared_edit(request, buffers);
    } else {
        return false;
    }
    std::array<std::uint8_t, 32U> digest{};
    digest.fill(static_cast<std::uint8_t>(feature.size() + 0x40U));
    request.defect_recipe_sha256 = digest;
    return true;
}

[[nodiscard]] bool report(
    const std::string_view feature,
    const int iteration,
    const bool succeeded) {
    PROCESS_MEMORY_COUNTERS_EX memory{};
    memory.cb = static_cast<DWORD>(sizeof(memory));
    if (!GetProcessMemoryInfo(
            GetCurrentProcess(),
            reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&memory),
            static_cast<DWORD>(sizeof(memory)))) {
        return false;
    }
    std::cout << "grainmend_memory feature=" << feature
              << " iteration=" << iteration
              << " ok=" << succeeded
              << " private=" << memory.PrivateUsage
              << " working=" << memory.WorkingSetSize
              << " peak_working=" << memory.PeakWorkingSetSize
              << " raw="
              << negaflow::pipeline::develop_export_detail::preview_raw_store_resident_bytes()
              << " decoded="
              << negaflow::pipeline::develop_export_detail::decoded_source_store_resident_bytes()
              << '\n';
    return true;
}

}  // namespace

int run_grain_mend_memory_probe(
    const std::filesystem::path& source,
    const std::filesystem::path& second_source,
    const std::string_view feature,
    const int iterations) {
    if (!std::filesystem::exists(source) || iterations <= 0 || iterations > 200) {
        std::cerr << "invalid grainmend memory probe arguments\n";
        return 2;
    }
    const bool switching = feature == "switch";
    if (switching && !std::filesystem::exists(second_source)) {
        std::cerr << "switch mode needs a second source\n";
        return 2;
    }

    RecipeBuffers first_buffers{};
    RecipeBuffers second_buffers{};
    negaflow::pipeline::DevelopExportRequest first{};
    negaflow::pipeline::DevelopExportRequest second{};
    if (!build_request(feature, source, first, first_buffers)) {
        std::cerr << "unknown grainmend memory probe feature\n";
        return 2;
    }
    if (switching && !build_request("clone", second_source, second, second_buffers)) {
        return 2;
    }

    negaflow::pipeline::develop_export_detail::preview_raw_store_reset();
    negaflow::pipeline::develop_export_detail::decoded_source_store_reset();

    std::vector<std::uint8_t> pixels{};
    for (int iteration = 1; iteration <= iterations; ++iteration) {
        // 사진 전환은 A→B→A 를 한 iteration 으로 셉니다. 한쪽만 반복하면 캐시가
        // 밀리지 않아 전환 뒤 회수를 잴 수 없습니다.
        const negaflow::pipeline::DevelopExportRequest& request =
            switching && (iteration % 2 == 0) ? second : first;
        pixels.assign(
            static_cast<std::size_t>(settled_box) * settled_box * 4U, 0U);
        const auto outcome = negaflow::pipeline::develop_preview(
            request, settled_box, settled_box, pixels.data(), pixels.size());
        if (!report(feature, iteration, outcome.succeeded)) {
            return 3;
        }
        if (!outcome.succeeded) {
            return 4;
        }
    }
    return 0;
}

}  // namespace negaflow::test_probes
