#include "negaflow/imaging/texture_stage.h"

#include "texture_stage_effects.h"
#include "texture_stage_math.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <new>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

using namespace negaflow::imaging::texture_stage_detail;

void discard_pixels(WorkingImage& image) noexcept {
    std::vector<negaflow::core::Rgba32F>{}.swap(image.pixels);
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

}  // namespace

bool valid_texture_stage_parameters(
    const TextureStageParameters& parameters) noexcept {
    const auto normalized = [](const float value) noexcept {
        return std::isfinite(value) && value >= 0.0F && value <= 1.0F;
    };
    const auto signed_normalized = [](const float value) noexcept {
        return std::isfinite(value) && value >= -1.0F && value <= 1.0F;
    };
    return normalized(parameters.grain) &&
           normalized(parameters.sharpness) &&
           normalized(parameters.halation) &&
           signed_normalized(parameters.clarity) &&
           signed_normalized(parameters.vignette);
}

TextureStageResult apply_texture_stage(
    WorkingImage image,
    const TextureStageParameters& parameters) noexcept {
    TextureStageResult result{};
    result.image = std::move(image);
    if (!valid_texture_stage_parameters(parameters)) {
        discard_pixels(result.image);
        return result;
    }
    result.info.kernel_status =
        negaflow::core::validate_finite_pixels(const_view(result.image));
    if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
        result.status = TextureStageStatus::kernel_failed;
        discard_pixels(result.image);
        return result;
    }

    try {
        if (parameters.sharpness > texture_stage_identity_threshold) {
            apply_unsharp(
                result.image,
                1.0F + parameters.sharpness * 1.2F,
                0.18F + parameters.sharpness * 0.42F,
                result.info.output_scratch_peak_bytes);
            result.info.sharpness_applied = true;
        }
        if (parameters.grain > texture_stage_identity_threshold) {
            apply_grain(result.image, parameters.grain);
            result.info.grain_applied = true;
        }
        if (std::abs(parameters.clarity) >
            texture_stage_identity_threshold) {
            if (parameters.clarity > 0.0F) {
                apply_unsharp(
                    result.image,
                    6.0F + parameters.clarity * 5.0F,
                    0.10F + parameters.clarity * 0.18F,
                    result.info.output_scratch_peak_bytes);
            } else {
                apply_negative_clarity(
                    result.image,
                    parameters.clarity,
                    result.info.output_scratch_peak_bytes);
            }
            result.info.clarity_applied = true;
        }
        if (parameters.halation > texture_stage_identity_threshold) {
            apply_halation(
                result.image,
                parameters.halation,
                result.info.output_scratch_peak_bytes);
            result.info.halation_applied = true;
        }
        if (std::abs(parameters.vignette) >
            texture_stage_identity_threshold) {
            apply_vignette(result.image, parameters.vignette);
            result.info.vignette_applied = true;
        }
        result.info.applied =
            result.info.grain_applied || result.info.sharpness_applied ||
            result.info.halation_applied || result.info.clarity_applied ||
            result.info.vignette_applied;
        result.status = TextureStageStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.status = TextureStageStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    } catch (...) {
        result.status = TextureStageStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    }
}

const char* texture_stage_status_name(
    const TextureStageStatus status) noexcept {
    switch (status) {
        case TextureStageStatus::ok:
            return "ok";
        case TextureStageStatus::invalid_parameter:
            return "invalid_parameter";
        case TextureStageStatus::kernel_failed:
            return "kernel_failed";
        case TextureStageStatus::allocation_failed:
            return "allocation_failed";
    }
    return "unknown";
}

bool valid_output_sharpening_parameters(
    const OutputSharpeningParameters& parameters) noexcept {
    return std::isfinite(parameters.strength) && parameters.strength >= 0.0F &&
           parameters.strength <= 1.0F &&
           parameters.medium <= OutputSharpeningMedium::glossy_paper &&
           parameters.dpi >= 0;
}

OutputSharpeningResult apply_output_sharpening(
    WorkingImage image,
    const OutputSharpeningParameters& parameters) noexcept {
    OutputSharpeningResult result{};
    result.image = std::move(image);
    if (!valid_output_sharpening_parameters(parameters)) {
        discard_pixels(result.image);
        return result;
    }
    result.info.kernel_status =
        negaflow::core::validate_finite_pixels(const_view(result.image));
    if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
        result.status = TextureStageStatus::kernel_failed;
        discard_pixels(result.image);
        return result;
    }
    if (parameters.strength <= texture_stage_identity_threshold) {
        result.status = TextureStageStatus::ok;
        return result;
    }
    struct MediumParameters final {
        float radius;
        float intensity;
        float reference_dpi;
    } base{};
    switch (parameters.medium) {
        case OutputSharpeningMedium::screen:
            base = {0.45F, 0.22F, 144.0F};
            break;
        case OutputSharpeningMedium::matte_paper:
            base = {1.00F, 0.34F, 300.0F};
            break;
        case OutputSharpeningMedium::glossy_paper:
            base = {0.75F, 0.28F, 300.0F};
            break;
    }
    const float effective_dpi = parameters.dpi > 0
        ? static_cast<float>(parameters.dpi) : base.reference_dpi;
    const float resolution_scale = std::clamp(
        effective_dpi / base.reference_dpi, 0.5F, 2.0F);
    result.info.radius = base.radius * std::sqrt(resolution_scale);
    result.info.intensity = base.intensity * parameters.strength;
    try {
        apply_unsharp(
            result.image,
            result.info.radius,
            result.info.intensity,
            result.info.scratch_peak_bytes);
        result.info.applied = true;
        result.status = TextureStageStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.status = TextureStageStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    } catch (...) {
        result.status = TextureStageStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    }
}

}  // namespace negaflow::imaging
