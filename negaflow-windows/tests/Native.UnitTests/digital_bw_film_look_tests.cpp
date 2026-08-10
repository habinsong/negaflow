#include "negaflow/imaging/digital_bw_emulsion_response.h"
#include "negaflow/imaging/digital_bw_film_look.h"
#include "negaflow/imaging/digital_bw_film_profile.h"
#include "negaflow/imaging/digital_film_physics.h"
#include "negaflow/imaging/film_emulation_registry.h"
#include "negaflow/imaging/working_film_look.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
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

constexpr std::array<negaflow::imaging::FilmEmulation, 15> black_and_white_films{
    negaflow::imaging::FilmEmulation::tri_x_400,
    negaflow::imaging::FilmEmulation::hp5_plus,
    negaflow::imaging::FilmEmulation::fp4_plus,
    negaflow::imaging::FilmEmulation::delta_100,
    negaflow::imaging::FilmEmulation::delta_400,
    negaflow::imaging::FilmEmulation::delta_3200,
    negaflow::imaging::FilmEmulation::tmax_100,
    negaflow::imaging::FilmEmulation::tmax_400,
    negaflow::imaging::FilmEmulation::tmax_p3200,
    negaflow::imaging::FilmEmulation::kentmere_400,
    negaflow::imaging::FilmEmulation::ortho_plus,
    negaflow::imaging::FilmEmulation::sfx_200,
    negaflow::imaging::FilmEmulation::rollei_ir,
    negaflow::imaging::FilmEmulation::scala_200x,
    negaflow::imaging::FilmEmulation::rollei_superpan,
};

[[nodiscard]] negaflow::imaging::WorkingImage make_image(
    const std::uint32_t width = 32U,
    const std::uint32_t height = 32U) {
    negaflow::imaging::WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.resize(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            image.pixels[static_cast<std::size_t>(y) * width + x] = {
                0.52F,
                0.34F,
                0.22F,
                0.2F + (0.7F * static_cast<float>(x) /
                        static_cast<float>(width - 1U)),
            };
        }
    }
    return image;
}

[[nodiscard]] bool same_pixels(
    const std::vector<negaflow::core::Rgba32F>& left,
    const std::vector<negaflow::core::Rgba32F>& right) noexcept {
    return left.size() == right.size() &&
           std::memcmp(
               left.data(),
               right.data(),
               left.size() * sizeof(left.front())) == 0;
}

[[nodiscard]] float response_value(
    const negaflow::imaging::FilmEmulation emulation,
    const float red,
    const float green,
    const float blue) {
    std::array<negaflow::core::Rgba32F, 1> pixel{{
        {red, green, blue, 0.625F},
    }};
    const auto status =
        negaflow::imaging::apply_digital_bw_emulsion_response(
            {pixel.data(), pixel.size(), 1U, 1U, 1U},
            {pixel.data(), pixel.size(), 1U, 1U, 1U},
            {emulation, 1.0});
    expect(
        status == negaflow::core::KernelStatus::ok &&
            pixel[0].red == pixel[0].green &&
            pixel[0].green == pixel[0].blue &&
            pixel[0].alpha == 0.625F,
        "the B&W response is neutral and preserves alpha");
    return pixel[0].red;
}

void test_complete_distinct_profile_registry() {
    std::array<std::array<double, 5>, black_and_white_films.size()> signatures{};
    for (std::size_t index = 0U; index < black_and_white_films.size(); ++index) {
        const auto film = black_and_white_films[index];
        const auto* const profile =
            negaflow::imaging::digital_bw_film_profile(film);
        expect(
            negaflow::imaging::valid_film_emulation(film) &&
                negaflow::imaging::is_black_and_white_film_emulation(film) &&
                profile != nullptr &&
                negaflow::imaging::digital_film_physics(film) == nullptr,
            "every B&W stock has exactly one B&W material profile");
        if (profile == nullptr) {
            continue;
        }
        const double weight_sum = profile->spectral_weights[0] +
            profile->spectral_weights[1] + profile->spectral_weights[2];
        expect(
            std::abs(weight_sum - 1.0) <= 1.0e-12,
            "every B&W spectral response is normalized");
        signatures[index] = {
            response_value(film, 0.52F, 0.34F, 0.22F),
            profile->grain_amplitude,
            profile->grain_size,
            profile->acutance_intensity,
            profile->halation_strength,
        };
        for (std::size_t prior = 0U; prior < index; ++prior) {
            double maximum_difference = 0.0;
            for (std::size_t field = 0U; field < signatures[index].size();
                 ++field) {
                maximum_difference = std::max(
                    maximum_difference,
                    std::abs(signatures[index][field] -
                             signatures[prior][field]));
            }
            expect(
                maximum_difference > 1.0e-3,
                "every selectable B&W stock has a distinguishable signature");
        }
    }
}

