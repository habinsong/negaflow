#include "negaflow/imaging/film_emulation_color.h"
#include "film_emulation_core_image_golden_fixture.h"
#include "film_emulation_color_fixture.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <iostream>
#include <limits>
#include <memory>
#include <new>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] bool nearly_equal(
    const float actual,
    const float expected,
    const float absolute_tolerance =
        negaflow::fixtures::film_emulation_color_absolute_tolerance,
    const float relative_tolerance =
        negaflow::fixtures::film_emulation_color_relative_tolerance) noexcept {
    const float difference = std::abs(actual - expected);
    const float scale = std::max(std::abs(actual), std::abs(expected));
    return difference <= absolute_tolerance + (relative_tolerance * scale);
}

void expect_pixel_near(
    const negaflow::core::Rgba32F actual,
    const negaflow::core::Rgba32F expected,
    const char* const message) {
    if (!nearly_equal(actual.red, expected.red) ||
        !nearly_equal(actual.green, expected.green) ||
        !nearly_equal(actual.blue, expected.blue) ||
        actual.alpha != expected.alpha) {
        std::cerr << "FAIL: " << message << " actual=[" << actual.red << ','
                  << actual.green << ',' << actual.blue << ',' << actual.alpha
                  << "] expected=[" << expected.red << ',' << expected.green
                  << ',' << expected.blue << ',' << expected.alpha << "]\n";
        ++failures;
    }
}

[[nodiscard]] std::unique_ptr<negaflow::imaging::FilmEmulationColorCube>
allocate_cube() {
    return std::unique_ptr<negaflow::imaging::FilmEmulationColorCube>{
        new (std::nothrow) negaflow::imaging::FilmEmulationColorCube};
}

[[nodiscard]] std::size_t signature_index() noexcept {
    constexpr std::size_t red = 8U;
    constexpr std::size_t green = 16U;
    constexpr std::size_t blue = 24U;
    constexpr std::size_t dimension =
        negaflow::imaging::film_emulation_cube_dimension;
    return ((blue * dimension) + green) * dimension + red;
}

[[nodiscard]] float chroma(const negaflow::core::Rgba32F pixel) noexcept {
    const float maximum = std::max(pixel.red, std::max(pixel.green, pixel.blue));
    const float minimum = std::min(pixel.red, std::min(pixel.green, pixel.blue));
    return maximum - minimum;
}

void test_profile_signatures_and_cube_contract() {
    expect(
        negaflow::imaging::film_emulation_color_cube_bytes == 431244U,
        "the RGB33 cube has a fixed 431244-byte payload");
    auto cube = allocate_cube();
    expect(cube != nullptr, "the bounded film cube allocation succeeds");
    if (cube == nullptr) {
        return;
    }

    for (const auto& signature :
         negaflow::fixtures::film_emulation_profile_signatures) {
        const negaflow::imaging::FilmEmulationColorParameters parameters{
            signature.emulation,
            1.0,
        };
        expect(
            negaflow::imaging::build_film_emulation_color_cube(
                parameters,
                *cube) == negaflow::core::KernelStatus::ok,
            "each film profile builds a color cube");
        expect(cube->ready && cube->emulation == signature.emulation &&
                   cube->intensity_step == 20U,
               "each full-strength cube records its profile and step");
        const auto actual = cube->entries[signature_index()];
        expect(
            nearly_equal(actual.red, signature.expected.red) &&
                nearly_equal(actual.green, signature.expected.green) &&
                nearly_equal(actual.blue, signature.expected.blue),
            "each film profile matches its independent cube signature");
    }
}

