#pragma once

#include "negaflow/imaging/working_film_look.h"
#include "negaflow/pipeline/film_look_workspace.h"

#include <cstdint>
#include <string_view>

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

// The Film Look workspace moved to negaflow_pipeline so the C ABI can run the same
// pipeline. These aliases keep the command call sites reading the same way.
using FilmLookWorkspacePrepareStatus =
    negaflow::pipeline::FilmLookWorkspacePrepareStatus;
using FilmLookCommandWorkspace = negaflow::pipeline::FilmLookWorkspaceStorage;

using negaflow::pipeline::film_look_workspace_bytes;
using negaflow::pipeline::film_look_workspace_prepare_status_name;
using negaflow::pipeline::film_look_workspace_view;
using negaflow::pipeline::prepare_film_look_workspace;

}  // namespace negaflow::cli
