#pragma once

#include "negaflow_abi.h"

#include <array>
#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>

namespace negaflow::develop_export_abi_tests {

extern int failures;

void expect(bool condition, const char* message);

[[nodiscard]] bool sha256(
    const std::vector<std::uint8_t>& bytes,
    std::array<std::uint8_t, 32U>& digest) noexcept;

[[nodiscard]] nf_develop_export_request_v1 make_request(
    const wchar_t* source,
    const wchar_t* destination);

[[nodiscard]] nf_develop_export_result_v1 make_result();

[[nodiscard]] nf_develop_export_request_v2 make_request_v2(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_result_v2 make_result_v2();

[[nodiscard]] nf_develop_export_result_v3 make_result_v3();

[[nodiscard]] nf_develop_run_state_v1 make_run_state();

[[nodiscard]] nf_soft_proof_v1 make_soft_proof();

[[nodiscard]] nf_develop_export_request_v3 make_request_v3(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v4 make_request_v4(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v5 make_request_v5(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v6 make_request_v6(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v7 make_request_v7(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v8 make_request_v8(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v9 make_request_v9(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v10 make_request_v10(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v11 make_request_v11(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v12 make_request_v12(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v13 make_request_v13(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v14 make_request_v14(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v15 make_request_v15(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v16 make_request_v16(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v17 make_request_v17(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v18 make_request_v18(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v19 make_request_v19(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v20 make_request_v20(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v21 make_request_v21(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v24 make_request_v24(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v25 make_request_v25(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v26 make_request_v26(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v27 make_request_v27(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v28 make_request_v28(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v29 make_request_v29(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] nf_develop_export_request_v30 make_request_v30(
    const wchar_t* source,
    const wchar_t* destination,
    std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO);

[[nodiscard]] bool write_file(
    const std::filesystem::path& path,
    const std::vector<std::uint8_t>& bytes);

[[nodiscard]] std::vector<std::uint8_t> read_file(const std::filesystem::path& path);

[[nodiscard]] std::vector<std::uint8_t> decode_png_bgra8(
    const std::filesystem::path& path,
    std::uint32_t expected_width,
    std::uint32_t expected_height);

[[nodiscard]] bool preview_is_neutral(const std::vector<std::uint8_t>& pixels) noexcept;

void test_argument_contract();
void test_request_validation();
void test_v2_contract();
void test_v3_contract();
void test_v4_contract();
void test_v5_contract();
void test_v6_contract();
void test_v7_contract();
void test_v8_contract();
void test_v9_contract();
void test_v10_contract();
void test_v11_contract();
void test_v12_contract();
void test_v18_contract();
void test_v19_contract();
void test_v20_contract();
void test_v21_contract();
void test_v24_contract();
void test_v25_contract();
void test_v26_contract();
void test_v27_contract();
void test_v28_contract();
void test_v29_contract();
void test_v30_contract();
void test_v32_contract();
void test_v34_contract();
void test_v35_contract();
void test_v36_contract();
void test_missing_source_is_not_a_validation_error();
void test_v2_missing_source_is_not_a_validation_error();
void test_full_develop(const std::filesystem::path& source);
void test_v2_auto_develop(const std::filesystem::path& source);
void test_preview(const std::filesystem::path& source);
void test_v2_auto_preview(const std::filesystem::path& source);
void test_v3_basic_tone_preview(const std::filesystem::path& source);
void test_v4_film_preview(const std::filesystem::path& source);
void test_v5_point_curve_preview(const std::filesystem::path& source);
void test_v6_color_mixer_preview(const std::filesystem::path& source);
void test_v8_grain_mend_preview(const std::filesystem::path& source);
void test_v2_grain_mend_detection(const std::filesystem::path& source);
void test_v3_grain_mend_detection_tuning(const std::filesystem::path& source);
void test_v4_grain_mend_micro_speck_detection(const std::filesystem::path& source);
void test_v7_grain_mend_review_handle();
void test_v9_film_scan_denoise_preview(const std::filesystem::path& source);
void test_v10_texture_preview(const std::filesystem::path& source);
void test_v11_bw_transform_preview(const std::filesystem::path& source);
void test_v11_rendered_digital_preview(const std::filesystem::path& source);
void test_v12_local_dodge_burn_preview(const std::filesystem::path& source);
void test_v13_color_model_preview(const std::filesystem::path& source);
void test_v14_scene_correction_preview(const std::filesystem::path& source);
void test_v15_develop_target_preview(const std::filesystem::path& source);
void test_v16_scanner_profile_preview(const std::filesystem::path& source);
void test_v17_positive_film_preview(const std::filesystem::path& source);
void test_v22_run_state();
void test_v22_cancel_during_run(const std::filesystem::path& source);
void test_auto_adjust_on_a_real_scan(const std::filesystem::path& source);
void test_v18_defect_region_preview_and_export();
void test_v35_defect_bake();

void test_defect_region_preview_keeps_source_coordinates();
void test_v23_soft_proof_preview();
void test_read_soft_proof_media();
void test_tiff_source_probe(const std::filesystem::path& source);
void test_standard_image_import_and_develop(const std::filesystem::path& source);
void test_soft_proof_on_a_real_scan(const std::filesystem::path& source);

}  // namespace negaflow::develop_export_abi_tests
