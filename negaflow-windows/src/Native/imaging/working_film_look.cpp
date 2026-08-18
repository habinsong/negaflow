#include "negaflow/imaging/working_film_look.h"

#include "negaflow/imaging/film_emulation_registry.h"
#include "negaflow/imaging/kernel_accelerator.h"

#include <algorithm>
#include <cmath>
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

// GPU 오케스트레이터에 넘길 계획을 만듭니다.
//
// ☠️ **여기가 게이트를 판정하는 유일한 자리입니다.** 아래 CPU 사슬의 조건과 한 글자도
//    달라선 안 됩니다 — 다르면 GPU 와 CPU 가 다른 것을 하고, 그 차이는 값으로만 드러납니다.
//    비어 있는 칸(널 포인터·`applied=false`·`requested=false`)이 곧 CPU 의 조기 반환입니다.
[[nodiscard]] bool try_plan_digital_film_look(
    const WorkingFilmLookParameters& parameters,
    const FilmEmulationColorParameters& color,
    const FilmEmulationAcutanceParameters& acutance,
    const WorkingFilmLookWorkspace& workspace,
    DigitalFilmLookPlan& plan) noexcept {
    const DigitalFilmPhysics* const physics =
        digital_film_physics(parameters.emulation);
    if (physics == nullptr) {
        // CPU 사슬은 물성이 없으면 헐레이션·그레인을 항등으로 지납니다. 그 경우까지
        // GPU 로 흉내내지 않고 CPU 에 맡깁니다 — 드문 경로에 두 벌을 만들 이유가 없습니다.
        return false;
    }
    const double strength = std::clamp(parameters.intensity, 0.0, 1.0);

    plan.halation_material = {
        physics->scatter_strength,
        physics->halation_strength,
        physics->halation_radius_ratio};
    plan.halation_strength = parameters.halation_override > 1.0e-3
        ? std::clamp(parameters.halation_override, 0.0, 1.0)
        : strength;
    plan.halation_requested = true;

    plan.cube = has_film_emulation_color_change(color) ? workspace.color_cube : nullptr;
    if (plan.cube != nullptr && !plan.cube->ready) {
        return false;
    }

    plan.acutance = has_film_emulation_acutance_change(acutance)
        ? prepare_film_emulation_acutance(acutance)
        : FilmEmulationAcutanceSetup{};

    // 색 프리셋의 세기는 CPU 사슬과 같은 `strength * 0.5` 입니다 — LUT 가 이미 스톡 색을
    // 담고 있어 보조 프리셋은 절반만 더합니다(macOS `DigitalFilmLook.swift:68`).
    const float preset_strength =
        static_cast<float>(std::clamp(strength * 0.5, 0.0, 1.0));
    const DigitalFilmColorPreset* const preset =
        digital_film_color_preset(parameters.emulation);
    plan.preset = (preset != nullptr && preset_strength > 1.0e-3F) ? preset : nullptr;
    plan.preset_strength = preset_strength;

    plan.grain = physics->grain;
    plan.grain_strength = parameters.grain_override > 1.0e-3
        ? std::clamp(parameters.grain_override, 0.0, 1.0)
        : strength;
    plan.grain_requested = true;
    return true;
}

}  // namespace

