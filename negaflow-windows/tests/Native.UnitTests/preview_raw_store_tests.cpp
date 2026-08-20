// 프리뷰 raw 프록시 상주 캐시의 시험입니다.
//
// 여기 있는 세 가지는 전부 **실제로 났던 고장**을 고정한 것입니다.
//   ① 썸네일(작은 상자, 다른 프레임) 렌더가 현상 중인 프레임의 프록시를 밀어냈습니다 —
//      프로세스 전역 슬롯이 하나뿐이라, 슬라이더 한 칸마다 원본을 다시 디코드했습니다.
//   ② 정착본이 있는데도 인터랙티브 상자가 디코드로 내려갔습니다. macOS
//      `DevelopFrameRenderer+Input.swift:51-52` 는 정착 raw 에서 Lanczos 로 파생합니다.
//   ③ 그 전역에 잠금이 없어 스레드가 겹치면 use-after-free 가 났습니다
//      (이벤트 로그 0xc0000374 힙 손상 · 0xc0000409 abort).

#include "negaflow/pipeline/develop_export.h"
#include "negaflow/pipeline/stage_timing.h"
#include "export/stages/decode.h"
#include "export/support/preview_raw_store.h"
#include "synthetic_wic_tiff.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <thread>
#include <vector>

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

    // ③ 같은 캐시를 여러 스레드가 동시에 두드려도 죽지 않는다.
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
