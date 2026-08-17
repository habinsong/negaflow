#include "invert.h"

#include "export/support/outcome.h"

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/auto_negative_base_resolver.h"

#include <utility>

namespace negaflow::pipeline::develop_export_detail {

std::optional<DevelopExportOutcome> invert_source(
    const DevelopExportRequest& request,
    RunTracker& tracker,
    negaflow::imaging::WorkingImage decoded_image,
    InvertStageOutput& out) noexcept {
    out.negative = request.negative;
    out.base_source = DevelopBaseSource::manual;
    out.developed_info = {};
    out.positive = request.film_polarity == FilmPolarity::positive;
    out.negative_source = !out.positive;
    tracker.begin(
        DevelopExportStage::develop,
        cost_of(
            auto_base_cost,
            out.negative_source &&
                request.base_estimation_mode != NegativeBaseEstimationMode::manual) +
            cost_of(invert_cost, out.negative_source));
    if (out.negative_source &&
        (request.base_estimation_mode == NegativeBaseEstimationMode::auto_estimate ||
         request.base_estimation_mode == NegativeBaseEstimationMode::preset)) {
        const negaflow::imaging::AutoNegativeBaseResult resolved =
            negaflow::imaging::resolve_auto_negative_base(
                decoded_image,
                out.negative.film_type);
        if (resolved.status != negaflow::imaging::AutoNegativeBaseStatus::ok) {
            return fail(
                DevelopExportStage::develop,
                negaflow::imaging::auto_negative_base_status_name(resolved.status));
        }
        if (request.base_estimation_mode == NegativeBaseEstimationMode::preset) {
            out.negative.use_preset_response = true;
            out.negative.preset_dmax_normalized = request.film_stock_preset->dmax_normalized;
            if (negaflow::imaging::confident_auto_negative_base_source(
                    resolved.source)) {
                out.negative.dmin = resolved.dmin;
                out.base_source = DevelopBaseSource::preset_measured;
            } else {
                out.negative.dmin = request.film_stock_preset->dmin;
                out.base_source = DevelopBaseSource::preset_fallback;
            }
            for (std::size_t channel = 0U; channel < out.negative.dmin.size(); ++channel) {
                out.negative.dmin[channel] *= request.film_stock_preset->light_gain[channel];
            }
        } else {
            out.negative.dmin = resolved.dmin;
        }
        if (request.base_estimation_mode == NegativeBaseEstimationMode::auto_estimate) {
            switch (resolved.source) {
            case negaflow::imaging::AutoNegativeBaseSource::connected_component:
                out.base_source = DevelopBaseSource::auto_connected_component;
                break;
            case negaflow::imaging::AutoNegativeBaseSource::continuous_border:
                out.base_source = DevelopBaseSource::auto_continuous_border;
                break;
            case negaflow::imaging::AutoNegativeBaseSource::distributed_mask:
                out.base_source = DevelopBaseSource::auto_distributed_mask;
                break;
            case negaflow::imaging::AutoNegativeBaseSource::strip_fallback:
                out.base_source = DevelopBaseSource::auto_strip_fallback;
                break;
            case negaflow::imaging::AutoNegativeBaseSource::scene_edge:
                out.base_source = DevelopBaseSource::auto_scene_edge;
                break;
            case negaflow::imaging::AutoNegativeBaseSource::fallback:
                out.base_source = DevelopBaseSource::auto_fallback;
                break;
            }
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
