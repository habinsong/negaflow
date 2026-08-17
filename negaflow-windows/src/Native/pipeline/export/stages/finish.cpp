#include "finish.h"

#include "export/support/outcome.h"

#include "negaflow/core/cancel_flag.h"
#include "negaflow/core/pixel.h"
#include "negaflow/imaging/working_image_resample.h"

#include <algorithm>
#include <cmath>
#include <utility>

namespace negaflow::pipeline::develop_export_detail {

std::optional<DevelopExportOutcome> apply_finish_stages(
    const DevelopExportRequest& request,
    const DevelopRunControl& control,
    const PreviewTarget* const preview,
    const DetectTarget* const detect,
    RunTracker& tracker,
    const InvertStageOutput& invert,
    const negaflow::imaging::WorkingFilmLookInfo& film_look_info,
    negaflow::imaging::WorkingImage grain_image,
    FinishStageOutput& out) noexcept {
    const auto& negative = invert.negative;

    tracker.begin(
        DevelopExportStage::film_scan_denoise,
        cost_of(denoise_cost, request.film_scan_denoise.strength > 0.0F));
    auto film_scan_denoise = negaflow::imaging::apply_film_scan_denoise(
        std::move(grain_image),
        request.film_scan_denoise,
        negaflow::core::CancelFlag{control.cancel_flag});
    if (film_scan_denoise.status ==
        negaflow::imaging::FilmScanDenoiseStatus::cancelled) {
        return cancelled_outcome(DevelopExportStage::film_scan_denoise);
    }
    if (film_scan_denoise.status !=
        negaflow::imaging::FilmScanDenoiseStatus::ok) {
        if (film_scan_denoise.status ==
            negaflow::imaging::FilmScanDenoiseStatus::kernel_failed) {
            return fail(
                DevelopExportStage::film_scan_denoise,
                negaflow::core::kernel_status_name(
                    film_scan_denoise.info.kernel_status));
        }
        return fail(
            DevelopExportStage::film_scan_denoise,
            negaflow::imaging::film_scan_denoise_status_name(
                film_scan_denoise.status));
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::film_scan_denoise);
    }

    tracker.begin(
        DevelopExportStage::local_dodge_burn,
        cost_of(dodge_burn_cost, !request.local_dodge_burn.adjustments.empty()));
    auto local_dodge_burn = negaflow::imaging::apply_local_dodge_burn(
        std::move(film_scan_denoise.image),
        request.local_dodge_burn);
    if (local_dodge_burn.status !=
        negaflow::imaging::LocalDodgeBurnStatus::ok) {
        if (local_dodge_burn.status ==
            negaflow::imaging::LocalDodgeBurnStatus::kernel_failed) {
            return fail(
                DevelopExportStage::local_dodge_burn,
                negaflow::core::kernel_status_name(
                    local_dodge_burn.info.kernel_status));
        }
        return fail(
            DevelopExportStage::local_dodge_burn,
            negaflow::imaging::local_dodge_burn_status_name(
                local_dodge_burn.status));
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::local_dodge_burn);
    }

    tracker.begin(DevelopExportStage::texture, cost_of(texture_cost, true));
    negaflow::imaging::TextureStageParameters texture_parameters =
        request.texture;
    if (film_look_info.route ==
        negaflow::imaging::FilmLookRoute::digital_film_look) {
        texture_parameters.grain = 0.0F;
        texture_parameters.halation = 0.0F;
    }
    auto texture = negaflow::imaging::apply_texture_stage(
        std::move(local_dodge_burn.image),
        texture_parameters);
    if (texture.status != negaflow::imaging::TextureStageStatus::ok) {
        if (texture.status ==
            negaflow::imaging::TextureStageStatus::kernel_failed) {
            return fail(
                DevelopExportStage::texture,
                negaflow::core::kernel_status_name(texture.info.kernel_status));
        }
        return fail(
            DevelopExportStage::texture,
            negaflow::imaging::texture_stage_status_name(texture.status));
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::texture);
    }

    tracker.begin(
        DevelopExportStage::black_and_white,
        cost_of(
            black_and_white_cost,
            negative.film_type ==
                negaflow::imaging::NegativeFilmType::black_and_white));
    auto black_and_white = negaflow::imaging::apply_bw_toning(
        std::move(texture.image),
        negative.film_type,
        request.bw_toning);
    if (black_and_white.status != negaflow::imaging::BwToningStatus::ok) {
        return fail(
            DevelopExportStage::black_and_white,
            negaflow::imaging::bw_toning_status_name(black_and_white.status));
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::black_and_white);
    }

    tracker.begin(DevelopExportStage::image_transform, cost_of(transform_cost, true));
    auto image_transform = negaflow::imaging::apply_image_transform(
        std::move(black_and_white.image),
        request.image_transform);
    if (image_transform.status != negaflow::imaging::ImageTransformStatus::ok) {
        return fail(
            DevelopExportStage::image_transform,
            negaflow::imaging::image_transform_status_name(
                image_transform.status));
    }

    bool output_resized = false;
    negaflow::imaging::WorkingImage output_image = std::move(image_transform.image);
    // macOS applies the optional long-edge cap after all geometric recipe transforms,
    // before final output sharpening and encoding. It is an export-only operation:
    // preview and review masks retain their source-derived geometry.
    if (preview == nullptr && detect == nullptr && request.output_long_edge != 0U) {
        const std::uint32_t current_long_edge = std::max(
            output_image.width, output_image.height);
        if (current_long_edge > request.output_long_edge) {
            const double scale = static_cast<double>(request.output_long_edge) /
                static_cast<double>(current_long_edge);
            const std::uint32_t output_width = static_cast<std::uint32_t>(
                std::max(1LL, std::llround(static_cast<double>(output_image.width) * scale)));
            const std::uint32_t output_height = static_cast<std::uint32_t>(
                std::max(1LL, std::llround(static_cast<double>(output_image.height) * scale)));
            auto resampled = negaflow::imaging::resample_working_image_lanczos3(
                output_image, output_width, output_height);
            if (resampled.status != negaflow::imaging::WorkingImageResampleStatus::ok) {
                return fail(
                    DevelopExportStage::image_transform,
                    negaflow::imaging::working_image_resample_status_name(resampled.status));
            }
            output_image = std::move(resampled.image);
            output_resized = true;
        }
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::image_transform);
    }

    negaflow::imaging::OutputSharpeningResult output_sharpening{};
    if (request.output_sharpening.strength >
        negaflow::imaging::texture_stage_identity_threshold) {
        tracker.begin(
            DevelopExportStage::output_sharpening,
            cost_of(output_sharpening_cost, true));
        output_sharpening = negaflow::imaging::apply_output_sharpening(
            std::move(output_image), request.output_sharpening);
        if (output_sharpening.status != negaflow::imaging::TextureStageStatus::ok) {
            return fail(
                DevelopExportStage::output_sharpening,
                negaflow::imaging::texture_stage_status_name(output_sharpening.status));
        }
        tracker.finish();
        if (tracker.cancelled()) {
            return cancelled_outcome(DevelopExportStage::output_sharpening);
        }
    } else {
        output_sharpening.status = negaflow::imaging::TextureStageStatus::ok;
        output_sharpening.image = std::move(output_image);
    }

    out.sharpening = std::move(output_sharpening);
    out.output_resized = output_resized;
    out.denoise = film_scan_denoise.info;
    out.dodge = local_dodge_burn.info;
    out.texture = texture.info;
    out.bw = black_and_white.info;
    out.transform = image_transform.info;
    return std::nullopt;
}

}  // namespace negaflow::pipeline::develop_export_detail
