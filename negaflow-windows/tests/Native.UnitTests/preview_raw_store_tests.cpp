// 프리뷰 raw 프록시 상주 캐시의 시험입니다.
//
// 여기 있는 네 가지는 전부 **실제로 났던 고장**을 고정한 것입니다.
//   ① 썸네일(작은 상자, 다른 프레임) 렌더가 현상 중인 프레임의 프록시를 밀어냈습니다 —
//      프로세스 전역 슬롯이 하나뿐이라, 슬라이더 한 칸마다 원본을 다시 디코드했습니다.
//   ② 정착본이 있는데도 인터랙티브 상자가 디코드로 내려갔습니다. macOS
//      `DevelopFrameRenderer+Input.swift:51-52` 는 정착 raw 에서 Lanczos 로 파생합니다.
//   ③ 그 전역에 잠금이 없어 스레드가 겹치면 use-after-free 가 났습니다
//      (이벤트 로그 0xc0000374 힙 손상 · 0xc0000409 abort).

#include "negaflow/pipeline/develop_export.h"
#include "negaflow/pipeline/frame_cache_limits.h"
#include "negaflow/pipeline/stage_timing.h"
#include "export/stages/decode.h"
#include "export/support/frame_cache_budget.h"
#include "export/support/preview_raw_store.h"
#include "grain_mend_memory_probe.h"
#include "synthetic_wic_tiff.h"

#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <thread>
#include <vector>

#include <windows.h>
#include <psapi.h>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] std::uint32_t decode_runs() {
    const auto timings = negaflow::pipeline::stage_timings();
    return timings
        .slots[static_cast<std::size_t>(negaflow::pipeline::DevelopExportStage::decode)]
        .runs;
}

[[nodiscard]] std::uint32_t stage_runs(
    const negaflow::pipeline::DevelopExportStage stage) {
    return negaflow::pipeline::stage_timings().slots[static_cast<std::size_t>(stage)].runs;
}

[[nodiscard]] bool write_source(
    const std::filesystem::path& path,
    const std::uint32_t width,
    const std::uint32_t height) {
    const std::vector<std::uint8_t> tiff =
        negaflow::test_fixtures::make_uncompressed_rgb16_defect_tiff(width, height);
    if (tiff.empty()) {
        return false;
    }
    std::ofstream out(path, std::ios::binary | std::ios::trunc);
    out.write(
        reinterpret_cast<const char*>(tiff.data()),
        static_cast<std::streamsize>(tiff.size()));
    return out.good();
}

[[nodiscard]] negaflow::pipeline::DevelopExportRequest request_for(
    const std::filesystem::path& source) {
    negaflow::pipeline::DevelopExportRequest request{};
    request.source = source;
    request.film_polarity = negaflow::pipeline::FilmPolarity::negative;
    request.base_estimation_mode = negaflow::pipeline::NegativeBaseEstimationMode::manual;
    request.negative.dmin = {0.18F, 0.11F, 0.08F};
    request.tone.exposure_stops = 0.25F;
    return request;
}

[[nodiscard]] negaflow::pipeline::DevelopExportRequest clone_request_for(
    const negaflow::pipeline::DevelopExportRequest& base,
    const std::size_t edit_count,
    const std::uint8_t recipe_byte) {
    negaflow::pipeline::DevelopExportRequest request = base;
    auto& recipe = request.defect_recipe;
    recipe.clone_points_storage.reserve(edit_count);
    recipe.clone_strokes_storage.reserve(edit_count);
    recipe.clones.reserve(edit_count);
    recipe.order.reserve(edit_count);
    for (std::size_t index = 0U; index < edit_count; ++index) {
        recipe.clone_points_storage.push_back(
            {0.40 + static_cast<double>(index) * 0.08, 0.48});
    }
    for (std::size_t index = 0U; index < edit_count; ++index) {
        negaflow::imaging::DefectCloneStroke stroke{};
        stroke.points = std::span{&recipe.clone_points_storage[index], 1U};
        stroke.offset_x = index == 0U ? 0.07 : -0.05;
        stroke.offset_y = index == 0U ? -0.03 : 0.06;
        stroke.diameter_pixels = 34.0;
        stroke.hardness = 0.65;
        recipe.clone_strokes_storage.push_back(stroke);
    }
    for (std::size_t index = 0U; index < edit_count; ++index) {
        negaflow::pipeline::DefectCloneEdit edit{};
        edit.parameters.strokes =
            std::span{&recipe.clone_strokes_storage[index], 1U};
        recipe.clones.push_back(edit);
        recipe.order.push_back(
            {negaflow::pipeline::DefectRecipeEditKind::clone, index});
    }
    std::array<std::uint8_t, 32U> digest{};
    digest.fill(recipe_byte);
    request.defect_recipe_sha256 = digest;
    return request;
}

