#include "negaflow/color/output_color_space.h"

#include "negaflow/color/icc_profile.h"

#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] bool near(const double left, const double right, const double tolerance) {
    return std::abs(left - right) <= tolerance;
}

// White must survive every primaries change: all three spaces share D65, so 1,1,1 in one
// is 1,1,1 in the others. A matrix that moves white is wrong no matter how it was derived.
void white_stays_white(const negaflow::color::OutputColorSpace space, const char* const name) {
    const negaflow::color::ColorMatrix matrix = negaflow::color::linear_srgb_to(space);
    for (std::size_t row = 0U; row < 3U; ++row) {
        const double sum = static_cast<double>(matrix[(row * 3U)]) +
            static_cast<double>(matrix[(row * 3U) + 1U]) +
            static_cast<double>(matrix[(row * 3U) + 2U]);
        expect(near(sum, 1.0, 1.0e-4), name);
    }
}

}  // namespace

int main() {
    using negaflow::color::OutputColorSpace;

    // sRGB is the pipeline's own space, so it must not touch the pixels at all.
    const negaflow::color::ColorMatrix identity =
        negaflow::color::linear_srgb_to(OutputColorSpace::srgb);
    for (std::size_t index = 0U; index < 9U; ++index) {
        const float expected = (index % 4U) == 0U ? 1.0F : 0.0F;
        expect(identity[index] == expected, "srgb matrix is identity");
    }

    white_stays_white(OutputColorSpace::display_p3, "display p3 keeps white");
    white_stays_white(OutputColorSpace::adobe_rgb, "adobe rgb keeps white");

    const negaflow::color::ColorMatrix p3 =
        negaflow::color::linear_srgb_to(OutputColorSpace::display_p3);
    const negaflow::color::ColorMatrix adobe =
        negaflow::color::linear_srgb_to(OutputColorSpace::adobe_rgb);
    // Both targets are wider than sRGB, so reproducing an sRGB primary needs *less* of the
    // target's more saturated primary. A coefficient above one would mean the conversion is
    // running backwards. The diagonal terms of the other channels are not a useful check —
    // where a chromaticity happens to be shared the term can land exactly on one.
    expect(p3[0] < 1.0F && p3[0] > 0.7F, "srgb red needs less display p3 red");
    expect(adobe[0] < 1.0F && adobe[0] > 0.5F, "srgb red needs less adobe rgb red");
    // Display P3 shares no primary with sRGB, so every sRGB primary becomes a mixture.
    expect(p3[1] > 0.0F && p3[3] > 0.0F, "display p3 mixes every primary");

    // Adobe RGB shares sRGB's red and blue chromaticities. That does not make the matrix
    // entry one - both systems renormalize so white lands on D65 and the wider green
    // changes that scaling - but red and blue must still pick up nothing else.
    expect(
        near(adobe[3], 0.0, 1.0e-6) && near(adobe[6], 0.0, 1.0e-6),
        "adobe rgb red stays pure");
    expect(
        near(adobe[2], 0.0, 1.0e-6) && near(adobe[5], 0.0, 1.0e-6),
        "adobe rgb blue stays pure");

    // Display P3 uses the sRGB curve; Adobe RGB uses gamma 563/256.
    expect(
        negaflow::color::encode_output_component(0.5F, OutputColorSpace::display_p3) ==
        negaflow::color::encode_output_component(0.5F, OutputColorSpace::srgb),
        "display p3 shares the srgb curve");
    expect(
        near(
            static_cast<double>(
                negaflow::color::encode_output_component(0.5F, OutputColorSpace::adobe_rgb)),
            std::pow(0.5, 256.0 / 563.0),
            1.0e-5),
        "adobe rgb uses gamma 563/256");

    for (const OutputColorSpace space : {
             OutputColorSpace::srgb,
             OutputColorSpace::display_p3,
             OutputColorSpace::adobe_rgb,
         }) {
        expect(
            negaflow::color::encode_output_component(0.0F, space) == 0.0F,
            "black encodes to black");
        expect(
            near(
                static_cast<double>(negaflow::color::encode_output_component(1.0F, space)),
                1.0,
                1.0e-5),
            "white encodes to white");

        // The generated profile has to pass the same validator a scanner profile does.
        const std::vector<std::uint8_t> profile = negaflow::color::build_icc_profile(space);
        expect(!profile.empty(), "profile is built");
        const negaflow::color::IccProfileValidationResult validated =
            negaflow::color::validate_icc_profile(profile);
        expect(
            validated.status == negaflow::color::IccProfileStatus::ok,
            "generated profile validates");
        expect(validated.info.tag_count == 9U, "profile carries every tag");
        expect(
            validated.info.declared_bytes == static_cast<std::uint32_t>(profile.size()),
            "profile declares its own size");
    }

    if (failures == 0) {
        std::cout << R"({"status":"ok","operation":"output_color_space_tests"})" << '\n';
        return 0;
    }
    std::cerr << failures << " failure(s)\n";
    return 1;
}
