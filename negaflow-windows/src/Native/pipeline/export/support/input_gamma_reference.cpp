#include "input_gamma_reference.h"
#include "export/stages/decode.h"
#include "export/stages/invert.h"
#include "export/support/outcome.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"
#include <mutex>
#include <vector>

namespace negaflow::pipeline::develop_export_detail {
namespace {
struct Entry {
    std::filesystem::path path;
    negaflow::imageio::ImageFileObservation observation;
    negaflow::imaging::NegativeFilmType film_type;
    std::optional<negaflow::imaging::FilmStockBasePreset> preset;
    std::array<float, 3> range;
};
std::mutex reference_mutex;
std::vector<Entry> references;
bool same_preset(const std::optional<negaflow::imaging::FilmStockBasePreset>& a,
                 const std::optional<negaflow::imaging::FilmStockBasePreset>& b) noexcept {
    return (!a && !b) || (a && b && a->dmin == b->dmin && a->dmax_normalized == b->dmax_normalized && a->light_gain == b->light_gain);
}
}

std::optional<DevelopExportOutcome> prepare_input_gamma_reference(
    const DevelopExportRequest& request, const DevelopRunControl& control, const ObservedSource& observed,
    std::optional<std::array<float, 3>>& range) noexcept {
    if (request.input_gamma.mode == 0U || request.film_polarity == FilmPolarity::positive) { return {}; }
    try {
        const auto preset = request.base_estimation_mode == NegativeBaseEstimationMode::preset
            ? request.film_stock_preset : std::nullopt;
        {
            const std::lock_guard lock(reference_mutex);
            for (const auto& entry : references) {
                if (entry.path == request.source && entry.film_type == request.negative.film_type &&
                    same_preset(entry.preset, preset) &&
                    negaflow::imageio::same_image_file_observation(entry.observation, observed.before.observation)) {
                    range = entry.range;
                    return {};
                }
            }
        }
        auto baseline = request;
        baseline.input_gamma = negaflow::imaging::resolve_input_gamma_source(request.source, {});
        baseline.base_scale = 1;
        baseline.base_estimation_mode = preset ? NegativeBaseEstimationMode::preset : NegativeBaseEstimationMode::auto_estimate;
        baseline.defect_recipe = {};
        baseline.defect_recipe_sha256.reset();
        baseline.proxy_input_long_edge = 640U;
        baseline.retain_preview_raw = false;
        const DevelopRunControl quiet{control.cancel_flag, nullptr, nullptr};
        RunTracker tracker{quiet, decode_cost.active};
        if (tracker.cancelled()) { return cancelled_outcome(DevelopExportStage::decode); }
        std::stop_source stop;
        negaflow::imaging::WorkingImage image;
        if (auto failed = decode_source(baseline, tracker, stop, observed, image)) { return failed; }
        shrink_to_proxy_long_edge(image, 640U);
        PreviewProxyHint hint;
        if (auto failed = resolve_negative_base(baseline, image, hint)) { return failed; }
        negaflow::imaging::ManualNegativeDevelopParameters parameters{hint.dmin, baseline.negative.film_type};
        parameters.use_preset_response = hint.use_preset_response;
        parameters.preset_dmax_normalized = hint.preset_dmax_normalized;
        auto measured = negaflow::imaging::develop_manual_negative(std::move(image), parameters);
        if (measured.status != negaflow::imaging::ManualNegativeDevelopStatus::ok) {
            return fail(DevelopExportStage::develop, "input_gamma_reference_failed");
        }
        if (tracker.cancelled()) { return cancelled_outcome(DevelopExportStage::develop); }
        range = measured.info.dmax_normalized;
        {
            const std::lock_guard lock(reference_mutex);
            if (references.size() >= 64U) { references.clear(); }
            references.push_back({request.source, observed.before.observation, request.negative.film_type, preset, *range});
        }
        return {};
    } catch (...) { return fail(DevelopExportStage::develop, "input_gamma_reference_failed"); }
}
}
