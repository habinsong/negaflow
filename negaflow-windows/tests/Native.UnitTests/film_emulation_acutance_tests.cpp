#include "negaflow/imaging/film_emulation_acutance.h"
#include "film_emulation_core_image_golden_fixture.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <limits>
#include <vector>

namespace {

constexpr std::uint32_t fixture_width = 33U;
constexpr std::uint32_t fixture_height = 9U;
constexpr std::uint32_t fixture_center_x = fixture_width / 2U;
constexpr std::uint32_t fixture_center_y = fixture_height / 2U;

int failures = 0;
float maximum_core_image_error = 0.0F;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] bool nearly_equal(
    const float actual,
    const float expected,
    const float tolerance =
        negaflow::fixtures::film_emulation_core_image_acutance_absolute_tolerance)
    noexcept {
    const float error = std::abs(actual - expected);
    maximum_core_image_error = std::max(maximum_core_image_error, error);
    return error <= tolerance;
}

[[nodiscard]] std::vector<negaflow::core::Rgba32F> make_pattern(
    const negaflow::fixtures::FilmEmulationAcutancePattern pattern) {
    std::vector<negaflow::core::Rgba32F> pixels(
        static_cast<std::size_t>(fixture_width) * fixture_height);
    if (pattern ==
        negaflow::fixtures::FilmEmulationAcutancePattern::neutral_impulse) {
        std::ranges::fill(
            pixels,
            negaflow::core::Rgba32F{0.25F, 0.25F, 0.25F, 1.0F});
        pixels[(static_cast<std::size_t>(fixture_center_y) * fixture_width) +
               fixture_center_x] = {0.75F, 0.75F, 0.75F, 1.0F};
        return pixels;
    }

    for (std::uint32_t row = 0U; row < fixture_height; ++row) {
        for (std::uint32_t column = 0U; column < fixture_width; ++column) {
            pixels[(static_cast<std::size_t>(row) * fixture_width) + column] =
                column < fixture_center_x
                    ? negaflow::core::Rgba32F{0.65F, 0.10F, 0.08F, 1.0F}
                    : negaflow::core::Rgba32F{0.10F, 0.65F, 0.16F, 1.0F};
        }
    }
    return pixels;
}

[[nodiscard]] negaflow::core::KernelStatus apply_fixture(
    const std::vector<negaflow::core::Rgba32F>& input,
    std::vector<negaflow::core::Rgba32F>& output,
    const negaflow::imaging::FilmEmulation emulation,
    std::vector<negaflow::imaging::FilmEmulationAcutanceScratchPixel>& scratch) {
    return negaflow::imaging::apply_film_emulation_acutance(
        {input.data(), input.size(), fixture_width, fixture_height, fixture_width},
        {output.data(), output.size(), fixture_width, fixture_height, fixture_width},
        {emulation, 1.0},
        {scratch.data(), scratch.size()});
}

