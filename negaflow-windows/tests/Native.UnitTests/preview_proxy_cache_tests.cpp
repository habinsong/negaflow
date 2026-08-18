#include "negaflow/pipeline/develop_export.h"
#include "negaflow/pipeline/stage_timing.h"
#include "synthetic_wic_tiff.h"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdlib>
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

[[nodiscard]] std::uint64_t fingerprint(const std::vector<std::uint8_t>& bytes) noexcept {
    std::uint64_t hash = 1469598103934665603ULL;
    for (const std::uint8_t byte : bytes) {
        hash ^= static_cast<std::uint64_t>(byte);
        hash *= 1099511628211ULL;
    }
    return hash;
}

[[nodiscard]] std::uint64_t stage_us(const negaflow::pipeline::DevelopExportStage stage) {
    const auto timings = negaflow::pipeline::stage_timings();
    return timings.slots[static_cast<std::size_t>(stage)].elapsed_microseconds;
}

[[nodiscard]] std::uint32_t stage_runs(const negaflow::pipeline::DevelopExportStage stage) {
    const auto timings = negaflow::pipeline::stage_timings();
    return timings.slots[static_cast<std::size_t>(stage)].runs;
}

}  // namespace

int main(int argc, char** argv) {
    (void)_putenv_s("NEGA_TIMING", "1");

    std::uint32_t source_width = 640U;
    std::uint32_t source_height = 480U;
    std::uint32_t preview_box = 160U;
    std::filesystem::path source =
        std::filesystem::temp_directory_path() / L"negaflow-preview-proxy-cache.tiff";
    bool wrote_temp = false;
    if (argc >= 2) {
        source = std::filesystem::path{argv[1]};
        if (argc >= 3) {
            preview_box = static_cast<std::uint32_t>(std::max(1, std::atoi(argv[2])));
        }
        if (!std::filesystem::exists(source)) {
            std::cerr << "FAIL: source does not exist\n";
            return 1;
        }
    } else {

    const std::vector<std::uint8_t> tiff =
        negaflow::test_fixtures::make_uncompressed_rgb16_defect_tiff(
            source_width,
            source_height);
    expect(!tiff.empty(), "synthetic source tiff is not empty");
    if (tiff.empty()) {
        return 1;
    }
    {
        std::ofstream out(source, std::ios::binary | std::ios::trunc);
        out.write(reinterpret_cast<const char*>(tiff.data()), static_cast<std::streamsize>(tiff.size()));
        expect(out.good(), "wrote synthetic source tiff");
    }
    wrote_temp = true;
    }

    negaflow::pipeline::DevelopExportRequest request{};
    request.source = source;
    request.film_polarity = negaflow::pipeline::FilmPolarity::negative;
    request.base_estimation_mode = negaflow::pipeline::NegativeBaseEstimationMode::manual;
    request.negative.dmin = {0.18F, 0.11F, 0.08F};
    request.tone.exposure_stops = 0.25F;

    std::vector<std::uint8_t> first_pixels(
        static_cast<std::size_t>(preview_box) * preview_box * 4U, 0U);
    std::vector<std::uint8_t> second_pixels = first_pixels;
    std::vector<std::uint8_t> third_pixels = first_pixels;

    negaflow::pipeline::reset_stage_timings();
    const auto first_started = std::chrono::steady_clock::now();
    const auto first = negaflow::pipeline::develop_preview(
        request,
        preview_box,
        preview_box,
        first_pixels.data(),
        first_pixels.size());
    const auto first_wall = std::chrono::duration_cast<std::chrono::microseconds>(
                                std::chrono::steady_clock::now() - first_started)
                                .count();
    expect(first.succeeded, "first preview succeeds");
    expect(first.image_width <= preview_box && first.image_height <= preview_box,
        "first preview fits the box");
    expect(
        stage_runs(negaflow::pipeline::DevelopExportStage::decode) >= 1U,
        "first preview decodes the source");
    const std::uint64_t first_decode_us =
        stage_us(negaflow::pipeline::DevelopExportStage::decode);
    const std::uint64_t first_fingerprint = fingerprint(first_pixels);

    negaflow::pipeline::reset_stage_timings();
    const auto second_started = std::chrono::steady_clock::now();
    const auto second = negaflow::pipeline::develop_preview(
        request,
        preview_box,
        preview_box,
        second_pixels.data(),
        second_pixels.size());
    const auto second_wall = std::chrono::duration_cast<std::chrono::microseconds>(
                                 std::chrono::steady_clock::now() - second_started)
                                 .count();
    expect(second.succeeded, "second preview succeeds");
    expect(
        second.image_width == first.image_width &&
            second.image_height == first.image_height,
        "second preview keeps the same geometry");
    const std::uint32_t second_decode_runs =
        stage_runs(negaflow::pipeline::DevelopExportStage::decode);
    const std::uint32_t second_develop_runs =
        stage_runs(negaflow::pipeline::DevelopExportStage::develop);
    expect(second_decode_runs == 0U, "second preview does not decode the source again");
    expect(
        fingerprint(second_pixels) == first_fingerprint,
        "same request reproduces the preview pixels");
    expect(second_develop_runs >= 1U, "second preview still runs develop on the proxy");

    request.tone.exposure_stops = 0.80F;
    negaflow::pipeline::reset_stage_timings();
    const auto third = negaflow::pipeline::develop_preview(
        request,
        preview_box,
        preview_box,
        third_pixels.data(),
        third_pixels.size());
    expect(third.succeeded, "exposure change preview succeeds");
    expect(
        stage_runs(negaflow::pipeline::DevelopExportStage::decode) == 0U,
        "slider-like exposure change does not re-decode");
    expect(
        fingerprint(third_pixels) != first_fingerprint,
        "exposure change actually changes preview pixels");

    request.tone.exposure_stops = 0.25F;
    request.destination =
        std::filesystem::temp_directory_path() / L"negaflow-preview-proxy-cache-export.png";
    std::error_code ignored{};
    std::filesystem::remove(request.destination, ignored);
    const auto exported = negaflow::pipeline::develop_and_export(request);
    expect(exported.succeeded, "export after preview cache still succeeds");
    if (wrote_temp) {
        expect(
            exported.image_width == source_width && exported.image_height == source_height,
            "export stays at source resolution");
    } else {
        expect(
            exported.image_width > first.image_width &&
                exported.image_height > first.image_height,
            "export stays larger than the preview proxy");
    }
    std::filesystem::remove(request.destination, ignored);
    if (wrote_temp) {
        std::filesystem::remove(source, ignored);
    }

    std::cout << "preview_proxy first_wall_us=" << first_wall
              << " first_decode_us=" << first_decode_us
              << " second_wall_us=" << second_wall
              << " second_decode_runs=" << second_decode_runs
              << " preview=" << first.image_width << "x" << first.image_height
              << " export=" << exported.image_width << "x" << exported.image_height
              << '\n';
    return failures == 0 ? 0 : 1;
}