bool valid_working_film_look_parameters(
    const WorkingFilmLookParameters& parameters) noexcept {
    if (!valid_source_kind(parameters.source_kind) ||
        !valid_film_emulation(parameters.emulation) ||
        !std::isfinite(parameters.intensity) ||
        !std::isfinite(parameters.grain_override) ||
        !std::isfinite(parameters.halation_override)) {
        return false;
    }
    if (parameters.emulation == FilmEmulation::none) {
        return true;
    }
    if (is_black_and_white_film_emulation(parameters.emulation)) {
        return valid_digital_bw_film_look_parameters(
                   {parameters.emulation,
                    parameters.intensity,
                    parameters.grain_override,
                    parameters.halation_override}) &&
               valid_film_emulation_acutance_parameters(
                   acutance_parameters(parameters));
    }
    return valid_film_emulation_color_parameters(color_parameters(parameters)) &&
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
    // Current macOS behavior: a scanned film image already contains its
    // emulsion response. Applying another stock response double-develops it.
    if (parameters.source_kind == DevelopSourceKind::film_scan) {
        route = FilmLookRoute::identity;
        return true;
    }
    const bool black_and_white_profile =
        is_black_and_white_film_emulation(parameters.emulation);
    if (parameters.emulation == FilmEmulation::none ||
        black_and_white_profile != parameters.monochrome) {
        route = FilmLookRoute::identity;
        return true;
    }
    if (black_and_white_profile) {
        if (!has_digital_bw_emulsion_response_change(
                {parameters.emulation, parameters.intensity})) {
            route = FilmLookRoute::identity;
            return true;
        }
        route = FilmLookRoute::digital_film_look;
        return true;
    }
    const bool changes =
        has_film_emulation_color_change(color_parameters(parameters)) ||
        has_film_emulation_acutance_change(acutance_parameters(parameters));
    if (!changes) {
        route = FilmLookRoute::identity;
        return true;
    }
    route = FilmLookRoute::digital_film_look;
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
    const bool black_and_white_profile =
        is_black_and_white_film_emulation(parameters.emulation);
    if (!black_and_white_profile) {
        result.info.color_intensity_step =
            film_emulation_intensity_step(color);
    }
    result.info.acutance_amount = film_emulation_acutance_amount(acutance);
    if (result.info.route == FilmLookRoute::digital_film_look &&
        has_film_emulation_acutance_change(acutance)) {
        result.info.required_acutance_scratch_pixels =
            film_emulation_acutance_scratch_pixel_count(result.image.width);
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

    const bool digital =
        result.info.route == FilmLookRoute::digital_film_look;
    if (!black_and_white_profile &&
        has_film_emulation_color_change(color) &&
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

    if (black_and_white_profile) {
        auto black_and_white = apply_digital_bw_film_look(
            std::move(result.image),
            {parameters.emulation,
             parameters.intensity,
             parameters.grain_override,
             parameters.halation_override},
            workspace.acutance);
        result.info.kernel_status = black_and_white.info.kernel_status;
        result.info.digital_halation_applied =
            black_and_white.info.digital_halation_applied;
        result.info.bw_emulsion_applied =
            black_and_white.info.emulsion_response_applied;
        result.info.acutance_applied =
            black_and_white.info.acutance_applied;
        result.info.digital_grain_applied =
            black_and_white.info.digital_grain_applied;
        result.image = std::move(black_and_white.image);
        if (black_and_white.status != DigitalBwFilmLookStatus::ok) {
            result.status = WorkingFilmLookStatus::digital_bw_film_look_failed;
            return result;
        }
        result.status = WorkingFilmLookStatus::ok;
        return result;
    }

    // 색 큐브는 **CPU 가 만듭니다** — 35,937 칸이고 프리셋·세기가 바뀔 때만 다시
    // 만들어지므로 GPU 로 옮길 이유가 없고, 옮기면 두 벌이 됩니다. GPU 사슬과 CPU 사슬이
    // **같은 표**를 봐야 하므로 두 갈래보다 앞에서 만듭니다.
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
    }

    // ☠️ 사슬 전체를 GPU 에 머무르게 하는 자리입니다. 재료마다 올렸다 내리면 24MP 에서
    //    왕복이 다섯 번(277 MB × 10)이고, 실측으로 그 전송이 커널보다 컸습니다.
    //    **게이트 판정은 여기서 합니다** — GPU 는 계획대로 돌리기만 합니다. 실패하면
    //    이미지를 손대지 않으므로 아래 CPU 사슬이 그대로 이어집니다.
    if (digital && approximate_acceleration_allowed()) {
        if (const KernelAccelerator* const table = kernel_accelerator();
            table != nullptr && table->digital_film_look != nullptr) {
            DigitalFilmLookPlan plan{};
            if (try_plan_digital_film_look(parameters, color, acutance, workspace, plan)) {
                DigitalFilmLookApplied applied{};
                if (table->digital_film_look(
                        reinterpret_cast<float*>(result.image.pixels.data()),
                        result.image.width,
                        result.image.height,
                        result.image.stride_pixels,
                        &plan,
                        &applied)) {
                    result.info.digital_halation_applied = applied.halation;
                    result.info.color_applied = applied.color;
                    result.info.acutance_applied = applied.acutance;
                    result.info.digital_color_preset_applied = applied.preset;
                    result.info.digital_grain_applied = applied.grain;
                    result.info.kernel_status =
                        negaflow::core::validate_finite_pixels(const_view(result.image));
                    if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
                        fail_kernel(result, result.info.kernel_status);
                        return result;
                    }
                    result.status = WorkingFilmLookStatus::ok;
                    return result;
                }
            }
        }
    }

    if (digital) {
        const double strength = std::clamp(parameters.intensity, 0.0, 1.0);
        const double halation_strength = parameters.halation_override > 1.0e-3
            ? std::clamp(parameters.halation_override, 0.0, 1.0)
            : strength;
        auto halation = apply_digital_halation(
            std::move(result.image),
            {parameters.emulation, halation_strength});
        if (halation.status != DigitalHalationStatus::ok) {
            result.info.kernel_status = halation.info.kernel_status;
            result.status = WorkingFilmLookStatus::digital_halation_failed;
            result.image = std::move(halation.image);
            return result;
        }
        result.info.digital_halation_applied = halation.info.applied;
        result.image = std::move(halation.image);
    }

    if (has_film_emulation_color_change(color)) {
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

    if (digital) {
        const double strength = std::clamp(parameters.intensity, 0.0, 1.0);
        auto preset = apply_digital_film_color_preset(
            std::move(result.image),
            {parameters.emulation, strength * 0.5});
        if (preset.status != DigitalFilmColorPresetStatus::ok) {
            result.info.kernel_status = preset.info.kernel_status;
            result.status = WorkingFilmLookStatus::digital_color_preset_failed;
            result.image = std::move(preset.image);
            return result;
        }
        result.info.digital_color_preset_applied = preset.info.applied;
        result.image = std::move(preset.image);

        const double grain_strength = parameters.grain_override > 1.0e-3
            ? std::clamp(parameters.grain_override, 0.0, 1.0)
            : strength;
        auto grain = apply_digital_film_grain(
            std::move(result.image),
            {parameters.emulation, grain_strength});
        if (grain.status != DigitalFilmGrainStatus::ok) {
            result.info.kernel_status = grain.info.kernel_status;
            result.status = WorkingFilmLookStatus::digital_grain_failed;
            result.image = std::move(grain.image);
            return result;
        }
        result.info.digital_grain_applied = grain.info.applied;
        result.image = std::move(grain.image);
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
        case WorkingFilmLookStatus::digital_halation_failed:
            return "digital_halation_failed";
        case WorkingFilmLookStatus::digital_color_preset_failed:
            return "digital_color_preset_failed";
        case WorkingFilmLookStatus::digital_grain_failed:
            return "digital_grain_failed";
        case WorkingFilmLookStatus::digital_bw_film_look_failed:
            return "digital_bw_film_look_failed";
    }
    return "unknown";
}

}  // namespace negaflow::imaging