void test_profile_contract_and_bounded_scratch() {
    for (const auto& expected :
         negaflow::fixtures::film_emulation_acutance_profile_signatures) {
        negaflow::imaging::FilmEmulationAcutanceProfile actual{};
        expect(
            negaflow::imaging::try_get_film_emulation_acutance_profile(
                expected.emulation,
                actual) &&
                actual.radius == expected.radius &&
                actual.intensity == expected.intensity,
            "each acutance profile matches the macOS baseline");
    }
    negaflow::imaging::FilmEmulationAcutanceProfile invalid{};
    expect(
        !negaflow::imaging::try_get_film_emulation_acutance_profile(
            static_cast<negaflow::imaging::FilmEmulation>(255U),
            invalid),
        "an unknown film profile has no acutance data");

    const std::size_t scratch_pixels =
        negaflow::imaging::film_emulation_acutance_scratch_pixel_count(10'000U);
    expect(
        scratch_pixels == 110'000U &&
            scratch_pixels *
                    sizeof(negaflow::imaging::FilmEmulationAcutanceScratchPixel) ==
                1'320'000U,
        "a ten-thousand-pixel row needs a bounded 1.32 MB scratch ring");
}

void test_core_image_golden_signatures() {
    const std::size_t scratch_size =
        negaflow::imaging::film_emulation_acutance_scratch_pixel_count(
            fixture_width);
    std::vector<negaflow::imaging::FilmEmulationAcutanceScratchPixel> scratch(
        scratch_size);
    for (const auto& golden :
         negaflow::fixtures::film_emulation_acutance_golden_cases) {
        const auto input = make_pattern(golden.pattern);
        std::vector<negaflow::core::Rgba32F> output(input.size());
        expect(
            apply_fixture(input, output, golden.emulation, scratch) ==
                negaflow::core::KernelStatus::ok,
            "the golden acutance pattern applies");
        for (std::size_t sample = 0U;
             sample < golden.expected_center_samples.size();
             ++sample) {
            const std::uint32_t column =
                negaflow::fixtures::film_emulation_acutance_sample_x_begin +
                static_cast<std::uint32_t>(sample);
            const auto actual =
                output[(static_cast<std::size_t>(fixture_center_y) *
                        fixture_width) +
                       column];
            const auto expected = golden.expected_center_samples[sample];
            expect(
                nearly_equal(actual.red, expected.red) &&
                    nearly_equal(actual.green, expected.green) &&
                    nearly_equal(actual.blue, expected.blue) &&
                    actual.alpha == expected.alpha,
                "the fitted Gaussian response stays within the Core Image golden envelope");
        }
    }
}

void test_in_place_parity_and_alpha_preservation() {
    const auto input = make_pattern(
        negaflow::fixtures::FilmEmulationAcutancePattern::saturated_step);
    std::vector<negaflow::core::Rgba32F> separate(input.size());
    std::vector<negaflow::imaging::FilmEmulationAcutanceScratchPixel> scratch(
        negaflow::imaging::film_emulation_acutance_scratch_pixel_count(
            fixture_width));
    expect(
        apply_fixture(
            input,
            separate,
            negaflow::imaging::FilmEmulation::velvia_50,
            scratch) == negaflow::core::KernelStatus::ok,
        "the separate acutance output applies");

    auto in_place = input;
    expect(
        negaflow::imaging::apply_film_emulation_acutance(
            {in_place.data(), in_place.size(), fixture_width, fixture_height,
             fixture_width},
            {in_place.data(), in_place.size(), fixture_width, fixture_height,
             fixture_width},
            {negaflow::imaging::FilmEmulation::velvia_50, 1.0},
            {scratch.data(), scratch.size()}) ==
            negaflow::core::KernelStatus::ok,
        "the exact in-place acutance path applies");
    expect(
        std::ranges::equal(
            in_place,
            separate,
            [](const negaflow::core::Rgba32F left,
               const negaflow::core::Rgba32F right) {
                return left.red == right.red && left.green == right.green &&
                       left.blue == right.blue && left.alpha == right.alpha;
            }),
        "in-place output is bit-exact with separate output");
    expect(
        std::ranges::all_of(in_place, [](const negaflow::core::Rgba32F pixel) {
            return pixel.alpha == 1.0F;
        }),
        "acutance preserves alpha exactly");
}

void test_tall_in_place_ring_reuse() {
    constexpr std::uint32_t width = 19U;
    constexpr std::uint32_t height = 23U;
    constexpr std::size_t stride = 21U;
    constexpr negaflow::core::Rgba32F padding{91.0F, 92.0F, 93.0F, 0.0F};
    const std::size_t capacity =
        (static_cast<std::size_t>(height - 1U) * stride) + width;
    std::vector<negaflow::core::Rgba32F> input(capacity, padding);
    for (std::uint32_t row = 0U; row < height; ++row) {
        for (std::uint32_t column = 0U; column < width; ++column) {
            const float red =
                (static_cast<float>(column) - 5.0F) / 20.0F;
            const float green = static_cast<float>(row % 11U) / 10.0F;
            const float blue = static_cast<float>(row + column) / 40.0F;
            const float alpha = static_cast<float>((row + column) % 5U) / 4.0F;
            input[(static_cast<std::size_t>(row) * stride) + column] =
                {red, green, blue, alpha};
        }
    }

    std::vector<negaflow::core::Rgba32F> separate(capacity, padding);
    std::vector<negaflow::imaging::FilmEmulationAcutanceScratchPixel> scratch(
        negaflow::imaging::film_emulation_acutance_scratch_pixel_count(width));
    const negaflow::imaging::FilmEmulationAcutanceParameters parameters{
        negaflow::imaging::FilmEmulation::velvia_50,
        0.73,
    };
    expect(
        negaflow::imaging::apply_film_emulation_acutance(
            {input.data(), input.size(), width, height, stride},
            {separate.data(), separate.size(), width, height, stride},
            parameters,
            {scratch.data(), scratch.size()}) ==
            negaflow::core::KernelStatus::ok,
        "a tall separate image applies through the scratch ring");

    auto in_place = input;
    expect(
        negaflow::imaging::apply_film_emulation_acutance(
            {in_place.data(), in_place.size(), width, height, stride},
            {in_place.data(), in_place.size(), width, height, stride},
            parameters,
            {scratch.data(), scratch.size()}) ==
            negaflow::core::KernelStatus::ok,
        "a tall in-place image applies while scratch slots wrap");
    expect(
        std::ranges::equal(
            in_place,
            separate,
            [](const negaflow::core::Rgba32F left,
               const negaflow::core::Rgba32F right) {
                return left.red == right.red && left.green == right.green &&
                       left.blue == right.blue && left.alpha == right.alpha;
            }),
        "wrapped in-place output and stride padding match separate output bit exactly");
}

void test_identity_clamping_and_failures() {
    const negaflow::core::Rgba32F padding{91.0F, 92.0F, 93.0F, 0.0F};
    std::array<negaflow::core::Rgba32F, 4> input{{
        {-0.25F, 0.5F, 1.5F, 0.25F},
        {0.2F, 0.4F, 0.8F, 1.0F},
        padding,
        padding,
    }};
    std::array<negaflow::core::Rgba32F, 4> output{{
        padding,
        padding,
        padding,
        padding,
    }};
    const negaflow::imaging::FilmEmulationAcutanceParameters none{
        negaflow::imaging::FilmEmulation::none,
        1.0,
    };
    expect(
        !negaflow::imaging::has_film_emulation_acutance_change(none) &&
            negaflow::imaging::apply_film_emulation_acutance(
                {input.data(), input.size(), 2U, 1U, 4U},
                {output.data(), output.size(), 2U, 1U, 4U},
                none,
                {nullptr, 0U}) == negaflow::core::KernelStatus::ok,
        "the none profile is identity without scratch");
    expect(
        output[0].red == input[0].red && output[0].blue == input[0].blue &&
            output[0].alpha == input[0].alpha &&
            output[2].red == padding.red && output[3].blue == padding.blue,
        "identity preserves extended pixels and stride padding bit exactly");

    negaflow::imaging::FilmEmulationAcutanceParameters parameters{
        negaflow::imaging::FilmEmulation::velvia_50,
        4.0,
    };
    expect(
        negaflow::imaging::film_emulation_acutance_amount(parameters) == 0.22 &&
            negaflow::imaging::has_film_emulation_acutance_change(parameters),
        "intensity above one clamps to the profile acutance amount");
    parameters.intensity = 0.001;
    expect(
        !negaflow::imaging::has_film_emulation_acutance_change(parameters),
        "the macOS stage identity threshold is preserved");
    parameters.intensity = -2.0;
    expect(
        !negaflow::imaging::has_film_emulation_acutance_change(parameters) &&
            negaflow::imaging::film_emulation_acutance_amount(parameters) == 0.0,
        "negative intensity clamps to identity");

    parameters = {
        static_cast<negaflow::imaging::FilmEmulation>(255U),
        1.0,
    };
    expect(
        !negaflow::imaging::valid_film_emulation_acutance_parameters(parameters),
        "an unknown film profile is rejected");
    parameters = {
        negaflow::imaging::FilmEmulation::velvia_50,
        std::numeric_limits<double>::quiet_NaN(),
    };
    expect(
        !negaflow::imaging::valid_film_emulation_acutance_parameters(parameters),
        "a non-finite intensity is rejected");

    std::array<negaflow::core::Rgba32F, 2> active{{
        {0.2F, 0.3F, 0.4F, 1.0F},
        {0.5F, 0.6F, 0.7F, 1.0F},
    }};
    parameters = {negaflow::imaging::FilmEmulation::velvia_50, 1.0};
    expect(
        negaflow::imaging::apply_film_emulation_acutance(
            {active.data(), active.size(), 2U, 1U, 2U},
            {active.data(), active.size(), 2U, 1U, 2U},
            parameters,
            {nullptr, 0U}) == negaflow::core::KernelStatus::invalid_argument,
        "an active acutance transform requires caller-owned scratch");
    std::array<negaflow::imaging::FilmEmulationAcutanceScratchPixel, 21> small{};
    expect(
        negaflow::imaging::apply_film_emulation_acutance(
            {active.data(), active.size(), 2U, 1U, 2U},
            {active.data(), active.size(), 2U, 1U, 2U},
            parameters,
            {small.data(), small.size()}) ==
            negaflow::core::KernelStatus::buffer_too_small,
        "undersized acutance scratch is rejected");
    std::array<negaflow::imaging::FilmEmulationAcutanceScratchPixel, 22> exact{};
    active[0].green = std::numeric_limits<float>::infinity();
    expect(
        negaflow::imaging::apply_film_emulation_acutance(
            {active.data(), active.size(), 2U, 1U, 2U},
            {active.data(), active.size(), 2U, 1U, 2U},
            parameters,
            {exact.data(), exact.size()}) ==
            negaflow::core::KernelStatus::non_finite_input,
        "a non-finite source pixel is rejected before filtering");

    std::array<negaflow::core::Rgba32F, 4> overlapping_views{{
        {0.1F, 0.2F, 0.3F, 1.0F},
        {0.4F, 0.5F, 0.6F, 1.0F},
        {0.7F, 0.8F, 0.9F, 1.0F},
        {1.0F, 1.1F, 1.2F, 1.0F},
    }};
    expect(
        negaflow::imaging::apply_film_emulation_acutance(
            {overlapping_views.data(), overlapping_views.size(), 2U, 1U, 2U},
            {overlapping_views.data() + 1U, overlapping_views.size() - 1U, 2U,
             1U, 2U},
            none,
            {nullptr, 0U}) == negaflow::core::KernelStatus::invalid_argument,
        "a partial input-output alias is rejected even for identity");

    std::array<negaflow::core::Rgba32F, 32> scratch_overlap{};
    std::ranges::fill(
        scratch_overlap,
        negaflow::core::Rgba32F{0.2F, 0.3F, 0.4F, 1.0F});
    std::array<negaflow::core::Rgba32F, 2> separate_output{};
    expect(
        negaflow::imaging::apply_film_emulation_acutance(
            {scratch_overlap.data(), scratch_overlap.size(), 2U, 1U, 2U},
            {separate_output.data(), separate_output.size(), 2U, 1U, 2U},
            {negaflow::imaging::FilmEmulation::velvia_50, 1.0},
            {reinterpret_cast<
                 negaflow::imaging::FilmEmulationAcutanceScratchPixel*>(
                 scratch_overlap.data() + 1U),
             22U}) == negaflow::core::KernelStatus::invalid_argument,
        "scratch storage overlapping an image view is rejected");
}

}  // namespace

int main() {
    test_profile_contract_and_bounded_scratch();
    test_core_image_golden_signatures();
    test_in_place_parity_and_alpha_preservation();
    test_tall_in_place_ring_reuse();
    test_identity_clamping_and_failures();

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"film_emulation_acutance\",\"failures\":"
              << failures << ",\"maximum_core_image_error\":"
              << maximum_core_image_error << "}\n";
    return failures == 0 ? 0 : 1;
}
