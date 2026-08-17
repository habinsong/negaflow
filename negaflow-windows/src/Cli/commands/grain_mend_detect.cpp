#include "grain_mend_detect.h"

#include "negaflow/imaging/grain_mend.h"
#include "negaflow/imaging/manual_negative_developer.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"

#include <array>
#include <charconv>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <filesystem>
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

}  // namespace

int run_grain_mend_detect(
    const int argument_count,
    const wchar_t* const arguments[]) {
    if (argument_count < 6 || argument_count > 8) {
        std::cerr << "usage: negaflow-cli --grain-mend-detect <source> "
                     "<dmin-r> <dmin-g> <dmin-b> [sensitivity] [guided]\n";
        return 2;
    }

    negaflow::imaging::ManualNegativeDevelopParameters develop{};
    if (!parse_finite_float(arguments[3], develop.dmin[0]) ||
        !parse_finite_float(arguments[4], develop.dmin[1]) ||
        !parse_finite_float(arguments[5], develop.dmin[2])) {
        return print_error("invalid_dmin");
    }
    float sensitivity = 1.0F;
    if (argument_count >= 7 && !parse_finite_float(arguments[6], sensitivity)) {
        return print_error("invalid_sensitivity");
    }
    const bool guided = argument_count >= 8 &&
        std::wstring_view{arguments[7]} == L"guided";

    const auto decode_started = std::chrono::steady_clock::now();
    negaflow::imageio::WicTiffDecodeControl decode_control{};
    decode_control.rows_per_copy = 64U;
    auto prepared = negaflow::imaging::decode_scanner_tiff_to_working_rows(
        std::filesystem::path{arguments[2]}, {}, {}, decode_control);
    if (prepared.decode.status != negaflow::imageio::WicTiffDecodeStatus::ok ||
        prepared.working.status != negaflow::imaging::ScannerToWorkingStatus::ok) {
        return print_error("decode_failed");
    }
    const auto develop_started = std::chrono::steady_clock::now();
    auto developed = negaflow::imaging::develop_manual_negative(
        std::move(prepared.working.image), develop);
    if (developed.status != negaflow::imaging::ManualNegativeDevelopStatus::ok) {
        return print_error("develop_failed");
    }
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
    const negaflow::imaging::GrainMendDetection detection =
        negaflow::imaging::detect_grain_mend(developed.image, parameters, roi);
    const auto finished = std::chrono::steady_clock::now();

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
              << ",\"source_width\":" << developed.image.width
              << ",\"source_height\":" << developed.image.height
              << ",\"detection_width\":" << detection.width
              << ",\"detection_height\":" << detection.height
              << ",\"accepted_pixels\":" << detection.accepted_pixels
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
              << micros(decode_started, develop_started)
              << ",\"develop_microseconds\":"
              << micros(develop_started, detect_started)
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
              << detection.timings.total_microseconds << '}'
              << ",\"total_microseconds\":" << micros(decode_started, finished)
              << "}\n";
    return detection.status == negaflow::imaging::GrainMendStatus::ok ? 0 : 1;
}

}  // namespace negaflow::cli