[[nodiscard]] negaflow::pipeline::DevelopExportOutcome preview_at(
    const negaflow::pipeline::DevelopExportRequest& request,
    const std::uint32_t box,
    std::vector<std::uint8_t>& pixels) {
    pixels.assign(static_cast<std::size_t>(box) * box * 4U, 0U);
    return negaflow::pipeline::develop_preview(
        request, box, box, pixels.data(), pixels.size());
}

// macOS `DevelopFrameRenderer.fullMaxDimension`.
constexpr std::uint32_t settled_box = 3600U;


}  // namespace

int main(int argc, char** argv) {
    (void)_putenv_s("NEGA_TIMING", "1");

    // `--grainmend-memory <source> <feature> <iterations> [<second-source>]`
    //
    // 앞 판은 Clone 한 기능만 100회 돌 수 있었습니다. 한 경계만 재고 "누수 없음" 이라고
    // 적지 않기 위해 Auto·Guided·Brush·Clone·IR 과 사진 A↔B 전환을 모두 받습니다.
    if ((argc == 5 || argc == 6) && std::string{argv[1]} == "--grainmend-memory") {
        const long parsed = std::strtol(argv[4], nullptr, 10);
        if (parsed <= 0 || parsed > std::numeric_limits<int>::max()) {
            return 2;
        }
        return negaflow::test_probes::run_grain_mend_memory_probe(
            std::filesystem::path{argv[2]},
            argc == 6 ? std::filesystem::path{argv[5]} : std::filesystem::path{},
            std::string{argv[3]},
            static_cast<int>(parsed));
    }

    using negaflow::pipeline::develop_export_detail::FrameCachePressureLevel;
    using negaflow::pipeline::develop_export_detail::effective_cache_budget_bytes;
    expect(
        effective_cache_budget_bytes(1234ULL, FrameCachePressureLevel::normal) == 1234ULL,
        "normal memory pressure keeps the cache budget");
    expect(
        effective_cache_budget_bytes(1234ULL, FrameCachePressureLevel::critical) == 0ULL,
        "critical memory pressure drops regenerable history budget");

    // ⑥ 설정 창이 건 상주 한도가 두 캐시의 예산에 실제로 닿는가.
    //    닿지 않던 것이 고장이었습니다 — 두 예산 함수가 설치 메모리만 보고 값을 정해,
    //    설정에서 자동·수동을 바꾸고 프레임 수를 올려도 엔진은 그대로였습니다.
    //    한도가 걸려 있으면 macOS 와 같은 셈이어야 합니다: cleaned raw 는 프레임당 190MB,
    //    프리뷰 프록시는 developed 프레임당 170MB 중 native Rgba32F 몫(16 / (16+4)).
    {
        using negaflow::pipeline::FrameCacheResidencyLimits;
        using negaflow::pipeline::develop_export_detail::decoded_source_budget_bytes;
        using negaflow::pipeline::develop_export_detail::preview_proxy_budget_bytes;
        using negaflow::pipeline::frame_cache_residency_limits;
        using negaflow::pipeline::set_frame_cache_residency_limits;

        constexpr double megabyte = 1024.0 * 1024.0;
        const std::uint64_t automatic_decoded = decoded_source_budget_bytes();
        const std::uint64_t automatic_proxy = preview_proxy_budget_bytes();

        set_frame_cache_residency_limits(FrameCacheResidencyLimits{4U, 8U});
        expect(
            frame_cache_residency_limits().cleaned_raw_frames == 4U &&
                frame_cache_residency_limits().developed_frames == 8U,
            "engine remembers the residency limits the settings pane picked");
        expect(
            decoded_source_budget_bytes() ==
                static_cast<std::uint64_t>(4.0 * 190.0 * megabyte),
            "cleaned raw budget follows the chosen frame count");
        expect(
            preview_proxy_budget_bytes() ==
                static_cast<std::uint64_t>(8.0 * 170.0 * (16.0 / 20.0) * megabyte),
            "preview proxy budget follows the chosen frame count");

        // 같은 상한을 절반으로 내리면 예산도 절반이어야 합니다 — 상한이 이름뿐이 아니라는 것.
        set_frame_cache_residency_limits(FrameCacheResidencyLimits{2U, 4U});
        expect(
            decoded_source_budget_bytes() ==
                static_cast<std::uint64_t>(2.0 * 190.0 * megabyte),
            "lowering the cleaned raw limit lowers the budget");
        expect(
            preview_proxy_budget_bytes() ==
                static_cast<std::uint64_t>(4.0 * 170.0 * (16.0 / 20.0) * megabyte),
            "lowering the developed limit lowers the budget");

        // 0/0 은 자동으로 되돌아갑니다 — 셸이 붙기 전과 CLI 가 그 자리에 있습니다.
        set_frame_cache_residency_limits(FrameCacheResidencyLimits{});
        expect(
            decoded_source_budget_bytes() == automatic_decoded &&
                preview_proxy_budget_bytes() == automatic_proxy,
            "clearing the limits returns both caches to the automatic budget");
    }

    // 인자를 주면 그 실제 스캔 두 장으로 잽니다. 합성 TIFF 는 값의 조건만 고정할 뿐,
    // "슬라이더 한 칸이 몇 ms 냐" 는 원본 해상도에서만 뜻이 있습니다.
    std::filesystem::path develop_source =
        std::filesystem::temp_directory_path() / L"negaflow-raw-store-develop.tiff";
    std::filesystem::path other_source =
        std::filesystem::temp_directory_path() / L"negaflow-raw-store-other.tiff";
    bool wrote_temp = false;
    if (argc >= 3) {
        develop_source = std::filesystem::path{argv[1]};
        other_source = std::filesystem::path{argv[2]};
        expect(std::filesystem::exists(develop_source), "develop source exists");
        expect(std::filesystem::exists(other_source), "other source exists");
    } else {
        expect(write_source(develop_source, 1600U, 1200U), "wrote develop source tiff");
        expect(write_source(other_source, 800U, 600U), "wrote other source tiff");
        wrote_temp = true;
    }
    if (failures != 0) {
        return 1;
    }

    const negaflow::pipeline::DevelopExportRequest develop = request_for(develop_source);
    const negaflow::pipeline::DevelopExportRequest other = request_for(other_source);
    std::vector<std::uint8_t> pixels{};
    negaflow::pipeline::develop_export_detail::preview_raw_store_reset();
    negaflow::pipeline::develop_export_detail::decoded_source_store_reset();

    // ① 썸네일이 현상 프레임의 프록시를 밀어내지 않는다.
    //    앞 판은 전역 슬롯 하나라, 사이에 낀 360 렌더가 1280 슬롯을 덮어써 세 번째가
    //    원본을 다시 디코드했습니다. 그것이 "슬라이더 한 칸마다 수 초" 의 정체입니다.
    negaflow::pipeline::reset_stage_timings();
    const auto cold_started = std::chrono::steady_clock::now();
    expect(preview_at(develop, 1280U, pixels).succeeded, "develop preview at 1280 succeeds");
    // 이 콜드 비용이 곧 **고치기 전의 슬라이더 한 칸 비용**입니다. 앞 판은 전역 슬롯이
    // 하나라 사이에 낀 썸네일 렌더가 매번 그것을 밀어냈고, 그래서 모든 칸이 이 길을
    // 처음부터 다시 갔습니다 — 디코드 + 원본 해상도 베이스 해석 + Lanczos.
    const auto cold_us = std::chrono::duration_cast<std::chrono::microseconds>(
                             std::chrono::steady_clock::now() - cold_started)
                             .count();
    expect(decode_runs() >= 1U, "first develop preview decodes");

    negaflow::pipeline::reset_stage_timings();
    expect(
        preview_at(other, 360U, pixels).succeeded,
        "thumbnail-sized preview of another frame succeeds");
    expect(decode_runs() >= 1U, "another frame decodes its own source");

    // 디코드 상주를 비워야 "프록시가 남았는가"를 디코드 캐시와 섞지 않고 잴 수 있습니다.
    // 프록시가 썸네일에 밀렸다면 아래 반복은 다시 디코드합니다.
    negaflow::pipeline::develop_export_detail::decoded_source_store_reset();
    negaflow::pipeline::reset_stage_timings();
    const auto repeat_started = std::chrono::steady_clock::now();
    expect(preview_at(develop, 1280U, pixels).succeeded, "develop preview at 1280 repeats");
    const auto repeat_us = std::chrono::duration_cast<std::chrono::microseconds>(
                               std::chrono::steady_clock::now() - repeat_started)
                               .count();
    expect(
        decode_runs() == 0U,
        "a thumbnail render of another frame does not evict the develop proxy");

    // ② 정착본이 있으면 인터랙티브 상자는 디코드하지 않고 Lanczos 로 파생한다.
    //    macOS `makeSnapshot` 의 `preloadedFullPreviewRaw` 자리.
    negaflow::pipeline::reset_stage_timings();
    const auto settled = preview_at(develop, settled_box, pixels);
    expect(settled.succeeded, "settled preview succeeds");

    negaflow::pipeline::develop_export_detail::decoded_source_store_reset();
    negaflow::pipeline::reset_stage_timings();
    const auto derived = preview_at(develop, 1024U, pixels);
    expect(derived.succeeded, "interactive preview at a new box succeeds");
    expect(
        decode_runs() == 0U,
        "a new interactive box derives from the settled raw instead of decoding");
    expect(
        derived.image_width <= 1024U && derived.image_height <= 1024U,
        "derived interactive preview fits its box");

    // ③ Defects raw proxy는 ordered recipe SHA-256이 같을 때만 재사용합니다. v34 이하처럼
    //    identity가 없으면 캐시를 막고, 다른 recipe가 같은 프레임 화소를 받지 않습니다.
    negaflow::pipeline::DevelopExportRequest recipe = develop;
    negaflow::pipeline::DefectBrushEdit disabled_brush{};
    disabled_brush.enabled = false;
    recipe.defect_recipe.brushes.push_back(disabled_brush);
    recipe.defect_recipe.order.push_back(
        {negaflow::pipeline::DefectRecipeEditKind::brush, 0U});
    std::array<std::uint8_t, 32U> recipe_one{};
    recipe_one.fill(0x11U);
    recipe.defect_recipe_sha256 = recipe_one;

    negaflow::pipeline::develop_export_detail::preview_raw_store_reset();
    negaflow::pipeline::develop_export_detail::decoded_source_store_reset();
    expect(preview_at(recipe, 1280U, pixels).succeeded, "recipe preview succeeds");
    negaflow::pipeline::develop_export_detail::decoded_source_store_reset();
    negaflow::pipeline::reset_stage_timings();
    expect(preview_at(recipe, 1280U, pixels).succeeded, "same recipe preview repeats");
    expect(decode_runs() == 0U, "same recipe identity reuses its raw proxy");

    std::array<std::uint8_t, 32U> recipe_two{};
    recipe_two.fill(0x22U);
    recipe.defect_recipe_sha256 = recipe_two;
    negaflow::pipeline::develop_export_detail::decoded_source_store_reset();
    negaflow::pipeline::reset_stage_timings();
    expect(preview_at(recipe, 1280U, pixels).succeeded, "changed recipe preview succeeds");
    expect(decode_runs() >= 1U, "changed recipe identity cannot reuse the old raw proxy");

    // ④ Brush/Clone도 macOS처럼 full-resolution cleaned raw에서 먼저 적용합니다. 첫
    // interactive가 만든 같은 recipe raw는 settled가 공유하며, cache 유무가 출력은 바꾸지 않습니다.
    negaflow::pipeline::DevelopExportRequest clone_recipe = develop;
    clone_recipe.defect_recipe.clone_points_storage.push_back({0.45, 0.50});
    negaflow::imaging::DefectCloneStroke clone_stroke{};
    clone_stroke.points = clone_recipe.defect_recipe.clone_points_storage;
    clone_stroke.offset_x = 0.08;
    clone_stroke.offset_y = -0.04;
    clone_stroke.diameter_pixels = 32.0;
    clone_stroke.hardness = 0.7;
    clone_recipe.defect_recipe.clone_strokes_storage.push_back(clone_stroke);
    negaflow::pipeline::DefectCloneEdit clone_edit{};
    clone_edit.parameters.strokes = clone_recipe.defect_recipe.clone_strokes_storage;
    clone_recipe.defect_recipe.clones.push_back(clone_edit);
    clone_recipe.defect_recipe.order.push_back(
        {negaflow::pipeline::DefectRecipeEditKind::clone, 0U});
    std::array<std::uint8_t, 32U> clone_sha{};
    clone_sha.fill(0x33U);
    clone_recipe.defect_recipe_sha256 = clone_sha;

    negaflow::pipeline::develop_export_detail::preview_raw_store_reset();
    negaflow::pipeline::develop_export_detail::decoded_source_store_reset();
    std::vector<std::uint8_t> clone_interactive{};
    expect(
        preview_at(clone_recipe, 1280U, clone_interactive).succeeded,
        "clone interactive preview succeeds");
    const std::uint64_t full_source_bytes =
        2ULL * 1600ULL * 1200ULL * sizeof(negaflow::core::Rgba32F);
    expect(
        negaflow::pipeline::develop_export_detail::decoded_source_store_resident_bytes() >=
            full_source_bytes,
        "clone preview retains full-resolution source and cleaned raw");

    negaflow::pipeline::develop_export_detail::preview_raw_store_reset();
    negaflow::pipeline::reset_stage_timings();
    std::vector<std::uint8_t> cached_settled{};
    expect(
        preview_at(clone_recipe, settled_box, cached_settled).succeeded,
        "clone settled preview reuses cleaned raw");
    expect(decode_runs() == 0U, "cleaned raw reuse skips decode");
    expect(
        stage_runs(negaflow::pipeline::DevelopExportStage::defect_component_repair) == 0U,
        "cleaned raw reuse skips ordered defect repair");

    negaflow::pipeline::develop_export_detail::preview_raw_store_reset();
    negaflow::pipeline::develop_export_detail::decoded_source_store_reset();
    std::vector<std::uint8_t> uncached_settled{};
    expect(
        preview_at(clone_recipe, settled_box, uncached_settled).succeeded,
        "uncached clone settled preview succeeds");
    expect(
        cached_settled == uncached_settled,
        "cleaned raw cache preserves exact settled output");

    // ⑤ 새 revision은 마지막 cached recipe를 접두라고 추정하지 않습니다. 명시 SHA가
    //    정확히 맞는 append만 첫 layer를 건너뛰며, source부터 두 layer를 적용한 출력과 같습니다.
    negaflow::pipeline::DevelopExportRequest prefix_recipe =
        clone_request_for(develop, 1U, 0x41U);
    negaflow::pipeline::develop_export_detail::preview_raw_store_reset();
    negaflow::pipeline::develop_export_detail::decoded_source_store_reset();
    expect(preview_at(prefix_recipe, 1280U, pixels).succeeded,
           "append prefix preview succeeds");

    negaflow::pipeline::DevelopExportRequest appended_recipe =
        clone_request_for(develop, 2U, 0x42U);
    appended_recipe.defect_recipe_append_prefix_sha256 =
        prefix_recipe.defect_recipe_sha256;
    appended_recipe.defect_recipe_append_prefix_edit_count = 1U;
    negaflow::pipeline::develop_export_detail::preview_raw_store_reset();
    negaflow::pipeline::reset_stage_timings();
    std::vector<std::uint8_t> appended_cached{};
    expect(preview_at(appended_recipe, 1280U, appended_cached).succeeded,
           "explicit append prefix preview succeeds");
    expect(decode_runs() == 0U, "explicit append prefix skips source decode");
    expect(stage_runs(negaflow::pipeline::DevelopExportStage::defect_component_repair) == 1U,
           "explicit append prefix applies only the new suffix stage");

    negaflow::pipeline::develop_export_detail::preview_raw_store_reset();
    negaflow::pipeline::develop_export_detail::decoded_source_store_reset();
    std::vector<std::uint8_t> appended_full{};
    expect(preview_at(clone_request_for(develop, 2U, 0x42U), 1280U, appended_full).succeeded,
           "full two-edit preview succeeds");
    expect(appended_cached == appended_full,
           "append-prefix reuse is byte-exact with a full ordered rebuild");

    negaflow::pipeline::develop_export_detail::preview_raw_store_reset();
    negaflow::pipeline::develop_export_detail::decoded_source_store_reset();
    expect(preview_at(prefix_recipe, 1280U, pixels).succeeded,
           "prefix is retained again for mismatch test");
    auto mismatched_prefix = clone_request_for(develop, 2U, 0x42U);
    std::array<std::uint8_t, 32U> wrong_prefix{};
    wrong_prefix.fill(0x99U);
    mismatched_prefix.defect_recipe_append_prefix_sha256 = wrong_prefix;
    mismatched_prefix.defect_recipe_append_prefix_edit_count = 1U;
    negaflow::pipeline::develop_export_detail::preview_raw_store_reset();
    negaflow::pipeline::reset_stage_timings();
    std::vector<std::uint8_t> mismatch_output{};
    expect(preview_at(mismatched_prefix, 1280U, mismatch_output).succeeded,
           "mismatched prefix falls back to a full rebuild");
    expect(decode_runs() >= 1U, "mismatched prefix does not reuse cleaned raw");
    expect(mismatch_output == appended_full,
           "mismatched prefix fallback preserves exact output");

    // ⑥ 먼 프레임의 persistent disk 채움은 최종 BGRA만 쓰고 native Rgba32F raw를
    //    카탈로그 전체에 중복 상주시지 않습니다.
    negaflow::pipeline::DevelopExportRequest background = other;
    background.retain_preview_raw = false;
    negaflow::pipeline::develop_export_detail::preview_raw_store_reset();
    expect(preview_at(background, 1280U, pixels).succeeded, "background preview succeeds");
    expect(
        negaflow::pipeline::develop_export_detail::preview_raw_store_resident_bytes() == 0ULL,
        "background preview does not retain a raw proxy");

    // ⑦ 같은 캐시를 여러 스레드가 동시에 두드려도 죽지 않는다.
    //    앱에서 겹치는 자리 그대로입니다 — 현상 프리뷰(큰 상자) + 썸네일 3개(360).
    std::atomic<int> concurrent_failures{0};
    std::vector<std::thread> workers{};
    const std::uint32_t boxes[] = {1280U, 360U, 512U, settled_box};
    for (std::uint32_t index = 0U; index < 4U; ++index) {
        workers.emplace_back([&, index]() {
            std::vector<std::uint8_t> local{};
            for (int round = 0; round < 6; ++round) {
                const negaflow::pipeline::DevelopExportRequest& target =
                    (index % 2U) == 0U ? develop : other;
                if (!preview_at(target, boxes[index], local).succeeded) {
                    concurrent_failures.fetch_add(1, std::memory_order_relaxed);
                }
            }
        });
    }
    for (std::thread& worker : workers) {
        worker.join();
    }
    expect(
        concurrent_failures.load(std::memory_order_relaxed) == 0,
        "concurrent previews across frames and boxes all succeed");

    std::error_code ignored{};
    if (wrote_temp) { std::filesystem::remove(develop_source, ignored); }
    if (wrote_temp) { std::filesystem::remove(other_source, ignored); }

    std::cout << "preview_raw_store cold_us=" << cold_us
              << " cached_us=" << repeat_us
              << " settled=" << settled.image_width << "x" << settled.image_height
              << " derived=" << derived.image_width << "x" << derived.image_height
              << '\n';
    return failures == 0 ? 0 : 1;
}
