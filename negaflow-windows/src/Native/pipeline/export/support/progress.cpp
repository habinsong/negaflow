#include "progress.h"

#include <algorithm>
#include <atomic>
#include <cmath>

namespace negaflow::pipeline::develop_export_detail {

std::uint32_t plan_total_cost(
    const DevelopExportRequest& request,
    const bool preview) noexcept {
    const bool negative_source = request.film_polarity == FilmPolarity::negative;
    const bool monochrome =
        request.negative.film_type ==
        negaflow::imaging::NegativeFilmType::black_and_white;
    const bool graded =
        request.develop_target != DevelopTarget::main ||
        !request.scanner_profile_id.empty();

    std::uint32_t total = 0U;
    total += cost_of(decode_cost, true);
    total += cost_of(defect_cost, !request.defect_recipe.order.empty());
    total += cost_of(
        auto_base_cost,
        negative_source &&
            request.base_estimation_mode != NegativeBaseEstimationMode::manual);
    total += cost_of(invert_cost, negative_source);
    total += cost_of(scene_correction_cost, true);
    total += cost_of(target_grade_cost, graded);
    total += cost_of(color_model_cost, true);
    total += cost_of(tone_cost, true);
    total += cost_of(
        film_look_cost,
        request.film_look.source_kind !=
            negaflow::imaging::DevelopSourceKind::film_scan);
    total += cost_of(
        grain_mend_cost,
        request.grain_mend.strength > negaflow::imaging::grain_mend_identity_threshold);
    total += cost_of(denoise_cost, request.film_scan_denoise.strength > 0.0);
    total += cost_of(
        dodge_burn_cost, !request.local_dodge_burn.adjustments.empty());
    total += cost_of(texture_cost, true);
    total += cost_of(black_and_white_cost, monochrome);
    total += cost_of(transform_cost, true);
    total += cost_of(
        output_sharpening_cost,
        request.output_sharpening.strength >
            negaflow::imaging::texture_stage_identity_threshold);
    total += cost_of(preview ? preview_output_cost : export_output_cost, true);
    return total;
}

RunTracker::RunTracker(
    const DevelopRunControl& control,
    const std::uint32_t total_cost) noexcept
    : control_{control},
      total_cost_{total_cost == 0U ? 1U : total_cost} {}

bool RunTracker::cancelled() const noexcept {
    if (control_.cancel_flag == nullptr) {
        return false;
    }
    return std::atomic_ref<std::uint32_t>(*control_.cancel_flag)
               .load(std::memory_order_relaxed) != 0U;
}

void RunTracker::begin(
    const DevelopExportStage stage,
    const std::uint32_t cost) noexcept {
    stage_cost_ = cost;
    if (control_.progress_stage != nullptr) {
        std::atomic_ref<std::uint32_t>(*control_.progress_stage)
            .store(static_cast<std::uint32_t>(stage), std::memory_order_relaxed);
    }
    publish(completed_cost_);
}

void RunTracker::within(const double fraction) noexcept {
    const double bounded = std::clamp(fraction, 0.0, 1.0);
    publish(
        completed_cost_ +
        static_cast<std::uint64_t>(bounded * static_cast<double>(stage_cost_)));
}

void RunTracker::finish() noexcept {
    completed_cost_ += stage_cost_;
    stage_cost_ = 0U;
    publish(completed_cost_);
}

void RunTracker::complete() noexcept {
    if (control_.progress_permille != nullptr) {
        std::atomic_ref<std::uint32_t>(*control_.progress_permille)
            .store(develop_progress_complete, std::memory_order_relaxed);
    }
}

void RunTracker::publish(const std::uint64_t reached) noexcept {
    if (control_.progress_permille == nullptr) {
        return;
    }
    const std::uint64_t permille = std::min<std::uint64_t>(
        (reached * develop_progress_complete) / total_cost_,
        develop_progress_complete);
    std::atomic_ref<std::uint32_t>(*control_.progress_permille)
        .store(static_cast<std::uint32_t>(permille), std::memory_order_relaxed);
}

DecodeProgressBridge::DecodeProgressBridge(
    RunTracker& tracker,
    std::stop_source& source) noexcept
    : tracker_{tracker}, source_{source} {}

void DecodeProgressBridge::report(
    const negaflow::imageio::WicTiffDecodeProgress progress) noexcept {
    if (progress.total_rows != 0U) {
        tracker_.within(
            static_cast<double>(progress.completed_rows) /
            static_cast<double>(progress.total_rows));
    }
    if (tracker_.cancelled()) {
        source_.request_stop();
    }
}

HashProgressBridge::HashProgressBridge(
    RunTracker& tracker,
    std::stop_source& source) noexcept
    : tracker_{tracker}, source_{source} {}

void HashProgressBridge::report(
    const negaflow::imageio::ImageContentHashProgress progress) noexcept {
    if (progress.total_bytes != 0U) {
        tracker_.within(
            static_cast<double>(progress.completed_bytes) /
            static_cast<double>(progress.total_bytes));
    }
    if (tracker_.cancelled()) {
        source_.request_stop();
    }
}

}  // namespace negaflow::pipeline::develop_export_detail
