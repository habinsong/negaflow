#include "negaflow/pipeline/develop_export.h"

#include "negaflow/core/pixel.h"
#include "negaflow/pipeline/film_look_workspace.h"

#include <utility>

namespace negaflow::pipeline {
namespace {

[[nodiscard]] DevelopExportOutcome fail(
    const DevelopExportStage stage,
    const char* const name,
    const std::uint32_t native_error_code = 0U,
    const std::uint32_t cleanup_error_code = 0U) noexcept {
    DevelopExportOutcome outcome{};
    outcome.succeeded = false;
    outcome.failed_stage = stage;
    outcome.failure_name = name;
    outcome.native_error_code = native_error_code;
    outcome.cleanup_error_code = cleanup_error_code;
    return outcome;
}

}  // namespace

const char* develop_export_stage_name(const DevelopExportStage stage) noexcept {
    switch (stage) {
        case DevelopExportStage::none:
            return "none";
        case DevelopExportStage::request_validation:
            return "request_validation";
        case DevelopExportStage::observe_source_before:
            return "observe_source_before";
        case DevelopExportStage::decode:
            return "decode";
        case DevelopExportStage::observe_source_after:
            return "observe_source_after";
        case DevelopExportStage::film_look_workspace:
            return "film_look_workspace";
        case DevelopExportStage::develop:
            return "develop";
        case DevelopExportStage::tone_adjust:
            return "tone_adjust";
        case DevelopExportStage::film_look:
            return "film_look";
        case DevelopExportStage::output:
            return "output";
    }
    return "unknown_stage";
}

namespace {

// Where a run ends. Publishing writes a verified 16-bit file; a preview stops before that
// and fills the caller's display buffer. Everything before the last stage is identical, so
// the two cannot drift into producing different pixels.
struct PreviewTarget final {
    std::uint32_t maximum_width{0};
    std::uint32_t maximum_height{0};
    std::uint8_t* pixels{nullptr};
    std::size_t capacity_bytes{0};
};

[[nodiscard]] std::uint32_t preview_extent(
    const std::uint32_t source,
    const std::uint32_t maximum) noexcept {
    return source <= maximum ? source : maximum;
}

[[nodiscard]] DevelopExportOutcome write_preview(
    const negaflow::imaging::WorkingImage& image,
    const PreviewTarget& target,
    DevelopExportOutcome outcome) noexcept {
    if (target.pixels == nullptr || target.maximum_width == 0U ||
        target.maximum_height == 0U) {
        return fail(DevelopExportStage::output, "invalid_preview_target");
    }

    const negaflow::output::WorkingToSrgb16Result converted =
        negaflow::output::convert_working_to_srgb16(image);
    if (converted.status != negaflow::output::WorkingToSrgb16Status::ok) {
        return fail(
            DevelopExportStage::output,
            negaflow::output::working_to_srgb16_status_name(converted.status));
    }

    const std::uint32_t source_width = converted.image.width;
    const std::uint32_t source_height = converted.image.height;
    if (source_width == 0U || source_height == 0U) {
        return fail(DevelopExportStage::output, "empty_preview_source");
    }

    // Fit inside the box without changing the aspect ratio. Integer arithmetic on the
    // larger side first so a very wide frame does not round its short side to zero.
    std::uint32_t width = preview_extent(source_width, target.maximum_width);
    std::uint32_t height = static_cast<std::uint32_t>(
        (static_cast<std::uint64_t>(source_height) * width) / source_width);
    if (height == 0U) {
        height = 1U;
    }
    if (height > target.maximum_height) {
        height = target.maximum_height;
        width = static_cast<std::uint32_t>(
            (static_cast<std::uint64_t>(source_width) * height) / source_height);
        if (width == 0U) {
            width = 1U;
        }
    }

    const std::uint64_t required =
        static_cast<std::uint64_t>(width) * static_cast<std::uint64_t>(height) * 4ULL;
    if (required > target.capacity_bytes) {
        return fail(DevelopExportStage::output, "preview_buffer_too_small");
    }

    const std::uint32_t samples_per_row = converted.image.stride_bytes / 2U;
    for (std::uint32_t y = 0U; y < height; ++y) {
        const std::uint32_t source_y0 =
            static_cast<std::uint32_t>((static_cast<std::uint64_t>(y) * source_height) / height);
        std::uint32_t source_y1 = static_cast<std::uint32_t>(
            (static_cast<std::uint64_t>(y + 1U) * source_height) / height);
        if (source_y1 <= source_y0) {
            source_y1 = source_y0 + 1U;
        }

        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::uint32_t source_x0 =
                static_cast<std::uint32_t>((static_cast<std::uint64_t>(x) * source_width) / width);
            std::uint32_t source_x1 = static_cast<std::uint32_t>(
                (static_cast<std::uint64_t>(x + 1U) * source_width) / width);
            if (source_x1 <= source_x0) {
                source_x1 = source_x0 + 1U;
            }

            std::uint64_t red = 0U;
            std::uint64_t green = 0U;
            std::uint64_t blue = 0U;
            std::uint64_t count = 0U;
            for (std::uint32_t sy = source_y0; sy < source_y1; ++sy) {
                const std::uint16_t* const row =
                    converted.image.samples.data() +
                    (static_cast<std::size_t>(sy) * samples_per_row);
                for (std::uint32_t sx = source_x0; sx < source_x1; ++sx) {
                    const std::uint16_t* const pixel = row + (static_cast<std::size_t>(sx) * 3U);
                    red += pixel[0];
                    green += pixel[1];
                    blue += pixel[2];
                    ++count;
                }
            }

            std::uint8_t* const destination =
                target.pixels + ((static_cast<std::size_t>(y) * width + x) * 4U);
            // BGRA8 with opaque alpha, which is what a XAML Image accepts. The samples are
            // 16-bit sRGB, so the shift is a plain narrowing, not a transfer function.
            destination[0] = static_cast<std::uint8_t>((blue / count) >> 8U);
            destination[1] = static_cast<std::uint8_t>((green / count) >> 8U);
            destination[2] = static_cast<std::uint8_t>((red / count) >> 8U);
            destination[3] = 0xFFU;
        }
    }

