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

constexpr std::array<EmulationCase, 12> emulation_cases{{
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
        negaflow::imaging::DevelopSourceKind::film_scan,
        negaflow::imaging::FilmEmulation::velvia_50,
        0.73,
    };
    expect(
        negaflow::cli::prepare_film_look_workspace(active, 4U, storage) ==
                negaflow::cli::FilmLookWorkspacePrepareStatus::ok &&
            storage.color_cube != nullptr &&
            storage.acutance_scratch.size() == 44U,
        "an active film recipe allocates one cube and eleven scratch rows");
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
            {negaflow::imaging::DevelopSourceKind::film_scan,
             negaflow::imaging::FilmEmulation::velvia_50,
             0.024},
            4U,
            storage) == negaflow::cli::FilmLookWorkspacePrepareStatus::ok &&
            storage.color_cube == nullptr &&
            storage.acutance_scratch.size() == 44U,
        "a spatial-only low strength avoids color cube allocation");
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
