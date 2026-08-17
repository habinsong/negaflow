#include "develop_export_abi_test_support.h"

namespace negaflow::develop_export_abi_tests {

void test_v3_basic_tone_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v3 neutral = make_request_v3(source_text.c_str(), nullptr);
    nf_develop_export_request_v3 adjusted = neutral;
    adjusted.density = 0.75F;
    adjusted.highlight = -0.50F;
    adjusted.shadow = 0.50F;
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> neutral_pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    std::vector<std::uint8_t> adjusted_pixels(neutral_pixels.size(), 0U);
    nf_develop_export_result_v2 neutral_result = make_result_v2();
    nf_develop_export_result_v2 adjusted_result = make_result_v2();

    expect(
        nf_develop_preview_v3(
            &neutral,
            box,
            box,
            neutral_pixels.data(),
            static_cast<std::uint32_t>(neutral_pixels.size()),
            &neutral_result) == NF_STATUS_OK && neutral_result.succeeded == 1U,
        "v3 neutral preview succeeds");
    expect(
        nf_develop_preview_v3(
            &adjusted,
            box,
            box,
            adjusted_pixels.data(),
            static_cast<std::uint32_t>(adjusted_pixels.size()),
            &adjusted_result) == NF_STATUS_OK && adjusted_result.succeeded == 1U,
        "v3 Basic Tone preview succeeds");
    expect(
        neutral_result.image_width == adjusted_result.image_width &&
            neutral_result.image_height == adjusted_result.image_height &&
            neutral_pixels != adjusted_pixels,
        "v3 Basic Tone changes preview pixels");
}

void test_v4_film_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v4 request = make_request_v4(
        source_text.c_str(), nullptr, NF_BASE_ESTIMATION_PRESET);
    request.film_stock_dmin_id = L"kodak-portra-400";
    request.light_source_profile_id = L"warm-led";
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_preview_v4(
            &request,
            box,
            box,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            &result) == NF_STATUS_OK && result.succeeded == 1U,
        "v4 Film preview succeeds");
    expect(
        result.base_source == NF_DEVELOP_BASE_SOURCE_PRESET_MEASURED ||
            result.base_source == NF_DEVELOP_BASE_SOURCE_PRESET_FALLBACK,
        "v4 Film preview reports measured-or-fallback provenance");
    expect(
        result.applied_dmin[0] > 0.0F && result.applied_dmin[1] > 0.0F &&
            result.applied_dmin[2] > 0.0F,
        "v4 Film preview reports applied base");
}

void test_v5_point_curve_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v5 neutral = make_request_v5(source_text.c_str(), nullptr);
    nf_develop_export_request_v5 adjusted = neutral;
    adjusted.point_curve_rgb.point_count = 3U;
    adjusted.point_curve_rgb.points[0U] = {0.0, 0.0};
    adjusted.point_curve_rgb.points[1U] = {0.5, 0.65};
    adjusted.point_curve_rgb.points[2U] = {1.0, 1.0};
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> neutral_pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    std::vector<std::uint8_t> adjusted_pixels(neutral_pixels.size(), 0U);
    nf_develop_export_result_v2 neutral_result = make_result_v2();
    nf_develop_export_result_v2 adjusted_result = make_result_v2();

    expect(
        nf_develop_preview_v5(
            &neutral, box, box, neutral_pixels.data(),
            static_cast<std::uint32_t>(neutral_pixels.size()), &neutral_result) == NF_STATUS_OK &&
            neutral_result.succeeded == 1U,
        "v5 neutral preview succeeds");
    expect(
        nf_develop_preview_v5(
            &adjusted, box, box, adjusted_pixels.data(),
            static_cast<std::uint32_t>(adjusted_pixels.size()), &adjusted_result) == NF_STATUS_OK &&
            adjusted_result.succeeded == 1U,
        "v5 Point Curve preview succeeds");
    expect(
        neutral_result.image_width == adjusted_result.image_width &&
            neutral_result.image_height == adjusted_result.image_height &&
            neutral_pixels != adjusted_pixels,
        "v5 Point Curve changes preview pixels");
}

void test_v6_color_mixer_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v6 neutral = make_request_v6(source_text.c_str(), nullptr);
    nf_develop_export_request_v6 adjusted = neutral;
    adjusted.color_mixer_saturation[0U] = -0.75F;
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> neutral_pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    std::vector<std::uint8_t> adjusted_pixels(neutral_pixels.size(), 0U);
    nf_develop_export_result_v2 neutral_result = make_result_v2();
    nf_develop_export_result_v2 adjusted_result = make_result_v2();
    expect(
        nf_develop_preview_v6(
            &neutral, box, box, neutral_pixels.data(),
            static_cast<std::uint32_t>(neutral_pixels.size()), &neutral_result) == NF_STATUS_OK &&
            neutral_result.succeeded == 1U,
        "v6 neutral preview succeeds");
    expect(
        nf_develop_preview_v6(
            &adjusted, box, box, adjusted_pixels.data(),
            static_cast<std::uint32_t>(adjusted_pixels.size()), &adjusted_result) == NF_STATUS_OK &&
            adjusted_result.succeeded == 1U,
        "v6 Color Mixer preview succeeds");
    expect(
        neutral_result.image_width == adjusted_result.image_width &&
            neutral_result.image_height == adjusted_result.image_height &&
            neutral_pixels != adjusted_pixels,
        "v6 Color Mixer changes preview pixels");
}

}  // namespace negaflow::develop_export_abi_tests
