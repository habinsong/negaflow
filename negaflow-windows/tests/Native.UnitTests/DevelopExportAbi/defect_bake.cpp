#include "develop_export_abi_test_support.h"
#include "synthetic_wic_tiff.h"

#include "negaflow/core/tiff_probe.h"
#include "negaflow/imageio/wic_tiff_decoder.h"

#include <array>
#include <cstring>

namespace negaflow::develop_export_abi_tests {

void test_v35_defect_bake() {
    constexpr std::uint32_t width = 64U;
    constexpr std::uint32_t height = 64U;
    constexpr std::uint32_t roi_x = 24U;
    constexpr std::uint32_t roi_top = 36U;
    constexpr std::uint32_t roi_width = 16U;
    constexpr std::uint32_t roi_height = 24U;
    constexpr std::uint32_t roi_y_up = height - roi_top - roi_height;

    const std::filesystem::path temporary = std::filesystem::temp_directory_path();
    const std::filesystem::path source = temporary / L"negaflow-defect-bake-source.tif";
    const std::filesystem::path destination =
        temporary / L"negaflow-defect-bake-output.tif";
    std::error_code ignored{};
    std::filesystem::remove(source, ignored);
    std::filesystem::remove(destination, ignored);

    const std::vector<std::uint8_t> source_bytes =
        negaflow::test_fixtures::make_uncompressed_rgb16_defect_tiff(width, height);
    expect(
        !source_bytes.empty() && write_file(source, source_bytes),
        "defect bake synthetic source is written");
    if (!std::filesystem::exists(source)) {
        return;
    }

    std::array<std::uint8_t, 32U> source_sha{};
    expect(sha256(source_bytes, source_sha), "defect bake source SHA-256 is calculated");

    std::vector<std::uint8_t> mask(
        static_cast<std::size_t>(roi_width) * roi_height,
        0U);
    for (std::uint32_t source_y = (height * 5U) / 8U;
         source_y < (height * 7U) / 8U;
         ++source_y) {
        const std::uint32_t local_y = source_y - roi_top;
        mask[static_cast<std::size_t>(local_y) * roi_width + 7U] = 0xffU;
        mask[static_cast<std::size_t>(local_y) * roi_width + 8U] = 0xffU;
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
    const nf_defect_recipe_edit_ref_v1 order{NF_DEFECT_RECIPE_EDIT_REGION, 0U};

    const std::wstring source_text = source.wstring();
    const std::wstring destination_text = destination.wstring();
    nf_develop_export_request_v35 request;
    std::memset(&request, 0, sizeof(request));
    request.v34.v33.v32.v31.v30 = make_request_v30(
        source_text.c_str(),
        destination_text.c_str(),
        NF_BASE_ESTIMATION_MANUAL);
    auto& base = request.v34.v33.v32.v31.v30.v29.v28.v27.v26.v25.v24.v21.v20.v19.v18
                     .v17.v16.v15.v14.v13.v12.v11.v10.v9.v8;
    base.struct_size = static_cast<std::uint32_t>(sizeof(request));
    base.output_format = NF_EXPORT_FORMAT_TIFF16;
    request.v34.v33.v32.v31.output_bit_depth = 16U;

    auto& v18 = request.v34.v33.v32.v31.v30.v29.v28.v27.v26.v25.v24.v21.v20.v19.v18;
    v18.defect_region_edits = &edit;
    v18.defect_region_edit_count = 1U;
    v18.defect_mask_bytes = mask.data();
    v18.defect_mask_byte_count = static_cast<std::uint32_t>(mask.size());
    auto& v19 = request.v34.v33.v32.v31.v30.v29.v28.v27.v26.v25.v24.v21.v20.v19;
    v19.defect_source_file_bytes = source_bytes.size();
    v19.defect_source_sha256 = source_sha.data();
    v19.has_defect_source_identity = 1U;
    auto& v20 = request.v34.v33.v32.v31.v30.v29.v28.v27.v26.v25.v24.v21.v20;
    v20.defect_edit_order = &order;
    v20.defect_edit_order_count = 1U;
    std::array<std::uint8_t, 32U> recipe_sha{};
    expect(sha256(mask, recipe_sha), "defect bake recipe fingerprint is calculated");
    request.defect_recipe_sha256 = recipe_sha.data();
    request.defect_recipe_sha256_size = static_cast<std::uint32_t>(recipe_sha.size());

    nf_develop_export_result_v3 result = make_result_v3();
    const bool baked =
        nf_develop_bake_defects_v1(&request, nullptr, &result) == NF_STATUS_OK &&
        result.succeeded == 1U && result.image_width == width &&
        result.image_height == height && result.output_file_bytes > 0U &&
        std::filesystem::exists(destination);
    expect(baked, "v1 defect bake ABI publishes a source-sized TIFF");

    const auto probe = negaflow::core::probe_tiff_file(destination);
    expect(
        baked && probe.status == negaflow::core::TiffProbeStatus::ok &&
            probe.info.samples_per_pixel == 3U &&
            probe.info.bits_per_sample_count == 3U &&
            probe.info.bits_per_sample[0] == 16U && probe.info.compression == 1U &&
            probe.info.icc_profile_bytes > 0U,
        "defect bake ABI publishes opaque uncompressed RGB16 with ICC");

    const auto source_decoded = negaflow::imageio::decode_tiff_with_wic(source);
    const auto baked_decoded = negaflow::imageio::decode_tiff_with_wic(destination);
    bool changed_inside = false;
    bool unchanged_outside = true;
    if (source_decoded.status == negaflow::imageio::WicTiffDecodeStatus::ok &&
        baked_decoded.status == negaflow::imageio::WicTiffDecodeStatus::ok &&
        source_decoded.image.samples.size() == baked_decoded.image.samples.size()) {
        for (std::uint32_t y = 0U; y < height; ++y) {
            for (std::uint32_t x = 0U; x < width; ++x) {
                const std::size_t offset =
                    (static_cast<std::size_t>(y) * width + x) * 3U;
                const bool changed = std::memcmp(
                    source_decoded.image.samples.data() + offset,
                    baked_decoded.image.samples.data() + offset,
                    3U * sizeof(std::uint16_t)) != 0;
                const bool inside = x >= roi_x && x < roi_x + roi_width &&
                    y >= roi_top && y < roi_top + roi_height;
                changed_inside = changed_inside || (inside && changed);
                unchanged_outside = unchanged_outside && (inside || !changed);
            }
        }
    }
    expect(
        changed_inside && unchanged_outside,
        "defect bake changes only the accepted raw repair region and skips develop stages");

    std::filesystem::remove(source, ignored);
    std::filesystem::remove(destination, ignored);
}

}  // namespace negaflow::develop_export_abi_tests
