#include "negaflow/pipeline/develop_export.h"

#include "negaflow/pipeline/gpu_accelerator.h"

#include "negaflow/imaging/kernel_accelerator.h"

#include <optional>

#include "export/stages/decode.h"
#include "export/stages/defect.h"
#include "export/stages/finish.h"
#include "export/stages/grade.h"
#include "export/stages/grain.h"
#include "export/stages/invert.h"
#include "export/stages/look.h"
#include "export/stages/observe.h"
#include "export/stages/publish.h"
#include "export/stages/validate.h"
#include "export/support/gamut.h"
#include "export/support/outcome.h"
#include "export/support/preview.h"
#include "export/support/preview_proxy.h"
#include "export/support/progress.h"

#include <stop_token>
#include <utility>

namespace negaflow::pipeline {

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
        case DevelopExportStage::grain_mend:
            return "grain_mend";
        case DevelopExportStage::film_scan_denoise:
            return "film_scan_denoise";
        case DevelopExportStage::local_dodge_burn:
            return "local_dodge_burn";
        case DevelopExportStage::texture:
            return "texture";
        case DevelopExportStage::black_and_white:
            return "black_and_white";
        case DevelopExportStage::image_transform:
            return "image_transform";
        case DevelopExportStage::output_sharpening:
            return "output_sharpening";
        case DevelopExportStage::color_model:
            return "color_model";
        case DevelopExportStage::scene_correction:
            return "scene_correction";
        case DevelopExportStage::target_grade:
            return "target_grade";
        case DevelopExportStage::defect_component_repair:
            return "defect_component_repair";
        case DevelopExportStage::defect_clone_stamp:
            return "defect_clone_stamp";
        case DevelopExportStage::defect_brush:
            return "defect_brush";
    }
    return "unknown_stage";
}

namespace {

using develop_export_detail::DetectTarget;
using develop_export_detail::FinishStageOutput;
using develop_export_detail::GrainStageOutput;
using develop_export_detail::InvertStageOutput;
using develop_export_detail::LookStageOutput;
using develop_export_detail::LookWorkspaceOutput;
using develop_export_detail::ObservedSource;
using develop_export_detail::PreviewTarget;
using develop_export_detail::RunTracker;
using develop_export_detail::apply_defect_stage;
using develop_export_detail::apply_finish_stages;
using develop_export_detail::apply_grade_stages;
using develop_export_detail::apply_grain_stage;
using develop_export_detail::apply_look_stages;
using develop_export_detail::cancelled_outcome;
using develop_export_detail::decode_source;
using develop_export_detail::invert_source;
using develop_export_detail::preview_proxy_materialize;
using develop_export_detail::preview_proxy_try_take;
using develop_export_detail::PreviewProxyHint;
using develop_export_detail::observe_source_before;
using develop_export_detail::plan_total_cost;
using develop_export_detail::prepare_look_workspace;
using develop_export_detail::publish_developed;
using develop_export_detail::validate_request;

// 공개 진입점은 여기로 모인다. 단계 본문은 export/ 아래 번역 단위가 소유한다.
[[nodiscard]] DevelopExportOutcome run_develop(
    const DevelopExportRequest& request,
    const PreviewTarget* const preview,
    const DevelopRunControl& control,
    const DetectTarget* const detect = nullptr) noexcept {
    if (auto failed = validate_request(request, preview, detect)) {
        return *failed;
    }
    // 값이 바이트까지 같아야 하는 경로(내보내기·골든)는 CPU 로 둡니다. 사용자가 기다리는
    // 프리뷰·검출에서만 GPU 를 켭니다 — `gpu_accelerator.h` 의 정책표.
    //
    // ☠️ 이 판정을 **여기서** 합니다. 반전 단계가 아래에서 도는데, 그 단계 안의 GPU 가속은
    //    `ApproximateAcceleratorScope` 를 보고 켜지므로 스코프가 먼저 열려 있어야 합니다.
    //    스코프는 스레드마다 따로라 다른 스레드의 내보내기는 영향을 안 받습니다.
    const GpuUsePolicy gpu_policy = (preview != nullptr || detect != nullptr)
        ? GpuUsePolicy::allowed
        : GpuUsePolicy::cpu_only;
    std::optional<negaflow::imaging::ApproximateAcceleratorScope> approximate_scope{};
    if (gpu_policy == GpuUsePolicy::allowed) {
        install_gpu_kernel_accelerator();
        approximate_scope.emplace();
    }

    RunTracker tracker{control, plan_total_cost(request, preview != nullptr)};
    std::stop_source stop{};
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::request_validation);
    }

    ObservedSource observed{};
    if (auto failed = observe_source_before(request, tracker, stop, observed)) {
        return *failed;
    }

    // macOS `preloadedPreviewRaw` — 슬라이더는 디코드 0회, 프록시 raw 에서 현상.
    PreviewProxyHint proxy_hint{};
    negaflow::imaging::WorkingImage decoded_image{};
    const bool used_preview_proxy = preview != nullptr && detect == nullptr &&
        preview_proxy_try_take(request, observed, *preview, decoded_image, proxy_hint);

    DefectRecipeStageResult defect_recipe{};
    if (!used_preview_proxy) {
        if (auto failed = decode_source(request, tracker, stop, observed, decoded_image)) {
            return *failed;
        }

        if (auto failed = apply_defect_stage(
                request, preview, detect, tracker, decoded_image, defect_recipe)) {
            return *failed;
        }
    }

    // macOS `runRegionDetect` 는 반전·톤·필름룩 전 cleaned raw 에서 검출한다.
    // 양화 뒤에서 돌리면 같은 먼지가 전혀 다른 대비로 보인다.
    if (detect != nullptr) {
        GrainStageOutput grain{};
        if (auto failed = apply_grain_stage(
                request,
                control,
                detect,
                tracker,
                std::move(decoded_image),
                grain)) {
            return *failed;
        }
        if (grain.detect_complete) {
            return grain.detect_outcome;
        }
        return cancelled_outcome(DevelopExportStage::grain_mend);
    }

    if (preview != nullptr && !used_preview_proxy) {
        if (auto failed = preview_proxy_materialize(
                request,
                observed,
                *preview,
                decoded_image,
                proxy_hint)) {
            return *failed;
        }
    }

    LookWorkspaceOutput look_workspace{};
    if (auto failed =
            prepare_look_workspace(request, decoded_image.width, look_workspace)) {
        return *failed;
    }

    InvertStageOutput invert{};
    if (auto failed = invert_source(
            request,
            tracker,
            std::move(decoded_image),
            invert,
            proxy_hint.image_is_proxy || proxy_hint.has_base ? &proxy_hint : nullptr)) {
        return *failed;
    }

    if (auto failed = apply_grade_stages(request, tracker, invert)) {
        return *failed;
    }

    LookStageOutput look{};
    if (auto failed = apply_look_stages(
            request,
            tracker,
            look_workspace,
            std::move(invert.image),
            gpu_policy,
            look)) {
        return *failed;
    }

    GrainStageOutput grain{};
    if (auto failed = apply_grain_stage(
            request, control, detect, tracker, std::move(look.image), grain)) {
        return *failed;
    }
    if (grain.detect_complete) {
        return grain.detect_outcome;
    }

    FinishStageOutput finish{};
    if (auto failed = apply_finish_stages(
            request,
            control,
            preview,
            detect,
            tracker,
            invert,
            look.info,
            std::move(grain.applied.image),
            finish)) {
        return *failed;
    }

    return publish_developed(
        request,
        preview,
        tracker,
        observed,
        defect_recipe,
        invert,
        look,
        grain,
        finish);
}

}  // namespace

