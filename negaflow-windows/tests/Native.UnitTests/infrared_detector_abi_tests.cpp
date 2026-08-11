#include "negaflow_abi.h"
#include "synthetic_wic_tiff.h"

#include <Windows.h>

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* name) {
    if (!condition) {
        ++failures;
        std::cerr << "FAIL " << name << '\n';
    }
}

void dark_disk(
    std::vector<float>& plane,
    const std::uint32_t width,
    const std::int32_t center_x,
    const std::int32_t center_y,
    const std::int32_t radius,
    const float value) {
    const std::uint32_t height = static_cast<std::uint32_t>(plane.size() / width);
    for (std::int32_t y = 0; y < static_cast<std::int32_t>(height); ++y) {
        for (std::int32_t x = 0; x < static_cast<std::int32_t>(width); ++x) {
            const std::int32_t dx = x - center_x;
            const std::int32_t dy = y - center_y;
            if (dx * dx + dy * dy <= radius * radius) {
                plane[static_cast<std::size_t>(y) * width + static_cast<std::uint32_t>(x)] = value;
            }
        }
    }
}

void test_layout_and_owned_payload_lifecycle() {
    static_assert(sizeof(nf_infrared_detector_parameters_v1) == 48U);
    static_assert(sizeof(nf_infrared_detection_summary_v1) == 112U);
    static_assert(sizeof(nf_infrared_cluster_v1) == 40U);
    static_assert(sizeof(nf_infrared_component_v1) == 32U);
    static_assert(sizeof(nf_infrared_preview_point_v1) == 8U);
    expect(nf_get_abi_version() == 34U, "abi_minor_34");

    constexpr std::uint32_t width = 128U;
    constexpr std::uint32_t height = 96U;
    std::vector<float> infrared(static_cast<std::size_t>(width) * height, 0.8F);
    std::vector<float> red(static_cast<std::size_t>(width) * height, 0.7F);
    dark_disk(infrared, width, 62, 48, 4, 0.48F);
    dark_disk(red, width, 62, 48, 4, 0.42F);

    nf_infrared_detector_parameters_v1 parameters{};
    parameters.struct_size = sizeof(parameters);
    parameters.sensitivity = 0.5;
    parameters.maximum_coverage = 0.05;
    parameters.dilate_radius = 1;
    parameters.minimum_area = 2;
    parameters.cluster_tile = 768;
    parameters.cluster_padding = 40;
    nf_infrared_detection_summary_v1 summary{};
    summary.struct_size = sizeof(summary);
    nf_infrared_detection_handle_v1* handle = nullptr;
    const nf_status_t status = nf_detect_infrared_defects_v1(
        infrared.data(), width * sizeof(float),
        red.data(), width * sizeof(float),
        width, height, &parameters, nullptr, &summary, &handle);
    expect(status == NF_STATUS_OK, "detect_call_ok");
    expect(summary.status == NF_INFRARED_DETECTION_OK, "detect_domain_ok");
    expect(summary.cluster_count >= 1U && summary.component_count >= 1U,
           "detect_counts");
    expect(handle != nullptr, "detect_handle_owned");
    if (handle == nullptr) return;

    nf_infrared_cluster_v1 cluster{};
    cluster.struct_size = sizeof(cluster);
    expect(nf_infrared_detection_get_cluster_v1(
               handle, 0U, &cluster, nullptr, 0U, nullptr, 0U) == NF_STATUS_OK,
           "cluster_query");
    expect(cluster.core_mask_byte_count ==
               static_cast<std::uint64_t>(cluster.width) * cluster.height * 4U,
           "cluster_mask_shape");
    expect(cluster.attenuation_value_count ==
               static_cast<std::uint64_t>(cluster.width) * cluster.height,
           "cluster_attenuation_shape");
    std::vector<std::uint8_t> mask(static_cast<std::size_t>(cluster.core_mask_byte_count));
    std::vector<std::uint16_t> attenuation(
        static_cast<std::size_t>(cluster.attenuation_value_count));
    cluster.struct_size = sizeof(cluster);
    expect(nf_infrared_detection_get_cluster_v1(
               handle, 0U, &cluster,
               mask.data(), mask.size(),
               attenuation.data(), attenuation.size()) == NF_STATUS_OK,
           "cluster_copy");
    const std::uint32_t y0 = height - cluster.roi_y_up - cluster.height;
    const std::size_t center = static_cast<std::size_t>(48U - y0) * cluster.width +
        62U - cluster.roi_x;
    expect(center < attenuation.size() && attenuation[center] > 6000U,
           "cluster_center_attenuation");

    nf_infrared_component_v1 component{};
    component.struct_size = sizeof(component);
    expect(nf_infrared_detection_get_component_v1(
               handle, 0U, &component, nullptr, 0U) == NF_STATUS_OK,
           "component_query");
    std::vector<nf_infrared_preview_point_v1> points(
        static_cast<std::size_t>(component.preview_point_count));
    component.struct_size = sizeof(component);
    expect(nf_infrared_detection_get_component_v1(
               handle, 0U, &component, points.data(), points.size()) == NF_STATUS_OK,
           "component_copy");
    expect(!points.empty(), "component_points");
    nf_infrared_detection_destroy_v1(handle);
}

