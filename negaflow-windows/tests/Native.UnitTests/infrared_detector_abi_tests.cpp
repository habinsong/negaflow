#include "negaflow/abi/build_info.h"
#include "negaflow/abi/infrared_detect.h"
#include "Diagnostics/infrared_pair_diagnostic.h"
#include "negaflow/imageio/wic_tiff_decoder.h"
#include "negaflow/imaging/infrared_plane_resample.h"
#include "negaflow/output/wic_jpeg_export.h"
#include "negaflow/output/wic_tiff_export.h"
#include "negaflow/output/working_to_srgb16.h"
#include "synthetic_wic_tiff.h"
#include "wic_multiframe_tiff_fixture.h"

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

void test_infrared_plane_resample_contract() {
    const std::vector<float> source{1.0F, 2.0F, 3.0F, 4.0F};
    std::vector<float> output{};
    expect(negaflow::imaging::resample_infrared_plane_to_extent(
               source, 2U, 2U, 4U, 4U, output),
           "infrared_resample_valid");
    expect(output.size() == 16U && output[0U] == 0.5625F && output[5U] == 1.75F,
           "infrared_resample_pixel_center_transparent_bilinear");
    expect(!negaflow::imaging::resample_infrared_plane_to_extent(
               std::span<const float>(source.data(), 2U),
               1U, 2U, 4U, 4U, output),
           "infrared_resample_rejects_single_pixel_extent");
}

[[nodiscard]] std::vector<std::uint16_t> copy_first_cluster_attenuation(
    nf_infrared_detection_handle_v1* const handle) {
    if (handle == nullptr) return {};
    nf_infrared_cluster_v1 cluster{};
    cluster.struct_size = sizeof(cluster);
    if (nf_infrared_detection_get_cluster_v1(
            handle, 0U, &cluster, nullptr, 0U, nullptr, 0U) != NF_STATUS_OK) {
        return {};
    }
    std::vector<std::uint8_t> mask(
        static_cast<std::size_t>(cluster.core_mask_byte_count));
    std::vector<std::uint16_t> attenuation(
        static_cast<std::size_t>(cluster.attenuation_value_count));
    cluster.struct_size = sizeof(cluster);
    if (nf_infrared_detection_get_cluster_v1(
            handle, 0U, &cluster,
            mask.data(), mask.size(),
            attenuation.data(), attenuation.size()) != NF_STATUS_OK) {
        return {};
    }
    return attenuation;
}

