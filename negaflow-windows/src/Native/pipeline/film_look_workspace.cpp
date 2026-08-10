#include "negaflow/pipeline/film_look_workspace.h"

#include <new>

namespace negaflow::pipeline {

FilmLookWorkspacePrepareStatus prepare_film_look_workspace(
    const negaflow::imaging::WorkingFilmLookParameters& parameters,
    const std::uint32_t image_width,
    FilmLookWorkspaceStorage& storage) noexcept {
    storage.color_cube.reset();
    std::vector<negaflow::imaging::FilmEmulationAcutanceScratchPixel>{}.swap(
        storage.acutance_scratch);
    if (!negaflow::imaging::valid_working_film_look_parameters(parameters)) {
        return FilmLookWorkspacePrepareStatus::invalid_parameters;
    }
    negaflow::imaging::FilmLookRoute route{};
    if (!negaflow::imaging::try_resolve_film_look_route(parameters, route)) {
        return FilmLookWorkspacePrepareStatus::invalid_parameters;
    }
    if (route == negaflow::imaging::FilmLookRoute::identity) {
        return FilmLookWorkspacePrepareStatus::ok;
    }
    if (negaflow::imaging::has_film_emulation_color_change(
            {parameters.emulation, parameters.intensity})) {
        storage.color_cube =
            std::unique_ptr<negaflow::imaging::FilmEmulationColorCube>{
                new (std::nothrow) negaflow::imaging::FilmEmulationColorCube};
        if (storage.color_cube == nullptr) {
            return FilmLookWorkspacePrepareStatus::allocation_failed;
        }
    }
    if (negaflow::imaging::has_film_emulation_acutance_change(
            {parameters.emulation, parameters.intensity})) {
        const std::size_t required =
            negaflow::imaging::film_emulation_acutance_scratch_pixel_count(
                image_width);
        if (required == 0U) {
            storage.color_cube.reset();
            return FilmLookWorkspacePrepareStatus::size_overflow;
        }
        try {
            storage.acutance_scratch.resize(required);
        } catch (const std::bad_alloc&) {
            storage.color_cube.reset();
            return FilmLookWorkspacePrepareStatus::allocation_failed;
        }
    }
    return FilmLookWorkspacePrepareStatus::ok;
}

negaflow::imaging::WorkingFilmLookWorkspace film_look_workspace_view(
    FilmLookWorkspaceStorage& storage) noexcept {
    return {
        storage.color_cube.get(),
        {storage.acutance_scratch.data(), storage.acutance_scratch.size()},
    };
}

std::size_t film_look_workspace_bytes(
    const FilmLookWorkspaceStorage& storage) noexcept {
    const std::size_t color_bytes = storage.color_cube == nullptr
        ? 0U
        : sizeof(negaflow::imaging::FilmEmulationColorCube);
    return color_bytes +
           (storage.acutance_scratch.size() *
            sizeof(negaflow::imaging::FilmEmulationAcutanceScratchPixel));
}

const char* film_look_workspace_prepare_status_name(
    const FilmLookWorkspacePrepareStatus status) noexcept {
    switch (status) {
        case FilmLookWorkspacePrepareStatus::ok:
            return "ok";
        case FilmLookWorkspacePrepareStatus::invalid_parameters:
            return "invalid_film_look_parameters";
        case FilmLookWorkspacePrepareStatus::size_overflow:
            return "film_look_workspace_size_overflow";
        case FilmLookWorkspacePrepareStatus::allocation_failed:
            return "film_look_workspace_allocation_failed";
    }
    return "unknown_film_look_workspace_status";
}

}  // namespace negaflow::pipeline
