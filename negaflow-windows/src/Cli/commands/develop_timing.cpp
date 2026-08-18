#include "develop_timing.h"

#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "negaflow/imaging/area_average.h"
#include "negaflow/imaging/kernel_accelerator.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"
#include "negaflow/pipeline/develop_export.h"
#include "negaflow/pipeline/gpu_accelerator.h"
#include "negaflow/pipeline/stage_timing.h"

namespace negaflow::cli {
namespace {

// 프리뷰 한 장을 실제 파이프라인으로 뽑고 단계별 표를 찍습니다.
//
// 왜 프리뷰인가 — 사용자가 기다리는 경로가 그것이고, GPU 정책도 프리뷰·검출에서만
// 켜집니다(`gpu_accelerator.h`). 내보내기로 재면 GPU 가 안 도는 시간을 재게 됩니다.
//
// 왜 별도 명령인가 — `--develop-negative-tiff` 는 `imaging::` 을 직접 불러
// `run_develop` 을 지나지 않습니다. 그 경로로는 단계별 표가 나오지 않습니다.
// **재는 자리와 실제 도는 자리가 다르면 그 숫자는 거짓말입니다.**

// 프리뷰 화소의 지문입니다. **병렬화가 값을 바꾸지 않았다**를 증명할 때 씁니다 —
// 같은 입력에 대해 직렬 빌드와 병렬 빌드의 이 값이 같아야 합니다.
// FNV-1a 64비트. 암호용이 아니라 대조용입니다.
[[nodiscard]] std::uint64_t fingerprint(const std::vector<std::uint8_t>& bytes) noexcept {
    std::uint64_t hash = 1469598103934665603ULL;
    for (const std::uint8_t byte : bytes) {
        hash ^= static_cast<std::uint64_t>(byte);
        hash *= 1099511628211ULL;
    }
    return hash;
}

[[nodiscard]] bool parse_float(const std::wstring_view text, float& value) noexcept {
    try {
        const std::wstring copy{text};
        std::size_t consumed = 0U;
        value = std::stof(copy, &consumed);
        return consumed == copy.size();
    } catch (...) {
        return false;
    }
}

int usage() {
    std::cerr << "usage: negaflow-cli --develop-timing <source> "
                 "[<dmin-r> <dmin-g> <dmin-b>] [repeats] [nocurve] [filmlook]\n"
                 "  NEGA_GPU=0 으로 CPU 만, 기본은 GPU 허용입니다.\n"
                 "  filmlook — 디지털 원본 필름 룩(헐레이션·색 큐브·아큐턴스·색 "
                 "프리셋·그레인)까지 켭니다.\n"
                 "             필름 스캔 경로는 이 사슬을 지나지 않으므로, 그 다섯 "
                 "단계를 재려면 이것이 있어야 합니다.\n"
                 "  bwlook — 디지털 원본 흑백 룩(헐레이션·유제·아큐턴스·그레인)을 켭니다.\n"
                 "  grain — TextureStage filmGrain 을 0.40 으로 켭니다(기본 0 이면 단계가 비어 있음).\n"
                 "  areaavg — 디코드된 working 이미지에 CIAreaAverage 대응 면적 평균을 재어 stderr 에 찍습니다.\n"
                 "             GPU 면적평균은 기본 끔. NEGA_GPU_AREA_AVERAGE=1 로만 켭니다.\n";
    return 2;
}

}  // namespace

int run_develop_timing(const int argument_count, const wchar_t* const arguments[]) {
    if (argument_count < 3 || argument_count > 8) {
        return usage();
    }

    pipeline::DevelopExportRequest request{};
    request.source = std::filesystem::path{arguments[2]};
    request.film_polarity = pipeline::FilmPolarity::negative;
    request.base_estimation_mode = pipeline::NegativeBaseEstimationMode::auto_estimate;

    if (argument_count >= 6) {
        float red = 0.0F;
        float green = 0.0F;
        float blue = 0.0F;
        if (!parse_float(arguments[3], red) || !parse_float(arguments[4], green) ||
            !parse_float(arguments[5], blue)) {
            return usage();
        }
        request.base_estimation_mode = pipeline::NegativeBaseEstimationMode::manual;
        request.negative.dmin = {red, green, blue};
    }

    int repeats = 1;
    if (argument_count >= 7 && std::wstring_view{arguments[6]} != L"nocurve" &&
        std::wstring_view{arguments[6]} != L"filmlook" &&
        std::wstring_view{arguments[6]} != L"bwlook") {
        float parsed = 0.0F;
        if (!parse_float(arguments[6], parsed) || parsed < 1.0F || parsed > 20.0F) {
            return usage();
        }
        repeats = static_cast<int>(parsed);
    }
    // dmin 셋을 안 줄 때도 회차를 정할 수 있어야 합니다 — 자동 베이스로 재는 것이
    // 사용자가 실제로 쓰는 경로입니다. `xN` 은 자리와 무관하게 읽습니다.
    for (int index = 2; index < argument_count; ++index) {
        const std::wstring_view token{arguments[index]};
        if (token.size() >= 2U && token.front() == L'x') {
            float parsed = 0.0F;
            if (!parse_float(token.substr(1U), parsed) || parsed < 1.0F || parsed > 20.0F) {
                return usage();
            }
            repeats = static_cast<int>(parsed);
        }
    }

    // 슬라이더를 실제로 민 것과 같게 톤을 켭니다. 전부 0 이면 단계가 통째로 건너뛰어져
    // **아무것도 안 재게 됩니다.**
    request.tone.exposure_stops = 0.3F;
    request.tone.basic.contrast = 0.4F;
    request.tone.basic.shadows = 0.2F;
    request.tone.basic.highlights = -0.2F;

    // ☠️ 파라메트릭 커브는 **GPU 경로 한가운데서 한 번 내립니다.** 밴드 측정
    //    (`measure_parametric_tone_curve_bands`)이 전 화소를 CPU `double` 로 훑기 때문입니다.
    //    커브를 끄고 켜면서 재면 그 왕복 비용이 그대로 드러납니다 —
    //    마지막 인자에 `nocurve` 를 주면 끕니다.
    bool curve = true;
    for (int index = 2; index < argument_count; ++index) {
        if (std::wstring_view{arguments[index]} == L"nocurve") {
            curve = false;
        }
    }
    if (curve) {
        request.tone.curve.lights = 0.15F;
        request.tone.curve.darks = -0.15F;
    }

    // 스캐너 타겟 그레이드는 `develop_target` 이 main 이 아닐 때만 돕니다. 기본으로
    // 재면 그 단계가 **0.00 ms** 로 나오고, 그것을 "빠르다" 로 읽으면 틀립니다 —
    // 안 돈 것입니다. `noritsu` 는 그 위에 장치 질감(luminance USM)까지 얹습니다.
    for (int index = 2; index < argument_count; ++index) {
        const std::wstring_view token{arguments[index]};
        if (token == L"noritsu") {
            request.develop_target = pipeline::DevelopTarget::noritsu;
        } else if (token == L"sp3000") {
            request.develop_target = pipeline::DevelopTarget::sp3000;
        } else if (token == L"f135") {
            request.develop_target = pipeline::DevelopTarget::f135;
        } else if (token == L"hr") {
            request.develop_target = pipeline::DevelopTarget::hr;
        }
    }

    // ☠️ 디지털 필름 룩은 **필름 스캔 경로가 지나지 않습니다**(`working_film_look.cpp`).
    //    스캔본에는 이미 유제를 통과한 신호가 들어 있어 같은 물리를 두 번 얹지 않기
    //    때문입니다. 그래서 헐레이션·그레인을 재려면 원본 종류를 바꿔야 하고,
    //    그렇게 재야 **실제로 도는 자리**와 같은 것을 재는 것입니다.
    for (int index = 2; index < argument_count; ++index) {
        if (std::wstring_view{arguments[index]} == L"filmlook") {
            request.film_look.source_kind =
                negaflow::imaging::DevelopSourceKind::rendered_digital;
            request.film_look.emulation = negaflow::imaging::FilmEmulation::portra_400;
            request.film_look.intensity = 0.8;
            // 디지털 원본은 반전 단계를 지나지 않습니다 —
            // `validate.cpp:66` 이 네거티브 극성과 디지털 원본의 조합을 거부합니다.
            request.film_polarity = pipeline::FilmPolarity::positive;
            request.base_estimation_mode =
                pipeline::NegativeBaseEstimationMode::auto_estimate;
        }
        if (std::wstring_view{arguments[index]} == L"bwlook") {
            request.film_look.source_kind =
                negaflow::imaging::DevelopSourceKind::rendered_digital;
            request.film_look.emulation = negaflow::imaging::FilmEmulation::tri_x_400;
            request.film_look.intensity = 0.8;
            request.film_look.monochrome = true;
            request.negative.film_type =
                negaflow::imaging::NegativeFilmType::black_and_white;
            request.film_polarity = pipeline::FilmPolarity::positive;
            request.base_estimation_mode =
                pipeline::NegativeBaseEstimationMode::auto_estimate;
        }
        if (std::wstring_view{arguments[index]} == L"grain") {
            request.texture.grain = 0.40F;
        }
    }

    bool measure_area_average = false;
    for (int index = 2; index < argument_count; ++index) {
        if (std::wstring_view{arguments[index]} == L"areaavg") {
            measure_area_average = true;
        }
    }

    // macOS 정착 프리뷰와 같은 한 변입니다(`fullMaxDimension`).
    constexpr std::uint32_t preview_edge = 3600U;
    std::vector<std::uint8_t> pixels(
        static_cast<std::size_t>(preview_edge) * preview_edge * 4U);

    std::cout << "{\"schema_version\":1,\"operation\":\"develop_timing\",\"gpu\":\""
              << pipeline::GpuAccelerator::shared().adapter_description() << "\",\"runs\":[";

    for (int run = 0; run < repeats; ++run) {
        pipeline::reset_stage_timings();
        const auto started = std::chrono::steady_clock::now();
        const pipeline::DevelopExportOutcome outcome = pipeline::develop_preview(
            request, preview_edge, preview_edge, pixels.data(), pixels.size());
        const auto finished = std::chrono::steady_clock::now();
        const auto wall = std::chrono::duration_cast<std::chrono::microseconds>(
                              finished - started)
                              .count();
        if (run != 0) {
            std::cout << ',';
        }
        std::cout << "{\"succeeded\":" << (outcome.succeeded ? "true" : "false")
                  << ",\"wall_microseconds\":" << wall
                  << ",\"pixel_fingerprint\":\"" << std::hex << fingerprint(pixels)
                  << std::dec << "\"";
        if (!outcome.succeeded) {
            std::cout << ",\"failed_stage\":\""
                      << pipeline::develop_export_stage_name(outcome.failed_stage)
                      << "\",\"failure\":\"" << outcome.failure_name << '"';
        }
        std::cout << '}';
        // 마지막 회차의 표만 찍습니다 — 앞 회차는 캐시가 차는 중이라 대표값이 아닙니다.
        if (run + 1 == repeats) {
            std::cout << "]}\n";
            pipeline::dump_stage_timings();
            if (measure_area_average) {
                negaflow::imageio::WicTiffDecodeControl decode_control{};
                decode_control.rows_per_copy = 64U;
                auto prepared = negaflow::imaging::decode_scanner_tiff_to_working_rows(
                    request.source, {}, {}, decode_control);
                if (prepared.decode.status !=
                        negaflow::imageio::WicTiffDecodeStatus::ok ||
                    prepared.working.status !=
                        negaflow::imaging::ScannerToWorkingStatus::ok) {
                    std::cerr << "[timing] area_average decode_failed\n";
                    return 1;
                }
                pipeline::install_gpu_kernel_accelerator();
                std::optional<negaflow::imaging::ApproximateAcceleratorScope> scope{};
                if (pipeline::GpuAccelerator::shared().available()) {
                    scope.emplace();
                }
                negaflow::imaging::AreaAverage average{};
                const auto started_avg = std::chrono::steady_clock::now();
                const bool ok = negaflow::imaging::area_average(
                    prepared.working.image,
                    0U,
                    0U,
                    prepared.working.image.width,
                    prepared.working.image.height,
                    average);
                const auto finished_avg = std::chrono::steady_clock::now();
                const double milliseconds =
                    static_cast<double>(
                        std::chrono::duration_cast<std::chrono::microseconds>(
                            finished_avg - started_avg)
                            .count()) /
                    1000.0;
                std::cerr << "[timing] area_average ok=" << (ok ? "true" : "false")
                          << " count=" << average.count << " mean=" << average.red << ","
                          << average.green << "," << average.blue << " ms=" << milliseconds
                          << (scope.has_value() ? " path=gpu-allowed\n" : " path=cpu\n");
            }
            return outcome.succeeded ? 0 : 1;
        }
    }
    std::cout << "]}\n";
    return 0;
}

}  // namespace negaflow::cli
