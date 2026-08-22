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

#include <new>
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
using develop_export_detail::fail;
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
//
// **`noexcept` 가 아닙니다.** 아래 `run_develop` 이 감쌉니다 — 이유는 그쪽 주석에.
[[nodiscard]] DevelopExportOutcome run_develop_unguarded(
    const DevelopExportRequest& request,
    const PreviewTarget* const preview,
    const DevelopRunControl& control,
    const DetectTarget* const detect) {
    if (auto failed = validate_request(request, preview, detect)) {
        return *failed;
    }
    // 값이 바이트까지 같아야 하는 경로(내보내기·골든)는 CPU 로 둡니다. 사용자가 기다리는
    // 프리뷰·검출에서만 GPU 를 켭니다 — `gpu_accelerator.h` 의 정책표.
    //
    // 이 판정을 **여기서** 합니다. 반전 단계가 아래에서 도는데, 그 단계 안의 GPU 가속은
    // `ApproximateAcceleratorScope` 를 보고 켜지므로 스코프가 먼저 열려 있어야 합니다.
    // 스코프는 스레드마다 따로라 다른 스레드의 내보내기는 영향을 안 받습니다.
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
        if (auto failed = decode_source(
                request, tracker, stop, observed, decoded_image, preview)) {
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

    // macOS `CIImage` 사슬은 GPU 에 머물고, 평가 지점은
    // `DevelopFrameRenderer+Developed.swift` `renderDisplayCGImage` 의
    // `context.createCGImage(..., format: .RGBA8)` 한 번입니다
    // (`sharedRenderContext`). 디코드는 묶지 않습니다 — 썸네일과 현상이
    // 직렬화됩니다. 항등 finish 는 호스트를 만지지 않고, `write_preview` 가
    // BGRA8 로 내립니다.
    // **선언 차례가 곧 파괴 차례입니다.** 상주 스코프의 소멸자는 GPU 에 머문 화소를
    // 호스트로 내리는데, 그 대상은 아래 단계 출력이 들고 있는 버퍼입니다. 스코프를
    // 이 자리보다 **먼저** 선언하면 함수가 끝날 때 이미지가 먼저 사라지고, 그 뒤에
    // 소멸자가 **해제된 메모리에 씁니다.** 2026-08-20 자동 레벨/자동 색상 단추를
    // 여러 번 누르면 앱이 죽던 원인이 이것이었습니다 — 크래시는 언제나
    // `gpu_working_image.cpp` `copy_rows` 안의 memcpy 였습니다(0xc0000005 쓰기).
    // 그래서 단계 출력들을 먼저 선언하고, 스코프를 **마지막에** 선언합니다.
    InvertStageOutput invert{};
    LookStageOutput look{};
    GrainStageOutput grain{};
    FinishStageOutput finish{};

    std::optional<GpuResidentScope> resident_scope{};
    if (gpu_policy == GpuUsePolicy::allowed) {
        resident_scope.emplace();
    }

    if (auto failed = invert_source(
            request,
            tracker,
            std::move(decoded_image),
            invert,
            proxy_hint.image_is_proxy || proxy_hint.has_base ? &proxy_hint : nullptr)) {
        return *failed;
    }

    if (auto failed = apply_grade_stages(request, tracker, gpu_policy, invert)) {
        return *failed;
    }

    // **상주 해제는 단계 안에서 합니다.** 예전에는 여기서 넘기기 직전에 무조건 내렸는데,
    // `std::vector` 이동은 버퍼 주소를 그대로 두므로 항등 단계를 지나는 흔한 경우에도
    // 매번 내렸다가 다시 올렸습니다. 실측(1536 한 틱): 업로드 2회 + 다운로드 3회 =
    // 약 125 MB. 그리고 그 때문에 grain·finish·publish 의 **상주 갈래가 한 번도
    // 안 돌았습니다** — `try_encode_preview_bgra` 가 항상 실패한 이유가 이것입니다.
    //
    // 지금 규칙은 `outcome.h` 의 `unbind_resident_and` 에 적혀 있습니다: 버퍼를
    // **실제로 소비해 버리는 자리**(비항등 갈래, 실패·취소 반환)에서만 내립니다.
    // 함수 끝의 `resident_scope` 는 아래 단계 출력들보다 **먼저** 소멸하므로, 살아 있는
    // 버퍼를 가리킨 채 스코프가 끝나는 것은 안전합니다(선언 차례가 곧 파괴 차례).
    if (auto failed = apply_look_stages(
            request,
            tracker,
            look_workspace,
            std::move(invert.image),
            gpu_policy,
            look)) {
        return *failed;
    }

    if (auto failed = apply_grain_stage(
            request, control, detect, tracker, std::move(look.image), grain)) {
        return *failed;
    }
    if (grain.detect_complete) {
        return grain.detect_outcome;
    }

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

    // 마무리 화소는 `finish.sharpening.image` 가 들고 있습니다. `write_preview` 가
    // 상주면 GPU 로 BGRA8 을 내리고, 아니면 스스로 `flush_resident()` 합니다 —
    // 여기서 미리 내리면 그 GPU 갈래가 영영 안 돕니다.
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

// 예외 차단막입니다. 이 파이프라인은 화소 버퍼를 통째로 들고 다니고
// (5088×3401 `Rgba32F` = 277MB 한 장), 그 할당은 실패할 수 있습니다. 그런데 공개
// 진입점 셋이 전부 `noexcept` 이므로, 예외가 여기까지 올라오면 C++ 는
// `std::terminate` → `abort()` 로 **프로세스를 죽입니다.**
//
// 실제로 죽고 있었습니다 — Windows 이벤트 로그의 `0xc0000409` 세 건이 전부
// `Negaflow.Native.dll +0xf4969` 이고, 그 자리를 디스어셈블하면
// `raise(SIGABRT)` → `IsProcessorFeaturePresent(23)` → `int 29h`, 곧 CRT `abort()`
// 입니다. 메모리가 모자란 것은 앱이 죽을 이유가 아니라 **이 렌더가 실패할 이유**이므로,
// 호출자가 읽을 수 있는 outcome 으로 바꿔 돌려줍니다.
[[nodiscard]] DevelopExportOutcome run_develop(
    const DevelopExportRequest& request,
    const PreviewTarget* const preview,
    const DevelopRunControl& control,
    const DetectTarget* const detect = nullptr) noexcept {
    try {
        return run_develop_unguarded(request, preview, control, detect);
    } catch (const std::bad_alloc&) {
        return fail(DevelopExportStage::none, "out_of_memory");
    } catch (...) {
        return fail(DevelopExportStage::none, "unhandled_exception");
    }
}

} // namespace

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
    if (!request.retain_preview_raw) {
        (void)GpuAccelerator::shared().trim_idle();
    }
    return outcome;
}

} // namespace negaflow::pipeline
