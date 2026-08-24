#include "synthetic_wic_tiff.h"
#include <algorithm>
#include <cmath>
#include <cstring>
#include "develop_export_abi_test_support.h"

namespace negaflow::develop_export_abi_tests {

void test_v18_defect_region_preview_and_export() {
    constexpr std::uint32_t width = 64U;
    constexpr std::uint32_t height = 64U;
    const std::filesystem::path temporary = std::filesystem::temp_directory_path();
    const std::filesystem::path source =
        temporary / L"negaflow-abi-v18-defect-source.tif";
    const std::filesystem::path identity_output =
        temporary / L"negaflow-abi-v18-defect-identity.png";
    const std::filesystem::path repaired_output =
        temporary / L"negaflow-abi-v18-defect-repaired.png";
    const std::filesystem::path mismatched_output =
        temporary / L"negaflow-abi-v19-defect-mismatch.png";
    const std::filesystem::path cloned_output =
        temporary / L"negaflow-abi-v20-clone.png";
    const std::filesystem::path brushed_output =
        temporary / L"negaflow-abi-v21-brush.png";
    const std::filesystem::path infrared_output =
        temporary / L"negaflow-abi-v24-infrared.png";
    const std::filesystem::path calibrated_output =
        temporary / L"negaflow-abi-v27-calibrated.png";
    const std::filesystem::path jpeg_output =
        temporary / L"negaflow-abi-v28-output.jpg";
    const std::filesystem::path longedge_output =
        temporary / L"negaflow-abi-v29-longedge.png";
    std::error_code ignored{};
    std::filesystem::remove(source, ignored);
    std::filesystem::remove(identity_output, ignored);
    std::filesystem::remove(repaired_output, ignored);
    std::filesystem::remove(mismatched_output, ignored);
    std::filesystem::remove(cloned_output, ignored);
    std::filesystem::remove(brushed_output, ignored);
    std::filesystem::remove(infrared_output, ignored);
    std::filesystem::remove(calibrated_output, ignored);
    std::filesystem::remove(jpeg_output, ignored);
    std::filesystem::remove(longedge_output, ignored);

    const std::vector<std::uint8_t> source_bytes =
        negaflow::test_fixtures::make_uncompressed_rgb16_defect_tiff(
            width,
            height);
    expect(
        !source_bytes.empty() && write_file(source, source_bytes),
        "v18 synthetic defect TIFF is written");
    if (!std::filesystem::exists(source)) {
        return;
    }
    std::array<std::uint8_t, 32U> source_identity{};
    expect(
        sha256(source_bytes, source_identity),
        "v19 source identity is calculated for the synthetic TIFF");

    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v18 identity =
        make_request_v18(source_text.c_str(), nullptr, NF_BASE_ESTIMATION_MANUAL);
    identity.v17.film_polarity = NF_FILM_POLARITY_POSITIVE;
    std::vector<std::uint8_t> identity_pixels(
        static_cast<std::size_t>(width) * height * 4U,
        0U);
    nf_develop_export_result_v2 identity_result = make_result_v2();
    expect(
        nf_develop_preview_v18(
            &identity,
            width,
            height,
            identity_pixels.data(),
            static_cast<std::uint32_t>(identity_pixels.size()),
            &identity_result) == NF_STATUS_OK &&
            identity_result.succeeded == 1U &&
            identity_result.image_width == width &&
            identity_result.image_height == height,
        "v18 identity preview succeeds at source resolution");

    constexpr std::uint32_t roi_x = 24U;
    constexpr std::uint32_t roi_top = 36U;
    constexpr std::uint32_t roi_width = 16U;
    constexpr std::uint32_t roi_height = 24U;
    constexpr std::uint32_t roi_y_up = height - roi_top - roi_height;
    std::vector<std::uint8_t> mask(
        static_cast<std::size_t>(roi_width) * roi_height,
        0U);
    for (std::uint32_t source_y = (height * 5U) / 8U;
         source_y < (height * 7U) / 8U;
         ++source_y) {
        const std::uint32_t local_y = source_y - roi_top;
        mask[static_cast<std::size_t>(local_y) * roi_width + 8U] = 0xffU;
        mask[static_cast<std::size_t>(local_y) * roi_width + 7U] = 0xffU;
    }
    nf_defect_region_edit_v1 edit{};
    edit.enabled = 1U;
    edit.roi_x = roi_x;
    edit.roi_y = roi_y_up;
    edit.width = roi_width;
    edit.height = roi_height;
    edit.mask_stride_bytes = roi_width;
    edit.mask_byte_count = static_cast<std::uint32_t>(mask.size());
    edit.strength = 1.0;
    edit.has_preferred_angle = 1U;
    edit.preferred_angle_degrees = 90.0;

    nf_develop_export_request_v18 repaired = identity;
    repaired.defect_region_edits = &edit;
    repaired.defect_region_edit_count = 1U;
    repaired.defect_mask_bytes = mask.data();
    repaired.defect_mask_byte_count = static_cast<std::uint32_t>(mask.size());
    std::vector<std::uint8_t> repaired_pixels(identity_pixels.size(), 0U);
    nf_develop_export_result_v2 repaired_result = make_result_v2();
    const bool repaired_preview_ok =
        nf_develop_preview_v18(
            &repaired,
            width,
            height,
            repaired_pixels.data(),
            static_cast<std::uint32_t>(repaired_pixels.size()),
            &repaired_result) == NF_STATUS_OK &&
        repaired_result.succeeded == 1U;
    expect(
        repaired_preview_ok && repaired_pixels != identity_pixels,
        "v18 ordered region repair changes the shared preview pipeline");
    edit.strength = 0.0;
    std::vector<std::uint8_t> zero_region_pixels(identity_pixels.size(), 0U);
    nf_develop_export_result_v2 zero_region_result = make_result_v2();
    expect(
        nf_develop_preview_v18(
            &repaired,
            width,
            height,
            zero_region_pixels.data(),
            static_cast<std::uint32_t>(zero_region_pixels.size()),
            &zero_region_result) == NF_STATUS_OK &&
            zero_region_result.succeeded == 1U && zero_region_pixels == identity_pixels,
        "v18 Auto and Guided region strength zero is pixel-identical to the source recipe");
    edit.strength = 1.0;

    nf_develop_export_request_v19 bound = make_request_v19(
        source_text.c_str(),
        nullptr,
        NF_BASE_ESTIMATION_MANUAL);
    bound.v18 = repaired;
    bound.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size =
        static_cast<std::uint32_t>(sizeof(bound));
    bound.defect_source_file_bytes = source_bytes.size();
    bound.defect_source_sha256 = source_identity.data();
    bound.has_defect_source_identity = 1U;
    std::vector<std::uint8_t> bound_pixels(identity_pixels.size(), 0U);
    nf_develop_export_result_v2 bound_result = make_result_v2();
    expect(
        nf_develop_preview_v19(
            &bound,
            width,
            height,
            bound_pixels.data(),
            static_cast<std::uint32_t>(bound_pixels.size()),
            &bound_result) == NF_STATUS_OK &&
            bound_result.succeeded == 1U &&
            bound_pixels == repaired_pixels,
        "v19 matching source identity preserves the shared defect preview pixels");

    nf_defect_clone_point_v1 clone_point{0.75, 0.25};
    nf_defect_clone_stroke_v1 clone_stroke{};
    clone_stroke.point_count = 1U;
    clone_stroke.offset_x = -0.5;
    clone_stroke.diameter_pixels = 10.0;
    clone_stroke.hardness = 1.0;
    nf_defect_clone_edit_v1 clone_edit{};
    clone_edit.enabled = 1U;
    clone_edit.stroke_count = 1U;
    clone_edit.strength = 1.0;
    nf_defect_recipe_edit_ref_v1 clone_order{
        NF_DEFECT_RECIPE_EDIT_CLONE, 0U};
    nf_develop_export_request_v20 cloned = make_request_v20(
        source_text.c_str(), nullptr, NF_BASE_ESTIMATION_MANUAL);
    cloned.v19.v18.v17.film_polarity = NF_FILM_POLARITY_POSITIVE;
    cloned.v19.defect_source_file_bytes = source_bytes.size();
    cloned.v19.defect_source_sha256 = source_identity.data();
    cloned.v19.has_defect_source_identity = 1U;
    cloned.defect_clone_edits = &clone_edit;
    cloned.defect_clone_edit_count = 1U;
    cloned.defect_clone_strokes = &clone_stroke;
    cloned.defect_clone_stroke_count = 1U;
    cloned.defect_clone_points = &clone_point;
    cloned.defect_clone_point_count = 1U;
    cloned.defect_edit_order = &clone_order;
    cloned.defect_edit_order_count = 1U;
    std::vector<std::uint8_t> cloned_pixels(identity_pixels.size(), 0U);
    nf_develop_export_result_v2 cloned_result = make_result_v2();
    const bool cloned_preview_ok =
        nf_develop_preview_v20(
            &cloned,
            width,
            height,
            cloned_pixels.data(),
            static_cast<std::uint32_t>(cloned_pixels.size()),
            &cloned_result) == NF_STATUS_OK &&
        cloned_result.succeeded == 1U;
    expect(
        cloned_preview_ok && cloned_pixels != identity_pixels,
        "v20 Clone Stamp changes the shared preview pipeline");
    clone_edit.strength = 0.0;
    std::vector<std::uint8_t> zero_clone_pixels(identity_pixels.size(), 0U);
    nf_develop_export_result_v2 zero_clone_result = make_result_v2();
    expect(
        nf_develop_preview_v20(
            &cloned,
            width,
            height,
            zero_clone_pixels.data(),
            static_cast<std::uint32_t>(zero_clone_pixels.size()),
            &zero_clone_result) == NF_STATUS_OK &&
            zero_clone_result.succeeded == 1U && zero_clone_pixels == identity_pixels,
        "v20 Clone strength zero is pixel-identical to the source recipe");
    clone_edit.strength = 1.0;

    std::array<nf_defect_brush_point_v1, 2U> brush_points{{
        {0.5, 0.625},
        {0.5, 0.875},
    }};
    nf_defect_brush_stroke_v1 brush_stroke{};
    brush_stroke.point_count = static_cast<std::uint32_t>(brush_points.size());
    brush_stroke.thickness = 0.04;
    nf_defect_brush_edit_v1 brush_edit{};
    brush_edit.enabled = 1U;
    brush_edit.stroke_count = 1U;
    brush_edit.strength = 1.0;
    nf_defect_recipe_edit_ref_v1 brush_order{
        NF_DEFECT_RECIPE_EDIT_BRUSH, 0U};
    nf_develop_export_request_v21 brushed = make_request_v21(
        source_text.c_str(), nullptr, NF_BASE_ESTIMATION_MANUAL);
    brushed.v20.v19.v18.v17.film_polarity = NF_FILM_POLARITY_POSITIVE;
    brushed.v20.v19.defect_source_file_bytes = source_bytes.size();
    brushed.v20.v19.defect_source_sha256 = source_identity.data();
    brushed.v20.v19.has_defect_source_identity = 1U;
    brushed.v20.defect_edit_order = &brush_order;
    brushed.v20.defect_edit_order_count = 1U;
    brushed.defect_brush_edits = &brush_edit;
    brushed.defect_brush_edit_count = 1U;
    brushed.defect_brush_strokes = &brush_stroke;
    brushed.defect_brush_stroke_count = 1U;
    brushed.defect_brush_points = brush_points.data();
    brushed.defect_brush_point_count =
        static_cast<std::uint32_t>(brush_points.size());
    std::vector<std::uint8_t> brushed_pixels(identity_pixels.size(), 0U);
    nf_develop_export_result_v2 brushed_result = make_result_v2();
    const bool brushed_preview_ok =
        nf_develop_preview_v21(
            &brushed,
            width,
            height,
            brushed_pixels.data(),
            static_cast<std::uint32_t>(brushed_pixels.size()),
            &brushed_result) == NF_STATUS_OK &&
        brushed_result.succeeded == 1U;
    expect(
        brushed_preview_ok && brushed_pixels != identity_pixels,
        "v21 Brush changes the shared preview pipeline");
    brush_edit.strength = 0.0;
    std::vector<std::uint8_t> zero_brush_pixels(identity_pixels.size(), 0U);
    nf_develop_export_result_v2 zero_brush_result = make_result_v2();
    expect(
        nf_develop_preview_v21(
            &brushed,
            width,
            height,
            zero_brush_pixels.data(),
            static_cast<std::uint32_t>(zero_brush_pixels.size()),
            &zero_brush_result) == NF_STATUS_OK &&
            zero_brush_result.succeeded == 1U && zero_brush_pixels == identity_pixels,
        "v21 Brush strength zero is pixel-identical to the source recipe");
    brush_edit.strength = 1.0;

    std::vector<std::uint8_t> infrared_core(mask.size(), 0U);
    std::vector<std::uint8_t> infrared_attenuation(mask.size() * 2U, 0U);
    for (std::size_t offset = 0U;
         offset < infrared_attenuation.size();
         offset += 2U) {
        infrared_attenuation[offset] = 0x00U;
        infrared_attenuation[offset + 1U] = 0x40U;
    }
    nf_defect_region_edit_v1 infrared_region{};
    infrared_region.enabled = 1U;
    infrared_region.roi_x = roi_x;
    infrared_region.roi_y = roi_y_up;
    infrared_region.width = roi_width;
    infrared_region.height = roi_height;
    infrared_region.mask_stride_bytes = roi_width;
    infrared_region.mask_byte_count =
        static_cast<std::uint32_t>(infrared_core.size());
    infrared_region.strength = 1.0;
    nf_defect_recipe_edit_ref_v1 infrared_order{
        NF_DEFECT_RECIPE_EDIT_REGION, 0U};
    nf_defect_infrared_edit_v1 infrared_edit{};
    infrared_edit.has_attenuation = 1U;
    infrared_edit.attenuation_stride_bytes = roi_width * 2U;
    infrared_edit.attenuation_byte_count =
        static_cast<std::uint32_t>(infrared_attenuation.size());
    nf_defect_infrared_item_v1 infrared_item{0U, 1U, 0U, 0U};
    const std::wstring infrared_output_text = infrared_output.wstring();
    nf_develop_export_request_v25 infrared = make_request_v25(
        source_text.c_str(),
        infrared_output_text.c_str(),
        NF_BASE_ESTIMATION_MANUAL);
    infrared.v24.v21.v20.v19.v18.v17.film_polarity =
        NF_FILM_POLARITY_POSITIVE;
    infrared.v24.v21.v20.v19.defect_source_file_bytes = source_bytes.size();
    infrared.v24.v21.v20.v19.defect_source_sha256 = source_identity.data();
    infrared.v24.v21.v20.v19.has_defect_source_identity = 1U;
    infrared.v24.v21.v20.v19.v18.defect_region_edits = &infrared_region;
    infrared.v24.v21.v20.v19.v18.defect_region_edit_count = 1U;
    infrared.v24.v21.v20.v19.v18.defect_mask_bytes = infrared_core.data();
    infrared.v24.v21.v20.v19.v18.defect_mask_byte_count =
        static_cast<std::uint32_t>(infrared_core.size());
    infrared.v24.v21.v20.defect_edit_order = &infrared_order;
    infrared.v24.v21.v20.defect_edit_order_count = 1U;
    infrared.v24.defect_infrared_edits = &infrared_edit;
    infrared.v24.defect_infrared_edit_count = 1U;
    infrared.v24.defect_infrared_attenuation_bytes = infrared_attenuation.data();
    infrared.v24.defect_infrared_attenuation_byte_count =
        static_cast<std::uint32_t>(infrared_attenuation.size());
    infrared.defect_infrared_items = &infrared_item;
    infrared.defect_infrared_item_count = 1U;
    std::vector<std::uint8_t> infrared_pixels(identity_pixels.size(), 0U);
    nf_develop_export_result_v3 infrared_preview_result = make_result_v3();
    const bool infrared_preview_ok =
        nf_develop_preview_v25(
            &infrared,
            nullptr,
            width,
            height,
            infrared_pixels.data(),
            static_cast<std::uint32_t>(infrared_pixels.size()),
            nullptr,
            &infrared_preview_result) == NF_STATUS_OK &&
        infrared_preview_result.succeeded == 1U;
    bool infrared_changed_inside = false;
    bool infrared_unchanged_outside = true;
    if (infrared_preview_ok) {
        for (std::uint32_t y = 0U; y < height; ++y) {
            for (std::uint32_t x = 0U; x < width; ++x) {
                const std::size_t offset =
                    (static_cast<std::size_t>(y) * width + x) * 4U;
                const bool changed = std::memcmp(
                    identity_pixels.data() + offset,
                    infrared_pixels.data() + offset,
                    4U) != 0;
                const bool inside = x >= roi_x && x < roi_x + roi_width &&
                    y >= roi_top && y < roi_top + roi_height;
                infrared_changed_inside =
                    infrared_changed_inside || (inside && changed);
                infrared_unchanged_outside =
                    infrared_unchanged_outside && (inside || !changed);
            }
        }
    }
    expect(
        infrared_preview_ok && infrared_changed_inside &&
            infrared_unchanged_outside,
        "v25 attenuation-only infrared replay changes only its ROI with a zero core");
    infrared_region.strength = 0.0;
    std::vector<std::uint8_t> zero_infrared_pixels(identity_pixels.size(), 0U);
    nf_develop_export_result_v3 zero_infrared_result = make_result_v3();
    expect(
        nf_develop_preview_v25(
            &infrared,
            nullptr,
            width,
            height,
            zero_infrared_pixels.data(),
            static_cast<std::uint32_t>(zero_infrared_pixels.size()),
            nullptr,
            &zero_infrared_result) == NF_STATUS_OK &&
            zero_infrared_result.succeeded == 1U &&
            zero_infrared_pixels == identity_pixels,
        "v25 Infrared strength zero is pixel-identical to the source recipe");
    infrared_region.strength = 1.0;

    const std::wstring calibrated_output_text = calibrated_output.wstring();
    nf_develop_export_request_v27 calibrated;
    std::memset(&calibrated, 0, sizeof(calibrated));
    calibrated.v26.v25 = infrared;
    calibrated.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
        .struct_size = static_cast<std::uint32_t>(sizeof(calibrated));
    calibrated.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
        .destination_path = calibrated_output_text.c_str();
    auto& calibrated_v10 =
        calibrated.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10;
    calibrated_v10.texture_grain = 0.35F;
    calibrated_v10.texture_sharpness = 0.45F;
    calibrated_v10.texture_clarity = -0.25F;
    calibrated_v10.texture_halation = 0.30F;
    calibrated_v10.texture_vignette = 0.20F;
    calibrated_v10.v9.noise_reduction_strength = 0.70F;
    calibrated_v10.v9.noise_reduction_luma = 0.65F;
    calibrated_v10.v9.noise_reduction_chroma = 0.40F;
    calibrated_v10.v9.noise_reduction_dark_tone = 0.55F;
    calibrated_v10.v9.noise_reduction_detail = 0.75F;
    calibrated_v10.v9.noise_reduction_grain_protect = 0.15F;
    calibrated.primary_calibration_red_hue = 0.20F;
    calibrated.primary_calibration_red_saturation = -0.15F;
    calibrated.primary_calibration_green_hue = 0.10F;
    calibrated.primary_calibration_green_saturation = 0.20F;
    calibrated.primary_calibration_blue_hue = -0.30F;
    calibrated.primary_calibration_blue_saturation = 0.25F;
    std::vector<std::uint8_t> calibrated_pixels(identity_pixels.size(), 0U);
    nf_develop_export_result_v3 calibrated_preview_result = make_result_v3();
    const bool calibrated_preview_ok =
        nf_develop_preview_v27(
            &calibrated,
            nullptr,
            width,
            height,
            calibrated_pixels.data(),
            static_cast<std::uint32_t>(calibrated_pixels.size()),
            nullptr,
            &calibrated_preview_result) == NF_STATUS_OK &&
        calibrated_preview_result.succeeded == 1U;
    nf_develop_export_result_v3 calibrated_export_result = make_result_v3();
    const bool calibrated_export_ok =
        nf_develop_export_v27(&calibrated, nullptr, &calibrated_export_result) ==
            NF_STATUS_OK &&
        calibrated_export_result.succeeded == 1U;
    const std::vector<std::uint8_t> calibrated_export_pixels =
        calibrated_export_ok
            ? decode_png_bgra8(calibrated_output, width, height)
            : std::vector<std::uint8_t>{};
    unsigned maximum_calibrated_difference = 0U;
    if (calibrated_export_pixels.size() == calibrated_pixels.size()) {
        for (std::size_t index = 0U; index < calibrated_pixels.size(); ++index) {
            maximum_calibrated_difference = std::max(
                maximum_calibrated_difference,
                static_cast<unsigned>(std::abs(
                    static_cast<int>(calibrated_export_pixels[index]) -
                    static_cast<int>(calibrated_pixels[index]))));
        }
    }
    expect(
        calibrated_preview_ok && calibrated_export_ok &&
            calibrated_pixels != infrared_pixels &&
            calibrated_export_pixels.size() == calibrated_pixels.size() &&
            maximum_calibrated_difference <= 1U,
        "v27 calibration, denoise and texture share the TIFF preview and export recipe");

    std::array<std::uint8_t, 32U> wrong_digest = source_identity;
    wrong_digest[0] ^= 0xffU;
    nf_develop_export_request_v19 mismatched = bound;
    mismatched.defect_source_sha256 = wrong_digest.data();
    std::vector<std::uint8_t> mismatched_pixels(identity_pixels.size(), 0U);
    nf_develop_export_result_v2 mismatched_result = make_result_v2();
    expect(
        nf_develop_preview_v19(
            &mismatched,
            width,
            height,
            mismatched_pixels.data(),
            static_cast<std::uint32_t>(mismatched_pixels.size()),
            &mismatched_result) == NF_STATUS_OK &&
            mismatched_result.succeeded == 0U &&
            mismatched_result.failed_stage ==
                NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE &&
            std::strcmp(
                mismatched_result.failure_name,
                "defect_source_identity_mismatch") == 0,
        "v19 mismatched source identity fails before decode and repair");
    if (repaired_preview_ok) {
        bool changed_inside = false;
        bool unchanged_outside = true;
        for (std::uint32_t y = 0U; y < height; ++y) {
            for (std::uint32_t x = 0U; x < width; ++x) {
                const std::size_t offset =
                    (static_cast<std::size_t>(y) * width + x) * 4U;
                const bool changed = std::memcmp(
                    identity_pixels.data() + offset,
                    repaired_pixels.data() + offset,
                    4U) != 0;
                const bool inside = x >= roi_x && x < roi_x + roi_width &&
                    y >= roi_top && y < roi_top + roi_height;
                changed_inside = changed_inside || (inside && changed);
                unchanged_outside = unchanged_outside && (inside || !changed);
            }
        }
        expect(
            changed_inside && unchanged_outside,
            "v18 converts bottom-origin ROI y and confines repair to that raw region");
    }

    nf_defect_region_edit_v1 outside = edit;
    outside.roi_x = width - roi_width + 1U;
    nf_develop_export_request_v18 invalid = repaired;
    invalid.defect_region_edits = &outside;
    std::vector<std::uint8_t> invalid_pixels(identity_pixels.size(), 0U);
    nf_develop_export_result_v2 invalid_result = make_result_v2();
    expect(
        nf_develop_preview_v18(
            &invalid,
            width,
            height,
            invalid_pixels.data(),
            static_cast<std::uint32_t>(invalid_pixels.size()),
            &invalid_result) == NF_STATUS_OK &&
            invalid_result.succeeded == 0U &&
            invalid_result.failed_stage ==
                NF_DEVELOP_STAGE_DEFECT_COMPONENT_REPAIR &&
            std::strcmp(invalid_result.failure_name, "invalid_argument") == 0,
        "v18 out-of-frame ROI fails closed at the component repair stage");

    const std::wstring identity_output_text = identity_output.wstring();
    nf_develop_export_request_v18 identity_export = make_request_v18(
        source_text.c_str(),
        identity_output_text.c_str(),
        NF_BASE_ESTIMATION_MANUAL);
    identity_export.v17.film_polarity = NF_FILM_POLARITY_POSITIVE;
    nf_develop_export_result_v2 identity_export_result = make_result_v2();
    const bool identity_export_ok =
        nf_develop_export_v18(&identity_export, &identity_export_result) ==
            NF_STATUS_OK &&
        identity_export_result.succeeded == 1U;

    const std::wstring jpeg_output_text = jpeg_output.wstring();
    nf_develop_export_request_v28 jpeg_export = make_request_v28(
        source_text.c_str(), jpeg_output_text.c_str(), NF_BASE_ESTIMATION_MANUAL);
    jpeg_export.v27.v26.v25.v24.v21.v20.v19.v18.v17.film_polarity =
        NF_FILM_POLARITY_POSITIVE;
    jpeg_export.v27.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
        .output_format = NF_EXPORT_FORMAT_JPEG8;
    jpeg_export.jpeg_quality = 0.96F;
    jpeg_export.output_dpi = 300U;
    nf_develop_export_result_v3 jpeg_export_result = make_result_v3();
    const bool jpeg_export_ok =
        nf_develop_export_v28(&jpeg_export, nullptr, &jpeg_export_result) == NF_STATUS_OK &&
        jpeg_export_result.succeeded == 1U;
    expect(
        jpeg_export_ok && jpeg_export_result.image_width == width &&
            jpeg_export_result.image_height == height &&
            jpeg_export_result.output_file_bytes != 0U &&
            std::filesystem::exists(jpeg_output),
        "v28 JPEG export publishes the shared develop result");

    const std::wstring longedge_output_text = longedge_output.wstring();
    nf_develop_export_request_v29 longedge_export = make_request_v29(
        source_text.c_str(), longedge_output_text.c_str(), NF_BASE_ESTIMATION_MANUAL);
    longedge_export.v28.v27.v26.v25.v24.v21.v20.v19.v18.v17.film_polarity =
        NF_FILM_POLARITY_POSITIVE;
    longedge_export.output_long_edge = 32U;
    nf_develop_export_result_v3 longedge_export_result = make_result_v3();
    const bool longedge_export_ok =
        nf_develop_export_v29(&longedge_export, nullptr, &longedge_export_result) ==
            NF_STATUS_OK &&
        longedge_export_result.succeeded == 1U;
    expect(
        longedge_export_ok && longedge_export_result.image_width == 32U &&
            longedge_export_result.image_height == 32U &&
            longedge_export_result.output_file_bytes != 0U &&
            decode_png_bgra8(longedge_output, 32U, 32U).size() == 32U * 32U * 4U,
        "v29 long-edge cap rescales the published PNG in the shared output path");

    const std::wstring cloned_output_text = cloned_output.wstring();
    cloned.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.destination_path =
        cloned_output_text.c_str();
    nf_develop_export_result_v2 cloned_export_result = make_result_v2();
    const bool cloned_export_ok =
        nf_develop_export_v20(&cloned, &cloned_export_result) == NF_STATUS_OK &&
        cloned_export_result.succeeded == 1U;
    expect(
        identity_export_ok && cloned_export_ok &&
            read_file(identity_output) != read_file(cloned_output),
        "v20 Clone Stamp changes the shared export pipeline");

    const std::wstring brushed_output_text = brushed_output.wstring();
    brushed.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.destination_path =
        brushed_output_text.c_str();
    nf_develop_export_result_v2 brushed_export_result = make_result_v2();
    const bool brushed_export_ok =
        nf_develop_export_v21(&brushed, &brushed_export_result) == NF_STATUS_OK &&
        brushed_export_result.succeeded == 1U;
    expect(
        identity_export_ok && brushed_export_ok &&
            read_file(identity_output) != read_file(brushed_output),
        "v21 Brush changes the shared export pipeline");

    nf_develop_export_result_v3 infrared_export_result = make_result_v3();
    const bool infrared_export_ok =
        nf_develop_export_v25(
            &infrared, nullptr, &infrared_export_result) == NF_STATUS_OK &&
        infrared_export_result.succeeded == 1U;
    const std::vector<std::uint8_t> infrared_export_pixels =
        infrared_export_ok
            ? decode_png_bgra8(infrared_output, width, height)
            : std::vector<std::uint8_t>{};
    unsigned maximum_infrared_difference = 0U;
    if (infrared_export_pixels.size() == infrared_pixels.size()) {
        for (std::size_t index = 0U; index < infrared_pixels.size(); ++index) {
            maximum_infrared_difference = std::max(
                maximum_infrared_difference,
                static_cast<unsigned>(std::abs(
                    static_cast<int>(infrared_export_pixels[index]) -
                    static_cast<int>(infrared_pixels[index]))));
        }
    }
    expect(
        infrared_preview_ok && infrared_export_ok &&
            infrared_export_pixels.size() == infrared_pixels.size() &&
            maximum_infrared_difference <= 1U,
        "v25 infrared preview and PNG16 export agree at 8-bit codec quantization");

    const std::wstring repaired_output_text = repaired_output.wstring();
    nf_develop_export_request_v19 repaired_export = bound;
    repaired_export.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.destination_path =
        repaired_output_text.c_str();
    nf_develop_export_result_v2 repaired_export_result = make_result_v2();
    const bool repaired_export_ok =
        nf_develop_export_v19(&repaired_export, &repaired_export_result) ==
            NF_STATUS_OK &&
        repaired_export_result.succeeded == 1U;
    expect(
        identity_export_ok && repaired_export_ok,
        "v18 identity and repaired exports both publish");
    if (identity_export_ok && repaired_export_ok) {
        const std::vector<std::uint8_t> identity_file = read_file(identity_output);
        const std::vector<std::uint8_t> repaired_file = read_file(repaired_output);
        expect(
            !identity_file.empty() && !repaired_file.empty() &&
                identity_file != repaired_file,
            "v19 source-bound region repair changes the shared export pipeline");
    }

    const std::wstring mismatched_output_text = mismatched_output.wstring();
    mismatched.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.destination_path =
        mismatched_output_text.c_str();
    mismatched_result = make_result_v2();
    expect(
        nf_develop_export_v19(&mismatched, &mismatched_result) == NF_STATUS_OK &&
            mismatched_result.succeeded == 0U &&
            mismatched_result.failed_stage ==
                NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE &&
            !std::filesystem::exists(mismatched_output),
        "v19 source mismatch publishes no output artifact");
    expect(
        read_file(source) == source_bytes,
        "ordered defect preview and export leave the source TIFF byte-exact");
    std::array<std::uint8_t, 32U> source_identity_after{};
    const std::vector<std::uint8_t> source_bytes_after = read_file(source);
    expect(
        sha256(source_bytes_after, source_identity_after) &&
            source_identity_after == source_identity,
        "v25 infrared preview and export preserve the source SHA-256");

    std::filesystem::remove(source, ignored);
    std::filesystem::remove(identity_output, ignored);
    std::filesystem::remove(repaired_output, ignored);
    std::filesystem::remove(mismatched_output, ignored);
    std::filesystem::remove(cloned_output, ignored);
    std::filesystem::remove(brushed_output, ignored);
    std::filesystem::remove(infrared_output, ignored);
    std::filesystem::remove(calibrated_output, ignored);
    std::filesystem::remove(jpeg_output, ignored);
    std::filesystem::remove(longedge_output, ignored);
}

}  // namespace negaflow::develop_export_abi_tests
