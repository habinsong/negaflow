#pragma once

#include "negaflow/imaging/working_film_look.h"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string_view>
#include <vector>

namespace negaflow::cli {

enum class FilmLookRecipeParseStatus : std::uint8_t {
    ok = 0,
    unknown_source_kind,
    unknown_emulation,
    invalid_intensity,
    invalid_parameters,
};

struct FilmLookCommandRecipe final {
    negaflow::imaging::WorkingFilmLookParameters parameters{};
    bool arguments_explicit{false};
};

[[nodiscard]] FilmLookRecipeParseStatus parse_film_look_recipe(
    std::wstring_view source_kind,
    std::wstring_view emulation,
    std::wstring_view intensity,
    FilmLookCommandRecipe& recipe) noexcept;

[[nodiscard]] const char* film_look_recipe_parse_status_name(
    FilmLookRecipeParseStatus status) noexcept;
[[nodiscard]] const char* film_emulation_recipe_name(
    negaflow::imaging::FilmEmulation emulation) noexcept;

enum class FilmLookWorkspacePrepareStatus : std::uint8_t {
    ok = 0,
    invalid_parameters,
    size_overflow,
    allocation_failed,
};

struct FilmLookCommandWorkspace final {
    std::unique_ptr<negaflow::imaging::FilmEmulationColorCube> color_cube{};
    std::vector<negaflow::imaging::FilmEmulationAcutanceScratchPixel>
        acutance_scratch{};
};

[[nodiscard]] FilmLookWorkspacePrepareStatus prepare_film_look_workspace(
    const negaflow::imaging::WorkingFilmLookParameters& parameters,
    std::uint32_t image_width,
    FilmLookCommandWorkspace& storage) noexcept;

[[nodiscard]] negaflow::imaging::WorkingFilmLookWorkspace
film_look_workspace_view(FilmLookCommandWorkspace& storage) noexcept;

[[nodiscard]] std::size_t film_look_workspace_bytes(
    const FilmLookCommandWorkspace& storage) noexcept;

[[nodiscard]] const char* film_look_workspace_prepare_status_name(
    FilmLookWorkspacePrepareStatus status) noexcept;

}  // namespace negaflow::cli