void test_spectral_response_contract() {
    using negaflow::imaging::FilmEmulation;
    const float tri_x_red =
        response_value(FilmEmulation::tri_x_400, 0.60F, 0.12F, 0.10F);
    const float ortho_red =
        response_value(FilmEmulation::ortho_plus, 0.60F, 0.12F, 0.10F);
    const float infrared_red =
        response_value(FilmEmulation::rollei_ir, 0.60F, 0.12F, 0.10F);
    expect(
        ortho_red < tri_x_red * 0.7F,
        "Ortho Plus renders red materially darker than Tri-X");
    expect(
        infrared_red > tri_x_red * 1.2F,
        "Rollei IR renders red materially brighter than Tri-X");

    const float tri_x_blue =
        response_value(FilmEmulation::tri_x_400, 0.12F, 0.20F, 0.62F);
    const float tmax_blue =
        response_value(FilmEmulation::tmax_100, 0.12F, 0.20F, 0.62F);
    expect(
        tmax_blue < tri_x_blue * 0.92F,
        "T-Max 100 renders blue darker than conventional Tri-X");
}

void test_complete_material_order_and_neutral_grain() {
    const auto source = make_image();
    std::vector<negaflow::imaging::FilmEmulationAcutanceScratchPixel> scratch(
        negaflow::imaging::film_emulation_acutance_scratch_pixel_count(
            source.width));
    auto result = negaflow::imaging::apply_digital_bw_film_look(
        source,
        {negaflow::imaging::FilmEmulation::tri_x_400, 0.8, 1.0, 0.8},
        {scratch.data(), scratch.size()});
    expect(
        result.status == negaflow::imaging::DigitalBwFilmLookStatus::ok &&
            result.info.digital_halation_applied &&
            result.info.emulsion_response_applied &&
            result.info.acutance_applied &&
            result.info.digital_grain_applied,
        "the complete B&W material graph applies in the fixed order");
    bool neutral_and_alpha_preserved = result.image.pixels.size() ==
        source.pixels.size();
    for (std::size_t index = 0U;
         neutral_and_alpha_preserved && index < result.image.pixels.size();
         ++index) {
        const auto pixel = result.image.pixels[index];
        neutral_and_alpha_preserved =
            pixel.red == pixel.green && pixel.green == pixel.blue &&
            pixel.alpha == source.pixels[index].alpha;
    }
    expect(
        neutral_and_alpha_preserved,
        "B&W acutance and density grain remain single-channel and preserve alpha");
}

void test_route_identity_and_matched_pipeline() {
    using negaflow::imaging::DevelopSourceKind;
    using negaflow::imaging::FilmEmulation;
    const auto source = make_image();
    const auto scanned = negaflow::imaging::apply_working_film_look(
        source,
        {DevelopSourceKind::film_scan, FilmEmulation::tri_x_400, 1.0,
         0.0, 0.0, true});
    const auto color_mismatch = negaflow::imaging::apply_working_film_look(
        source,
        {DevelopSourceKind::rendered_digital, FilmEmulation::tri_x_400, 1.0,
         0.0, 0.0, false});
    const auto bw_mismatch = negaflow::imaging::apply_working_film_look(
        source,
        {DevelopSourceKind::rendered_digital, FilmEmulation::velvia_50, 1.0,
         0.0, 0.0, true});
    expect(
        scanned.status == negaflow::imaging::WorkingFilmLookStatus::ok &&
            scanned.info.route == negaflow::imaging::FilmLookRoute::identity &&
            same_pixels(scanned.image.pixels, source.pixels),
        "a selected B&W stock remains identity for a film scan");
    expect(
        color_mismatch.status == negaflow::imaging::WorkingFilmLookStatus::ok &&
            color_mismatch.info.route ==
                negaflow::imaging::FilmLookRoute::identity &&
            same_pixels(color_mismatch.image.pixels, source.pixels) &&
            bw_mismatch.status == negaflow::imaging::WorkingFilmLookStatus::ok &&
            bw_mismatch.info.route ==
                negaflow::imaging::FilmLookRoute::identity &&
            same_pixels(bw_mismatch.image.pixels, source.pixels),
        "color and B&W process/profile mismatches are exact identity");

    std::vector<negaflow::imaging::FilmEmulationAcutanceScratchPixel> scratch(
        negaflow::imaging::film_emulation_acutance_scratch_pixel_count(
            source.width));
    const auto matched = negaflow::imaging::apply_working_film_look(
        source,
        {DevelopSourceKind::rendered_digital, FilmEmulation::tri_x_400, 0.8,
         0.8, 0.8, true},
        {nullptr, {scratch.data(), scratch.size()}});
    expect(
        matched.status == negaflow::imaging::WorkingFilmLookStatus::ok &&
            matched.info.route ==
                negaflow::imaging::FilmLookRoute::digital_film_look &&
            matched.info.bw_emulsion_applied &&
            !matched.info.color_applied &&
            !matched.info.color_cube_built &&
            !same_pixels(matched.image.pixels, source.pixels),
        "a matched digital B&W route needs no color cube and changes pixels");
}

}  // namespace

int main() {
    test_complete_distinct_profile_registry();
    test_spectral_response_contract();
    test_complete_material_order_and_neutral_grain();
    test_route_identity_and_matched_pipeline();

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"digital_bw_film_look\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