    outcome.image_width = width;
    outcome.image_height = height;
    outcome.output_file_bytes = required;
    outcome.succeeded = true;
    outcome.failure_name = "ok";
    return outcome;
}

[[nodiscard]] DevelopExportOutcome run_develop(
    const DevelopExportRequest& request,
    const PreviewTarget* const preview) noexcept {
    if (request.source.empty() || (preview == nullptr && request.destination.empty())) {
        return fail(DevelopExportStage::request_validation, "missing_path");
    }
    if (request.format != DevelopExportFormat::png16 &&
        request.format != DevelopExportFormat::tiff16) {
        return fail(DevelopExportStage::request_validation, "unknown_export_format");
    }
    if (request.rows_per_copy == 0U) {
        return fail(DevelopExportStage::request_validation, "invalid_rows_per_copy");
    }
    if (request.base_estimation_mode != NegativeBaseEstimationMode::manual &&
        request.base_estimation_mode != NegativeBaseEstimationMode::auto_estimate &&
        request.base_estimation_mode != NegativeBaseEstimationMode::preset) {
        return fail(DevelopExportStage::request_validation, "unsupported_base_estimation_mode");
    }
    if (request.base_estimation_mode == NegativeBaseEstimationMode::preset &&
        !request.film_stock_preset) {
        return fail(DevelopExportStage::request_validation, "unknown_film_stock");
    }
    if (!negaflow::imaging::valid_working_tone_adjust_parameters(request.tone)) {
        return fail(
            DevelopExportStage::request_validation,
            "invalid_tone_adjustment_parameter");
    }
    if (!negaflow::imaging::valid_working_film_look_parameters(request.film_look)) {
        return fail(
            DevelopExportStage::request_validation, "invalid_film_look_parameters");
    }
    // The rendered-digital graph is not implemented, and a negative develop is not a
    // meaningful thing to ask of it. Refuse rather than silently developing anyway.
    if (request.film_look.source_kind !=
        negaflow::imaging::DevelopSourceKind::film_scan) {
        return fail(
            DevelopExportStage::request_validation,
            "negative_develop_requires_film_scan_source");
    }

    const negaflow::imageio::ImageFileObservationResult before =
        negaflow::imageio::observe_image_file(request.source);
    if (before.status != negaflow::imageio::ImageFileObservationStatus::ok) {
        return fail(
            DevelopExportStage::observe_source_before,
            negaflow::imageio::image_file_observation_status_name(before.status),
            before.native_error_code);
    }

    negaflow::imageio::WicTiffDecodeControl decode_control{};
    decode_control.rows_per_copy = request.rows_per_copy;
    auto prepared = negaflow::imaging::decode_scanner_tiff_to_working_rows(
        request.source,
        {},
        {},
        decode_control);
    if (prepared.decode.status != negaflow::imageio::WicTiffDecodeStatus::ok) {
        if (prepared.decode.status ==
                negaflow::imageio::WicTiffDecodeStatus::row_sink_failed &&
            prepared.working.status !=
                negaflow::imaging::ScannerToWorkingStatus::invalid_argument) {
            return fail(
                DevelopExportStage::decode,
                negaflow::imaging::scanner_to_working_status_name(
                    prepared.working.status),
                prepared.working.info.native_error_code);
        }
        return fail(
            DevelopExportStage::decode,
            negaflow::imageio::wic_tiff_decode_status_name(prepared.decode.status));
    }
    if (prepared.working.status != negaflow::imaging::ScannerToWorkingStatus::ok) {
        return fail(
            DevelopExportStage::decode,
            negaflow::imaging::scanner_to_working_status_name(
                prepared.working.status),
            prepared.working.info.native_error_code);
    }

    const negaflow::imageio::ImageFileObservationResult after =
        negaflow::imageio::observe_image_file(request.source);
    if (after.status != negaflow::imageio::ImageFileObservationStatus::ok) {
        return fail(
            DevelopExportStage::observe_source_after,
            negaflow::imageio::image_file_observation_status_name(after.status),
            after.native_error_code);
    }
    if (!negaflow::imageio::same_image_file_observation(
            before.observation,
            after.observation)) {
        return fail(
            DevelopExportStage::observe_source_after, "source_changed_during_decode");
    }

    const std::uint32_t decoded_width = prepared.working.image.width;
    const std::uint32_t decoded_height = prepared.working.image.height;

    FilmLookWorkspaceStorage workspace{};
    const FilmLookWorkspacePrepareStatus workspace_status =
        prepare_film_look_workspace(request.film_look, decoded_width, workspace);
    if (workspace_status != FilmLookWorkspacePrepareStatus::ok) {
        return fail(
            DevelopExportStage::film_look_workspace,
            film_look_workspace_prepare_status_name(workspace_status));
    }
    const std::size_t workspace_bytes = film_look_workspace_bytes(workspace);

    negaflow::imaging::ManualNegativeDevelopParameters negative = request.negative;
    DevelopBaseSource base_source = DevelopBaseSource::manual;
    if (request.base_estimation_mode == NegativeBaseEstimationMode::auto_estimate ||
        request.base_estimation_mode == NegativeBaseEstimationMode::preset) {
        const negaflow::imaging::AutoNegativeBaseResult resolved =
            negaflow::imaging::resolve_auto_negative_base(
                prepared.working.image,
                negative.film_type);
        if (resolved.status != negaflow::imaging::AutoNegativeBaseStatus::ok) {
            return fail(
                DevelopExportStage::develop,
                negaflow::imaging::auto_negative_base_status_name(resolved.status));
        }
        if (request.base_estimation_mode == NegativeBaseEstimationMode::preset) {
            negative.use_preset_response = true;
            negative.preset_dmax_normalized = request.film_stock_preset->dmax_normalized;
            if (resolved.source == negaflow::imaging::AutoNegativeBaseSource::connected_component) {
                negative.dmin = resolved.dmin;
                base_source = DevelopBaseSource::preset_measured;
            } else {
                negative.dmin = request.film_stock_preset->dmin;
                base_source = DevelopBaseSource::preset_fallback;
            }
            for (std::size_t channel = 0U; channel < negative.dmin.size(); ++channel) {
                negative.dmin[channel] *= request.film_stock_preset->light_gain[channel];
            }
        } else {
            negative.dmin = resolved.dmin;
        }
        if (request.base_estimation_mode == NegativeBaseEstimationMode::auto_estimate) {
            switch (resolved.source) {
            case negaflow::imaging::AutoNegativeBaseSource::connected_component:
                base_source = DevelopBaseSource::auto_connected_component;
                break;
            case negaflow::imaging::AutoNegativeBaseSource::continuous_border:
                base_source = DevelopBaseSource::auto_continuous_border;
                break;
            case negaflow::imaging::AutoNegativeBaseSource::distributed_mask:
                base_source = DevelopBaseSource::auto_distributed_mask;
                break;
            case negaflow::imaging::AutoNegativeBaseSource::strip_fallback:
                base_source = DevelopBaseSource::auto_strip_fallback;
                break;
            case negaflow::imaging::AutoNegativeBaseSource::scene_edge:
                base_source = DevelopBaseSource::auto_scene_edge;
                break;
            case negaflow::imaging::AutoNegativeBaseSource::fallback:
                base_source = DevelopBaseSource::auto_fallback;
                break;
            }
        }
    }

    auto developed = negaflow::imaging::develop_manual_negative(
        std::move(prepared.working.image),
        negative);
    if (developed.status != negaflow::imaging::ManualNegativeDevelopStatus::ok) {
        if (developed.status ==
            negaflow::imaging::ManualNegativeDevelopStatus::kernel_failed) {
            return fail(
                DevelopExportStage::develop,
                negaflow::core::kernel_status_name(developed.info.kernel_status));
        }
        return fail(
            DevelopExportStage::develop,
            negaflow::imaging::manual_negative_develop_status_name(developed.status));
    }

    auto adjusted = negaflow::imaging::apply_working_tone_adjustments(
        std::move(developed.image),
        request.tone);
    if (adjusted.status != negaflow::imaging::WorkingToneAdjustStatus::ok) {
        if (adjusted.status ==
            negaflow::imaging::WorkingToneAdjustStatus::kernel_failed) {
            return fail(
                DevelopExportStage::tone_adjust,
                negaflow::core::kernel_status_name(adjusted.info.kernel_status));
        }
        if (adjusted.status ==
            negaflow::imaging::WorkingToneAdjustStatus::measurement_failed) {
            return fail(
                DevelopExportStage::tone_adjust,
                negaflow::imaging::tone_curve_measurement_status_name(
                    adjusted.info.measurement.status));
        }
        return fail(
            DevelopExportStage::tone_adjust,
            negaflow::imaging::working_tone_adjust_status_name(adjusted.status));
    }

    auto film_look = negaflow::imaging::apply_working_film_look(
        std::move(adjusted.image),
        request.film_look,
        film_look_workspace_view(workspace));
    if (film_look.status != negaflow::imaging::WorkingFilmLookStatus::ok) {
        if (film_look.status ==
            negaflow::imaging::WorkingFilmLookStatus::kernel_failed) {
            return fail(
                DevelopExportStage::film_look,
                negaflow::core::kernel_status_name(film_look.info.kernel_status));
        }
        return fail(
            DevelopExportStage::film_look,
            negaflow::imaging::working_film_look_status_name(film_look.status));
    }

    DevelopExportOutcome outcome{};
    outcome.image_width = decoded_width;
    outcome.image_height = decoded_height;
    outcome.source_file_bytes = before.observation.file_bytes;
    outcome.film_look_workspace_bytes = workspace_bytes;
    outcome.film_look_route = film_look.info.route;
    outcome.film_look_color_applied = film_look.info.color_applied;
    outcome.film_look_acutance_applied = film_look.info.acutance_applied;
    outcome.applied_dmin = developed.info.applied_dmin;
    outcome.base_source = base_source;

    if (preview != nullptr) {
        return write_preview(film_look.image, *preview, outcome);
    }

    if (request.format == DevelopExportFormat::png16) {
        const negaflow::output::WicPngExportResult exported =
            negaflow::output::export_working_to_srgb16_png(
                film_look.image,
                request.destination);
        if (exported.status != negaflow::output::WicPngExportStatus::ok) {
            if (exported.status ==
                negaflow::output::WicPngExportStatus::working_conversion_failed) {
                return fail(
                    DevelopExportStage::output,
                    negaflow::output::working_to_srgb16_status_name(
                        exported.conversion_status),
                    exported.native_error_code,
                    exported.cleanup_error_code);
            }
            return fail(
                DevelopExportStage::output,
                negaflow::output::wic_png_export_status_name(exported.status),
                exported.native_error_code,
                exported.cleanup_error_code);
        }
        outcome.output_file_bytes = exported.info.artifact_bytes;
        outcome.succeeded = true;
        outcome.failure_name = "ok";
        return outcome;
    }

    const negaflow::output::WicTiffExportResult exported =
        negaflow::output::export_working_to_srgb16_tiff(
            film_look.image,
            request.destination);
    if (exported.status != negaflow::output::WicTiffExportStatus::ok) {
        if (exported.status ==
            negaflow::output::WicTiffExportStatus::working_conversion_failed) {
            return fail(
                DevelopExportStage::output,
                negaflow::output::working_to_srgb16_status_name(
                    exported.conversion_status),
                exported.native_error_code,
                exported.cleanup_error_code);
        }
        return fail(
            DevelopExportStage::output,
            negaflow::output::wic_tiff_export_status_name(exported.status),
            exported.native_error_code,
            exported.cleanup_error_code);
    }
    outcome.output_file_bytes = exported.info.artifact_bytes;
    outcome.succeeded = true;
    outcome.failure_name = "ok";
    return outcome;
}

}  // namespace

DevelopExportOutcome develop_and_export(
    const DevelopExportRequest& request) noexcept {
    return run_develop(request, nullptr);
}

DevelopExportOutcome develop_preview(
    const DevelopExportRequest& request,
    const std::uint32_t maximum_width,
    const std::uint32_t maximum_height,
    std::uint8_t* const pixels,
    const std::size_t pixel_capacity_bytes) noexcept {
    const PreviewTarget target{
        maximum_width,
        maximum_height,
        pixels,
        pixel_capacity_bytes,
    };
    return run_develop(request, &target);
}

}  // namespace negaflow::pipeline
