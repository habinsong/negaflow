#include "auto_base_probe.h"

#include "negaflow/imaging/auto_negative_base_resolver.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"

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
    if (prepared.decode.status != negaflow::imageio::WicTiffDecodeStatus::ok ||
        prepared.working.status != negaflow::imaging::ScannerToWorkingStatus::ok) {
        return print_error("decode_failed");
    }

    const auto started = std::chrono::steady_clock::now();
    const negaflow::imaging::AutoNegativeBaseResult resolved =
        negaflow::imaging::resolve_auto_negative_base(
            prepared.working.image,
            monochrome ? negaflow::imaging::NegativeFilmType::black_and_white
                       : negaflow::imaging::NegativeFilmType::color);
    const auto finished = std::chrono::steady_clock::now();
    if (resolved.status != negaflow::imaging::AutoNegativeBaseStatus::ok) {
        return print_error(
            negaflow::imaging::auto_negative_base_status_name(resolved.status));
    }

    std::cout << "{\"status\":\"ok\",\"operation\":\"auto_base_probe\""
              << ",\"width\":" << prepared.working.image.width
              << ",\"height\":" << prepared.working.image.height
              << ",\"film\":\"" << (monochrome ? "bw" : "color") << '"'
              << ",\"source\":\"" << source_name(resolved.source) << '"'
              << ",\"dmin\":[" << resolved.dmin[0] << ',' << resolved.dmin[1]
              << ',' << resolved.dmin[2] << ']';
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
