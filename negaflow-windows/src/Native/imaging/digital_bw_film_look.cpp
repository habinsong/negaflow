#include "negaflow/imaging/digital_bw_film_look.h"

#include "negaflow/imaging/digital_bw_film_profile.h"
#include "negaflow/imaging/digital_film_grain.h"
#include "negaflow/imaging/digital_halation.h"
#include "negaflow/imaging/kernel_accelerator.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

void discard_pixels(WorkingImage& image) noexcept {
    std::vector<negaflow::core::Rgba32F>{}.swap(image.pixels);
}

[[nodiscard]] negaflow::core::ConstImageView const_view(
    const WorkingImage& image) noexcept {
    return {
        image.pixels.data(), image.pixels.size(), image.width, image.height,
        image.stride_pixels};
}

[[nodiscard]] negaflow::core::ImageView mutable_view(
    WorkingImage& image) noexcept {
    return {
        image.pixels.data(), image.pixels.size(), image.width, image.height,
        image.stride_pixels};
}

[[nodiscard]] double resolve_override(
    const double value,
    const double fallback) noexcept {
    return value > 1.0e-3 ? std::clamp(value, 0.0, 1.0) : fallback;
}

}  // namespace

bool valid_digital_bw_film_look_parameters(
    const DigitalBwFilmLookParameters& parameters) noexcept {
    return digital_bw_film_profile(parameters.emulation) != nullptr &&
           std::isfinite(parameters.intensity) &&
           std::isfinite(parameters.grain_override) &&
           std::isfinite(parameters.halation_override);
}

DigitalBwFilmLookResult apply_digital_bw_film_look(
    WorkingImage image,
    const DigitalBwFilmLookParameters& parameters,
    const FilmEmulationAcutanceScratch acutance_scratch) noexcept {
    DigitalBwFilmLookResult result{};
    result.image = std::move(image);
    if (!valid_digital_bw_film_look_parameters(parameters)) {
        discard_pixels(result.image);
        return result;
    }
    const double strength = std::clamp(parameters.intensity, 0.0, 1.0);
    if (strength <= 1.0e-3) {
        result.info.kernel_status =
            negaflow::core::validate_finite_pixels(const_view(result.image));
        if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
            result.status = DigitalBwFilmLookStatus::emulsion_response_failed;
            discard_pixels(result.image);
            return result;
        }
        result.status = DigitalBwFilmLookStatus::ok;
        return result;
    }

    const DigitalBwFilmProfile& profile =
        *digital_bw_film_profile(parameters.emulation);
    const double halation_strength =
        resolve_override(parameters.halation_override, strength);

    if (approximate_acceleration_allowed()) {
        if (const KernelAccelerator* const table = kernel_accelerator();
            table != nullptr && table->digital_bw_film_look != nullptr) {
            DigitalBwFilmLookPlan plan{};
            plan.halation_material = {
                {profile.scatter_strength, profile.scatter_strength,
                 profile.scatter_strength},
                {profile.halation_strength, profile.halation_strength,
                 profile.halation_strength},
                profile.halation_radius_ratio,
            };
            plan.halation_strength = halation_strength;
            plan.halation_requested = true;
            plan.emulsion = prepare_digital_bw_emulsion_response(
                {parameters.emulation, strength});
            const FilmEmulationAcutanceParameters acutance{
                parameters.emulation, strength};
            plan.acutance = has_film_emulation_acutance_change(acutance)
                ? prepare_film_emulation_acutance(acutance)
                : FilmEmulationAcutanceSetup{};
            plan.grain = {profile.grain_amplitude, 0.0, profile.grain_size};
            plan.grain_strength = resolve_override(parameters.grain_override, strength);
            plan.grain_requested = true;
            DigitalBwFilmLookApplied applied{};
            if (table->digital_bw_film_look(
                    reinterpret_cast<float*>(result.image.pixels.data()),
                    result.image.width,
                    result.image.height,
                    result.image.stride_pixels,
                    &plan,
                    &applied)) {
                result.info.digital_halation_applied = applied.halation;
                result.info.emulsion_response_applied = applied.emulsion;
                result.info.acutance_applied = applied.acutance;
                result.info.digital_grain_applied = applied.grain;
                result.info.kernel_status =
                    negaflow::core::validate_finite_pixels(const_view(result.image));
                if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
                    result.status = DigitalBwFilmLookStatus::emulsion_response_failed;
                    discard_pixels(result.image);
                    return result;
                }
                result.status = DigitalBwFilmLookStatus::ok;
                return result;
            }
        }
    }
    const DigitalHalationMaterial halation_material{
        {profile.scatter_strength, profile.scatter_strength,
         profile.scatter_strength},
        {profile.halation_strength, profile.halation_strength,
         profile.halation_strength},
        profile.halation_radius_ratio,
    };
    auto halation = apply_digital_halation_material(
        std::move(result.image), halation_material, halation_strength);
    if (halation.status != DigitalHalationStatus::ok) {
        result.info.kernel_status = halation.info.kernel_status;
        result.status = DigitalBwFilmLookStatus::digital_halation_failed;
        result.image = std::move(halation.image);
        return result;
    }
    result.info.digital_halation_applied = halation.info.applied;
    result.image = std::move(halation.image);

    result.info.kernel_status = apply_digital_bw_emulsion_response(
        const_view(result.image),
        mutable_view(result.image),
        {parameters.emulation, strength});
    if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
        result.status = DigitalBwFilmLookStatus::emulsion_response_failed;
        discard_pixels(result.image);
        return result;
    }
    result.info.emulsion_response_applied = true;

    const FilmEmulationAcutanceParameters acutance{
        parameters.emulation, strength};
    if (has_film_emulation_acutance_change(acutance)) {
        result.info.kernel_status = apply_film_emulation_acutance(
            const_view(result.image),
            mutable_view(result.image),
            acutance,
            acutance_scratch);
        if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
            result.status = DigitalBwFilmLookStatus::acutance_failed;
            discard_pixels(result.image);
            return result;
        }
        result.info.acutance_applied = true;
    }

    const double grain_strength =
        resolve_override(parameters.grain_override, strength);
    auto grain = apply_digital_film_grain_material(
        std::move(result.image),
        {profile.grain_amplitude, 0.0, profile.grain_size},
        grain_strength);
    if (grain.status != DigitalFilmGrainStatus::ok) {
        result.info.kernel_status = grain.info.kernel_status;
        result.status = DigitalBwFilmLookStatus::digital_grain_failed;
        result.image = std::move(grain.image);
        return result;
    }
    result.info.digital_grain_applied = grain.info.applied;
    result.image = std::move(grain.image);
    result.info.kernel_status = negaflow::core::KernelStatus::ok;
    result.status = DigitalBwFilmLookStatus::ok;
    return result;
}

const char* digital_bw_film_look_status_name(
    const DigitalBwFilmLookStatus status) noexcept {
    switch (status) {
        case DigitalBwFilmLookStatus::ok: return "ok";
        case DigitalBwFilmLookStatus::invalid_parameter:
            return "invalid_parameter";
        case DigitalBwFilmLookStatus::digital_halation_failed:
            return "digital_halation_failed";
        case DigitalBwFilmLookStatus::emulsion_response_failed:
            return "emulsion_response_failed";
        case DigitalBwFilmLookStatus::acutance_failed:
            return "acutance_failed";
        case DigitalBwFilmLookStatus::digital_grain_failed:
            return "digital_grain_failed";
    }
    return "unknown_status";
}

}  // namespace negaflow::imaging
