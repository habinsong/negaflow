#include "negaflow/imaging/custom_color_target.h"
#include "Fixtures/custom_color_target_samples.h"
#include <cmath>
#include <cstring>
#include <iostream>
#include <limits>
#include <numbers>

namespace {
int failures = 0;
void expect(bool value, const char* message) {
    if (!value) { std::cerr << "FAIL: " << message << '\n'; ++failures; }
}
} // namespace

int main() {
    using namespace negaflow;
    double maximum_error = 0;
    for (const auto& sample : custom_target_samples) {
        const auto* profile = imaging::custom_color_target_profile(sample.target);
        expect(profile != nullptr, "custom profile exists");
        if (profile == nullptr) { continue; }
        const double angle = sample.lch[2] * std::numbers::pi / 180;
        const auto actual = imaging::evaluate_custom_color_target(
            {sample.lch[0], sample.lch[1] * std::cos(angle), sample.lch[1] * std::sin(angle)}, *profile);
        for (std::size_t i = 0; i < 3; ++i) {
            const double error = std::abs(actual[i] - sample.expected[i]);
            maximum_error = std::max(maximum_error, error);
            expect(error < 0.0001, "macOS custom-3 independent Lab reference");
        }
    }
    for (std::uint32_t target = 7; target <= 24; ++target) {
        const auto& profile = *imaging::custom_color_target_profile(target);
        double previous = -1e10;
        for (int step = -50; step <= 1250; ++step) {
            const auto lab = imaging::evaluate_custom_color_target({step / 10.0, 24, 16}, profile);
            expect(lab[0] > previous, "extended tone remains strictly increasing");
            previous = lab[0];
        }
        const auto white = imaging::evaluate_custom_color_target({100, 0, 0}, profile);
        expect(white[0] >= 96 && white[0] <= 98.5 && white[1] == 0 && white[2] == 0,
               "custom white compression preserves neutral endpoint");

        core::Rgba32F source[6]{{0.35F, 0.20F, 0.12F, 1}, {0.35F, 0.20F, 0.12F, 0.25F},
            {99, 99, 99, 1}, {-0.08F, 1.4F, 0.1F, 1}, {0.2F, 0.3F, 0.4F, 0}, {99, 99, 99, 1}};
        core::Rgba32F output[6]{};
        output[2] = output[5] = {17, 17, 17, 1};
        expect(imaging::apply_custom_color_target({source, 6, 2, 2, 3}, {output, 6, 2, 2, 3}, target)
            == core::KernelStatus::ok, "multi-row stride and extended RGB render");
        expect(output[0].red == output[1].red && output[0].green == output[1].green &&
            output[0].blue == output[1].blue && output[1].alpha == 0.25F, "unassociated alpha remains unchanged");
        expect(output[4].red == 0 && output[4].green == 0 && output[4].blue == 0 && output[4].alpha == 0,
            "transparent pixel remains transparent");
        expect(output[2].red == 17 && output[5].red == 17, "row padding untouched");
        expect(std::memcmp(source, output, sizeof(source)) != 0, "custom changes pixels");
        core::Rgba32F in_place[6];
        std::memcpy(in_place, source, sizeof(source));
        expect(imaging::apply_custom_color_target({in_place, 6, 2, 2, 3}, {in_place, 6, 2, 2, 3}, target)
            == core::KernelStatus::ok, "in-place pipeline render");
        for (std::size_t i : {0U, 1U, 3U, 4U}) {
            expect(std::memcmp(&in_place[i], &output[i], sizeof(core::Rgba32F)) == 0, "in-place matches separate output");
        }
    }
    core::Rgba32F source{-0.1F, 1.5F, 0.23F, 0.25F}, result{};
    for (std::uint32_t target = 0; target < 7; ++target) {
        expect(imaging::apply_custom_color_target({&source, 1, 1, 1, 1}, {&result, 1, 1, 1, 1}, target)
            == core::KernelStatus::ok && std::memcmp(&source, &result, sizeof(source)) == 0,
            "standard targets are bit-exact identity");
    }
    expect(imaging::apply_custom_color_target({&source, 1, 1, 1, 1}, {&result, 1, 1, 1, 1}, 25)
        == core::KernelStatus::invalid_parameter, "unknown target rejected");
    source.red = std::numeric_limits<float>::quiet_NaN();
    expect(imaging::apply_custom_color_target({&source, 1, 1, 1, 1}, {&result, 1, 1, 1, 1}, 7)
        == core::KernelStatus::non_finite_input, "non-finite input rejected");
    std::cout << "custom_color_target: samples=" << std::size(custom_target_samples)
              << " max_lab_error=" << maximum_error << " failures=" << failures << '\n';
    return failures == 0 ? 0 : 1;
}
