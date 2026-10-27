// 자동 밸런스를 켠 프리뷰가 같은 프록시에서 장면 측정을 다시 하지 않는지 확인합니다.
//
// 슬라이더를 한 번 밀 때마다(그리고 자동 밸런스를 껐다 켤 때마다) 장면 밀도 범위와 평균 채도를
// 다시 쟀고, 그것이 3600 × 2400 프록시에서 프리뷰 한 장당 약 30 ms 였습니다. 측정은 같은
// 프록시·베이스·크롭이면 결정적이라, 같은 프록시를 쥔 캐시 항목이 메모를 함께 들고 있으면 두 번째
// 요청부터 건너뛸 수 있습니다. 이 시험은 **건너뛰어도 화소가 같다**는 것과 **입력이 바뀌면 다시
// 잰다**는 것을 고정합니다.

#include "negaflow/pipeline/develop_export.h"
#include "export/support/scene_measurement_memo.h"
#include "synthetic_wic_tiff.h"

#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

struct Counts {
    std::uint64_t range_hits;
    std::uint64_t range_misses;
    std::uint64_t saturation_hits;
    std::uint64_t saturation_misses;
};

[[nodiscard]] Counts counts() {
    const auto& c = negaflow::pipeline::develop_export_detail::scene_measurement_memo_counters();
    return {c.range_hits.load(), c.range_misses.load(), c.saturation_hits.load(),
            c.saturation_misses.load()};
}

}  // namespace

int main() {
    const std::filesystem::path source =
        std::filesystem::temp_directory_path() / L"negaflow-scene-measurement-memo.tiff";
    {
        const std::vector<std::uint8_t> tiff =
            negaflow::test_fixtures::make_uncompressed_rgb16_defect_tiff(640U, 480U);
        std::ofstream out(source, std::ios::binary | std::ios::trunc);
        out.write(reinterpret_cast<const char*>(tiff.data()), static_cast<std::streamsize>(tiff.size()));
        expect(out.good(), "wrote the synthetic source");
    }

    negaflow::pipeline::DevelopExportRequest request{};
    request.source = source;
    request.film_polarity = negaflow::pipeline::FilmPolarity::negative;
    request.base_estimation_mode = negaflow::pipeline::NegativeBaseEstimationMode::manual;
    request.negative.dmin = {0.18F, 0.11F, 0.08F};
    request.auto_balance = true;

    constexpr std::uint32_t box = 160U;
    const auto preview = [&](const negaflow::pipeline::DevelopExportRequest& r) {
        std::vector<std::uint8_t> pixels(static_cast<std::size_t>(box) * box * 4U, 0U);
        const auto outcome = negaflow::pipeline::develop_preview(r, box, box, pixels.data(), pixels.size());
        expect(outcome.succeeded, "preview succeeds");
        return pixels;
    };

    const Counts start = counts();
    const auto first = preview(request);
    const Counts after_first = counts();
    expect(after_first.range_misses == start.range_misses + 1U &&
               after_first.range_hits == start.range_hits,
        "the first ON preview measures the scene range");

    const auto second = preview(request);
    const Counts after_second = counts();
    expect(after_second.range_hits == after_first.range_hits + 1U &&
               after_second.range_misses == after_first.range_misses,
        "the second ON preview reuses the scene range");
    expect(after_second.saturation_hits == after_first.saturation_hits + 1U,
        "the second ON preview reuses the mean saturation");
    expect(first == second, "reusing the measurements leaves the preview pixels unchanged");

    // 톤 슬라이더는 측정 입력이 아니다 — 그래도 재사용하고 화소만 바뀐다.
    auto toned = request;
    toned.tone.exposure_stops = 0.4F;
    const auto third = preview(toned);
    const Counts after_third = counts();
    expect(after_third.range_hits == after_second.range_hits + 1U &&
               after_third.range_misses == after_second.range_misses,
        "an exposure change does not re-measure the scene");
    expect(third != first, "the exposure change still reaches the pixels");

    // 자동 밸런스를 끄면 측정 자체가 없다. 다시 켜면 아직 메모에 있다.
    auto off = request;
    off.auto_balance = false;
    const auto off_pixels = preview(off);
    const Counts after_off = counts();
    expect(after_off.range_hits == after_third.range_hits &&
               after_off.range_misses == after_third.range_misses,
        "OFF does not look at the measurements");
    expect(off_pixels != first, "OFF renders differently from ON");
    const auto back_on = preview(request);
    const Counts after_back = counts();
    expect(after_back.range_hits == after_off.range_hits + 1U, "switching back to ON reuses the range");
    expect(back_on == first, "ON after OFF reproduces the first ON preview");

    // 베이스가 바뀌면 다시 잰다(키에 dmin 이 있다).
    auto other_base = request;
    other_base.negative.dmin = {0.20F, 0.11F, 0.08F};
    (void)preview(other_base);
    const Counts after_base = counts();
    expect(after_base.range_misses == after_back.range_misses + 1U,
        "a different base measures again");

    std::error_code ignored;
    std::filesystem::remove(source, ignored);
    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"preview_scene_measurement_memo\",\"failures\":" << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
