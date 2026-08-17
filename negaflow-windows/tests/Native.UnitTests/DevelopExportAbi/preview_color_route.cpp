#include "develop_export_abi_test_support.h"

namespace negaflow::develop_export_abi_tests {

void test_v13_color_model_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v13 baseline =
        make_request_v13(source_text.c_str(), nullptr);
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> baseline_pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    nf_develop_export_result_v2 baseline_result = make_result_v2();
    expect(
        nf_develop_preview_v13(
            &baseline,
            box,
            box,
            baseline_pixels.data(),
            static_cast<std::uint32_t>(baseline_pixels.size()),
            &baseline_result) == NF_STATUS_OK && baseline_result.succeeded == 1U,
        "v13 identity preview succeeds");

    nf_develop_export_request_v13 request = baseline;
    request.warmth = 0.7F;
    request.tint = -0.35F;
    request.color_depth = 0.4F;
    request.vibrance = 0.3F;
    request.saturation = 0.2F;
    request.red_primary = 0.1F;
    request.green_primary = -0.1F;
    request.blue_primary = 0.15F;
    std::vector<std::uint8_t> pixels(baseline_pixels.size(), 0U);
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_preview_v13(
            &request,
            box,
            box,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            &result) == NF_STATUS_OK && result.succeeded == 1U &&
            pixels != baseline_pixels,
        "v13 ColorModel changes the shared preview pipeline");
}

void test_v14_scene_correction_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v14 baseline =
        make_request_v14(source_text.c_str(), nullptr);
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> baseline_pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    nf_develop_export_result_v2 baseline_result = make_result_v2();
    expect(
        nf_develop_preview_v14(
            &baseline,
            box,
            box,
            baseline_pixels.data(),
            static_cast<std::uint32_t>(baseline_pixels.size()),
            &baseline_result) == NF_STATUS_OK && baseline_result.succeeded == 1U,
        "v14 identity preview succeeds");

    nf_develop_export_request_v14 request = baseline;
    request.auto_levels = 1U;
    request.auto_neutral_balance = 1U;
    std::vector<std::uint8_t> pixels(baseline_pixels.size(), 0U);
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_preview_v14(
            &request,
            box,
            box,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            &result) == NF_STATUS_OK && result.succeeded == 1U &&
            pixels != baseline_pixels,
        "v14 scene correction changes the shared preview pipeline");
}

void test_v15_develop_target_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v15 baseline =
        make_request_v15(source_text.c_str(), nullptr);
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> baseline_pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    nf_develop_export_result_v2 baseline_result = make_result_v2();
    expect(
        nf_develop_preview_v15(
            &baseline,
            box,
            box,
            baseline_pixels.data(),
            static_cast<std::uint32_t>(baseline_pixels.size()),
            &baseline_result) == NF_STATUS_OK && baseline_result.succeeded == 1U,
        "v15 MAIN target reaches the shared preview pipeline");

    std::vector<std::vector<std::uint8_t>> target_outputs;
    for (const std::uint32_t target : {
             NF_DEVELOP_TARGET_NORITSU,
             NF_DEVELOP_TARGET_SP3000,
             NF_DEVELOP_TARGET_F135,
             NF_DEVELOP_TARGET_HR}) {
        nf_develop_export_request_v15 request = baseline;
        request.develop_target = target;
        std::vector<std::uint8_t> pixels(baseline_pixels.size(), 0U);
        nf_develop_export_result_v2 result = make_result_v2();
        expect(
            nf_develop_preview_v15(
                &request,
                box,
                box,
                pixels.data(),
                static_cast<std::uint32_t>(pixels.size()),
                &result) == NF_STATUS_OK && result.succeeded == 1U &&
                pixels != baseline_pixels,
            "v15 scanner target changes the shared preview pixels");
        target_outputs.push_back(std::move(pixels));
    }
    expect(target_outputs[0] != target_outputs[1] &&
               target_outputs[1] != target_outputs[2] &&
               target_outputs[2] != target_outputs[3],
           "v15 scanner targets remain distinct in shared preview");

    nf_develop_export_request_v15 rescue = baseline;
    rescue.develop_target = NF_DEVELOP_TARGET_RESCUE;
    std::vector<std::uint8_t> rescue_pixels(baseline_pixels.size(), 0U);
    nf_develop_export_result_v2 rescue_result = make_result_v2();
    expect(
        nf_develop_preview_v15(
            &rescue,
            box,
            box,
            rescue_pixels.data(),
            static_cast<std::uint32_t>(rescue_pixels.size()),
            &rescue_result) == NF_STATUS_OK && rescue_result.succeeded == 1U,
        "v15 Rescue target reaches the shared preview pipeline");
}