void test_fixed_fixture_and_in_place_parity() {
    auto cube = allocate_cube();
    expect(cube != nullptr, "the fixture cube allocation succeeds");
    if (cube == nullptr) {
        return;
    }
    expect(
        negaflow::imaging::build_film_emulation_color_cube(
            negaflow::fixtures::film_emulation_color_parameters,
            *cube) == negaflow::core::KernelStatus::ok &&
            cube->intensity_step == 15U,
        "0.73 intensity builds the macOS-compatible 0.75 cube step");

    std::array<negaflow::core::Rgba32F,
               negaflow::fixtures::film_emulation_color_input.size()> output{};
    expect(
        negaflow::imaging::apply_film_emulation_color_cube(
            {negaflow::fixtures::film_emulation_color_input.data(),
             negaflow::fixtures::film_emulation_color_input.size(),
             4U,
             3U,
             4U},
            {output.data(), output.size(), 4U, 3U, 4U},
            negaflow::fixtures::film_emulation_color_parameters,
            cube.get()) == negaflow::core::KernelStatus::ok,
        "the fixed film-emulation fixture applies");
    for (std::size_t index = 0U; index < output.size(); ++index) {
        expect_pixel_near(
            output[index],
            negaflow::fixtures::film_emulation_color_expected[index],
            "the fixed fixture matches the independent Float32 calculation");
    }
    float maximum_core_image_error = 0.0F;
    for (std::size_t index = 0U; index < output.size(); ++index) {
        const auto expected =
            negaflow::fixtures::film_emulation_core_image_color_expected[index];
        maximum_core_image_error = std::max(
            maximum_core_image_error,
            std::max(
                std::abs(output[index].red - expected.red),
                std::max(
                    std::abs(output[index].green - expected.green),
                    std::abs(output[index].blue - expected.blue))));
    }
    expect(
        maximum_core_image_error <=
            negaflow::fixtures::film_emulation_core_image_color_absolute_tolerance,
        "the platform-neutral cube stays within the measured Core Image envelope");

    auto in_place = negaflow::fixtures::film_emulation_color_input;
    expect(
        negaflow::imaging::apply_film_emulation_color_cube(
            {in_place.data(), in_place.size(), 4U, 3U, 4U},
            {in_place.data(), in_place.size(), 4U, 3U, 4U},
            negaflow::fixtures::film_emulation_color_parameters,
            cube.get()) == negaflow::core::KernelStatus::ok,
        "in-place film-emulation sampling applies");
    for (std::size_t index = 0U; index < output.size(); ++index) {
        expect_pixel_near(
            in_place[index],
            output[index],
            "in-place film-emulation sampling matches separate output");
    }
}

void test_identity_quantization_and_clamping() {
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
    const negaflow::imaging::FilmEmulationColorParameters none{
        negaflow::imaging::FilmEmulation::none,
        1.0,
    };
    expect(
        !negaflow::imaging::has_film_emulation_color_change(none) &&
            negaflow::imaging::apply_film_emulation_color_cube(
                {input.data(), input.size(), 2U, 1U, 4U},
                {output.data(), output.size(), 2U, 1U, 4U},
                none,
                nullptr) == negaflow::core::KernelStatus::ok,
        "the none profile copies without a cube");
    expect(output[0].red == input[0].red && output[0].blue == input[0].blue &&
               output[0].alpha == input[0].alpha &&
               output[2].red == padding.red && output[3].blue == padding.blue,
           "identity preserves extended active pixels and stride padding");

    negaflow::imaging::FilmEmulationColorParameters quantized{
        negaflow::imaging::FilmEmulation::velvia_50,
        0.024,
    };
    expect(negaflow::imaging::film_emulation_intensity_step(quantized) == 0U &&
               !negaflow::imaging::has_film_emulation_color_change(quantized),
           "an intensity below the first 5-percent half-step is color identity");
    quantized.intensity = 0.025;
    expect(negaflow::imaging::film_emulation_intensity_step(quantized) == 1U &&
               negaflow::imaging::has_film_emulation_color_change(quantized),
           "the exact first half-step rounds away from zero");
    quantized.intensity = 4.0;
    expect(negaflow::imaging::film_emulation_intensity_step(quantized) == 20U,
           "intensity above one clamps to the full-strength cube");
    quantized.intensity = -2.0;
    expect(negaflow::imaging::film_emulation_intensity_step(quantized) == 0U &&
               !negaflow::imaging::has_film_emulation_color_change(quantized),
           "negative intensity clamps to color identity");
}

void test_profile_properties() {
    auto e100_cube = allocate_cube();
    auto velvia_cube = allocate_cube();
    expect(e100_cube != nullptr && velvia_cube != nullptr,
           "property-test cubes allocate");
    if (e100_cube == nullptr || velvia_cube == nullptr) {
        return;
    }

    const negaflow::imaging::FilmEmulationColorParameters e100{
        negaflow::imaging::FilmEmulation::ektachrome_e100,
        1.0,
    };
    const negaflow::imaging::FilmEmulationColorParameters velvia{
        negaflow::imaging::FilmEmulation::velvia_50,
        1.0,
    };
    expect(
        negaflow::imaging::build_film_emulation_color_cube(e100, *e100_cube) ==
                negaflow::core::KernelStatus::ok &&
            negaflow::imaging::build_film_emulation_color_cube(
                velvia,
                *velvia_cube) == negaflow::core::KernelStatus::ok,
        "E100 and Velvia property cubes build");

    const negaflow::core::Rgba32F source{0.14F, 0.42F, 0.16F, 0.7F};
    auto e100_output = source;
    auto velvia_output = source;
    expect(
        negaflow::imaging::apply_film_emulation_color_cube(
            {&source, 1U, 1U, 1U, 1U},
            {&e100_output, 1U, 1U, 1U, 1U},
            e100,
            e100_cube.get()) == negaflow::core::KernelStatus::ok &&
            negaflow::imaging::apply_film_emulation_color_cube(
                {&source, 1U, 1U, 1U, 1U},
                {&velvia_output, 1U, 1U, 1U, 1U},
                velvia,
                velvia_cube.get()) == negaflow::core::KernelStatus::ok &&
            chroma(velvia_output) > chroma(e100_output) + 0.03F &&
            e100_output.alpha == source.alpha &&
            velvia_output.alpha == source.alpha,
        "Velvia boosts green-patch chroma more than E100 and preserves alpha");
}

