#pragma once

#include "negaflow/imaging/working_film_look.h"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <vector>

namespace negaflow::pipeline {

// The Film Look stage needs a colour cube and an acutance scratch row band whose
// sizes depend on the recipe and the image width. Both are caller-owned so that a
// repeated develop reuses them instead of rebuilding. This lived in the CLI, which
// meant the C ABI could not develop an image without a copy of it; it is shared now.
enum class FilmLookWorkspacePrepareStatus : std::uint8_t {
    ok = 0,
    invalid_parameters,
    size_overflow,
    allocation_failed,
};

struct FilmLookWorkspaceStorage final {
    std::unique_ptr<negaflow::imaging::FilmEmulationColorCube> color_cube{};
    std::vector<negaflow::imaging::FilmEmulationAcutanceScratchPixel>
        acutance_scratch{};
};

[[nodiscard]] FilmLookWorkspacePrepareStatus prepare_film_look_workspace(
    const negaflow::imaging::WorkingFilmLookParameters& parameters,
    std::uint32_t image_width,
    FilmLookWorkspaceStorage& storage) noexcept;

[[nodiscard]] negaflow::imaging::WorkingFilmLookWorkspace film_look_workspace_view(
    FilmLookWorkspaceStorage& storage) noexcept;

[[nodiscard]] std::size_t film_look_workspace_bytes(
    const FilmLookWorkspaceStorage& storage) noexcept;

[[nodiscard]] const char* film_look_workspace_prepare_status_name(
    FilmLookWorkspacePrepareStatus status) noexcept;

}  // namespace negaflow::pipeline
