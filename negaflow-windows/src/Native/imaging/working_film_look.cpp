#include "negaflow/imaging/working_film_look.h"

#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

void discard_pixels(WorkingImage& image) noexcept {
    std::vector<negaflow::core::Rgba32F>{}.swap(image.pixels);
}

[[nodiscard]] bool valid_source_kind(
    const DevelopSourceKind source_kind) noexcept {
    switch (source_kind) {
        case DevelopSourceKind::film_scan:
        case DevelopSourceKind::rendered_digital:
            return true;
    }
    return false;
}

[[nodiscard]] negaflow::core::ConstImageView const_view(
    const WorkingImage& image) noexcept {
    return {
        image.pixels.data(),
        image.pixels.size(),
        image.width,
        image.height,
        image.stride_pixels,
    };
}

[[nodiscard]] negaflow::core::ImageView mutable_view(
    WorkingImage& image) noexcept {
    return {
        image.pixels.data(),
        image.pixels.size(),
        image.width,
        image.height,
        image.stride_pixels,
    };
}

[[nodiscard]] FilmEmulationColorParameters color_parameters(
    const WorkingFilmLookParameters& parameters) noexcept {
    return {parameters.emulation, parameters.intensity};
}

[[nodiscard]] FilmEmulationAcutanceParameters acutance_parameters(
    const WorkingFilmLookParameters& parameters) noexcept {
    return {parameters.emulation, parameters.intensity};
}

void fail_kernel(
    WorkingFilmLookResult& result,
    const negaflow::core::KernelStatus status) noexcept {
    result.info.kernel_status = status;
    result.status = WorkingFilmLookStatus::kernel_failed;
    discard_pixels(result.image);
}

}  // namespace

bool valid_working_film_look_parameters(
    const WorkingFilmLookParameters& parameters) noexcept {
    return valid_source_kind(parameters.source_kind) &&
           valid_film_emulation_color_parameters(color_parameters(parameters)) &&
           valid_film_emulation_acutance_parameters(
               acutance_parameters(parameters));
}

bool try_resolve_film_look_route(
    const WorkingFilmLookParameters& parameters,
    FilmLookRoute& route) noexcept {
    route = FilmLookRoute::invalid;
    if (!valid_working_film_look_parameters(parameters)) {
        return false;
    }
    const bool changes =
        has_film_emulation_color_change(color_parameters(parameters)) ||
        has_film_emulation_acutance_change(acutance_parameters(parameters));
    if (!changes) {
        route = FilmLookRoute::identity;
        return true;
    }
    route = parameters.source_kind == DevelopSourceKind::rendered_digital
                ? FilmLookRoute::digital_film_look
                : FilmLookRoute::film_scan_emulation;
    return true;
}