void test_parameter_cube_and_view_failures() {
    auto cube = allocate_cube();
    expect(cube != nullptr, "failure-test cube allocates");
    if (cube == nullptr) {
        return;
    }

    negaflow::imaging::FilmEmulationColorParameters invalid{
        static_cast<negaflow::imaging::FilmEmulation>(255U),
        0.5,
    };
    expect(!negaflow::imaging::valid_film_emulation_color_parameters(invalid) &&
               negaflow::imaging::build_film_emulation_color_cube(
                   invalid,
                   *cube) == negaflow::core::KernelStatus::invalid_parameter,
           "unknown film profile values are rejected");
    invalid = {negaflow::imaging::FilmEmulation::velvia_50,
               std::numeric_limits<double>::quiet_NaN()};
    expect(!negaflow::imaging::valid_film_emulation_color_parameters(invalid) &&
               negaflow::imaging::build_film_emulation_color_cube(
                   invalid,
                   *cube) ==
                   negaflow::core::KernelStatus::non_finite_parameter,
           "non-finite film intensity is rejected");

    const auto parameters = negaflow::fixtures::film_emulation_color_parameters;
    std::array<negaflow::core::Rgba32F, 2> pixels{{
        {0.2F, 0.3F, 0.4F, 1.0F},
        {0.5F, 0.6F, 0.7F, 1.0F},
    }};
    expect(
        negaflow::imaging::apply_film_emulation_color_cube(
            {pixels.data(), pixels.size(), 2U, 1U, 2U},
            {pixels.data(), pixels.size(), 2U, 1U, 2U},
            parameters,
            nullptr) == negaflow::core::KernelStatus::invalid_argument,
        "an active transform requires its matching cube");
    expect(
        negaflow::imaging::build_film_emulation_color_cube(parameters, *cube) ==
            negaflow::core::KernelStatus::ok,
        "the valid failure-test cube builds");
    auto wrong_step = parameters;
    wrong_step.intensity = 0.69;
    expect(
        negaflow::imaging::apply_film_emulation_color_cube(
            {pixels.data(), pixels.size(), 2U, 1U, 2U},
            {pixels.data(), pixels.size(), 2U, 1U, 2U},
            wrong_step,
            cube.get()) == negaflow::core::KernelStatus::invalid_argument,
        "a stale cube intensity step is rejected");
    expect(
        negaflow::imaging::apply_film_emulation_color_cube(
            {pixels.data(), pixels.size(), 2U, 1U, 1U},
            {pixels.data(), pixels.size(), 2U, 1U, 2U},
            parameters,
            cube.get()) == negaflow::core::KernelStatus::invalid_stride,
        "an invalid film-emulation source stride is rejected");

    const float saved = cube->entries[0].red;
    cube->entries[0].red = std::numeric_limits<float>::quiet_NaN();
    expect(
        negaflow::imaging::apply_film_emulation_color_cube(
            {pixels.data(), pixels.size(), 2U, 1U, 2U},
            {pixels.data(), pixels.size(), 2U, 1U, 2U},
            parameters,
            cube.get()) == negaflow::core::KernelStatus::invalid_parameter,
        "a non-finite cube payload is rejected before pixel processing");
    cube->entries[0].red = saved;
    pixels[0].blue = std::numeric_limits<float>::infinity();
    expect(
        negaflow::imaging::apply_film_emulation_color_cube(
            {pixels.data(), pixels.size(), 2U, 1U, 2U},
            {pixels.data(), pixels.size(), 2U, 1U, 2U},
            parameters,
            cube.get()) == negaflow::core::KernelStatus::non_finite_input,
        "a non-finite source pixel is rejected");
}

}  // namespace

int main() {
    test_profile_signatures_and_cube_contract();
    test_fixed_fixture_and_in_place_parity();
    test_identity_quantization_and_clamping();
    test_profile_properties();
    test_parameter_cube_and_view_failures();

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"film_emulation_color\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
