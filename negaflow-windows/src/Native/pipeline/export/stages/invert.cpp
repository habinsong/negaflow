#include "invert.h"

#include "export/support/outcome.h"

#include "negaflow/core/pixel.h"
#include "negaflow/pipeline/gpu_accelerator.h"
#include "negaflow/imaging/analysis_region.h"
#include "negaflow/imaging/auto_negative_base_resolver.h"
#include "negaflow/imaging/channel_range_shape.h"
#include "negaflow/imaging/film_base_scale.h"

#include "export/support/scene_measurement_memo.h"
#include "export/support/preview_proxy.h"

#include <memory>
#include <utility>

namespace negaflow::pipeline::develop_export_detail {
namespace {

void apply_resolved_base(InvertStageOutput& out, const PreviewProxyHint& hint) noexcept {
    out.negative.dmin = hint.dmin;
    out.base_source = hint.base_source;
    out.negative.use_preset_response = hint.use_preset_response;
    out.negative.preset_range_factor = hint.preset_range_factor;
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
    hint.preset_range_factor = {};
    // 크롭이 있으면 베이스를 크롭 바깥 띠(리베이트)에서 먼저 찾습니다(macOS `developBase`
    // 의 `analysisRegion`). 정규 좌표라 원본이든 프록시든 같은 영역입니다.
    hint.base_region = negaflow::imaging::analysis_region_from_transform(
        request.image_transform, image.width, image.height);
    hint.base_image_width = image.width;
    hint.base_image_height = image.height;
    const negaflow::imaging::AutoNegativeBaseResult resolved =
        negaflow::imaging::resolve_auto_negative_base(
            image, request.negative.film_type, hint.base_region);
    if (resolved.status != negaflow::imaging::AutoNegativeBaseStatus::ok) {
        return fail(
            DevelopExportStage::develop,
            negaflow::imaging::auto_negative_base_status_name(resolved.status));
    }
    hint.measurement_method = method_of(resolved.source);
    hint.diagnostics = resolved.diagnostics;
    // 필름을 고르지 않은 프리셋 모드는 **자동으로 떨어집니다.**
    //
    // 필름 표에서 필름을 "없음" 으로 두면 모드는 preset 인 채 스톡만 비게 됩니다. 앞 판은
    // 그 조합을 통째로 실패로 돌려보냈고, 화면에는 아무 설명 없이 빈 캔버스가 남았습니다.
    // 게다가 사진이 안 보이니 현상 패널이 그 프레임을 들지 못해 모드를 되돌릴 수도 없는
    // 막다른 골목이었습니다(2026-09-01 보고: 필름스톡을 없음으로 두고 재시작하면 그
    // 사진만 프리뷰가 사라짐).
    //
    // 고를 필름이 없다는 것은 "표에서 가져올 값이 없다" 는 뜻이지 "현상할 수 없다" 는 뜻이
    // 아닙니다. 측정한 베이스가 이미 있으므로 그것으로 갑니다 — 아래 측정 경로와 같은
    // 자리입니다.
    if (request.base_estimation_mode == NegativeBaseEstimationMode::preset &&
        request.film_stock_preset.has_value()) {
        hint.use_preset_response = true;
        hint.preset_range_factor = request.film_stock_preset->range_factor;
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
    const PreviewProxyHint* const hint,
    const std::optional<std::array<float, 3>>& input_gamma_reference) noexcept {
    out.negative = request.negative;
    const bool toggle_target = request.develop_target == DevelopTarget::main ||
        request.develop_target == DevelopTarget::print || request.develop_target >= DevelopTarget::emulsion;
    out.negative.legacy_scene_response = toggle_target && request.auto_balance;
    out.negative.adaptive_density = out.negative.legacy_scene_response ||
        request.develop_target == DevelopTarget::noritsu || request.develop_target == DevelopTarget::sp3000 ||
        request.develop_target == DevelopTarget::f135 || request.develop_target == DevelopTarget::hr;
    out.negative.linear_output = !toggle_target && !out.negative.adaptive_density &&
        (request.develop_target == DevelopTarget::rescue || request.scanner_profile_id.empty());
    out.negative.input_gamma_reference_range = input_gamma_reference;
    out.base_source = DevelopBaseSource::manual;
    out.developed_info = {};
    out.positive = request.film_polarity == FilmPolarity::positive;
    out.negative_source = !out.positive;
    out.analysis_region = negaflow::imaging::analysis_region_from_transform(
        request.image_transform, decoded_image.width, decoded_image.height);
    out.negative.analysis_region = out.analysis_region;
    const bool needs_base =
        out.negative_source &&
        (request.base_estimation_mode == NegativeBaseEstimationMode::auto_estimate ||
         request.base_estimation_mode == NegativeBaseEstimationMode::preset);
    tracker.begin(
        DevelopExportStage::develop,
        cost_of(auto_base_cost, needs_base && (hint == nullptr || !hint->has_base)) +
            cost_of(invert_cost, out.negative_source));
    // 앞 단계 사이에 취소됐으면 베이스 추정과 반전(정착 크기 75~170 ms)을 돌지 않습니다.
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::develop);
    }
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