DevelopExportOutcome develop_and_export(
    const DevelopExportRequest& request,
    const DevelopRunControl& control) noexcept {
    return run_develop(request, nullptr, control);
}

GrainMendDetectionOutcome develop_detect_grain_mend(
    const DevelopExportRequest& request,
    std::uint8_t* const mask,
    const std::size_t mask_capacity_bytes,
    const DevelopRunControl& control,
    const negaflow::imaging::GrainMendRoi& roi) noexcept {
    GrainMendDetectionOutcome detection{};
    const DetectTarget target{mask, mask_capacity_bytes, &detection, roi};
    detection.outcome = run_develop(request, nullptr, control, &target);
    return detection;
}

DevelopExportOutcome develop_preview(
    const DevelopExportRequest& request,
    const std::uint32_t maximum_width,
    const std::uint32_t maximum_height,
    std::uint8_t* const pixels,
    const std::size_t pixel_capacity_bytes,
    const DevelopRunControl& control,
    const DevelopPreviewProof& proof) noexcept {
    // Profile-only proofing changes which space the frame is shown in, not its values, so
    // only the paper and ink simulation resolves to an affine here.
    const PreviewTarget target{
        maximum_width,
        maximum_height,
        pixels,
        pixel_capacity_bytes,
        proof.enabled && proof.simulate_paper_and_black_ink
            ? negaflow::color::soft_proof_transfer(proof.paper)
            : negaflow::color::SoftProofTransfer{},
        proof.clipping_overlay,
    };
    DevelopExportOutcome outcome = run_develop(request, &target, control);
    if (outcome.succeeded && proof.enabled && proof.warn_out_of_gamut) {
        develop_export_detail::mark_out_of_gamut(
            pixels,
            outcome.image_width,
            outcome.image_height,
            request.output_color_space);
    }
    return outcome;
}

}  // namespace negaflow::pipeline
