#include "look.h"

#include "export/support/outcome.h"

#include "negaflow/core/pixel.h"
#include "negaflow/core/negative_inversion.h"
#include "negaflow/imaging/custom_color_target.h"
#include "negaflow/imaging/scanner_target_grade.h"
#include "negaflow/imaging/working_tone_adjuster.h"
#include "negaflow/pipeline/gpu_accelerator.h"

#include <optional>
#include <utility>

namespace negaflow::pipeline::develop_export_detail {

std::optional<DevelopExportOutcome> prepare_look_workspace(
    const DevelopExportRequest& request,
    const std::uint32_t decoded_width,
    LookWorkspaceOutput& out) noexcept {
    out.parameters = request.film_look;
    out.parameters.monochrome =
        request.negative.film_type ==
        negaflow::imaging::NegativeFilmType::black_and_white;

    const FilmLookWorkspacePrepareStatus workspace_status =
        prepare_film_look_workspace(out.parameters, decoded_width, out.workspace);
    if (workspace_status != FilmLookWorkspacePrepareStatus::ok) {
        return fail(
            DevelopExportStage::film_look_workspace,
            film_look_workspace_prepare_status_name(workspace_status));
    }
    out.workspace_bytes = film_look_workspace_bytes(out.workspace);
    return std::nullopt;
}

std::optional<DevelopExportOutcome> apply_look_stages(
    const DevelopExportRequest& request,
    RunTracker& tracker,
    LookWorkspaceOutput& workspace,
    negaflow::imaging::WorkingImage developed_image,
    const GpuUsePolicy gpu_policy,
    const std::optional<negaflow::imaging::AnalysisRegion>& analysis_region,
    const bool linear_negative_output,
    LookStageOutput& out) noexcept {
    tracker.begin(DevelopExportStage::tone_adjust, cost_of(tone_cost, true));

    // **GPU 를 먼저 시도하고, 처리하지 못했으면 CPU 로 갑니다.**
    // 가속기는 실패할 때 이미지를 손대지 않으므로(`gpu_accelerator.h`) 그대로 이어서
    // CPU 판을 부르면 됩니다. 두 경로의 화소는 동치 시험이 `1e-5` 로 묶습니다.
    // + 노출 숄더의 헤드룸은 필름 마스터 화이트에서 나옵니다(흑백 네거티브만 0.85 화이트).
    negaflow::imaging::WorkingToneAdjustParameters tone = request.tone;
    tone.exposure_headroom_stops = static_cast<float>(negaflow::core::exposure_headroom_stops(
        request.film_polarity == FilmPolarity::negative &&
        request.negative.film_type == negaflow::imaging::NegativeFilmType::black_and_white));
    // 커브 대역은 크롭한 사진 영역 안에서 잽니다(macOS `applyToneCurves(region:)`).
    tone.analysis_region = analysis_region;
    // 출력 톤(macOS `NegativeLinearResponse.output`)은 반전이 선형 기준 응답을 쓴 경우에만
    // 붙습니다(`linear_output`, macOS `NegativeLinearResponse.applies`). MAIN·PRINT·커스텀은
    // v4 인화 응답이 이미 어깨와 토우를 가지므로 여기서 한 번 더 접으면 명부가 0.84 에서
    // 막히고 검정이 뜹니다.
    if (request.film_polarity == FilmPolarity::negative && linear_negative_output) {
        const bool accelerated = gpu_policy == GpuUsePolicy::allowed &&
            GpuAccelerator::shared().apply_negative_output_tone(
                reinterpret_cast<float*>(developed_image.pixels.data()), developed_image.width,
                developed_image.height, developed_image.stride_pixels, tone.exposure_stops,
                request.negative.film_type == imaging::NegativeFilmType::black_and_white);
        if (!accelerated) {
            GpuAccelerator::shared().flush_resident();
            const auto status = core::apply_negative_output_tone(
                {developed_image.pixels.data(), developed_image.pixels.size(), developed_image.width,
                 developed_image.height, developed_image.stride_pixels}, tone.exposure_stops,
                request.negative.film_type == imaging::NegativeFilmType::black_and_white);
            if (status != core::KernelStatus::ok) {
                return unbind_resident_and(developed_image,
                    fail(DevelopExportStage::tone_adjust, core::kernel_status_name(status)));
            }
        }
        tone.exposure_stops = 0;
    }
    // 톤 조정 한 번(GPU 먼저, 못 하면 CPU). 실패하면 그 단계 이름으로 돌려줍니다.
    const auto run_tone = [gpu_policy](
        negaflow::imaging::WorkingImage image,
        const negaflow::imaging::WorkingToneAdjustParameters& parameters)
        -> negaflow::imaging::WorkingToneAdjustResult {
        negaflow::imaging::WorkingToneAdjustResult result{};
        const GpuToneOutcome accelerated =
            GpuAccelerator::shared().apply_working_tone_adjustments(
                gpu_policy, image, parameters, {});
        if (accelerated.handled) {
            result.status = negaflow::imaging::WorkingToneAdjustStatus::ok;
            result.info = accelerated.info;
            result.image = std::move(image);
            return result;
        }
        GpuAccelerator::shared().flush_resident();
        return negaflow::imaging::apply_working_tone_adjustments(std::move(image), parameters);
    };
    const auto tone_failure = [](negaflow::imaging::WorkingToneAdjustResult& failed)
        -> std::optional<DevelopExportOutcome> {
        // 여기서 돌아가면 `failed.image` 는 반환 뒤 사라집니다. 상주로 묶여 있으면
        // 지금 풀어야 합니다 — 이유는 `outcome.h` 의 `unbind_resident_and` 설명.
        if (failed.status ==
            negaflow::imaging::WorkingToneAdjustStatus::kernel_failed) {
            return unbind_resident_and(failed.image, fail(
                DevelopExportStage::tone_adjust,
                negaflow::core::kernel_status_name(failed.info.kernel_status)));
        }
        if (failed.status ==
            negaflow::imaging::WorkingToneAdjustStatus::measurement_failed) {
            return unbind_resident_and(failed.image, fail(
                DevelopExportStage::tone_adjust,
                negaflow::imaging::tone_curve_measurement_status_name(
                    failed.info.measurement.status)));
        }
        return unbind_resident_and(failed.image, fail(
            DevelopExportStage::tone_adjust,
            negaflow::imaging::working_tone_adjust_status_name(failed.status)));
    };

    // 스캐너 타깃(SP·HS·F135·HR)의 고정 렌더링은 화이트 밸런스·노출·기본 톤·파라메트릭 커브 뒤,
    // 포인트 커브·믹서·그레이딩·캘리브레이션 앞입니다(macOS
    // `ScannerTargetGrade.applyAfterSceneAdjustments`). 예전에는 반전 직후에 걸어, 흰색을 0.95
    // 근처까지 그린 인화 출력 위에서 MAIN 의 여유(흰색 0.70)를 전제로 만든 슬라이더가 다시
    // 돌았습니다 — 같은 사진에서 노출 +0.5 의 클리핑이 MAIN 0.1%·SP 28.6%(2026-11-07 실측).
    // 슬라이더가 모두 0 이면 앞 단계가 항등이라 결과는 예전과 같습니다.
    std::optional<negaflow::imaging::ScannerTargetStyle> scanner_target{};
    switch (request.develop_target) {
        case DevelopTarget::noritsu:
            scanner_target = negaflow::imaging::ScannerTargetStyle::noritsu;
            break;
        case DevelopTarget::sp3000:
            scanner_target = negaflow::imaging::ScannerTargetStyle::sp3000;
            break;
        case DevelopTarget::f135:
            scanner_target = negaflow::imaging::ScannerTargetStyle::f135;
            break;
        case DevelopTarget::hr:
            scanner_target = negaflow::imaging::ScannerTargetStyle::hr;
            break;
        default:
            break;
    }

    negaflow::imaging::WorkingToneAdjustResult adjusted{};
    if (!scanner_target.has_value()) {
        adjusted = run_tone(std::move(developed_image), tone);
        if (adjusted.status != negaflow::imaging::WorkingToneAdjustStatus::ok) {
            return tone_failure(adjusted);
        }
    } else {
        negaflow::imaging::WorkingToneAdjustParameters scene = tone;
        scene.point_curves = {};
        scene.color_mixer = {};
        scene.color_grading = {};
        scene.primary_calibration = {};
        adjusted = run_tone(std::move(developed_image), scene);
        if (adjusted.status != negaflow::imaging::WorkingToneAdjustStatus::ok) {
            return tone_failure(adjusted);
        }
        // 화상은 GPU 에 머문 채로 렌더링합니다(흑백 luma 붕괴도 커널 안에서 합니다).
        negaflow::imaging::ScannerTargetGradeInfo target_info{};
        const negaflow::core::KernelStatus target_status =
            negaflow::imaging::apply_scanner_target_grade(
                {
                    adjusted.image.pixels.data(),
                    adjusted.image.pixels.size(),
                    adjusted.image.width,
                    adjusted.image.height,
                    adjusted.image.stride_pixels,
                },
                *scanner_target,
                request.negative.film_type == negaflow::imaging::NegativeFilmType::black_and_white,
                request.film_polarity == FilmPolarity::positive,
                request.scanner_profile_id,
                target_info);
        if (target_status != negaflow::core::KernelStatus::ok) {
            return unbind_resident_and(adjusted.image, fail(
                DevelopExportStage::target_grade,
                negaflow::core::kernel_status_name(target_status)));
        }
        negaflow::imaging::WorkingToneAdjustParameters output = tone;
        output.exposure_stops = 0.0F;
        output.basic = {};
        output.curve = {};
        adjusted = run_tone(std::move(adjusted.image), output);
        if (adjusted.status != negaflow::imaging::WorkingToneAdjustStatus::ok) {
            return tone_failure(adjusted);
        }
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return unbind_resident_and(
            adjusted.image, cancelled_outcome(DevelopExportStage::tone_adjust));
    }

    // 톤·캘리브레이션 뒤, film look의 identity 조기 반환보다 먼저 한 번 적용합니다.
    const auto target = static_cast<std::uint32_t>(request.develop_target);
    if (imaging::custom_color_target_profile(target) != nullptr) {
        const auto* table = imaging::kernel_accelerator();
        const bool handled = gpu_policy == GpuUsePolicy::allowed && table != nullptr &&
            table->custom_color_target != nullptr && table->custom_color_target(
                reinterpret_cast<float*>(adjusted.image.pixels.data()), adjusted.image.width,
                adjusted.image.height, adjusted.image.stride_pixels, target);
        if (!handled) {
            GpuAccelerator::shared().flush_resident();
            const core::ImageView pixels{adjusted.image.pixels.data(), adjusted.image.pixels.size(),
                adjusted.image.width, adjusted.image.height, adjusted.image.stride_pixels};
            const auto status = imaging::apply_custom_color_target(
                {pixels.pixels, pixels.pixel_capacity, pixels.width, pixels.height, pixels.stride_pixels}, pixels, target);
            if (status != core::KernelStatus::ok) {
                return unbind_resident_and(adjusted.image, fail(
                    DevelopExportStage::tone_adjust, core::kernel_status_name(status)));
            }
        }
    }

    if (tracker.cancelled()) {
        return unbind_resident_and(adjusted.image, cancelled_outcome(DevelopExportStage::tone_adjust));
    }

    tracker.begin(
        DevelopExportStage::film_look,
        cost_of(
            film_look_cost,
            request.film_look.source_kind !=
                negaflow::imaging::DevelopSourceKind::film_scan));

    negaflow::imaging::FilmLookRoute route = negaflow::imaging::FilmLookRoute::invalid;
    const bool resolved = negaflow::imaging::try_resolve_film_look_route(
        workspace.parameters, route);
    const float* const resident_pixels =
        reinterpret_cast<const float*>(adjusted.image.pixels.data());
    if (resolved && route == negaflow::imaging::FilmLookRoute::identity &&
        GpuAccelerator::shared().has_resident_image(
            resident_pixels, adjusted.image.width, adjusted.image.height)) {
        bool finite = false;
        if (GpuAccelerator::shared().check_resident_finite(
                resident_pixels,
                adjusted.image.width,
                adjusted.image.height,
                adjusted.image.stride_pixels,
                &finite) &&
            finite) {
            tracker.finish();
            if (tracker.cancelled()) {
                return unbind_resident_and(
                    adjusted.image, cancelled_outcome(DevelopExportStage::film_look));
            }
            out.image = std::move(adjusted.image);
            out.workspace_bytes = workspace.workspace_bytes;
            out.info.route = negaflow::imaging::FilmLookRoute::identity;
            out.info.kernel_status = negaflow::core::KernelStatus::ok;
            return std::nullopt;
        }
        GpuAccelerator::shared().flush_resident();
    } else if (!resolved || route != negaflow::imaging::FilmLookRoute::identity) {
        GpuAccelerator::shared().flush_resident();
    }

    auto film_look = negaflow::imaging::apply_working_film_look(
        std::move(adjusted.image),
        workspace.parameters,
        film_look_workspace_view(workspace.workspace));
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

    tracker.finish();
    if (tracker.cancelled()) {
        return unbind_resident_and(
            film_look.image, cancelled_outcome(DevelopExportStage::film_look));
    }

    out.image = std::move(film_look.image);
    out.workspace_bytes = workspace.workspace_bytes;
    out.info = film_look.info;
    return std::nullopt;
}

} // namespace negaflow::pipeline::develop_export_detail
