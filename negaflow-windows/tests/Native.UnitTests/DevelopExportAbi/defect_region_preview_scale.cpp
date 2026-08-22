#include "synthetic_wic_tiff.h"
#include "develop_export_abi_test_support.h"

namespace negaflow::develop_export_abi_tests {

/// region 과 infrared 편집의 ROI·마스크는 원본 화소 좌표입니다. 프리뷰 디코드가 대상 크기로
/// 줄어들면 그 좌표가 작아진 이미지 밖으로 나가 defect 단계가 통째로 invalid_argument 로
/// 끝났습니다. 실제 카탈로그의 OpticFilm8100_frame_7 은 5088x3401 기준 roi (1332,3340) 52x36 을
/// 들고 있어 1536 프리뷰에서 매번 실패했고, 화면에 아무것도 뜨지 않았습니다.
///
/// 여기서는 스케일러가 실제로 도는 16-bit RGBA 원본으로 두 방향을 함께 봅니다. 원본 좌표 편집이
/// 있으면 축소하지 않아 프리뷰가 성공해야 하고, 없으면 예전처럼 대상 크기로 줄어야 합니다.
void test_defect_region_preview_keeps_source_coordinates() {
    constexpr std::uint32_t width = 64U;
    constexpr std::uint32_t height = 64U;
    constexpr std::uint32_t preview_edge = 16U;
    const std::filesystem::path source =
        std::filesystem::temp_directory_path() /
        L"negaflow-abi-defect-preview-scale.tif";
    std::error_code ignored{};
    std::filesystem::remove(source, ignored);

    const std::vector<std::uint8_t> source_bytes =
        negaflow::test_fixtures::make_uncompressed_rgba16_defect_tiff(width, height);
    expect(
        !source_bytes.empty() && write_file(source, source_bytes),
        "defect preview scale fixture is written");

    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v18 plain =
        make_request_v18(source_text.c_str(), nullptr, NF_BASE_ESTIMATION_MANUAL);
    plain.v17.film_polarity = NF_FILM_POLARITY_POSITIVE;

    std::vector<std::uint8_t> pixels(
        static_cast<std::size_t>(width) * height * 4U,
        0U);
    nf_develop_export_result_v2 plain_result = make_result_v2();
    expect(
        nf_develop_preview_v18(
            &plain,
            preview_edge,
            preview_edge,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            &plain_result) == NF_STATUS_OK &&
            plain_result.succeeded == 1U &&
            plain_result.image_width == preview_edge &&
            plain_result.image_height == preview_edge,
        "a preview without source-pixel defects still decodes at the preview size");

    // 이 fixture 의 흠집은 x 31~32, 아래로 센 y 40~55 입니다. ROI 는 그 자리를 덮되
    // roi_x 24 가 프리뷰 상자 16 밖이므로, 축소가 걸리면 반드시 실패하는 배치입니다.
    constexpr std::uint32_t roi_x = 24U;
    constexpr std::uint32_t roi_width = 16U;
    constexpr std::uint32_t roi_height = 16U;
    constexpr std::uint32_t roi_top = 40U;
    constexpr std::uint32_t roi_y = height - roi_top - roi_height;
    std::vector<std::uint8_t> mask(
        static_cast<std::size_t>(roi_width) * roi_height,
        0U);
    for (std::uint32_t y = 0U; y < roi_height; ++y) {
        mask[static_cast<std::size_t>(y) * roi_width + 7U] = 0xffU;
        mask[static_cast<std::size_t>(y) * roi_width + 8U] = 0xffU;
    }
    nf_defect_region_edit_v1 edit{};
    edit.enabled = 1U;
    edit.roi_x = roi_x;
    edit.roi_y = roi_y;
    edit.width = roi_width;
    edit.height = roi_height;
    edit.mask_stride_bytes = roi_width;
    edit.mask_byte_count = static_cast<std::uint32_t>(mask.size());
    edit.strength = 1.0;

    nf_develop_export_request_v18 repaired = plain;
    repaired.defect_region_edits = &edit;
    repaired.defect_region_edit_count = 1U;
    repaired.defect_mask_bytes = mask.data();
    repaired.defect_mask_byte_count = static_cast<std::uint32_t>(mask.size());

    std::vector<std::uint8_t> repaired_pixels(pixels.size(), 0U);
    nf_develop_export_result_v2 repaired_result = make_result_v2();
    expect(
        nf_develop_preview_v18(
            &repaired,
            preview_edge,
            preview_edge,
            repaired_pixels.data(),
            static_cast<std::uint32_t>(repaired_pixels.size()),
            &repaired_result) == NF_STATUS_OK &&
            repaired_result.succeeded == 1U,
        "a source-coordinate region ROI outside the preview box still previews");
    expect(
        repaired_result.image_width == preview_edge &&
            repaired_result.image_height == preview_edge,
        "the source-pixel defect preview still delivers the requested preview size");
    expect(
        repaired_pixels != pixels,
        "the region repair reaches the preview pixels at the full source ROI");

    std::filesystem::remove(source, ignored);
}

}  // namespace negaflow::develop_export_abi_tests
