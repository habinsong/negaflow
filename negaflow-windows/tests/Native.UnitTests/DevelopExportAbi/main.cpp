#include "develop_export_abi_test_support.h"

#include <filesystem>
#include <iostream>

int main(const int argument_count, const char* const arguments[]) {
    using namespace negaflow::develop_export_abi_tests;
    test_argument_contract();
    test_request_validation();
    test_v2_contract();
    test_v3_contract();
    test_v4_contract();
    test_v5_contract();
    test_v6_contract();
    test_v7_contract();
    test_v8_contract();
    test_v9_contract();
    test_v10_contract();
    test_v11_contract();
    test_v12_contract();
    test_v18_contract();
    test_v19_contract();
    test_v20_contract();
    test_v21_contract();
    test_v24_contract();
    test_v25_contract();
    test_v26_contract();
    test_v27_contract();
    test_v28_contract();
    test_v29_contract();
    test_v30_contract();
    test_v32_contract();
    test_v34_contract();
    test_v35_contract();
    test_missing_source_is_not_a_validation_error();
    test_v2_missing_source_is_not_a_validation_error();
    test_v18_defect_region_preview_and_export();
    test_defect_region_preview_keeps_source_coordinates();
    test_v22_run_state();
    test_v23_soft_proof_preview();
    test_read_soft_proof_media();

    if (argument_count >= 2) {
        const std::filesystem::path source{arguments[1]};
        if (std::filesystem::exists(source)) {
            test_full_develop(source);
            test_preview(source);
            test_v2_auto_develop(source);
            test_v2_auto_preview(source);
            test_v3_basic_tone_preview(source);
            test_v4_film_preview(source);
            test_v5_point_curve_preview(source);
            test_v6_color_mixer_preview(source);
            test_v8_grain_mend_preview(source);
            test_v2_grain_mend_detection(source);
            test_v3_grain_mend_detection_tuning(source);
            test_v4_grain_mend_micro_speck_detection(source);
            test_v9_film_scan_denoise_preview(source);
            test_v10_texture_preview(source);
            test_v11_bw_transform_preview(source);
            test_v11_rendered_digital_preview(source);
            test_v12_local_dodge_burn_preview(source);
            test_v13_color_model_preview(source);
            test_v14_scene_correction_preview(source);
            test_v15_develop_target_preview(source);
            test_v16_scanner_profile_preview(source);
            test_v17_positive_film_preview(source);
            test_v22_cancel_during_run(source);
            test_auto_adjust_on_a_real_scan(source);
            test_soft_proof_on_a_real_scan(source);
            test_tiff_source_probe(source);
            test_standard_image_import_and_develop(source);
        } else {
            std::cerr << "FAIL: the supplied source fixture does not exist\n";
            ++failures;
        }
    }

    if (failures != 0) {
        std::cerr << failures << " check(s) failed\n";
        return 1;
    }
    std::cout << "{\"status\":\"ok\",\"operation\":\"develop_export_abi_tests\"}\n";
    return 0;

}
