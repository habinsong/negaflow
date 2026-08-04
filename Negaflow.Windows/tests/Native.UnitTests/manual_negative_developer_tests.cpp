#include "negaflow/core/negative_inversion.h"
#include "negaflow/imaging/manual_negative_developer.h"

#include <array>
#include <cstddef>
#include <iostream>
#include <limits>
#include <utility>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] bool pixels_equal(
    const negaflow::core::Rgba32F& left,
    const negaflow::core::Rgba32F& right) noexcept {
    return left.red == right.red && left.green == right.green &&
           left.blue == right.blue && left.alpha == right.alpha;
}

negaflow::imaging::WorkingImage make_working_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 2U;
    image.height = 1U;
    image.stride_pixels = 2U;
    image.pixels = {
        {0.72F, 0.32F, 0.15F, 1.0F},
        {0.12F, 0.08F, 0.04F, 0.5F},
    };
    return image;
}

}  // namespace

int main() {
    negaflow::imaging::WorkingImage source = make_working_image();
    std::array<negaflow::core::Rgba32F, 2> expected{};
    const negaflow::core::NegativeInversionParameters reference_parameters{
        {0.72F, 0.32F, 0.15F},
        {1.55F, 1.55F, 1.55F},
    };
    const auto reference_status = negaflow::core::apply_negative_inversion(
        {source.pixels.data(), source.pixels.size(), 2U, 1U, 2U},
        {expected.data(), expected.size(), 2U, 1U, 2U},
        reference_parameters,
        negaflow::core::color_negative_print_response());
    expect(reference_status == negaflow::core::KernelStatus::ok, "reference inversion succeeds");

    const negaflow::imaging::ManualNegativeDevelopParameters parameters{
        {0.72F, 0.32F, 0.15F},
        negaflow::imaging::NegativeFilmType::color,
    };
    const auto developed = negaflow::imaging::develop_manual_negative(
        std::move(source),
        parameters);
    expect(
        developed.status == negaflow::imaging::ManualNegativeDevelopStatus::ok,
        "manual color negative development succeeds");
    expect(
        developed.info.dmax_normalized == std::array<float, 3>{1.55F, 1.55F, 1.55F},
        "color generic density range is fixed");
    expect(developed.image.pixels.size() == expected.size(), "developed pixel count");
    if (developed.image.pixels.size() == expected.size()) {
        expect(pixels_equal(developed.image.pixels[0], expected[0]), "first in-place pixel exact");
        expect(pixels_equal(developed.image.pixels[1], expected[1]), "second in-place pixel exact");
        expect(developed.image.pixels[1].alpha == 0.5F, "alpha is preserved in place");
    }

    const negaflow::imaging::ManualNegativeDevelopParameters clamped_parameters{
        {0.0F, 2.0F, 0.5F},
        negaflow::imaging::NegativeFilmType::black_and_white,
    };
    const auto clamped = negaflow::imaging::develop_manual_negative(
        make_working_image(),
        clamped_parameters);
    expect(
        clamped.status == negaflow::imaging::ManualNegativeDevelopStatus::ok &&
            clamped.info.applied_dmin == std::array<float, 3>{0.001F, 1.0F, 0.5F},
        "manual Dmin follows baseline clamp");
    expect(
        clamped.info.dmax_normalized == std::array<float, 3>{2.17F, 2.17F, 2.17F},
        "B&W generic density range is fixed");

    auto non_finite_parameters = parameters;
    non_finite_parameters.dmin[1] = std::numeric_limits<float>::quiet_NaN();
    const auto non_finite = negaflow::imaging::develop_manual_negative(
        make_working_image(),
        non_finite_parameters);
    expect(
        non_finite.status == negaflow::imaging::ManualNegativeDevelopStatus::invalid_parameter &&
            non_finite.image.pixels.empty(),
        "non-finite manual parameter publishes no pixels");

    auto malformed = make_working_image();
    malformed.stride_pixels = 1U;
    const auto failed = negaflow::imaging::develop_manual_negative(
        std::move(malformed),
        parameters);
    expect(
        failed.status == negaflow::imaging::ManualNegativeDevelopStatus::kernel_failed &&
            failed.info.kernel_status == negaflow::core::KernelStatus::invalid_stride &&
            failed.image.pixels.empty(),
        "invalid working layout publishes no pixels");

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"manual_negative_developer\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
