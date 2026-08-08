// Measures how much of the ColorSync/ICM input divergence survives development.
//
// colorsync_icm_parity_tests reports up to a 20x gap between the two colour
// management systems, but only in deep shadow. That gap is only worth acting on
// if it is still there after the negative is developed, because the develop
// stage works in log density and could either amplify or flatten it.
//
// This runs the committed macOS reference values and the measured Windows ICM
// values through the same develop_manual_negative the CLI uses, then reports the
// difference in the sRGB code values a viewer would actually see.

#include "colorsync_icm_parity_fixture.h"
#include "negaflow/color/srgb_transfer.h"
#include "negaflow/imaging/manual_negative_developer.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

// Measured on this machine by colorsync_icm_parity_tests, from
// baseline/colorsync-icm-parity-windows-v1.json. Every channel is kept, because
// a chromatic patch can sit inside the divergent shadow band on one channel and
// outside it on another, and that asymmetry is a hue shift rather than a
// brightness shift.
constexpr std::array<std::array<float, 3>, 34> windows_icm_linear{{
    {0.0F, 0.0F, 0.0F},
    {1.53535057e-05F, 1.53535057e-05F, 1.53535057e-05F},
    {4.60605152e-05F, 4.60605152e-05F, 4.60605152e-05F},
    {0.000187785176F, 0.000188966209F, 0.000187785176F},
    {0.00138535863F, 0.00139244471F, 0.00138299644F},
    {0.0102840895F, 0.010339465F, 0.0102672717F},
    {0.0473710001F, 0.0475117601F, 0.0473827273F},
    {0.115605287F, 0.115644731F, 0.115634874F},
    {0.217696011F, 0.217724532F, 0.217838645F},
    {0.35562101F, 0.355734974F, 0.355677992F},
    {0.53106606F, 0.531138062F, 0.531234026F},
    {0.745375037F, 0.745550513F, 0.745608985F},
    {0.999756992F, 1.0F, 0.999826491F},
    {0.999826491F, 0.000105112456F, 0.0F},
    {0.0F, 1.0F, 0.0F},
    {0.0F, 0.0F, 1.0F},
    {0.0F, 0.99993062F, 0.999895871F},
    {0.999826491F, 0.0F, 0.99996525F},
    {0.999618232F, 0.99993062F, 0.000105112456F},
    {0.999756992F, 0.217724532F, 0.217810124F},
    {0.217581883F, 0.99996525F, 0.217567667F},
    {0.217667446F, 0.217824414F, 0.999861121F},
    {0.217681736F, 1.0F, 0.999826491F},
    {0.999756992F, 0.217681736F, 1.0F},
    {0.999618232F, 0.99996525F, 0.217924282F},
    {0.750914216F, 0.52955544F, 0.405228853F},
    {0.560913563F, 0.293805361F, 0.17373313F},
    {0.153949678F, 0.0599539876F, 0.0277693216F},
    {0.893016398F, 0.893276334F, 0.893406391F},
    {0.956210136F, 0.956446946F, 0.956649899F},
    {0.0290961321F, 0.000188966209F, 0.000243293995F},
    {0.000230302569F, 0.000511389808F, 0.0289156754F},
    {0.00334528717F, 0.00336404541F, 0.00334154186F},
    {4.60605152e-05F, 4.60605152e-05F, 6.14140226e-05F},
}};

[[nodiscard]] negaflow::imaging::WorkingImage build_row(const bool use_macos) {
    const auto& patches = negaflow::fixtures::colorsync_icm_parity_patches;
    negaflow::imaging::WorkingImage image{};
    image.width = static_cast<std::uint32_t>(patches.size());
    image.height = 1U;
    image.stride_pixels = image.width;
    image.pixels.reserve(patches.size());
    for (std::size_t index = 0U; index < patches.size(); ++index) {
        const std::array<float, 3>& source =
            use_macos ? patches[index].macos_linear : windows_icm_linear[index];
        image.pixels.push_back({source[0], source[1], source[2], 1.0F});
    }
    return image;
}

// The develop output is linear working light. What a viewer sees is the encoded
// value, so the divergence is reported there: below one code value at 8 bits it
// cannot be seen at all.
[[nodiscard]] int srgb_code8(const float linear) noexcept {
    const float encoded = negaflow::color::linear_to_srgb_encoded(std::clamp(linear, 0.0F, 1.0F));
    return static_cast<int>(std::lround(std::clamp(encoded, 0.0F, 1.0F) * 255.0F));
}

