#include "grain_mend_detect.h"

#include "negaflow/imaging/grain_mend.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"
#include "negaflow/pipeline/gpu_accelerator.h"

#include <array>
#include <charconv>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string_view>
#include <system_error>
#include <utility>

namespace negaflow::cli {
namespace {

[[nodiscard]] bool parse_finite_float(
    const std::wstring_view text,
    float& value) noexcept {
    if (text.empty() || text.size() > 63U) {
        return false;
    }
    std::array<char, 64> ascii{};
    for (std::size_t index = 0U; index < text.size(); ++index) {
        if (text[index] < 0 || text[index] > 127) {
            return false;
        }
        ascii[index] = static_cast<char>(text[index]);
    }
    const auto [end, error] = std::from_chars(
        ascii.data(),
        ascii.data() + text.size(),
        value,
        std::chars_format::general);
    return error == std::errc{} &&
           end == ascii.data() + text.size() && std::isfinite(value);
}

int print_error(const std::string_view code) {
    std::cerr << "{\"schema_version\":1,\"status\":\"error\",\"error\":{\"code\":\""
              << code << "\"}}\n";
    return 2;
}

constexpr std::wstring_view dump_prefix = L"dump=";

/// 성분 하나하나를 CSV 로 적습니다. 개수만 보면 "어디를" 골랐는지 알 수 없어서, 화면
/// 대조 없이도 영역별 밀도를 셀 수 있게 좌표를 남깁니다.
void write_component_dump(
    const std::filesystem::path& path,
    const negaflow::imaging::GrainMendDetection& detection) {
    std::ofstream file{path, std::ios::binary | std::ios::trunc};
    if (!file) {
        return;
    }
    file << "classification,centroid_x,centroid_y,minimum_x,minimum_y,"
            "maximum_x,maximum_y,area,confidence\n";
    for (const auto& component : detection.components) {
        std::size_t sum_x = 0U;
        std::size_t sum_y = 0U;
        for (const std::size_t pixel : component.pixels) {
            sum_x += pixel % detection.width;
            sum_y += pixel / detection.width;
        }
        const std::size_t area = std::max<std::size_t>(
            1U, component.pixels.size());
        file << static_cast<unsigned>(component.classification) << ','
             << (sum_x / area) << ',' << (sum_y / area) << ','
             << component.minimum_x << ',' << component.minimum_y << ','
             << component.maximum_x << ',' << component.maximum_y << ','
             << component.pixels.size() << ',' << component.confidence << '\n';
    }
}

}  // namespace

int run_grain_mend_detect(
    const int input_argument_count,
    const wchar_t* const arguments[]) {
    // 마지막 인자가 `dump=<경로>` 면 계측 출력이며 나머지 파싱에서 뺍니다.
    std::filesystem::path dump_path{};
    int argument_count = input_argument_count;
    if (argument_count >= 4) {
        const std::wstring_view last{arguments[argument_count - 1]};
        if (last.size() > dump_prefix.size() &&
            last.substr(0U, dump_prefix.size()) == dump_prefix) {
            dump_path = std::filesystem::path{last.substr(dump_prefix.size())};
            --argument_count;
        }
    }
    const bool use_auto_dmin = argument_count >= 4 &&
        std::wstring_view{arguments[3]} == L"auto";
    if (use_auto_dmin) {
        if (argument_count < 4 || argument_count > 6) {
            std::cerr << "usage: negaflow-cli --grain-mend-detect <source> "
                         "auto [sensitivity] [guided]\n";
            return 2;
        }
    } else if (argument_count < 6 || argument_count > 8) {
        std::cerr << "usage: negaflow-cli --grain-mend-detect <source> "
                     "<dmin-r> <dmin-g> <dmin-b> [sensitivity] [guided]\n"
                     "   or: negaflow-cli --grain-mend-detect <source> "
                     "auto [sensitivity] [guided]\n";
        return 2;
    }

    float sensitivity = 1.0F;
    bool guided = false;
    if (use_auto_dmin) {
        if (argument_count >= 5 &&
            !parse_finite_float(arguments[4], sensitivity)) {
            return print_error("invalid_sensitivity");
        }
        guided = argument_count >= 6 &&
            std::wstring_view{arguments[5]} == L"guided";
    } else {
        float ignored_dmin = 0.0F;
        if (!parse_finite_float(arguments[3], ignored_dmin) ||
            !parse_finite_float(arguments[4], ignored_dmin) ||
            !parse_finite_float(arguments[5], ignored_dmin)) {
            return print_error("invalid_dmin");
        }
        if (argument_count >= 7 &&
            !parse_finite_float(arguments[6], sensitivity)) {
            return print_error("invalid_sensitivity");
        }
        guided = argument_count >= 8 &&
            std::wstring_view{arguments[7]} == L"guided";
    }

    const auto decode_started = std::chrono::steady_clock::now();
    negaflow::imageio::WicTiffDecodeControl decode_control{};
    decode_control.rows_per_copy = 64U;
    auto prepared = negaflow::imaging::decode_scanner_tiff_to_working_rows(
        std::filesystem::path{arguments[2]}, {}, {}, decode_control);
    if (prepared.decode.status != negaflow::imageio::WicTiffDecodeStatus::ok ||
        prepared.working.status != negaflow::imaging::ScannerToWorkingStatus::ok) {
        return print_error("decode_failed");
    }
    // macOS `runRegionDetect` 는 현상(반전/톤/필름룩) 전 cleaned raw 에서 검출한다.
    // dmin 인자는 예전 계측기 호환용으로만 받고, 검출 입력에는 쓰지 않는다.
    const auto detect_started = std::chrono::steady_clock::now();

    negaflow::imaging::GrainMendParameters parameters{};
    parameters.strength = 1.0;
    parameters.dust_sensitivity = sensitivity;
    parameters.scratch_sensitivity = std::min(1.0, sensitivity + 0.1);
    parameters.protect_detail = 0.6;
    // 자동은 전역 계약(구조선 격자 배제)을 켭니다. 가이드는 사용자가 범위를 지목한 경로입니다.
    parameters.reject_structure_lines = !guided;
    parameters.detect_micro_specks = true;
    negaflow::imaging::GrainMendRoi roi{};
    if (guided) {
        roi.x = 0.25;
        roi.y = 0.25;
        roi.width = 0.5;
        roi.height = 0.5;
    }
    // 검출 안쪽의 형태학이 GPU 를 쓰게 표를 겁니다. 여러 번 불러도 한 번만 겁니다.
    // `NEGA_GPU=0` 이면 장치를 안 열므로 표도 안 걸리고 CPU 그대로 돕니다.
    negaflow::pipeline::install_gpu_kernel_accelerator();
    const negaflow::imaging::GrainMendDetection detection =
        negaflow::imaging::detect_grain_mend(
            prepared.working.image, parameters, roi);
    const auto finished = std::chrono::steady_clock::now();
    if (!dump_path.empty()) {
        write_component_dump(dump_path, detection);
    }

    const auto micros = [](const auto from, const auto to) {
        return static_cast<std::uint64_t>(
            std::chrono::duration_cast<std::chrono::microseconds>(to - from).count());
    };
    std::array<std::size_t, 7U> by_class{};
    double confidence_sum = 0.0;
    for (const auto& component : detection.components) {
        const auto index = static_cast<std::size_t>(component.classification);
        if (index < by_class.size()) {
            ++by_class[index];
        }
        confidence_sum += component.confidence;
    }
    std::cout << "{\"schema_version\":1,\"status\":\""
              << (detection.status == negaflow::imaging::GrainMendStatus::ok
                      ? "ok"
                      : "failed")
              << "\",\"operation\":\"grain_mend_detect\""
              << ",\"source_width\":" << prepared.working.image.width
              << ",\"source_height\":" << prepared.working.image.height
              << ",\"input_domain\":\"cleaned_raw\""
              << ",\"dmin_mode\":\"unused\""
              << ",\"detection_width\":" << detection.width
              << ",\"detection_height\":" << detection.height
              << ",\"accepted_pixels\":" << detection.accepted_pixels
              // macOS `applyingWholeFrameAutomaticRiskFlag` 의 결과입니다. 자동에서만
              // 채워지고, 성분을 버리지 않으므로 개수와 함께 읽어야 합니다.
              << ",\"automatic_false_positive_risk\":"
              << (detection.automatic_false_positive_risk ? "true" : "false")
              << ",\"automatic_candidate_pixel_fraction\":"
              << detection.automatic_candidate_pixel_fraction
              << ",\"component_count\":" << detection.components.size()
              << ",\"mean_confidence\":"
              << (detection.components.empty()
                      ? 0.0
                      : confidence_sum /
                            static_cast<double>(detection.components.size()))
              << ",\"by_class\":{\"dust\":" << by_class[0]
              << ",\"pinhole\":" << by_class[1]
              << ",\"scratch_horizontal\":" << by_class[2]
              << ",\"scratch_vertical\":" << by_class[3]
              << ",\"scratch_diagonal\":" << by_class[4]
              << ",\"emulsion\":" << by_class[5]
              << ",\"micro_speck\":" << by_class[6] << '}'
              << ",\"stages\":{\"decode_microseconds\":"
              << micros(decode_started, detect_started)
              << ",\"develop_microseconds\":0"
              << ",\"detect_microseconds\":" << micros(detect_started, finished)
              << ",\"tile_count\":" << detection.timings.tile_count
              << ",\"worker_count\":" << detection.timings.worker_count
              << ",\"detection_image_microseconds\":"
              << detection.timings.detection_image_microseconds
              << ",\"evidence_microseconds\":"
              << detection.timings.evidence_microseconds
              << ",\"speck_microseconds\":"
              << detection.timings.speck_microseconds
              << ",\"dust_morphology_microseconds\":"
              << detection.timings.dust_morphology_microseconds
              << ",\"scratch_angles_microseconds\":"
              << detection.timings.scratch_angles_microseconds
              << ",\"stitch_microseconds\":"
              << detection.timings.stitch_microseconds
              << ",\"components_microseconds\":"
              << detection.timings.components_microseconds
              << ",\"tiled_total_microseconds\":"
              << detection.timings.total_microseconds
              << ",\"dust_weak_pixels\":"
              << detection.timings.dust_weak_pixels
              << ",\"dust_raw_weak_pixels\":"
              << detection.timings.dust_raw_weak_pixels
              << ",\"dust_strong_pixels\":"
              << detection.timings.dust_strong_pixels
              << ",\"dust_components_raw\":"
              << detection.timings.dust_components_raw
              << ",\"dust_components_after_grain_field\":"
              << detection.timings.dust_components_after_grain_field
              << ",\"speck_mask_pixels\":"
              << detection.timings.speck_mask_pixels
              << ",\"speck_merged\":"
              << detection.timings.speck_merged
              << ",\"speck_skipped_overlap\":"
              << detection.timings.speck_skipped_overlap
              << ",\"dust_components_collected\":"
              << detection.timings.dust_components_collected
              << ",\"dust_dropped_no_strong\":"
              << detection.timings.dust_dropped_no_strong
              << ",\"dust_dropped_strong_fraction\":"
              << detection.timings.dust_dropped_strong_fraction
              << ",\"dust_dropped_gate\":"
              << detection.timings.dust_dropped_gate
              << ",\"dust_dropped_isolation\":"
              << detection.timings.dust_dropped_isolation
              << ",\"dust_kept\":"
              << detection.timings.dust_kept
              << ",\"dust_pixels_above_weak_abs\":"
              << detection.timings.dust_pixels_above_weak_abs
              << ",\"dust_pixels_above_abs\":"
              << detection.timings.dust_pixels_above_abs
              << ",\"valid_pixels\":"
              << detection.timings.valid_pixels
              << ",\"dust_magnitude_mean\":"
              << (detection.timings.valid_pixels == 0U
                      ? 0.0
                      : detection.timings.dust_magnitude_sum /
                            static_cast<double>(
                                detection.timings.valid_pixels))
              << ",\"dust_noise_mean\":"
              << (detection.timings.valid_pixels == 0U
                      ? 0.0
                      : detection.timings.dust_noise_sum /
                            static_cast<double>(
                                detection.timings.valid_pixels)) << '}'
              << ",\"total_microseconds\":" << micros(decode_started, finished)
              << "}\n";
    return detection.status == negaflow::imaging::GrainMendStatus::ok ? 0 : 1;
}

}  // namespace negaflow::cli
