// 자동 레벨을 켠 채 프리뷰를 겹쳐 돌리는 시험입니다.
//
// 사용자가 앱에서 **자동 레벨 단추를 여러 번 누르면 앱이 강제 종료**된다고 보고했고,
// 이벤트 로그에 `Negaflow.Native.dll` 안의 액세스 위반(0xc0000005 @ +0x1546cb)이
// 남았습니다(2026-08-20). 자동 레벨은 `stages/grade.cpp` 의 장면 보정 갈래를 켜고,
// 그 갈래는 화소를 만지기 전에 `GpuAccelerator::flush_resident()` 를 부릅니다.
// 상주 프레임은 **남의 소유 버퍼를 가리키는 생포인터**라, 겹친 렌더가 그 버퍼를
// 놓아 버리면 다운로드가 죽은 메모리에 씁니다.
//
// 이 시험은 그 자리를 앱과 같은 모양으로 두드립니다: 현상 프리뷰(큰 상자)와 썸네일
// 크기 렌더를 여러 스레드에서 자동 레벨을 켜고 끄며 반복합니다.

#include "negaflow/pipeline/develop_export.h"
#include "synthetic_wic_tiff.h"

#include <atomic>
#include <cstdint>
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
    const std::filesystem::path& source,
    const bool auto_levels,
    const bool auto_neutral_balance) {
    negaflow::pipeline::DevelopExportRequest request{};
    request.source = source;
    request.film_polarity = negaflow::pipeline::FilmPolarity::negative;
    request.base_estimation_mode = negaflow::pipeline::NegativeBaseEstimationMode::manual;
    request.negative.dmin = {0.18F, 0.11F, 0.08F};
    request.tone.exposure_stops = 0.25F;
    request.scene_correction.auto_levels = auto_levels;
    request.scene_correction.auto_neutral_balance = auto_neutral_balance;
    return request;
}

[[nodiscard]] bool preview_at(
    const negaflow::pipeline::DevelopExportRequest& request,
    const std::uint32_t box,
    std::vector<std::uint8_t>& pixels) {
    pixels.assign(static_cast<std::size_t>(box) * box * 4U, 0U);
    return negaflow::pipeline::develop_preview(
               request, box, box, pixels.data(), pixels.size())
        .succeeded;
}

}  // namespace

int main() {
    const std::filesystem::path source =
        std::filesystem::temp_directory_path() / "negaflow_auto_levels_stress.tiff";
    if (!write_source(source, 512U, 384U)) {
        std::cerr << "FAIL: could not write the test source\n";
        return 1;
    }

    // ① 한 스레드에서 자동 레벨을 켜고 끄기를 반복해도 살아 있어야 합니다.
    //    사용자가 단추를 여러 번 누른 것과 같은 자리입니다.
    {
        std::vector<std::uint8_t> pixels{};
        bool ok = true;
        for (int round = 0; round < 12; ++round) {
            const bool on = (round % 2) == 0;
            ok = preview_at(request_for(source, on, on), 512U, pixels) && ok;
        }
        expect(ok, "toggling auto levels repeatedly keeps rendering");
    }

    // ② 앱과 같은 겹침: 현상 프리뷰(큰 상자) + 썸네일 셋이 자동 레벨을 켠 채 동시에.
    {
        std::atomic<int> render_failures{0};
        std::vector<std::thread> workers{};
        const std::uint32_t boxes[] = {512U, 360U, 360U, 360U};
        for (std::uint32_t index = 0U; index < 4U; ++index) {
            workers.emplace_back([&, index]() {
                std::vector<std::uint8_t> local{};
                for (int round = 0; round < 8; ++round) {
                    const bool on = ((round + static_cast<int>(index)) % 2) == 0;
                    if (!preview_at(request_for(source, on, on), boxes[index], local)) {
                        render_failures.fetch_add(1, std::memory_order_relaxed);
                    }
                }
            });
        }
        for (std::thread& worker : workers) {
            worker.join();
        }
        expect(
            render_failures.load(std::memory_order_relaxed) == 0,
            "concurrent auto-levels previews all succeed");
    }

    std::error_code ignored{};
    std::filesystem::remove(source, ignored);
    std::cout << "preview_auto_levels_stress done\n";
    return failures == 0 ? 0 : 1;
}
