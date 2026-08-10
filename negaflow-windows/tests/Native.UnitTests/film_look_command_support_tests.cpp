#include "film_look_command_support.h"

#include <array>
#include <cstddef>
#include <iostream>
#include <string_view>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

struct EmulationCase final {
    const wchar_t* argument;
    negaflow::imaging::FilmEmulation emulation;
    const char* report_name;
};

constexpr std::array<EmulationCase, 43> emulation_cases{{
    {L"none", negaflow::imaging::FilmEmulation::none, "none"},
    {L"ektachrome_e100", negaflow::imaging::FilmEmulation::ektachrome_e100,
     "ektachrome_e100"},
    {L"provia_100f", negaflow::imaging::FilmEmulation::provia_100f,
     "provia_100f"},
    {L"velvia_50", negaflow::imaging::FilmEmulation::velvia_50, "velvia_50"},
    {L"portra_160", negaflow::imaging::FilmEmulation::portra_160, "portra_160"},
    {L"portra_400", negaflow::imaging::FilmEmulation::portra_400, "portra_400"},
    {L"portra_800", negaflow::imaging::FilmEmulation::portra_800, "portra_800"},
    {L"ektar_100", negaflow::imaging::FilmEmulation::ektar_100, "ektar_100"},
    {L"ultramax_400", negaflow::imaging::FilmEmulation::ultramax_400,
     "ultramax_400"},
    {L"colorplus_200", negaflow::imaging::FilmEmulation::colorplus_200,
     "colorplus_200"},
    {L"fujicolor_c200", negaflow::imaging::FilmEmulation::fujicolor_c200,
     "fujicolor_c200"},
    {L"pro_400h", negaflow::imaging::FilmEmulation::pro_400h, "pro_400h"},
    {L"tri_x_400", negaflow::imaging::FilmEmulation::tri_x_400, "tri_x_400"},
    {L"hp5_plus", negaflow::imaging::FilmEmulation::hp5_plus, "hp5_plus"},
    {L"fp4_plus", negaflow::imaging::FilmEmulation::fp4_plus, "fp4_plus"},
    {L"delta_100", negaflow::imaging::FilmEmulation::delta_100, "delta_100"},
    {L"delta_400", negaflow::imaging::FilmEmulation::delta_400, "delta_400"},
    {L"delta_3200", negaflow::imaging::FilmEmulation::delta_3200, "delta_3200"},
    {L"tmax_100", negaflow::imaging::FilmEmulation::tmax_100, "tmax_100"},
    {L"tmax_400", negaflow::imaging::FilmEmulation::tmax_400, "tmax_400"},
    {L"tmax_p3200", negaflow::imaging::FilmEmulation::tmax_p3200,
     "tmax_p3200"},
    {L"kentmere_400", negaflow::imaging::FilmEmulation::kentmere_400,
     "kentmere_400"},
    {L"ortho_plus", negaflow::imaging::FilmEmulation::ortho_plus,
     "ortho_plus"},
    {L"sfx_200", negaflow::imaging::FilmEmulation::sfx_200, "sfx_200"},
    {L"rollei_ir", negaflow::imaging::FilmEmulation::rollei_ir, "rollei_ir"},
    {L"scala_200x", negaflow::imaging::FilmEmulation::scala_200x,
     "scala_200x"},
    {L"rollei_superpan", negaflow::imaging::FilmEmulation::rollei_superpan,
     "rollei_superpan"},
    {L"velvia_100", negaflow::imaging::FilmEmulation::velvia_100,
     "velvia_100"},
    {L"e100_vs", negaflow::imaging::FilmEmulation::e100_vs, "e100_vs"},
    {L"astia_100f", negaflow::imaging::FilmEmulation::astia_100f,
     "astia_100f"},
    {L"kodachrome_64", negaflow::imaging::FilmEmulation::kodachrome_64,
     "kodachrome_64"},
    {L"gold_200", negaflow::imaging::FilmEmulation::gold_200, "gold_200"},
    {L"pro_image_100", negaflow::imaging::FilmEmulation::pro_image_100,
     "pro_image_100"},
    {L"superia_400", negaflow::imaging::FilmEmulation::superia_400,
     "superia_400"},
    {L"superia_premium_400",
     negaflow::imaging::FilmEmulation::superia_premium_400,
     "superia_premium_400"},
    {L"superia_200", negaflow::imaging::FilmEmulation::superia_200,
     "superia_200"},
    {L"reala_100", negaflow::imaging::FilmEmulation::reala_100,
     "reala_100"},
    {L"industrial_100", negaflow::imaging::FilmEmulation::industrial_100,
     "industrial_100"},
    {L"lomo_cn_800", negaflow::imaging::FilmEmulation::lomo_cn_800,
     "lomo_cn_800"},
    {L"vision3_500t", negaflow::imaging::FilmEmulation::vision3_500t,
     "vision3_500t"},
    {L"vision3_250d", negaflow::imaging::FilmEmulation::vision3_250d,
     "vision3_250d"},
    {L"vision3_50d", negaflow::imaging::FilmEmulation::vision3_50d,
     "vision3_50d"},
    {L"vision3_200t", negaflow::imaging::FilmEmulation::vision3_200t,
     "vision3_200t"},
}};

