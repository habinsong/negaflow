#include "negaflow/imaging/working_film_look.h"
#include "film_emulation_color_fixture.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <limits>
#include <memory>
#include <new>
#include <utility>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] std::unique_ptr<negaflow::imaging::FilmEmulationColorCube>
allocate_cube() {
    return std::unique_ptr<negaflow::imaging::FilmEmulationColorCube>{
        new (std::nothrow) negaflow::imaging::FilmEmulationColorCube};
}

[[nodiscard]] negaflow::imaging::WorkingImage make_working_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 4U;
    image.height = 3U;
    image.stride_pixels = 4U;
    image.pixels.assign(
        negaflow::fixtures::film_emulation_color_input.begin(),
        negaflow::fixtures::film_emulation_color_input.end());
    return image;
}

[[nodiscard]] bool same_pixel(
    const negaflow::core::Rgba32F left,
    const negaflow::core::Rgba32F right) noexcept {
    return left.red == right.red && left.green == right.green &&
           left.blue == right.blue && left.alpha == right.alpha;
}

void test_explicit_route_resolution() {
    negaflow::imaging::FilmLookRoute route =
        negaflow::imaging::FilmLookRoute::invalid;
    expect(
        negaflow::imaging::try_resolve_film_look_route(
            {negaflow::imaging::DevelopSourceKind::film_scan,
             negaflow::imaging::FilmEmulation::none,
             1.0},
            route) &&
            route == negaflow::imaging::FilmLookRoute::identity,
        "a film scan without a selected look resolves to identity");
    expect(
        negaflow::imaging::try_resolve_film_look_route(
            {negaflow::imaging::DevelopSourceKind::film_scan,
             negaflow::imaging::FilmEmulation::velvia_50,
             0.73},
            route) &&
            route == negaflow::imaging::FilmLookRoute::identity,
        "an active film scan bypasses a second emulsion response");
    expect(
        negaflow::imaging::try_resolve_film_look_route(
            {negaflow::imaging::DevelopSourceKind::rendered_digital,
             negaflow::imaging::FilmEmulation::velvia_50,
             0.73},
            route) &&
            route == negaflow::imaging::FilmLookRoute::digital_film_look,
        "an active digital source resolves to its distinct complete graph");
    expect(
        negaflow::imaging::try_resolve_film_look_route(
            {negaflow::imaging::DevelopSourceKind::rendered_digital,
             negaflow::imaging::FilmEmulation::velvia_50,
             0.73,
             0.0,
             0.0,
             true},
            route) &&
            route == negaflow::imaging::FilmLookRoute::identity,
        "a color stock is not applied to a monochrome digital process");
    expect(
        negaflow::imaging::try_resolve_film_look_route(
            {negaflow::imaging::DevelopSourceKind::film_scan,
             negaflow::imaging::FilmEmulation::velvia_50,
             0.001},
            route) &&
            route == negaflow::imaging::FilmLookRoute::identity,
        "the macOS strength threshold resolves to identity");
    expect(
        !negaflow::imaging::try_resolve_film_look_route(
            {static_cast<negaflow::imaging::DevelopSourceKind>(255U),
             negaflow::imaging::FilmEmulation::velvia_50,
             1.0},
            route) &&
            route == negaflow::imaging::FilmLookRoute::invalid,
        "an unknown source kind is rejected rather than inferred");
    expect(
        !negaflow::imaging::try_resolve_film_look_route(
            {negaflow::imaging::DevelopSourceKind::film_scan,
             negaflow::imaging::FilmEmulation::velvia_50,
             std::numeric_limits<double>::quiet_NaN()},
            route),
        "a non-finite film look strength is rejected");
}

