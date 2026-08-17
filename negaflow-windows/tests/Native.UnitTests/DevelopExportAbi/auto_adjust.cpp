#include "negaflow/imaging/auto_adjust.h"
#include <iostream>
#include "develop_export_abi_test_support.h"

namespace negaflow::develop_export_abi_tests {

void test_auto_adjust_on_a_real_scan(const std::filesystem::path& source) {
    // Auto adjust reads a *neutral develop*, meaning the tone sliders at zero but the
    // frame otherwise properly rendered. Feeding it a default manual Dmin produces a
    // rendering that is not a photograph, and auto then correctly pushes every slider to
    // its clamp — which proves nothing about the algorithm. Auto base gives it a real
    // starting image.
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v21 request = make_request_v21(
        source_text.c_str(), nullptr, NF_BASE_ESTIMATION_AUTO);
    constexpr std::uint32_t box = 512U;
    std::vector<std::uint8_t> pixels(
        static_cast<std::size_t>(box) * box * 4U, 0U);
    nf_develop_export_result_v3 result = make_result_v3();
    expect(
        nf_develop_preview_v22(
            &request,
            box,
            box,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            nullptr,
            &result) == NF_STATUS_OK && result.succeeded == 1U,
        "the neutral develop preview auto adjust reads succeeds");

    negaflow::imaging::AutoAdjustStats stats{};
    expect(
        negaflow::imaging::compute_auto_adjust_stats(
            pixels.data(),
            result.image_width,
            result.image_height,
            static_cast<std::size_t>(result.image_width) * 4U,
            stats),
        "statistics come back from a real developed frame");

    const negaflow::imaging::AutoToneResult tone =
        negaflow::imaging::auto_tone(stats);
    const negaflow::imaging::AutoWhiteBalanceResult balance =
        negaflow::imaging::auto_white_balance(stats);
    std::cout << "{\"note\":\"auto_adjust_real_scan\",\"exposure\":" << tone.exposure
              << ",\"contrast\":" << tone.contrast
              << ",\"highlights\":" << tone.highlights
              << ",\"shadows\":" << tone.shadows
              << ",\"whites\":" << tone.whites
              << ",\"blacks\":" << tone.blacks
              << ",\"density\":" << tone.density
              << ",\"vibrance\":" << tone.vibrance
              << ",\"warmth\":" << balance.warmth
              << ",\"tint\":" << balance.tint << "}" << std::endl;

    // The engine refuses values outside these ranges, so auto must never propose one.
    expect(
        tone.exposure >= -3.0 && tone.exposure <= 3.0 &&
            tone.contrast >= -0.45 && tone.contrast <= 0.55 &&
            tone.highlights <= 0.0 && tone.highlights >= -1.0 &&
            tone.shadows >= 0.0 && tone.shadows <= 0.8 &&
            tone.whites >= -1.0 && tone.whites <= 1.0 &&
            tone.blacks >= -1.0 && tone.blacks <= 0.15 &&
            tone.density >= -0.4 && tone.density <= 0.4 &&
            tone.vibrance >= 0.0 && tone.vibrance <= 0.6,
        "every automatic tone value on a real scan is inside the engine's range");
    expect(
        balance.warmth >= -0.6 && balance.warmth <= 0.6 &&
            balance.tint >= -0.6 && balance.tint <= 0.6,
        "the automatic white balance on a real scan is inside its clamp");
}

}  // namespace negaflow::develop_export_abi_tests
