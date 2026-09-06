#include "negaflow/abi/film_base_pick.h"
#include "request/develop_request_map.h"
#include "result/develop_result_write.h"
#include "negaflow/imaging/film_base_picker.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"
#include "export/stages/decode.h"
#include "export/stages/defect.h"
#include "export/stages/observe.h"
#include "export/support/outcome.h"

#include <chrono>
#include <cmath>

using namespace negaflow::abi::detail;
using namespace negaflow::pipeline;
using namespace negaflow::pipeline::develop_export_detail;

nf_status_t NF_CALL nf_pick_film_base_v2(const nf_develop_export_request_v39* request,
    double unit_x, double unit_y, nf_develop_run_state_v1* run_state,
    nf_develop_export_result_v3* result, nf_film_base_pick_v1* picked) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v39(request, result, status)) { return status; }
    if (picked == nullptr || picked->struct_size < sizeof(*picked) ||
        !std::isfinite(unit_x) || !std::isfinite(unit_y) ||
        unit_x < 0.0 || unit_x > 1.0 || unit_y < 0.0 || unit_y > 1.0) { return NF_STATUS_INVALID_ARGUMENT; }
    picked->status = NF_FILM_BASE_PICK_INVALID_IMAGE;
    picked->red = picked->green = picked->blue = 0.0F;
    DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) { return status; }
    DevelopExportRequest mapped{};
    nf_develop_export_result_v2 failure{};
    if (!map_request_v39(*request, false, mapped, failure)) {
        write_request_rejection_v3(failure, *result);
        return NF_STATUS_OK;
    }
    mapped.proxy_input_long_edge = 0U;
    const auto started = std::chrono::steady_clock::now();
    const auto complete = [&](const DevelopExportOutcome& outcome) {
        write_outcome_v3(outcome, elapsed_microseconds(started, std::chrono::steady_clock::now()), *result);
        return NF_STATUS_OK;
    };
    try {
        mapped.input_gamma = negaflow::imaging::resolve_input_gamma_source(mapped.source, mapped.input_gamma);
        RunTracker tracker{control, decode_cost.active + defect_cost.active};
        std::stop_source stop;
        ObservedSource observed{};
        if (auto error = observe_source_before(mapped, tracker, stop, observed)) { return complete(*error); }
        negaflow::imaging::WorkingImage image;
        if (auto error = decode_source(mapped, tracker, stop, observed, image)) { return complete(*error); }
        DefectRecipeStageResult recipe;
        if (auto error = apply_defect_stage(mapped, control, nullptr, nullptr, tracker, image, recipe)) { return complete(*error); }
        const auto sample = negaflow::imaging::sample_film_base(image, unit_x, unit_y, mapped.negative.film_type);
        const auto after = negaflow::imageio::observe_image_file(mapped.source);
        if (after.status != negaflow::imageio::ImageFileObservationStatus::ok ||
            !negaflow::imageio::same_image_file_observation(observed.before.observation, after.observation)) {
            return complete(fail(DevelopExportStage::observe_source_after, "source_changed_during_pick"));
        }
        if (tracker.cancelled()) { return complete(cancelled_outcome(DevelopExportStage::decode)); }
        picked->status = static_cast<uint32_t>(sample.status);
        if (sample.status == negaflow::imaging::FilmBasePickStatus::ok) {
            picked->red = sample.rgb[0]; picked->green = sample.rgb[1]; picked->blue = sample.rgb[2];
        }
        DevelopExportOutcome outcome;
        outcome.succeeded = true;
        outcome.failure_name = "ok";
        outcome.applied_input_gamma = mapped.input_gamma;
        tracker.complete();
        return complete(outcome);
    } catch (...) { return complete(fail(DevelopExportStage::decode, "film_base_pick_failed")); }
}