void run_case(const float dmin_value) {
    negaflow::imaging::ManualNegativeDevelopParameters parameters{};
    parameters.dmin = {dmin_value, dmin_value, dmin_value};
    parameters.film_type = negaflow::imaging::NegativeFilmType::color;

    auto macos = negaflow::imaging::develop_manual_negative(build_row(true), parameters);
    auto windows = negaflow::imaging::develop_manual_negative(build_row(false), parameters);
    expect(
        macos.status == negaflow::imaging::ManualNegativeDevelopStatus::ok &&
            windows.status == negaflow::imaging::ManualNegativeDevelopStatus::ok,
        "both develop runs succeed");
    if (macos.status != negaflow::imaging::ManualNegativeDevelopStatus::ok ||
        windows.status != negaflow::imaging::ManualNegativeDevelopStatus::ok) {
        return;
    }

    const auto& patches = negaflow::fixtures::colorsync_icm_parity_patches;
    int worst_code_delta = 0;
    std::string worst_patch;
    int worst_channel_spread = 0;
    std::string worst_spread_patch;
    int patches_over_one_code = 0;

    std::cout << "\ndmin = " << std::fixed << std::setprecision(3) << dmin_value << '\n';
    std::cout << std::left << std::setw(22) << "patch" << std::right << std::setw(16)
              << "macOS sRGB8" << std::setw(16) << "windows sRGB8" << std::setw(14)
              << "delta RGB" << std::setw(9) << "spread" << '\n';
    for (std::size_t index = 0U; index < patches.size(); ++index) {
        const auto& macos_pixel = macos.image.pixels[index];
        const auto& windows_pixel = windows.image.pixels[index];
        const std::array<int, 3> macos_code{
            srgb_code8(macos_pixel.red),
            srgb_code8(macos_pixel.green),
            srgb_code8(macos_pixel.blue)};
        const std::array<int, 3> windows_code{
            srgb_code8(windows_pixel.red),
            srgb_code8(windows_pixel.green),
            srgb_code8(windows_pixel.blue)};
        std::array<int, 3> delta{};
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            delta[channel] = std::abs(macos_code[channel] - windows_code[channel]);
        }
        const int max_delta = *std::max_element(delta.begin(), delta.end());
        // A shift shared by all three channels reads as brightness. A shift that
        // differs between channels reads as a colour cast, which is far more
        // visible in a film scan, so it is tracked separately.
        const int spread = max_delta - *std::min_element(delta.begin(), delta.end());
        if (max_delta > 0) {
            ++patches_over_one_code;
        }
        if (max_delta > worst_code_delta) {
            worst_code_delta = max_delta;
            worst_patch = std::string{patches[index].name};
        }
        if (spread > worst_channel_spread) {
            worst_channel_spread = spread;
            worst_spread_patch = std::string{patches[index].name};
        }
        if (max_delta > 0) {
            std::ostringstream macos_text;
            macos_text << macos_code[0] << "," << macos_code[1] << "," << macos_code[2];
            std::ostringstream windows_text;
            windows_text << windows_code[0] << "," << windows_code[1] << ","
                         << windows_code[2];
            std::ostringstream delta_text;
            delta_text << delta[0] << "," << delta[1] << "," << delta[2];
            std::cout << std::left << std::setw(22) << std::string{patches[index].name}
                      << std::right << std::setw(16) << macos_text.str() << std::setw(16)
                      << windows_text.str() << std::setw(14) << delta_text.str()
                      << std::setw(9) << spread << '\n';
        }
    }
    std::cout << "  patches differing by at least one 8-bit code: " << patches_over_one_code
              << " of " << patches.size() << '\n';
    std::cout << "  worst 8-bit code delta: " << worst_code_delta;
    if (!worst_patch.empty()) {
        std::cout << " at " << worst_patch;
    }
    std::cout << "\n  worst channel spread (colour cast): " << worst_channel_spread;
    if (!worst_spread_patch.empty()) {
        std::cout << " at " << worst_spread_patch;
    }
    std::cout << '\n';
}

}  // namespace

int main() {
    std::cout << "develop impact of the ColorSync/ICM input divergence\n";
    std::cout << "(colour negative, fixed print response, tone left at identity)\n";
    // Dmin is the film base transmittance. A real colour negative base sits well
    // below 1.0 because of the orange mask, so the sweep brackets plausible bases
    // rather than assuming one.
    for (const float dmin_value : {1.0F, 0.6F, 0.3F}) {
        run_case(dmin_value);
    }

    if (failures != 0) {
        std::cerr << failures << " develop impact test(s) failed\n";
        return 1;
    }
    std::cout << "\ndevelop impact probe completed\n";
    return 0;
}