void test_film_scan_order_and_workspace_reuse() {
    const negaflow::imaging::WorkingFilmLookParameters parameters{
        negaflow::imaging::DevelopSourceKind::film_scan,
        negaflow::imaging::FilmEmulation::velvia_50,
        0.73,
    };
    const auto source = make_working_image();
    auto routed = negaflow::imaging::apply_working_film_look(
        source,
        parameters);
    expect(
        routed.status == negaflow::imaging::WorkingFilmLookStatus::ok &&
            routed.info.route == negaflow::imaging::FilmLookRoute::identity &&
            !routed.info.color_applied && !routed.info.acutance_applied &&
            std::ranges::equal(routed.image.pixels, source.pixels, same_pixel),
        "a film scan preserves pixels and needs no film-look workspace");
}

void test_identity() {
    const auto source = make_working_image();
    const auto identity = negaflow::imaging::apply_working_film_look(
        source,
        {negaflow::imaging::DevelopSourceKind::rendered_digital,
         negaflow::imaging::FilmEmulation::none,
         1.0});
    expect(
        identity.status == negaflow::imaging::WorkingFilmLookStatus::ok &&
            identity.info.route == negaflow::imaging::FilmLookRoute::identity &&
            std::ranges::equal(identity.image.pixels, source.pixels, same_pixel),
        "an identity route needs no workspace and preserves pixels bit exactly");
}

void test_fail_closed_routes_and_workspace_errors() {
    const auto invalid_parameters =
        negaflow::imaging::apply_working_film_look(
            make_working_image(),
            {static_cast<negaflow::imaging::DevelopSourceKind>(255U),
             negaflow::imaging::FilmEmulation::velvia_50,
             0.73});
    expect(
        invalid_parameters.status ==
                negaflow::imaging::WorkingFilmLookStatus::invalid_parameter &&
            invalid_parameters.info.route ==
                negaflow::imaging::FilmLookRoute::invalid &&
            invalid_parameters.image.pixels.empty(),
        "invalid route parameters fail closed without published pixels");

    auto digital_cube = allocate_cube();
    expect(digital_cube != nullptr, "the digital-route cube allocates");
    if (digital_cube == nullptr) {
        return;
    }
    std::vector<negaflow::imaging::FilmEmulationAcutanceScratchPixel>
        digital_scratch(
            negaflow::imaging::film_emulation_acutance_scratch_pixel_count(4U));
    const auto digital = negaflow::imaging::apply_working_film_look(
        make_working_image(),
        {negaflow::imaging::DevelopSourceKind::rendered_digital,
         negaflow::imaging::FilmEmulation::vision3_500t,
         0.73},
        {digital_cube.get(),
         {digital_scratch.data(), digital_scratch.size()}});
    expect(
        digital.status == negaflow::imaging::WorkingFilmLookStatus::ok &&
            digital.info.route ==
                negaflow::imaging::FilmLookRoute::digital_film_look &&
            digital.info.color_applied && digital.info.acutance_applied &&
            !digital.info.digital_halation_applied &&
            digital.info.digital_color_preset_applied &&
            digital.info.digital_grain_applied &&
            !digital.image.pixels.empty(),
        "the complete digital graph runs in fixed order on a tiny frame");

    auto invalid_source = make_working_image();
    invalid_source.pixels[0].red = std::numeric_limits<float>::infinity();
    const auto invalid_identity = negaflow::imaging::apply_working_film_look(
        std::move(invalid_source),
        {negaflow::imaging::DevelopSourceKind::film_scan,
         negaflow::imaging::FilmEmulation::none,
         1.0});
    expect(
        invalid_identity.status ==
                negaflow::imaging::WorkingFilmLookStatus::kernel_failed &&
            invalid_identity.info.kernel_status ==
                negaflow::core::KernelStatus::non_finite_input &&
            invalid_identity.image.pixels.empty(),
        "identity still validates source pixels before publication");
}

}  // namespace

int main() {
    test_explicit_route_resolution();
    test_film_scan_order_and_workspace_reuse();
    test_identity();
    test_fail_closed_routes_and_workspace_errors();

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"working_film_look\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