    out.reference_base = out.negative.dmin;
    if (out.negative_source && request.base_estimation_mode == NegativeBaseEstimationMode::auto_estimate) {
        out.negative.dmin = negaflow::imaging::scale_auto_film_base(out.reference_base, request.base_scale);
    }
    // 롤 교정의 재료: 자동 밸런스가 켜져 있든 꺼져 있든 이 프레임의 채널 범위 모양을 잰다. 반전이
    // 화상을 고치기 전에 재야 하고, 자동 밸런스 측정과 같은 키(legacy 켬)를 쓰므로 프록시 메모를
    // 함께 쓴다. 베이스는 macOS `ChannelRangeCalibration.measure` 처럼 밑 크기 조정 전 추정값이다.
    if (request.measure_range_shape && out.negative_source &&
        out.negative.film_type == negaflow::imaging::NegativeFilmType::color) {
        const std::shared_ptr<SceneMeasurementMemo> shape_memo =
            hint != nullptr ? hint->scene_memo : nullptr;
        SceneMeasurementInputs shape_inputs{};
        shape_inputs.dmin = out.reference_base;
        shape_inputs.film_type = out.negative.film_type;
        shape_inputs.region = out.negative.analysis_region;
        shape_inputs.legacy_scene_response = true;
        shape_inputs.width = decoded_image.width;
        shape_inputs.height = decoded_image.height;
        std::optional<negaflow::imaging::SceneRangeMeasurement> measured =
            shape_memo != nullptr ? shape_memo->find_range(shape_inputs) : std::nullopt;
        if (!measured) {
            measured = negaflow::imaging::measure_scene_range(
                decoded_image, out.reference_base, out.negative.film_type,
                out.negative.analysis_region, true);
            if (measured && shape_memo != nullptr) {
                shape_memo->store_range(shape_inputs, *measured);
            }
        }
        if (measured) {
            out.range_shape = negaflow::imaging::channel_range_shape(measured->dmax_normalized);
        }
    }
    if (out.negative_source) {
        // 같은 프록시에서 이미 잰 장면 측정이 있으면 다시 재지 않는다(자동 밸런스 켠 슬라이더 조작과
        // 껐다 켜기가 매번 두 측정을 반복했다). 키에 측정 입력을 모두 넣어 낡은 값을 쓰지 않는다.
        const std::shared_ptr<SceneMeasurementMemo> memo = hint != nullptr ? hint->scene_memo : nullptr;
        SceneMeasurementInputs range_inputs{};
        SaturationInputs saturation_inputs{};
        if (memo != nullptr && out.negative.adaptive_density) {
            range_inputs.dmin = out.negative.dmin;
            range_inputs.film_type = out.negative.film_type;
            range_inputs.region = out.negative.analysis_region;
            range_inputs.legacy_scene_response = out.negative.legacy_scene_response;
            range_inputs.width = decoded_image.width;
            range_inputs.height = decoded_image.height;
            saturation_inputs.scene = range_inputs;
            saturation_inputs.use_preset_response = out.negative.use_preset_response;
            saturation_inputs.preset_range_factor = out.negative.preset_range_factor;
            saturation_inputs.input_gamma_reference_range = out.negative.input_gamma_reference_range;
            saturation_inputs.channel_range = out.negative.channel_range;
            saturation_inputs.linear_output = out.negative.linear_output;
            out.negative.reused_scene_range = memo->find_range(range_inputs);
            out.negative.reused_mean_saturation = memo->find_saturation(saturation_inputs);
        }
        const bool reused_range = out.negative.reused_scene_range.has_value();
        const bool reused_saturation = out.negative.reused_mean_saturation.has_value();
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
        if (memo != nullptr && out.negative.adaptive_density) {
            if (!reused_range && developed.info.scene_range) {
                memo->store_range(range_inputs, *developed.info.scene_range);
            }
            if (!reused_saturation && developed.info.muted_scene_vibrance.saturation_measured) {
                memo->store_saturation(
                    saturation_inputs, developed.info.muted_scene_vibrance.mean_saturation);
            }
        }
        out.developed_info = developed.info;
        out.image = std::move(developed.image);
    } else {
        // Positive film scans and rendered-digital input are already positive
        // working images. Negative base and inversion do not participate.
        out.image = std::move(decoded_image);
    }

    if (out.image.camera_to_working) {
        GpuAccelerator::shared().flush_resident();
        if (!negaflow::imaging::apply_deferred_camera_transform(out.image)) {
            return fail(DevelopExportStage::develop, "invalid_camera_to_working_matrix");
        }
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::develop);
    }
    return std::nullopt;
}

}  // namespace negaflow::pipeline::develop_export_detail