void write_file(
    const std::filesystem::path& path,
    const std::vector<std::uint8_t>& bytes) {
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    output.write(reinterpret_cast<const char*>(bytes.data()),
                 static_cast<std::streamsize>(bytes.size()));
    output.close();
    expect(output.good(), "paired_tiff_fixture_write");
}

void test_paired_tiff_ingestion() {
    const std::filesystem::path root = std::filesystem::temp_directory_path() /
        (L"negaflow-ir-abi-" + std::to_wstring(GetCurrentProcessId()));
    std::error_code error{};
    std::filesystem::remove_all(root, error);
    error.clear();
    std::filesystem::create_directories(root, error);
    expect(!error, "paired_tiff_temp_create");
    const std::filesystem::path visible = root / L"visible.tiff";
    const std::filesystem::path infrared = root / L"infrared.tiff";
    write_file(visible, negaflow::test_fixtures::make_infrared_detector_visible_tiff(128U, 96U));
    write_file(infrared, negaflow::test_fixtures::make_infrared_detector_gray_tiff(128U, 96U));

    nf_infrared_detector_parameters_v1 parameters{};
    parameters.struct_size = sizeof(parameters);
    parameters.sensitivity = 0.5;
    parameters.maximum_coverage = 0.05;
    parameters.dilate_radius = 1;
    parameters.minimum_area = 2;
    parameters.alignment_search_radius = 0;
    parameters.cluster_tile = 768;
    parameters.cluster_padding = 40;
    nf_infrared_detection_summary_v1 summary{};
    summary.struct_size = sizeof(summary);
    nf_infrared_detection_handle_v1* handle = nullptr;
    expect(nf_detect_infrared_defects_from_tiff_v1(
               visible.c_str(), infrared.c_str(), &parameters, nullptr,
               &summary, &handle) == NF_STATUS_OK,
           "paired_tiff_call_ok");
    expect(summary.status == NF_INFRARED_DETECTION_OK &&
               summary.width == 128U && summary.height == 96U && handle != nullptr,
           "paired_tiff_detects_gray16_companion");
    nf_infrared_detection_destroy_v1(handle);

    std::uint32_t cancel = 1U;
    summary = {};
    summary.struct_size = sizeof(summary);
    handle = nullptr;
    expect(nf_detect_infrared_defects_from_tiff_v1(
               visible.c_str(), infrared.c_str(), &parameters, &cancel,
               &summary, &handle) == NF_STATUS_OK &&
               summary.status == NF_INFRARED_DETECTION_CANCELLED && handle == nullptr,
           "paired_tiff_cancel_before_decode");
    std::filesystem::remove_all(root, error);
}

void test_non_success_has_no_handle() {
    constexpr std::uint32_t width = 64U;
    constexpr std::uint32_t height = 64U;
    std::vector<float> plane(static_cast<std::size_t>(width) * height, 0.8F);
    nf_infrared_detector_parameters_v1 parameters{};
    parameters.struct_size = sizeof(parameters);
    parameters.sensitivity = 0.5;
    parameters.maximum_coverage = 0.05;
    parameters.dilate_radius = 1;
    parameters.minimum_area = 2;
    parameters.cluster_tile = 64;
    parameters.cluster_padding = 4;
    nf_infrared_detection_summary_v1 summary{};
    summary.struct_size = sizeof(summary);
    nf_infrared_detection_handle_v1* handle = reinterpret_cast<nf_infrared_detection_handle_v1*>(1);
    expect(nf_detect_infrared_defects_v1(
               plane.data(), width * sizeof(float), plane.data(), width * sizeof(float),
               width, height, &parameters, nullptr, &summary, &handle) == NF_STATUS_OK,
           "no_defects_call_ok");
    expect(summary.status == NF_INFRARED_DETECTION_NO_DEFECTS, "no_defects_status");
    expect(handle == nullptr, "no_defects_no_handle");

    std::uint32_t cancel = 1U;
    summary = {};
    summary.struct_size = sizeof(summary);
    expect(nf_detect_infrared_defects_v1(
               plane.data(), width * sizeof(float), plane.data(), width * sizeof(float),
               width, height, &parameters, &cancel, &summary, &handle) == NF_STATUS_OK,
           "cancel_call_ok");
    expect(summary.status == NF_INFRARED_DETECTION_CANCELLED, "cancel_status");
    expect(handle == nullptr, "cancel_no_handle");
}

}  // namespace

int main() {
    test_layout_and_owned_payload_lifecycle();
    test_non_success_has_no_handle();
    test_paired_tiff_ingestion();
    if (failures != 0) {
        std::cerr << failures << " infrared detector ABI checks failed\n";
        return 1;
    }
    std::cout << "infrared detector ABI checks passed\n";
    return 0;
}
