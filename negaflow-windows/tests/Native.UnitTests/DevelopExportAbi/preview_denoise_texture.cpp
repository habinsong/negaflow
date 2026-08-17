#include "develop_export_abi_test_support.h"

#include <iostream>

namespace negaflow::develop_export_abi_tests {

void test_v9_film_scan_denoise_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v9 request =
        make_request_v9(source_text.c_str(), nullptr);
    request.noise_reduction_strength = 0.7F;
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_preview_v9(
            &request,
            box,
            box,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            &result) == NF_STATUS_OK &&
            result.succeeded == 1U,
        "v9 nonzero FilmScanDenoise preview succeeds through the shared pipeline");
    // FilmScanDenoise runs its tile rows concurrently. The tiles write disjoint cores, so
    // the split must not move a pixel; this fingerprint is what makes that checkable on a
    // real scan rather than argued from the code. Forcing the whole engine inline
    // reproduces exactly this value.
    std::uint64_t fingerprint = 1469598103934665603ULL;
    for (const std::uint8_t value : pixels) {
        fingerprint = (fingerprint ^ value) * 1099511628211ULL;
    }
    std::cout << "{\"note\":\"denoise_preview_pixels\",\"fnv1a64\":\"" << std::hex
              << fingerprint << std::dec << "\"}" << std::endl;
}

void test_v10_texture_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v10 request =
        make_request_v10(source_text.c_str(), nullptr);
    request.texture_sharpness = 0.6F;
    request.texture_vignette = 0.3F;
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_preview_v10(
            &request,
            box,
            box,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            &result) == NF_STATUS_OK &&
            result.succeeded == 1U,
        "v10 Texture preview succeeds through the shared pipeline");
    // Texture's blur runs its tile rows concurrently on the same disjoint-core contract as
    // FilmScanDenoise, and its grain hashes the absolute coordinate rather than running a
    // sequence. Both claims are only worth anything if the pixels come out the same, so
    // the fingerprint is reported for comparison against a forced-inline build.
    std::uint64_t fingerprint = 1469598103934665603ULL;
    for (const std::uint8_t value : pixels) {
        fingerprint = (fingerprint ^ value) * 1099511628211ULL;
    }
    std::cout << "{\"note\":\"texture_preview_pixels\",\"fnv1a64\":\"" << std::hex
              << fingerprint << std::dec << "\",\"wall_microseconds\":"
              << result.wall_microseconds << "}" << std::endl;
}

void test_v11_bw_transform_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v11 request =
        make_request_v11(source_text.c_str(), nullptr);
    request.v10.v9.v8.film_type = NF_FILM_TYPE_BLACK_AND_WHITE;
    request.bw_toning_mode = 2U;
    request.bw_toning_shadow_hue = 32.0;
    request.bw_toning_highlight_hue = 48.0;
    request.bw_toning_strength = 0.8;
    request.image_rotation = 1U;
    request.has_crop = 1U;
    request.crop_x = 0.1;
    request.crop_y = 0.1;
    request.crop_width = 0.8;
    request.crop_height = 0.8;
    request.straighten_angle = 3.0;
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_preview_v11(
            &request,
            box,
            box,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            &result) == NF_STATUS_OK && result.succeeded == 1U &&
            result.image_width > 0U && result.image_height > 0U,
        "v11 B&W toning and ImageTransform preview succeeds through the shared pipeline");
}

