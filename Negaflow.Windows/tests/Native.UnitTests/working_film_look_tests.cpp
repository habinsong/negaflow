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
            route ==
                negaflow::imaging::FilmLookRoute::film_scan_emulation,
        "an active film scan resolves to the bounded film stage");
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
    auto cube = allocate_cube();
    expect(cube != nullptr, "the caller-owned route cube allocates");
    if (cube == nullptr) {
        return;
    }
    std::vector<negaflow::imaging::FilmEmulationAcutanceScratchPixel> scratch(
        negaflow::imaging::film_emulation_acutance_scratch_pixel_count(4U));
    const negaflow::imaging::WorkingFilmLookParameters parameters{
        negaflow::imaging::DevelopSourceKind::film_scan,
        negaflow::imaging::FilmEmulation::velvia_50,
        0.73,
    };

    auto manual = make_working_image();
    expect(
        negaflow::imaging::build_film_emulation_color_cube(
            {parameters.emulation, parameters.intensity},
            *cube) == negaflow::core::KernelStatus::ok &&
            negaflow::imaging::apply_film_emulation_color_cube(
                {manual.pixels.data(), manual.pixels.size(), 4U, 3U, 4U},
                {manual.pixels.data(), manual.pixels.size(), 4U, 3U, 4U},
                {parameters.emulation, parameters.intensity},
                cube.get()) == negaflow::core::KernelStatus::ok &&
            negaflow::imaging::apply_film_emulation_acutance(
                {manual.pixels.data(), manual.pixels.size(), 4U, 3U, 4U},
                {manual.pixels.data(), manual.pixels.size(), 4U, 3U, 4U},
                {parameters.emulation, parameters.intensity},
                {scratch.data(), scratch.size()}) ==
                negaflow::core::KernelStatus::ok,
        "the manual color then acutance sequence succeeds");

    cube->ready = false;
    auto routed = negaflow::imaging::apply_working_film_look(
        make_working_image(),
        parameters,
        {cube.get(), {scratch.data(), scratch.size()}});
    expect(
        routed.status == negaflow::imaging::WorkingFilmLookStatus::ok &&
            routed.info.route ==
                negaflow::imaging::FilmLookRoute::film_scan_emulation &&
            routed.info.color_cube_built &&
            !routed.info.color_cube_reused && routed.info.color_applied &&
            routed.info.acutance_applied &&
            routed.info.color_intensity_step == 15U &&
            std::abs(routed.info.acutance_amount - 0.1606) < 1.0e-12 &&
            routed.info.required_acutance_scratch_pixels == 44U,
        "the film route reports its exact ordered work and bounded workspace");
    expect(
        std::ranges::equal(routed.image.pixels, manual.pixels, same_pixel),
        "the routed result is bit-exact with manual color then acutance");

    auto reused = negaflow::imaging::apply_working_film_look(
        make_working_image(),
        parameters,
        {cube.get(), {scratch.data(), scratch.size()}});
    expect(
        reused.status == negaflow::imaging::WorkingFilmLookStatus::ok &&
            !reused.info.color_cube_built && reused.info.color_cube_reused &&
            std::ranges::equal(reused.image.pixels, manual.pixels, same_pixel),
        "a matching caller cube is reused without changing pixels");
}

void test_spatial_only_low_strength_and_identity() {
    std::vector<negaflow::imaging::FilmEmulationAcutanceScratchPixel> scratch(
        negaflow::imaging::film_emulation_acutance_scratch_pixel_count(4U));
    const negaflow::imaging::WorkingFilmLookParameters low{
        negaflow::imaging::DevelopSourceKind::film_scan,
        negaflow::imaging::FilmEmulation::velvia_50,
        0.024,
    };
    auto manual = make_working_image();
    expect(
        negaflow::imaging::apply_film_emulation_acutance(
            {manual.pixels.data(), manual.pixels.size(), 4U, 3U, 4U},
            {manual.pixels.data(), manual.pixels.size(), 4U, 3U, 4U},
            {low.emulation, low.intensity},
            {scratch.data(), scratch.size()}) ==
            negaflow::core::KernelStatus::ok,
        "the low-strength manual acutance applies");
    const auto routed = negaflow::imaging::apply_working_film_look(
        make_working_image(),
        low,
        {nullptr, {scratch.data(), scratch.size()}});
    expect(
        routed.status == negaflow::imaging::WorkingFilmLookStatus::ok &&
            !routed.info.color_applied && routed.info.acutance_applied &&
            routed.info.color_intensity_step == 0U &&
            std::ranges::equal(routed.image.pixels, manual.pixels, same_pixel),
        "unquantized spatial strength remains active below the first color step");

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

    const auto digital = negaflow::imaging::apply_working_film_look(
        make_working_image(),
        {negaflow::imaging::DevelopSourceKind::rendered_digital,
         negaflow::imaging::FilmEmulation::velvia_50,
         0.73});
    expect(
        digital.status ==
                negaflow::imaging::WorkingFilmLookStatus::unsupported_route &&
            digital.info.route ==
                negaflow::imaging::FilmLookRoute::digital_film_look &&
            digital.info.kernel_status ==
                negaflow::core::KernelStatus::ok &&
            digital.image.pixels.empty(),
        "an incomplete digital graph is a visible failure with no pixels");

    const negaflow::imaging::WorkingFilmLookParameters film{
        negaflow::imaging::DevelopSourceKind::film_scan,
        negaflow::imaging::FilmEmulation::velvia_50,
        0.73,
    };
    const auto missing_cube = negaflow::imaging::apply_working_film_look(
        make_working_image(),
        film);
    expect(
        missing_cube.status ==
                negaflow::imaging::WorkingFilmLookStatus::kernel_failed &&
            missing_cube.info.kernel_status ==
                negaflow::core::KernelStatus::invalid_argument &&
            missing_cube.image.pixels.empty(),
        "an active color route fails closed without a caller cube");

    auto invalid_layout_source = make_working_image();
    invalid_layout_source.width = 0U;
    const auto invalid_layout =
        negaflow::imaging::apply_working_film_look(
            std::move(invalid_layout_source),
            film);
    expect(
        invalid_layout.status ==
                negaflow::imaging::WorkingFilmLookStatus::kernel_failed &&
            invalid_layout.info.kernel_status ==
                negaflow::core::KernelStatus::invalid_dimensions &&
            invalid_layout.image.pixels.empty(),
        "an invalid image layout is reported before missing workspace");

    auto cube = allocate_cube();
    expect(cube != nullptr, "the failure-test cube allocates");
    if (cube == nullptr) {
        return;
    }
    std::vector<negaflow::imaging::FilmEmulationAcutanceScratchPixel> small(43U);
    const auto small_scratch = negaflow::imaging::apply_working_film_look(
        make_working_image(),
        film,
        {cube.get(), {small.data(), small.size()}});
    expect(
        small_scratch.status ==
                negaflow::imaging::WorkingFilmLookStatus::kernel_failed &&
            !small_scratch.info.color_cube_built &&
            !small_scratch.info.color_applied &&
            small_scratch.info.kernel_status ==
                negaflow::core::KernelStatus::buffer_too_small &&
            small_scratch.image.pixels.empty(),
        "a small spatial workspace fails before building or applying color");

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
    test_spatial_only_low_strength_and_identity();
    test_fail_closed_routes_and_workspace_errors();

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"working_film_look\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
