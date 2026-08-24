#include "infrared_pair_diagnostic.h"

#include "negaflow/abi/infrared_detect.h"

#include <chrono>
#include <cstdint>
#include <iostream>

int run_infrared_pair_diagnostic(
    const wchar_t* const visible_path,
    const wchar_t* const infrared_path) {
    nf_infrared_detector_parameters_v1 parameters{};
    parameters.struct_size = sizeof(parameters);
    parameters.sensitivity = 0.5;
    parameters.maximum_coverage = 0.05;
    parameters.dilate_radius = 1;
    parameters.minimum_area = 2;
    parameters.alignment_search_radius = 32;
    parameters.cluster_tile = 768;
    parameters.cluster_padding = 40;

    nf_infrared_detection_summary_v1 summary{};
    summary.struct_size = sizeof(summary);
    nf_infrared_detection_handle_v1* handle = nullptr;
    const auto started = std::chrono::steady_clock::now();
    const nf_status_t call_status = nf_detect_infrared_defects_from_files_v2(
        visible_path,
        infrared_path,
        NF_INFRARED_VISIBLE_SOURCE_SCANNER_TIFF,
        &parameters,
        nullptr,
        &summary,
        &handle);
    const auto finished = std::chrono::steady_clock::now();
    const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(
        finished - started).count();

    std::cout << "{\"operation\":\"infrared_pair_diagnostic\""
              << ",\"call_status\":" << call_status
              << ",\"detection_status\":" << summary.status
              << ",\"width\":" << summary.width
              << ",\"height\":" << summary.height
              << ",\"offset_x\":" << summary.offset_x
              << ",\"offset_y\":" << summary.offset_y
              << ",\"coverage\":" << summary.coverage
              << ",\"candidate_count\":" << summary.candidate_count
              << ",\"confirmed_count\":" << summary.confirmed_count
              << ",\"cluster_count\":" << summary.cluster_count
              << ",\"component_count\":" << summary.component_count
              << ",\"elapsed_microseconds\":" << elapsed << "}\n";

    const bool succeeded = call_status == NF_STATUS_OK &&
        summary.status == NF_INFRARED_DETECTION_OK && handle != nullptr;
    nf_infrared_detection_destroy_v1(handle);
    return succeeded ? 0 : 1;
}