void test_layout_and_owned_payload_lifecycle() {
    static_assert(sizeof(nf_infrared_detector_parameters_v1) == 48U);
    static_assert(sizeof(nf_infrared_detection_summary_v1) == 112U);
    static_assert(sizeof(nf_infrared_cluster_v1) == 40U);
    static_assert(sizeof(nf_infrared_component_v1) == 32U);
    static_assert(sizeof(nf_infrared_preview_point_v1) == 8U);
    expect(nf_get_abi_version() == NF_ABI_VERSION, "abi_version_matches_public_header");

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

    const std::filesystem::path half_infrared = root / L"infrared-half.tiff";
    write_file(
        half_infrared,
        negaflow::test_fixtures::make_infrared_detector_gray_tiff(64U, 48U));
    summary = {};
    summary.struct_size = sizeof(summary);
    handle = nullptr;
    expect(nf_detect_infrared_defects_from_tiff_v1(
               visible.c_str(), half_infrared.c_str(), &parameters, nullptr,
               &summary, &handle) == NF_STATUS_OK,
           "paired_resampled_infrared_call_ok");
    expect(summary.status == NF_INFRARED_DETECTION_OK &&
               summary.width == 128U && summary.height == 96U && handle != nullptr,
           "paired_resampled_infrared_matches_visible_extent");
    nf_infrared_detection_destroy_v1(handle);

    const std::filesystem::path oriented_visible = root / L"visible-oriented.tiff";
    const std::filesystem::path oriented_infrared = root / L"infrared-oriented.tiff";
    write_file(oriented_visible,
               negaflow::test_fixtures::make_infrared_detector_visible_tiff(
                   128U, 96U, 6U));
    write_file(oriented_infrared,
               negaflow::test_fixtures::make_infrared_detector_gray_tiff(96U, 128U));
    parameters.alignment_search_radius = 4;
    summary = {};
    summary.struct_size = sizeof(summary);
    handle = nullptr;
    expect(nf_detect_infrared_defects_from_files_v2(
               oriented_visible.c_str(), infrared.c_str(),
               NF_INFRARED_VISIBLE_SOURCE_SCANNER_TIFF,
               &parameters, nullptr, &summary, &handle) == NF_STATUS_OK,
           "paired_scanner_orientation_call_ok");
    expect(summary.status == NF_INFRARED_DETECTION_OK &&
               summary.width == 128U && summary.height == 96U && handle != nullptr,
           "paired_scanner_orientation_keeps_stored_pixels");
    nf_infrared_detection_destroy_v1(handle);

    summary = {};
    summary.struct_size = sizeof(summary);
    handle = nullptr;
    expect(nf_detect_infrared_defects_from_files_v2(
               oriented_visible.c_str(), oriented_infrared.c_str(),
               NF_INFRARED_VISIBLE_SOURCE_IMPORTED_FILE,
               &parameters, nullptr, &summary, &handle) == NF_STATUS_OK,
           "paired_imported_orientation_call_ok");
    expect(summary.status == NF_INFRARED_DETECTION_OK &&
               summary.width == 96U && summary.height == 128U && handle != nullptr,
           "paired_imported_orientation_rotates_visible_pixels");
    nf_infrared_detection_destroy_v1(handle);
    parameters.alignment_search_radius = 0;

    negaflow::imaging::WorkingImage jpeg_working{};
    jpeg_working.width = 128U;
    jpeg_working.height = 96U;
    jpeg_working.stride_pixels = 128U;
    jpeg_working.pixels.assign(
        static_cast<std::size_t>(jpeg_working.width) * jpeg_working.height,
        negaflow::core::Rgba32F{0.70F, 0.66F, 0.62F, 1.0F});
    for (std::int32_t y = 0; y < static_cast<std::int32_t>(jpeg_working.height); ++y) {
        for (std::int32_t x = 0; x < static_cast<std::int32_t>(jpeg_working.width); ++x) {
            const std::int32_t dx = x - 62;
            const std::int32_t dy = y - 48;
            if (dx * dx + dy * dy <= 16) {
                jpeg_working.pixels[
                    static_cast<std::size_t>(y) * jpeg_working.stride_pixels +
                    static_cast<std::uint32_t>(x)].red = 0.42F;
            }
        }
    }
    const std::filesystem::path jpeg_visible = root / L"visible.jpg";
    const auto jpeg_export = negaflow::output::export_working_to_srgb8_jpeg(
        jpeg_working, jpeg_visible, 1.0F);
    expect(jpeg_export.status == negaflow::output::WicJpegExportStatus::ok,
           "paired_standard_visible_fixture_export");
    summary = {};
    summary.struct_size = sizeof(summary);
    handle = nullptr;
    expect(nf_detect_infrared_defects_from_tiff_v1(
               jpeg_visible.c_str(), infrared.c_str(), &parameters, nullptr,
               &summary, &handle) == NF_STATUS_OK,
           "paired_standard_visible_call_ok");
    expect(summary.status == NF_INFRARED_DETECTION_OK &&
               summary.width == 128U && summary.height == 96U && handle != nullptr,
           "paired_standard_visible_detects_gray16_companion");
    nf_infrared_detection_destroy_v1(handle);

    const auto srgb16 = negaflow::output::convert_working_to_srgb16(jpeg_working);
    expect(srgb16.status == negaflow::output::WorkingToSrgb16Status::ok &&
               srgb16.image.channels == 3U,
           "paired_icc_encoded_samples_convert");
    const std::filesystem::path tagged_visible = root / L"visible-tagged.tiff";
    const std::filesystem::path untagged_visible = root / L"visible-untagged.tiff";
    const auto tagged_export = negaflow::output::export_working_to_srgb16_tiff(
        jpeg_working, tagged_visible);
    expect(tagged_export.status == negaflow::output::WicTiffExportStatus::ok &&
               tagged_export.info.color_profile_bytes > 0U,
           "paired_icc_tagged_fixture_export");
    expect(negaflow::test_fixtures::write_single_frame_tiff16(
               untagged_visible,
               srgb16.image.width,
               srgb16.image.height,
               static_cast<std::uint8_t>(srgb16.image.channels),
               srgb16.image.samples),
           "paired_icc_untagged_fixture_write");
    const auto tagged_raw = negaflow::imageio::decode_tiff_with_wic(tagged_visible);
    const auto untagged_raw = negaflow::imageio::decode_tiff_with_wic(untagged_visible);
    expect(tagged_raw.status == negaflow::imageio::WicTiffDecodeStatus::ok &&
               untagged_raw.status == negaflow::imageio::WicTiffDecodeStatus::ok &&
               !tagged_raw.image.icc_profile.empty() &&
               untagged_raw.image.icc_profile.empty() &&
               tagged_raw.image.samples == untagged_raw.image.samples,
           "paired_icc_fixtures_differ_only_by_profile");

    nf_infrared_detection_summary_v1 tagged_summary{};
    tagged_summary.struct_size = sizeof(tagged_summary);
    nf_infrared_detection_handle_v1* tagged_handle = nullptr;
    expect(nf_detect_infrared_defects_from_files_v2(
               tagged_visible.c_str(), infrared.c_str(),
               NF_INFRARED_VISIBLE_SOURCE_IMPORTED_FILE,
               &parameters, nullptr, &tagged_summary, &tagged_handle) == NF_STATUS_OK,
           "paired_icc_tagged_call_ok");
    expect(tagged_summary.status == NF_INFRARED_DETECTION_OK && tagged_handle != nullptr,
           "paired_icc_tagged_detects");
    nf_infrared_detection_summary_v1 untagged_summary{};
    untagged_summary.struct_size = sizeof(untagged_summary);
    nf_infrared_detection_handle_v1* untagged_handle = nullptr;
    expect(nf_detect_infrared_defects_from_files_v2(
               untagged_visible.c_str(), infrared.c_str(),
               NF_INFRARED_VISIBLE_SOURCE_IMPORTED_FILE,
               &parameters, nullptr, &untagged_summary, &untagged_handle) == NF_STATUS_OK,
           "paired_icc_untagged_call_ok");
    expect(untagged_summary.status == NF_INFRARED_DETECTION_OK && untagged_handle != nullptr,
           "paired_icc_untagged_detects");
    const auto tagged_attenuation = copy_first_cluster_attenuation(tagged_handle);
    const auto untagged_attenuation = copy_first_cluster_attenuation(untagged_handle);
    expect(!tagged_attenuation.empty() && !untagged_attenuation.empty() &&
               tagged_attenuation != untagged_attenuation,
           "paired_icc_profile_changes_detector_attenuation");
    nf_infrared_detection_destroy_v1(tagged_handle);
    nf_infrared_detection_destroy_v1(untagged_handle);

    constexpr std::size_t area = 128U * 96U;
    std::vector<float> first_visible_red(area, 0.70F);
    std::vector<float> first_infrared(area, 0.80F);
    dark_disk(first_visible_red, 128U, 62, 48, 4, 0.42F);
    dark_disk(first_infrared, 128U, 62, 48, 4, 0.48F);
    std::vector<std::uint16_t> visible_first(area * 3U);
    std::vector<std::uint16_t> visible_second(area * 3U);
    std::vector<std::uint16_t> infrared_first(area);
    std::vector<std::uint16_t> infrared_second(area);
    for (std::size_t pixel = 0U; pixel < area; ++pixel) {
        visible_first[pixel * 3U] =
            static_cast<std::uint16_t>(first_visible_red[pixel] * 65'535.0F);
        visible_first[pixel * 3U + 1U] = 43'253U;
        visible_first[pixel * 3U + 2U] = 40'632U;
        visible_second[pixel * 3U] = 45'874U;
        visible_second[pixel * 3U + 1U] = 43'253U;
        visible_second[pixel * 3U + 2U] = 40'632U;
        infrared_first[pixel] =
            static_cast<std::uint16_t>(first_infrared[pixel] * 65'535.0F);
        infrared_second[pixel] = 52'428U;
    }
    const std::filesystem::path multi_visible = root / L"visible-multi.tiff";
    const std::filesystem::path multi_infrared = root / L"infrared-multi.tiff";
    expect(negaflow::test_fixtures::write_two_frame_tiff16(
               multi_visible, 128U, 96U, 3U, visible_first, visible_second),
           "paired_multiframe_visible_fixture_write");
    expect(negaflow::test_fixtures::write_two_frame_tiff16(
               multi_infrared, 128U, 96U, 1U, infrared_first, infrared_second),
           "paired_multiframe_infrared_fixture_write");
    const auto default_multi_decode =
        negaflow::imageio::decode_tiff_with_wic(multi_infrared);
    expect(default_multi_decode.status ==
               negaflow::imageio::WicTiffDecodeStatus::preflight_failed,
           "paired_multiframe_default_decode_remains_fail_closed");
    summary = {};
    summary.struct_size = sizeof(summary);
    handle = nullptr;
    expect(nf_detect_infrared_defects_from_tiff_v1(
               multi_visible.c_str(), multi_infrared.c_str(), &parameters, nullptr,
               &summary, &handle) == NF_STATUS_OK,
           "paired_multiframe_call_ok");
    expect(summary.status == NF_INFRARED_DETECTION_OK &&
               summary.width == 128U && summary.height == 96U && handle != nullptr,
           "paired_multiframe_uses_first_visible_and_infrared_frames");
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

int wmain(const int argument_count, const wchar_t* const arguments[]) {
    if (argument_count == 3) {
        return run_infrared_pair_diagnostic(arguments[1], arguments[2]);
    }
    test_infrared_plane_resample_contract();
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
