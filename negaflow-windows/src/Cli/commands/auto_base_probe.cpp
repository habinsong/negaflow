#include "auto_base_probe.h"

#include "negaflow/imaging/auto_negative_base_resolver.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"
#include "negaflow/imaging/scanner_to_working.h"
#include "negaflow/imageio/wic_standard_image_decoder.h"

#include <chrono>
#include <cstddef>
#include <filesystem>
#include <iostream>
#include <string_view>

namespace negaflow::cli {
namespace {

[[nodiscard]] int print_error(const std::string_view code) {
    std::cout << "{\"status\":\"error\",\"code\":\"" << code << "\"}\n";
    return 2;
}

[[nodiscard]] const char* source_name(
    const negaflow::imaging::AutoNegativeBaseSource source) noexcept {
    switch (source) {
        case negaflow::imaging::AutoNegativeBaseSource::connected_component:
            return "connected_component";
        case negaflow::imaging::AutoNegativeBaseSource::scene_edge:
            return "scene_edge";
        case negaflow::imaging::AutoNegativeBaseSource::fallback:
            return "fallback";
        case negaflow::imaging::AutoNegativeBaseSource::continuous_border:
            return "continuous_border";
        case negaflow::imaging::AutoNegativeBaseSource::distributed_mask:
            return "distributed_mask";
        case negaflow::imaging::AutoNegativeBaseSource::strip_fallback:
            return "strip_fallback";
    }
    return "unknown";
}

}  // namespace

int run_auto_base_probe(const int argument_count, const wchar_t* const arguments[]) {
    if (argument_count < 3 || argument_count > 4) {
        return print_error("invalid_argument_count");
    }
    const bool monochrome =
        argument_count == 4 && std::wstring_view{arguments[3]} == L"bw";

    negaflow::imageio::WicTiffDecodeControl decode_control{};
    decode_control.rows_per_copy = 64U;
    auto prepared = negaflow::imaging::decode_scanner_tiff_to_working_rows(
        std::filesystem::path{arguments[2]}, {}, {}, decode_control);
    negaflow::imaging::WorkingImage image{};
    if (prepared.decode.status == negaflow::imageio::WicTiffDecodeStatus::ok &&
        prepared.working.status == negaflow::imaging::ScannerToWorkingStatus::ok) {
        image = std::move(prepared.working.image);
    } else {
        // 스캐너 TIFF 가 아닌 원본입니다. 현상 파이프라인이 그런 파일에 쓰는 길을 그대로
        // 탑니다(`stages/decode.cpp`) — RAW 는 함께 싣는 LibRaw 가 현상합니다. 진단이
        // 앱과 다른 파일만 볼 수 있으면 카메라 스캔 보고를 여기서 못 좁힙니다.
        const negaflow::imageio::WicStandardImageDecodeResult decoded =
            negaflow::imageio::decode_standard_image_with_wic(
                std::filesystem::path{arguments[2]}, {}, {}, {});
        if (decoded.status != negaflow::imageio::WicStandardImageDecodeStatus::ok) {
            return print_error(
                negaflow::imageio::wic_standard_image_decode_status_name(decoded.status));
        }
        negaflow::imaging::ScannerToWorkingResult working =
            negaflow::imaging::convert_scanner_to_working(decoded.image);
        if (working.status != negaflow::imaging::ScannerToWorkingStatus::ok) {
            return print_error(
                negaflow::imaging::scanner_to_working_status_name(working.status));
        }
        image = std::move(working.image);
    }

    const auto started = std::chrono::steady_clock::now();
    const negaflow::imaging::AutoNegativeBaseResult resolved =
        negaflow::imaging::resolve_auto_negative_base(
            image,
            monochrome ? negaflow::imaging::NegativeFilmType::black_and_white
                       : negaflow::imaging::NegativeFilmType::color);
    const auto finished = std::chrono::steady_clock::now();
    if (resolved.status != negaflow::imaging::AutoNegativeBaseStatus::ok) {
        return print_error(
            negaflow::imaging::auto_negative_base_status_name(resolved.status));
    }

    std::cout << "{\"status\":\"ok\",\"operation\":\"auto_base_probe\""
              << ",\"width\":" << image.width
              << ",\"height\":" << image.height
              << ",\"film\":\"" << (monochrome ? "bw" : "color") << '"'
              << ",\"source\":\"" << source_name(resolved.source) << '"'
              << ",\"dmin\":[" << resolved.dmin[0] << ',' << resolved.dmin[1]
              << ',' << resolved.dmin[2] << ']'
              // 고른 베이스보다 밝은 필름 화소의 비율과, 그래서 리베이트를 다시 쟀는지.
              // 이 둘이 "왜 어둡게 나왔나" 를 기록만으로 되짚는 자리입니다.
              << ",\"brighterThanBase\":" << resolved.brighter_than_base
              << ",\"rebateRescued\":"
              << (resolved.rebate_rescued ? "true" : "false");
    if (resolved.diagnostics.has_value()) {
        const auto& diagnostics = *resolved.diagnostics;
        std::cout << ",\"method\":\""
                  << negaflow::imaging::film_base_measurement_method_name(diagnostics.method)
                  << "\",\"evidenceScore\":" << diagnostics.evidence_score
                  << ",\"sampledPixelCount\":" << diagnostics.sampled_pixel_count
                  << ",\"anomalies\":[";
        for (std::size_t index = 0U; index < diagnostics.anomalies.size(); ++index) {
            if (index > 0U) {
                std::cout << ',';
            }
            std::cout << '"'
                      << negaflow::imaging::film_base_measurement_anomaly_name(
                             diagnostics.anomalies[index])
                      << '"';
        }
        std::cout << ']';
    }
    std::cout << ",\"microseconds\":"
              << std::chrono::duration_cast<std::chrono::microseconds>(
                     finished - started)
                     .count()
              << "}\n";
    return 0;
}

}  // namespace negaflow::cli