WorkingFilmLookResult apply_working_film_look(
    WorkingImage image,
    const WorkingFilmLookParameters& parameters,
    const WorkingFilmLookWorkspace workspace) noexcept {
    WorkingFilmLookResult result{};
    result.image = std::move(image);
    if (!try_resolve_film_look_route(parameters, result.info.route)) {
        discard_pixels(result.image);
        return result;
    }

    const FilmEmulationColorParameters color = color_parameters(parameters);
    const FilmEmulationAcutanceParameters acutance =
        acutance_parameters(parameters);
    result.info.color_intensity_step =
        film_emulation_intensity_step(color);
    result.info.acutance_amount = film_emulation_acutance_amount(acutance);
    if (has_film_emulation_acutance_change(acutance)) {
        result.info.required_acutance_scratch_pixels =
            film_emulation_acutance_scratch_pixel_count(result.image.width);
    }

    if (result.info.route == FilmLookRoute::digital_film_look) {
        result.status = WorkingFilmLookStatus::unsupported_route;
        discard_pixels(result.image);
        return result;
    }

    if (result.info.route == FilmLookRoute::identity) {
        result.info.kernel_status =
            negaflow::core::validate_finite_pixels(const_view(result.image));
        if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
            fail_kernel(result, result.info.kernel_status);
            return result;
        }
        result.status = WorkingFilmLookStatus::ok;
        return result;
    }

    const negaflow::core::KernelStatus image_status =
        negaflow::core::validate_image_view(const_view(result.image));
    if (image_status != negaflow::core::KernelStatus::ok) {
        fail_kernel(result, image_status);
        return result;
    }

    if (has_film_emulation_color_change(color) &&
        workspace.color_cube == nullptr) {
        fail_kernel(result, negaflow::core::KernelStatus::invalid_argument);
        return result;
    }
    if (has_film_emulation_acutance_change(acutance)) {
        if (result.info.required_acutance_scratch_pixels == 0U) {
            fail_kernel(result, negaflow::core::KernelStatus::size_overflow);
            return result;
        }
        if (workspace.acutance.pixels == nullptr) {
            fail_kernel(result, negaflow::core::KernelStatus::invalid_argument);
            return result;
        }
        if (workspace.acutance.pixel_capacity <
            result.info.required_acutance_scratch_pixels) {
            fail_kernel(result, negaflow::core::KernelStatus::buffer_too_small);
            return result;
        }
    }

    if (has_film_emulation_color_change(color)) {
        if (workspace.color_cube->ready &&
            workspace.color_cube->emulation == color.emulation &&
            workspace.color_cube->intensity_step ==
                result.info.color_intensity_step) {
            result.info.color_cube_reused = true;
        } else {
            const negaflow::core::KernelStatus build_status =
                build_film_emulation_color_cube(color, *workspace.color_cube);
            if (build_status != negaflow::core::KernelStatus::ok) {
                fail_kernel(result, build_status);
                return result;
            }
            result.info.color_cube_built = true;
        }
        const negaflow::core::KernelStatus color_status =
            apply_film_emulation_color_cube(
                const_view(result.image),
                mutable_view(result.image),
                color,
                workspace.color_cube);
        if (color_status != negaflow::core::KernelStatus::ok) {
            fail_kernel(result, color_status);
            return result;
        }
        result.info.color_applied = true;
    }

    if (has_film_emulation_acutance_change(acutance)) {
        const negaflow::core::KernelStatus acutance_status =
            apply_film_emulation_acutance(
                const_view(result.image),
                mutable_view(result.image),
                acutance,
                workspace.acutance);
        if (acutance_status != negaflow::core::KernelStatus::ok) {
            fail_kernel(result, acutance_status);
            return result;
        }
        result.info.acutance_applied = true;
    }

    result.info.kernel_status = negaflow::core::KernelStatus::ok;
    result.status = WorkingFilmLookStatus::ok;
    return result;
}

const char* develop_source_kind_name(
    const DevelopSourceKind source_kind) noexcept {
    switch (source_kind) {
        case DevelopSourceKind::film_scan:
            return "film_scan";
        case DevelopSourceKind::rendered_digital:
            return "rendered_digital";
    }
    return "unknown";
}

const char* film_look_route_name(const FilmLookRoute route) noexcept {
    switch (route) {
        case FilmLookRoute::invalid:
            return "invalid";
        case FilmLookRoute::identity:
            return "identity";
        case FilmLookRoute::film_scan_emulation:
            return "film_scan_emulation";
        case FilmLookRoute::digital_film_look:
            return "digital_film_look";
    }
    return "unknown";
}

const char* working_film_look_status_name(
    const WorkingFilmLookStatus status) noexcept {
    switch (status) {
        case WorkingFilmLookStatus::ok:
            return "ok";
        case WorkingFilmLookStatus::invalid_parameter:
            return "invalid_parameter";
        case WorkingFilmLookStatus::unsupported_route:
            return "unsupported_route";
        case WorkingFilmLookStatus::kernel_failed:
            return "kernel_failed";
    }
    return "unknown";
}

}  // namespace negaflow::imaging