void test_recipe_parsing() {
    for (const EmulationCase& item : emulation_cases) {
        negaflow::cli::FilmLookCommandRecipe recipe{};
        const auto status = negaflow::cli::parse_film_look_recipe(
            L"film_scan", item.argument, L"0.73", recipe);
        expect(status == negaflow::cli::FilmLookRecipeParseStatus::ok,
               "a known film emulation parses");
        expect(recipe.arguments_explicit &&
                   recipe.parameters.source_kind ==
                       negaflow::imaging::DevelopSourceKind::film_scan &&
                   recipe.parameters.emulation == item.emulation &&
                   recipe.parameters.intensity == 0.73,
               "a parsed recipe preserves every explicit field");
        expect(std::string_view{
                   negaflow::cli::film_emulation_recipe_name(item.emulation)} ==
                   item.report_name,
               "a known film emulation round-trips to its report name");
    }

    negaflow::cli::FilmLookCommandRecipe digital{};
    expect(
        negaflow::cli::parse_film_look_recipe(
            L"rendered_digital", L"velvia_50", L"1", digital) ==
                negaflow::cli::FilmLookRecipeParseStatus::ok &&
            digital.parameters.source_kind ==
                negaflow::imaging::DevelopSourceKind::rendered_digital,
        "rendered digital is parsed as a distinct explicit source");

    negaflow::cli::FilmLookCommandRecipe invalid{};
    expect(
        negaflow::cli::parse_film_look_recipe(
            L"guessed", L"velvia_50", L"1", invalid) ==
            negaflow::cli::FilmLookRecipeParseStatus::unknown_source_kind,
        "an unknown source kind is not inferred");
    expect(
        negaflow::cli::parse_film_look_recipe(
            L"film_scan", L"unknown", L"1", invalid) ==
            negaflow::cli::FilmLookRecipeParseStatus::unknown_emulation,
        "an unknown film emulation is rejected");
    expect(
        negaflow::cli::parse_film_look_recipe(
            L"film_scan", L"velvia_50", L"0.73suffix", invalid) ==
            negaflow::cli::FilmLookRecipeParseStatus::invalid_intensity,
        "a partially parsed film look intensity is rejected");
    expect(
        negaflow::cli::parse_film_look_recipe(
            L"film_scan", L"velvia_50", L"nan", invalid) ==
            negaflow::cli::FilmLookRecipeParseStatus::invalid_intensity,
        "a non-finite film look intensity is rejected");
}

void test_workspace_preparation() {
    negaflow::cli::FilmLookCommandWorkspace storage{};
    expect(
        negaflow::cli::prepare_film_look_workspace(
            {negaflow::imaging::DevelopSourceKind::film_scan,
             negaflow::imaging::FilmEmulation::none,
             1.0},
            4U,
            storage) == negaflow::cli::FilmLookWorkspacePrepareStatus::ok &&
            storage.color_cube == nullptr && storage.acutance_scratch.empty() &&
            negaflow::cli::film_look_workspace_bytes(storage) == 0U,
        "an identity recipe allocates no workspace");

    const negaflow::imaging::WorkingFilmLookParameters active{
        negaflow::imaging::DevelopSourceKind::rendered_digital,
        negaflow::imaging::FilmEmulation::velvia_50,
        0.73,
    };
    expect(
        negaflow::cli::prepare_film_look_workspace(active, 4U, storage) ==
                negaflow::cli::FilmLookWorkspacePrepareStatus::ok &&
            storage.color_cube != nullptr &&
            storage.acutance_scratch.size() == 44U,
        "an active digital recipe allocates one cube and eleven scratch rows");
    const auto view = negaflow::cli::film_look_workspace_view(storage);
    expect(
        view.color_cube == storage.color_cube.get() &&
            view.acutance.pixels == storage.acutance_scratch.data() &&
            view.acutance.pixel_capacity == storage.acutance_scratch.size(),
        "the workspace view borrows the owned storage exactly");
    expect(
        negaflow::cli::film_look_workspace_bytes(storage) ==
            sizeof(negaflow::imaging::FilmEmulationColorCube) +
                (44U * sizeof(
                    negaflow::imaging::FilmEmulationAcutanceScratchPixel)),
        "workspace bytes include cube storage and bounded scratch");

    expect(
        negaflow::cli::prepare_film_look_workspace(
            {negaflow::imaging::DevelopSourceKind::rendered_digital,
             negaflow::imaging::FilmEmulation::velvia_50,
             0.024},
            4U,
            storage) == negaflow::cli::FilmLookWorkspacePrepareStatus::ok &&
            storage.color_cube == nullptr &&
            storage.acutance_scratch.size() == 44U,
        "a spatial-only low strength avoids color cube allocation");

    expect(
        negaflow::cli::prepare_film_look_workspace(
            {negaflow::imaging::DevelopSourceKind::rendered_digital,
             negaflow::imaging::FilmEmulation::tri_x_400,
             0.8,
             0.0,
             0.0,
             true},
            4U,
            storage) == negaflow::cli::FilmLookWorkspacePrepareStatus::ok &&
            storage.color_cube == nullptr &&
            storage.acutance_scratch.size() == 44U,
        "a matched B&W recipe allocates acutance scratch without a color cube");

    expect(
        negaflow::cli::prepare_film_look_workspace(
            {negaflow::imaging::DevelopSourceKind::rendered_digital,
             negaflow::imaging::FilmEmulation::tri_x_400,
             0.8},
            4U,
            storage) == negaflow::cli::FilmLookWorkspacePrepareStatus::ok &&
            storage.color_cube == nullptr && storage.acutance_scratch.empty(),
        "a B&W profile selected in a color process allocates no workspace");
}

}  // namespace

int main() {
    test_recipe_parsing();
    test_workspace_preparation();

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"film_look_command_support\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