void test_v16_scanner_profile_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> baseline_pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    std::vector<std::uint8_t> profile_pixels(baseline_pixels.size(), 0U);

    nf_develop_export_request_v16 baseline =
        make_request_v16(source_text.c_str(), nullptr);
    nf_develop_export_result_v2 baseline_result = make_result_v2();
    expect(
        nf_develop_preview_v16(
            &baseline,
            box,
            box,
            baseline_pixels.data(),
            static_cast<std::uint32_t>(baseline_pixels.size()),
            &baseline_result) == NF_STATUS_OK && baseline_result.succeeded == 1U,
        "v16 baseline preview succeeds");

    nf_develop_export_request_v16 profiled = baseline;
    profiled.scanner_profile_id =
        L"noritsu__color-nega__kodak-ultramax-400";
    nf_develop_export_result_v2 profile_result = make_result_v2();
    expect(
        nf_develop_preview_v16(
            &profiled,
            box,
            box,
            profile_pixels.data(),
            static_cast<std::uint32_t>(profile_pixels.size()),
            &profile_result) == NF_STATUS_OK && profile_result.succeeded == 1U &&
            profile_pixels != baseline_pixels,
        "v16 scanner profile changes the shared preview pixels");

    nf_develop_export_request_v16 common_target = baseline;
    common_target.v15.develop_target = NF_DEVELOP_TARGET_NORITSU;
    std::vector<std::uint8_t> common_target_pixels(baseline_pixels.size(), 0U);
    nf_develop_export_result_v2 common_target_result = make_result_v2();
    expect(
        nf_develop_preview_v16(
            &common_target,
            box,
            box,
            common_target_pixels.data(),
            static_cast<std::uint32_t>(common_target_pixels.size()),
            &common_target_result) == NF_STATUS_OK &&
            common_target_result.succeeded == 1U,
        "v16 NORITSU common relative target preview succeeds");

    nf_develop_export_request_v16 matched_target = common_target;
    matched_target.scanner_profile_id =
        L"noritsu__color-nega__kodak-ektar-100";
    std::vector<std::uint8_t> matched_target_pixels(baseline_pixels.size(), 0U);
    nf_develop_export_result_v2 matched_target_result = make_result_v2();
    expect(
        nf_develop_preview_v16(
            &matched_target,
            box,
            box,
            matched_target_pixels.data(),
            static_cast<std::uint32_t>(matched_target_pixels.size()),
            &matched_target_result) == NF_STATUS_OK &&
            matched_target_result.succeeded == 1U &&
            matched_target_pixels != common_target_pixels,
        "v16 matched profile selects a distinct scanner target signature");
}

void test_v17_positive_film_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> negative_pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    std::vector<std::uint8_t> positive_pixels(negative_pixels.size(), 0U);

    nf_develop_export_request_v17 negative =
        make_request_v17(source_text.c_str(), nullptr);
    nf_develop_export_result_v2 negative_result = make_result_v2();
    expect(
        nf_develop_preview_v17(
            &negative,
            box,
            box,
            negative_pixels.data(),
            static_cast<std::uint32_t>(negative_pixels.size()),
            &negative_result) == NF_STATUS_OK && negative_result.succeeded == 1U,
        "v17 negative film preview succeeds");

    nf_develop_export_request_v17 positive = negative;
    positive.film_polarity = NF_FILM_POLARITY_POSITIVE;
    nf_develop_export_result_v2 positive_result = make_result_v2();
    expect(
        nf_develop_preview_v17(
            &positive,
            box,
            box,
            positive_pixels.data(),
            static_cast<std::uint32_t>(positive_pixels.size()),
            &positive_result) == NF_STATUS_OK && positive_result.succeeded == 1U &&
            positive_pixels != negative_pixels,
        "v17 positive film bypasses negative inversion");

    nf_develop_export_request_v17 monochrome = positive;
    monochrome.v16.v15.v14.v13.v12.v11.v10.v9.v8.film_type =
        NF_FILM_TYPE_BLACK_AND_WHITE;
    std::vector<std::uint8_t> monochrome_pixels(negative_pixels.size(), 0U);
    nf_develop_export_result_v2 monochrome_result = make_result_v2();
    expect(
        nf_develop_preview_v17(
            &monochrome,
            box,
            box,
            monochrome_pixels.data(),
            static_cast<std::uint32_t>(monochrome_pixels.size()),
            &monochrome_result) == NF_STATUS_OK &&
            monochrome_result.succeeded == 1U,
        "v17 black-and-white positive film preview succeeds");
    expect(
        preview_is_neutral(monochrome_pixels),
        "v17 black-and-white positive output is neutral");
}

// The point of v22 is that a long call can be stopped and watched. Both facilities are
// checked against a real decode/develop/publish run, not a stub, because the interesting

}  // namespace negaflow::develop_export_abi_tests
