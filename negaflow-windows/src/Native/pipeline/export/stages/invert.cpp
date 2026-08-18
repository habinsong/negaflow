#include "invert.h"

#include "export/support/outcome.h"

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/auto_negative_base_resolver.h"

#include <utility>

namespace negaflow::pipeline::develop_export_detail {
namespace {

void apply_resolved_base(InvertStageOutput& out, const PreviewProxyHint& hint) noexcept {
    out.negative.dmin = hint.dmin;
    out.base_source = hint.base_source;
    out.negative.use_preset_response = hint.use_preset_response;
    out.negative.preset_dmax_normalized = hint.preset_dmax_normalized;
    out.measurement_method = hint.measurement_method;
    out.diagnostics = hint.diagnostics;
}

[[nodiscard]] std::optional<negaflow::imaging::FilmBaseMeasurementMethod> method_of(
    const negaflow::imaging::AutoNegativeBaseSource source) noexcept {
    using negaflow::imaging::AutoNegativeBaseSource;
    using negaflow::imaging::FilmBaseMeasurementMethod;
    switch (source) {
        case AutoNegativeBaseSource::connected_component:
            return FilmBaseMeasurementMethod::connected_component;
        case AutoNegativeBaseSource::continuous_border:
            return FilmBaseMeasurementMethod::continuous_border;
        case AutoNegativeBaseSource::distributed_mask:
            return FilmBaseMeasurementMethod::distributed_mask;
        case AutoNegativeBaseSource::strip_fallback:
            return FilmBaseMeasurementMethod::strip_fallback;
        case AutoNegativeBaseSource::scene_edge:
        case AutoNegativeBaseSource::fallback:
            return std::nullopt;
    }
    return std::nullopt;
}

[[nodiscard]] bool identity_light_gain(const std::array<float, 3>& gain) noexcept {
    return gain[0] == 1.0F && gain[1] == 1.0F && gain[2] == 1.0F;
}

}  // namespace

std::optional<DevelopExportOutcome> resolve_negative_base(
    const DevelopExportRequest& request,
    const negaflow::imaging::WorkingImage& image,
    PreviewProxyHint& hint) noexcept {
    hint.has_base = false;
    hint.use_preset_response = false;
    hint.preset_dmax_normalized = {};
    const negaflow::imaging::AutoNegativeBaseResult resolved =
        negaflow::imaging::resolve_auto_negative_base(image, request.negative.film_type);
    if (resolved.status != negaflow::imaging::AutoNegativeBaseStatus::ok) {
        return fail(
            DevelopExportStage::develop,
            negaflow::imaging::auto_negative_base_status_name(resolved.status));
    }
    hint.measurement_method = method_of(resolved.source);
    hint.diagnostics = resolved.diagnostics;
    if (request.base_estimation_mode == NegativeBaseEstimationMode::preset) {
        if (!request.film_stock_preset.has_value()) {
            return fail(DevelopExportStage::develop, "missing_film_stock_preset");
        }
        hint.use_preset_response = true;
        hint.preset_dmax_normalized = request.film_stock_preset->dmax_normalized;
        if (negaflow::imaging::confident_auto_negative_base_source(resolved.source)) {
            hint.dmin = resolved.dmin;
            hint.base_source = DevelopBaseSource::preset_measured;
            // macOS `applyLightSourceGain` keeps source but drops measurement
            // diagnostics when a non-neutral gain is applied.
            if (!identity_light_gain(request.film_stock_preset->light_gain)) {
                hint.diagnostics = std::nullopt;
            }
        } else {
            hint.dmin = request.film_stock_preset->dmin;
            hint.base_source = DevelopBaseSource::preset_fallback;
            hint.measurement_method = std::nullopt;
            hint.diagnostics = std::nullopt;
        }
        for (std::size_t channel = 0U; channel < hint.dmin.size(); ++channel) {
            hint.dmin[channel] *= request.film_stock_preset->light_gain[channel];
        }
    } else {
        hint.dmin = resolved.dmin;
        switch (resolved.source) {
        case negaflow::imaging::AutoNegativeBaseSource::connected_component:
            hint.base_source = DevelopBaseSource::auto_connected_component;
            break;
        case negaflow::imaging::AutoNegativeBaseSource::continuous_border:
            hint.base_source = DevelopBaseSource::auto_continuous_border;
            break;
        case negaflow::imaging::AutoNegativeBaseSource::distributed_mask:
            hint.base_source = DevelopBaseSource::auto_distributed_mask;
            break;
        case negaflow::imaging::AutoNegativeBaseSource::strip_fallback:
            hint.base_source = DevelopBaseSource::auto_strip_fallback;
            break;
        case negaflow::imaging::AutoNegativeBaseSource::scene_edge:
            hint.base_source = DevelopBaseSource::auto_scene_edge;
            break;
        case negaflow::imaging::AutoNegativeBaseSource::fallback:
            hint.base_source = DevelopBaseSource::auto_fallback;
            break;
        }
    }
    hint.has_base = true;
    return std::nullopt;
}

std::optional<DevelopExportOutcome> invert_source(
    const DevelopExportRequest& request,
    RunTracker& tracker,
    negaflow::imaging::WorkingImage decoded_image,
    InvertStageOutput& out,
    const PreviewProxyHint* const hint) noexcept {
    out.negative = request.negative;
    out.base_source = DevelopBaseSource::manual;
    out.developed_info = {};
    out.positive = request.film_polarity == FilmPolarity::positive;
    out.negative_source = !out.positive;
    const bool needs_base =
        out.negative_source &&
        (request.base_estimation_mode == NegativeBaseEstimationMode::auto_estimate ||
         request.base_estimation_mode == NegativeBaseEstimationMode::preset);
    tracker.begin(
        DevelopExportStage::develop,
        cost_of(auto_base_cost, needs_base && (hint == nullptr || !hint->has_base)) +
            cost_of(invert_cost, out.negative_source));
    if (needs_base) {
        if (hint != nullptr && hint->has_base) {
            apply_resolved_base(out, *hint);
        } else {
            PreviewProxyHint resolved{};
            if (auto failed = resolve_negative_base(request, decoded_image, resolved)) {
                return failed;
            }
            apply_resolved_base(out, resolved);
        }
    }

    if (out.negative_source) {
        auto developed = negaflow::imaging::develop_manual_negative(
            std::move(decoded_image),
            out.negative);
        if (developed.status != negaflow::imaging::ManualNegativeDevelopStatus::ok) {
            if (developed.status ==
                negaflow::imaging::ManualNegativeDevelopStatus::kernel_failed) {
                return fail(
                    DevelopExportStage::develop,
                    negaflow::core::kernel_status_name(
                        developed.info.kernel_status));
            }
            return fail(
                DevelopExportStage::develop,
                negaflow::imaging::manual_negative_develop_status_name(
                    developed.status));
        }
        out.developed_info = developed.info;
        out.image = std::move(developed.image);
    } else {
        // Positive film scans and rendered-digital input are already positive
        // working images. Negative base and inversion do not participate.
        out.image = std::move(decoded_image);
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::develop);
    }
    return std::nullopt;
}

}  // namespace negaflow::pipeline::develop_export_detail
