#include "request/develop_request_map.h"

#include "support/abi_text.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <limits>
#include <new>
#include <string>
#include <string_view>
#include <vector>

namespace negaflow::abi::detail {

// v5–v11: 포인트 커브·컬러 믹서·그레이딩·노이즈·텍스처·BW·곧게 펴기.

[[nodiscard]] bool map_point_curve(
    const nf_point_curve_v1& source,
    negaflow::imaging::PointCurve& destination) noexcept {
    if (source.reserved != 0U || source.point_count > NF_POINT_CURVE_MAX_POINTS) {
        return false;
    }
    destination.point_count = source.point_count;
    for (std::size_t index = 0U; index < source.point_count; ++index) {
        destination.points[index] = {source.points[index].x, source.points[index].y};
    }
    return true;
}

[[nodiscard]] bool map_request_v5(
    const nf_develop_export_request_v5& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    nf_develop_export_request_v4 prefix{};
    std::memcpy(&prefix, &request, sizeof(prefix));
    if (!map_request_v4(prefix, require_destination, pipeline_request, result)) {
        return false;
    }
    if (!map_point_curve(request.point_curve_rgb, pipeline_request.tone.point_curves.rgb) ||
        !map_point_curve(request.point_curve_red, pipeline_request.tone.point_curves.red) ||
        !map_point_curve(request.point_curve_green, pipeline_request.tone.point_curves.green) ||
        !map_point_curve(request.point_curve_blue, pipeline_request.tone.point_curves.blue) ||
        !negaflow::imaging::valid_point_curves(pipeline_request.tone.point_curves)) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("invalid_point_curves", result.failure_name);
        return false;
    }
    return true;
}

[[nodiscard]] bool map_request_v6(
    const nf_develop_export_request_v6& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    nf_develop_export_request_v5 prefix{};
    std::memcpy(&prefix, &request, sizeof(prefix));
    if (!map_request_v5(prefix, require_destination, pipeline_request, result)) {
        return false;
    }
    for (std::size_t index = 0U; index < 8U; ++index) {
        pipeline_request.tone.color_mixer.hue[index] = request.color_mixer_hue[index];
        pipeline_request.tone.color_mixer.saturation[index] = request.color_mixer_saturation[index];
        pipeline_request.tone.color_mixer.luminance[index] = request.color_mixer_luminance[index];
    }
    if (!negaflow::imaging::valid_color_mixer_parameters(pipeline_request.tone.color_mixer)) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("invalid_color_mixer", result.failure_name);
        return false;
    }
    return true;
}

[[nodiscard]] bool map_request_v7(
    const nf_develop_export_request_v7& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    nf_develop_export_request_v6 prefix{};
    std::memcpy(&prefix, &request, sizeof(prefix));
    if (!map_request_v6(prefix, require_destination, pipeline_request, result)) {
        return false;
    }
    pipeline_request.tone.color_grading.shadows = {
        request.color_grading_shadows_hue,
        request.color_grading_shadows_saturation,
        request.color_grading_shadows_luminance};
    pipeline_request.tone.color_grading.midtones = {
        request.color_grading_midtones_hue,
        request.color_grading_midtones_saturation,
        request.color_grading_midtones_luminance};
    pipeline_request.tone.color_grading.highlights = {
        request.color_grading_highlights_hue,
        request.color_grading_highlights_saturation,
        request.color_grading_highlights_luminance};
    pipeline_request.tone.color_grading.blending = request.color_grading_blending;
    pipeline_request.tone.color_grading.balance = request.color_grading_balance;
    if (!negaflow::imaging::valid_color_grading_parameters(pipeline_request.tone.color_grading)) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("invalid_color_grading", result.failure_name);
        return false;
    }
    return true;
}

[[nodiscard]] bool map_request_v8(
    const nf_develop_export_request_v8& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    nf_develop_export_request_v7 prefix{};
    std::memcpy(&prefix, &request, sizeof(prefix));
    if (!map_request_v7(prefix, require_destination, pipeline_request, result)) {
        return false;
    }
    pipeline_request.grain_mend.strength = request.defect_removal_strength;
    if (!negaflow::imaging::valid_grain_mend_parameters(
            pipeline_request.grain_mend)) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("invalid_grain_mend_parameters", result.failure_name);
        return false;
    }
    return true;
}