void test_v11_rendered_digital_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v11 request =
        make_request_v11(source_text.c_str(), nullptr);
    request.v10.v9.v8.film_look_source_kind =
        NF_DEVELOP_SOURCE_RENDERED_DIGITAL;
    request.v10.v9.v8.film_emulation = 39U;  // Vision3 500T
    request.v10.v9.v8.film_emulation_intensity = 0.7;
    request.v10.texture_grain = 0.45F;
    request.v10.texture_halation = 0.55F;
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_preview_v11(
            &request,
            box,
            box,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            &result) == NF_STATUS_OK && result.succeeded == 1U &&
            result.film_look_route == NF_FILM_LOOK_ROUTE_DIGITAL_FILM_LOOK,
        "v11 Vision3 rendered-digital preview completes the dedicated Film Look graph");

    nf_develop_export_request_v11 black_and_white = request;
    black_and_white.v10.v9.v8.film_type = NF_FILM_TYPE_BLACK_AND_WHITE;
    black_and_white.v10.v9.v8.film_emulation = 12U;  // Tri-X 400
    std::vector<std::uint8_t> black_and_white_pixels(pixels.size(), 0U);
    nf_develop_export_result_v2 black_and_white_result = make_result_v2();
    expect(
        nf_develop_preview_v11(
            &black_and_white,
            box,
            box,
            black_and_white_pixels.data(),
            static_cast<std::uint32_t>(black_and_white_pixels.size()),
            &black_and_white_result) == NF_STATUS_OK &&
            black_and_white_result.succeeded == 1U &&
            black_and_white_result.film_look_route ==
                NF_FILM_LOOK_ROUTE_DIGITAL_FILM_LOOK,
        "v11 rendered-digital B&W preview completes the dedicated Film Look graph");
    expect(
        preview_is_neutral(black_and_white_pixels),
        "the rendered-digital B&W Film Look exports neutral RGB");
}

void test_v12_local_dodge_burn_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v12 baseline =
        make_request_v12(source_text.c_str(), nullptr);
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> baseline_pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    nf_develop_export_result_v2 baseline_result = make_result_v2();
    expect(
        nf_develop_preview_v12(
            &baseline,
            box,
            box,
            baseline_pixels.data(),
            static_cast<std::uint32_t>(baseline_pixels.size()),
            &baseline_result) == NF_STATUS_OK && baseline_result.succeeded == 1U,
        "v12 identity preview succeeds");

    nf_local_dodge_burn_point_v1 points[]{
        {0.38F, 0.50F},
        {0.62F, 0.50F},
    };
    nf_local_dodge_burn_stroke_v1 stroke{};
    stroke.point_count = 2U;
    stroke.thickness = 0.12F;
    stroke.feather = 0.02F;
    nf_local_dodge_burn_adjustment_v1 adjustment{};
    adjustment.mode = NF_LOCAL_DODGE_BURN_MODE_DODGE;
    adjustment.enabled = 1U;
    adjustment.mask_kind = NF_LOCAL_DODGE_BURN_MASK_BRUSH;
    adjustment.stroke_count = 1U;
    adjustment.amount = 0.8F;
    adjustment.center_x = 0.5F;
    adjustment.center_y = 0.5F;
    adjustment.radius = 0.25F;
    adjustment.feather = 0.25F;
    adjustment.start_x = 0.5F;
    adjustment.end_x = 0.5F;
    adjustment.end_y = 1.0F;
    nf_develop_export_request_v12 request = baseline;
    request.local_adjustments = &adjustment;
    request.local_adjustment_count = 1U;
    request.local_strokes = &stroke;
    request.local_stroke_count = 1U;
    request.local_points = points;
    request.local_point_count = 2U;
    std::vector<std::uint8_t> pixels(baseline_pixels.size(), 0U);
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_preview_v12(
            &request,
            box,
            box,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            &result) == NF_STATUS_OK && result.succeeded == 1U &&
            pixels != baseline_pixels,
        "v12 brush Local Dodge/Burn changes the shared preview pipeline");
    // The box blurs carry a running sum along each line and the application is per pixel,
    // so splitting by row and by column must not move a result. Reported so a build with
    // the engine forced inline can be compared against this value.
    std::uint64_t fingerprint = 1469598103934665603ULL;
    for (const std::uint8_t value : pixels) {
        fingerprint = (fingerprint ^ value) * 1099511628211ULL;
    }
    std::cout << "{\"note\":\"dodge_burn_preview_pixels\",\"fnv1a64\":\"" << std::hex
              << fingerprint << std::dec << "\",\"wall_microseconds\":"
              << result.wall_microseconds << "}" << std::endl;
}

}  // namespace negaflow::develop_export_abi_tests