[[nodiscard]] bool map_request_v9(
    const nf_develop_export_request_v9& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v8(
            request.v8,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }

    pipeline_request.film_scan_denoise.strength =
        request.noise_reduction_strength;
    pipeline_request.film_scan_denoise.axes = {
        request.noise_reduction_luma,
        request.noise_reduction_chroma,
        request.noise_reduction_dark_tone,
        request.noise_reduction_detail,
        request.noise_reduction_grain_protect,
    };
    switch (request.noise_reduction_film_profile) {
        case NF_FILM_SCAN_DENOISE_COLOR_NEGATIVE:
            pipeline_request.film_scan_denoise.film_profile =
                negaflow::imaging::FilmScanDenoiseFilmProfile::color_negative;
            break;
        case NF_FILM_SCAN_DENOISE_COLOR_POSITIVE:
            pipeline_request.film_scan_denoise.film_profile =
                negaflow::imaging::FilmScanDenoiseFilmProfile::color_positive;
            break;
        case NF_FILM_SCAN_DENOISE_BLACK_AND_WHITE_NEGATIVE:
            pipeline_request.film_scan_denoise.film_profile =
                negaflow::imaging::FilmScanDenoiseFilmProfile::
                    black_and_white_negative;
            break;
        case NF_FILM_SCAN_DENOISE_BLACK_AND_WHITE_POSITIVE:
            pipeline_request.film_scan_denoise.film_profile =
                negaflow::imaging::FilmScanDenoiseFilmProfile::
                    black_and_white_positive;
            break;
        default:
            result.succeeded = 0U;
            result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
            copy_failure_name(
                "invalid_film_scan_denoise_parameters",
                result.failure_name);
            return false;
    }
    if (!negaflow::imaging::valid_film_scan_denoise_parameters(
            pipeline_request.film_scan_denoise)) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name(
            "invalid_film_scan_denoise_parameters",
            result.failure_name);
        return false;
    }
    return true;
}

[[nodiscard]] bool map_request_v10(
    const nf_develop_export_request_v10& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v9(
            request.v9,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }
    pipeline_request.texture = {
        request.texture_grain,
        request.texture_sharpness,
        request.texture_halation,
        request.texture_clarity,
        request.texture_vignette,
    };
    pipeline_request.film_look.grain_override = request.texture_grain;
    pipeline_request.film_look.halation_override = request.texture_halation;
    if (!negaflow::imaging::valid_texture_stage_parameters(
            pipeline_request.texture)) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("invalid_texture_parameters", result.failure_name);
        return false;
    }
    return true;
}

[[nodiscard]] bool map_request_v11(
    const nf_develop_export_request_v11& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v10(
            request.v10,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }
    switch (request.bw_toning_mode) {
        case 0U:
            pipeline_request.bw_toning.mode =
                negaflow::imaging::BwToningMode::none;
            break;
        case 1U:
            pipeline_request.bw_toning.mode =
                negaflow::imaging::BwToningMode::selenium;
            break;
        case 2U:
            pipeline_request.bw_toning.mode =
                negaflow::imaging::BwToningMode::sepia;
            break;
        default:
            pipeline_request.bw_toning.mode =
                static_cast<negaflow::imaging::BwToningMode>(request.bw_toning_mode);
            break;
    }
    pipeline_request.bw_toning.shadow_hue = request.bw_toning_shadow_hue;
    pipeline_request.bw_toning.highlight_hue = request.bw_toning_highlight_hue;
    pipeline_request.bw_toning.strength = request.bw_toning_strength;
    pipeline_request.image_transform = {
        static_cast<negaflow::imaging::ImageRotation>(request.image_rotation),
        request.flip_horizontal != 0U,
        request.flip_vertical != 0U,
        request.has_crop != 0U,
        {
            request.crop_x,
            request.crop_y,
            request.crop_width,
            request.crop_height,
        },
        request.straighten_angle,
    };
    if ((request.flip_horizontal > 1U) || (request.flip_vertical > 1U) ||
        (request.has_crop > 1U) ||
        !negaflow::imaging::valid_bw_toning_parameters(
            pipeline_request.bw_toning) ||
        !negaflow::imaging::valid_image_transform_parameters(
            pipeline_request.image_transform)) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name(
            "invalid_post_pipeline_parameters",
            result.failure_name);
        return false;
    }
    return true;
}

}  // namespace negaflow::abi::detail
