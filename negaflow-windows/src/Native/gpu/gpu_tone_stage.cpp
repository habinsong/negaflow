#include "negaflow/gpu/gpu_tone_stage.h"

#include <cmath>
#include <new>
#include <utility>
#include <vector>

#include "negaflow/gpu/gpu_color_kernels.h"
#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_stage_kernels.h"
#include "negaflow/gpu/gpu_neighborhood.h"
#include "negaflow/gpu/gpu_tone_kernels.h"
#include "negaflow/gpu/gpu_working_image.h"

namespace negaflow::gpu {
namespace {

using negaflow::imaging::ToneCurveMeasurementStatus;
using negaflow::imaging::WorkingToneAdjustStatus;

// 매개변수 변환은 **CPU 준비 함수를 그대로 부르고 옮겨 담기만** 합니다.
// 여기서 다시 계산하면 두 벌이 되어 갈라집니다.
[[nodiscard]] GpuBasicToneParameters to_gpu(
    const imaging::BasicToneParameters& parameters) noexcept {
    return {
        parameters.contrast,
        parameters.density,
        parameters.highlights,
        parameters.shadows,
        parameters.whites,
        parameters.blacks};
}

[[nodiscard]] GpuParametricToneCurveParameters to_gpu(
    const imaging::ParametricToneCurveParameters& parameters,
    const imaging::ParametricToneCurveBands& bands) noexcept {
    GpuParametricToneCurveParameters gpu{};
    gpu.highlights = parameters.highlights;
    gpu.lights = parameters.lights;
    gpu.darks = parameters.darks;
    gpu.shadows = parameters.shadows;
    gpu.shadow_low = bands.shadow_low;
    gpu.shadow_high = bands.shadow_high;
    gpu.dark_low = bands.dark_low;
    gpu.dark_high = bands.dark_high;
    gpu.light_low = bands.light_low;
    gpu.light_high = bands.light_high;
    gpu.highlight_low = bands.highlight_low;
    gpu.highlight_high = bands.highlight_high;
    return gpu;
}

[[nodiscard]] GpuColorMixerParameters to_gpu(
    const imaging::ColorMixerParameters& parameters) noexcept {
    GpuColorMixerParameters gpu{};
    for (std::size_t band = 0U; band < imaging::color_mixer_band_count; ++band) {
        gpu.hue[band] = parameters.hue[band];
        gpu.saturation[band] = parameters.saturation[band];
        gpu.luminance[band] = parameters.luminance[band];
    }
    return gpu;
}

[[nodiscard]] GpuColorGradeSetup to_gpu(const imaging::ColorGradingSetup& setup) noexcept {
    GpuColorGradeSetup gpu{};
    for (int index = 0; index < 3; ++index) {
        gpu.shadow_offset[index] = setup.shadow_offset[index];
        gpu.midtone_offset[index] = setup.midtone_offset[index];
        gpu.highlight_offset[index] = setup.highlight_offset[index];
    }
    gpu.pivot = setup.pivot;
    gpu.width = setup.width;
    return gpu;
}

[[nodiscard]] GpuPrimaryCalibrationParameters to_gpu(
    const imaging::PrimaryCalibrationParameters& parameters) noexcept {
    return {
        parameters.red_hue,
        parameters.red_saturation,
        parameters.green_hue,
        parameters.green_saturation,
        parameters.blue_hue,
        parameters.blue_saturation};
}

[[nodiscard]] GpuPointCurveLuts to_gpu(const imaging::PointCurveLuts& luts) noexcept {
    GpuPointCurveLuts gpu{};
    for (std::size_t index = 0U; index < GpuPointCurveLuts::lut_size; ++index) {
        gpu.red[index] = luts.red[index];
        gpu.green[index] = luts.green[index];
        gpu.blue[index] = luts.blue[index];
    }
    return gpu;
}

[[nodiscard]] negaflow::core::ConstImageView const_view(
    const imaging::WorkingImage& image) noexcept {
    return {
        image.pixels.data(), image.pixels.size(), image.width, image.height,
        image.stride_pixels};
}

} // namespace

// 커널 일곱과 핑퐁 두 장입니다. 텍스처는 크기가 바뀔 때만 다시 만듭니다.
struct GpuToneStage::State final {
    GpuExposure exposure{};
    GpuBasicTone basic{};
    GpuParametricToneCurve curve{};
    GpuPointCurve point_curve{};
    GpuColorMixer mixer{};
    GpuColorGrade grade{};
    GpuPrimaryCalibration primary{};

    mutable GpuWorkingImage front{};
    mutable GpuWorkingImage back{};
    mutable std::uint32_t width{0U};
    mutable std::uint32_t height{0U};
    mutable GpuWorkingImage retained_front{};
    mutable GpuWorkingImage retained_back{};
    mutable std::uint32_t retained_width{0U};
    mutable std::uint32_t retained_height{0U};
    // 측정 스냅숏은 **호출부 이미지가 아니라** 여기로 내립니다. 호출부 이미지에 쓰면,
    // 그 뒤 한 걸음이라도 실패해 CPU 로 되돌아갈 때 CPU 가 **반쯤 처리된 화소**를
    // 다시 처리하게 됩니다. 그 순간 값이 조용히 틀어집니다.
    mutable std::vector<negaflow::core::Rgba32F> measurement_pixels{};
    // 밴드 측정 앞의 전 화소 유한성 확인을 GPU 에서 합니다. 4바이트만 회수합니다.
    GpuFiniteCheck finite{};

    [[nodiscard]] bool ensure_images(
        const GpuDevice& device,
        const std::uint32_t needed_width,
        const std::uint32_t needed_height) const noexcept {
        if (front.is_valid() && width == needed_width && height == needed_height) {
            return true;
        }
        if (retained_front.is_valid() && retained_width == needed_width &&
            retained_height == needed_height) {
            GpuWorkingImage swap_front = std::move(front);
            GpuWorkingImage swap_back = std::move(back);
            front = std::move(retained_front);
            back = std::move(retained_back);
            retained_front = std::move(swap_front);
            retained_back = std::move(swap_back);
            std::swap(width, retained_width);
            std::swap(height, retained_height);
            return true;
        }
        retained_front = std::move(front);
        retained_back = std::move(back);
        retained_width = width;
        retained_height = height;
        if (GpuWorkingImage::create(device, needed_width, needed_height, front) !=
                GpuImageStatus::ok ||
            GpuWorkingImage::create(device, needed_width, needed_height, back) !=
                GpuImageStatus::ok) {
            front = GpuWorkingImage{};
            back = GpuWorkingImage{};
            retained_front = GpuWorkingImage{};
            retained_back = GpuWorkingImage{};
            width = 0U;
            height = 0U;
            retained_width = 0U;
            retained_height = 0U;
            return false;
        }
        width = needed_width;
        height = needed_height;
        return true;
    }
};

GpuToneStage::~GpuToneStage() {
    delete state_;
    state_ = nullptr;
}

bool GpuToneStage::is_valid() const noexcept { return state_ != nullptr; }

GpuKernelStatus GpuToneStage::create(const GpuDevice& device, GpuToneStage& stage) noexcept {
    delete stage.state_;
    stage.state_ = nullptr;
    if (!device.is_usable()) {
        return GpuKernelStatus::device_unavailable;
    }

    auto* const state = new (std::nothrow) State{};
    if (state == nullptr) {
        return GpuKernelStatus::resource_creation_failed;
    }
    const bool made =
        GpuExposure::create(device, state->exposure) == GpuKernelStatus::ok &&
        GpuBasicTone::create(device, state->basic) == GpuKernelStatus::ok &&
        GpuParametricToneCurve::create(device, state->curve) == GpuKernelStatus::ok &&
        GpuPointCurve::create(device, state->point_curve) == GpuKernelStatus::ok &&
        GpuColorMixer::create(device, state->mixer) == GpuKernelStatus::ok &&
        GpuColorGrade::create(device, state->grade) == GpuKernelStatus::ok &&
        GpuPrimaryCalibration::create(device, state->primary) == GpuKernelStatus::ok &&
        GpuFiniteCheck::create(device, state->finite) == GpuKernelStatus::ok;
    if (!made) {
        delete state;
        return GpuKernelStatus::resource_creation_failed;
    }
    stage.state_ = state;
    return GpuKernelStatus::ok;
}

GpuToneStageResult GpuToneStage::apply(
    const GpuDevice& device,
    imaging::WorkingImage& image,
    const imaging::WorkingToneAdjustParameters& parameters,
    const imaging::ToneCurveMeasurementLimits& measurement_limits) const noexcept {
    GpuToneStageResult result{};
    result.info.kernel_status = negaflow::core::KernelStatus::ok;

    if (state_ == nullptr || !device.is_usable()) {
        return result; // handled == false — 호출부가 CPU 로 갑니다.
    }
    // 검증은 CPU 판과 **같은 함수**를 씁니다. 여기서 다시 쓰면 두 벌이 됩니다.
    if (!imaging::valid_working_tone_adjust_parameters(parameters)) {
        return result;
    }
    if (image.width == 0U || image.height == 0U || image.stride_pixels < image.width) {
        return result;
    }
    // CPU 판의 첫 관문입니다 — 비유한 화소는 여기서 걸러야 GPU 로 들어가지 않습니다.
    const negaflow::core::KernelStatus validated =
        negaflow::core::validate_image_view(const_view(image));
    if (validated != negaflow::core::KernelStatus::ok) {
        // 값 문제는 CPU 판이 같은 판정을 내리므로 그쪽에 맡깁니다.
        return result;
    }

    // CPU 판(`working_tone_adjuster.cpp:84-102`)의 게이트를 그대로 옮깁니다.
    const bool exposure_changes =
        std::abs(parameters.exposure_stops) > imaging::tone_change_threshold;
    const bool basic_changes = imaging::has_basic_tone_change(parameters.basic);
    const bool curve_changes = imaging::has_parametric_tone_curve_change(parameters.curve);
    const bool point_curve_changes = imaging::has_point_curve_change(parameters.point_curves);
    const bool mixer_changes = imaging::has_color_mixer_change(parameters.color_mixer);
    const bool grading_changes = imaging::has_color_grading_change(parameters.color_grading);
    const bool primary_changes =
        imaging::has_primary_calibration_change(parameters.primary_calibration);
    if (!exposure_changes && !basic_changes && !curve_changes && !point_curve_changes &&
        !mixer_changes && !grading_changes && !primary_changes) {
        // 아무것도 안 움직였습니다. 올릴 이유가 없습니다 — CPU 판도 그대로 돌려줍니다.
        result.handled = true;
        result.status = WorkingToneAdjustStatus::ok;
        result.info.measurement.status = ToneCurveMeasurementStatus::ok;
        result.info.measurement.kernel_status = negaflow::core::KernelStatus::ok;
        return result;
    }

    if (!state_->ensure_images(device, image.width, image.height)) {
        return result;
    }
    // ensure 가 이미 front/back 을 들고 있습니다. 정적 upload() 는 create() 를
    // 다시 불러 138 MB DEFAULT+스테이징을 렌더마다 버렸습니다.
    if (state_->front.upload_into(
            device, image.pixels.data(), image.stride_pixels) != GpuImageStatus::ok) {
        return result;
    }
    return apply_on(
        device, state_->front, state_->back, image, parameters, measurement_limits, true);
}

GpuToneStageResult GpuToneStage::apply_on(
    const GpuDevice& device,
    GpuWorkingImage& input,
    GpuWorkingImage& scratch,
    imaging::WorkingImage& image,
    const imaging::WorkingToneAdjustParameters& parameters,
    const imaging::ToneCurveMeasurementLimits& measurement_limits,
    const bool download) const noexcept {
    GpuToneStageResult result{};
    result.info.kernel_status = negaflow::core::KernelStatus::ok;
    if (state_ == nullptr || !device.is_usable() || !input.is_valid() || !scratch.is_valid()) {
        return result;
    }
    if (!imaging::valid_working_tone_adjust_parameters(parameters)) {
        return result;
    }
    const bool exposure_changes =
        std::abs(parameters.exposure_stops) > imaging::tone_change_threshold;
    const bool basic_changes = imaging::has_basic_tone_change(parameters.basic);
    const bool curve_changes = imaging::has_parametric_tone_curve_change(parameters.curve);
    const bool point_curve_changes = imaging::has_point_curve_change(parameters.point_curves);
    const bool mixer_changes = imaging::has_color_mixer_change(parameters.color_mixer);
    const bool grading_changes = imaging::has_color_grading_change(parameters.color_grading);
    const bool primary_changes =
        imaging::has_primary_calibration_change(parameters.primary_calibration);
    if (!exposure_changes && !basic_changes && !curve_changes && !point_curve_changes &&
        !mixer_changes && !grading_changes && !primary_changes) {
        if (download &&
            input.download(device, image.pixels.data(), image.stride_pixels) !=
                GpuImageStatus::ok) {
            return result;
        }
        result.handled = true;
        result.status = WorkingToneAdjustStatus::ok;
        result.info.measurement.status = ToneCurveMeasurementStatus::ok;
        result.info.measurement.kernel_status = negaflow::core::KernelStatus::ok;
        return result;
    }

    // 핑퐁. `read` 가 현재 결과이고 `write` 가 다음 목적지입니다.
    GpuWorkingImage* read = &input;
    GpuWorkingImage* write = &scratch;
    const auto swap_after = [&](const GpuKernelStatus status) noexcept {
        if (status == GpuKernelStatus::ok) {
            std::swap(read, write);
        }
        return status;
    };

    if (exposure_changes) {
        if (swap_after(state_->exposure.dispatch(
                device, *read, *write, parameters.exposure_stops)) != GpuKernelStatus::ok) {
            return result;
        }
        result.info.exposure_applied = true;
    }

    if (basic_changes) {
        if (swap_after(state_->basic.dispatch(
                device, *read, *write, to_gpu(parameters.basic))) != GpuKernelStatus::ok) {
            return result;
        }
        result.info.basic_tone_applied = true;
    }

    if (curve_changes) {
        // 주의 여기서 한 번 내립니다. 측정이 전 화소를 `double` 로 훑기 때문입니다 —
        // 헤더의 설명 참고. 커브가 꺼져 있으면 이 왕복이 없습니다.
        //
        // 실측 2026-08-19: 있는 `GpuMipHalve` 로 ≤256 프록시를 만들어 재면
        // GPU/CPU 최대 오차가 **2.55e-04** (허용 1e-5). 밴드 오차 2.48e-04.
        // 값을 바꾸므로 쓰지 않습니다. `GpuAreaAverage` 는 영역 평균 하나라
        // 백분위 격자를 대체하지 못합니다.
        const std::size_t needed =
            static_cast<std::size_t>(image.width) * static_cast<std::size_t>(image.height);
        if (state_->measurement_pixels.size() != needed) {
            state_->measurement_pixels.assign(needed, negaflow::core::Rgba32F{});
        }
        if (read->download(device, state_->measurement_pixels.data(), image.width) !=
            GpuImageStatus::ok) {
            return result;
        }
        const negaflow::core::ConstImageView snapshot{
            state_->measurement_pixels.data(),
            state_->measurement_pixels.size(),
            image.width,
            image.height,
            image.width};
        bool all_finite = false;
        if (state_->finite.dispatch(device, *read, all_finite) != GpuKernelStatus::ok) {
            all_finite = false;
        }
        result.info.measurement = imaging::measure_parametric_tone_curve_bands(
            snapshot, measurement_limits, all_finite);
        if (result.info.measurement.status != ToneCurveMeasurementStatus::ok) {
            // CPU 판과 같은 실패입니다. 여기서 끝내면 CPU 로 다시 돌 이유가 없습니다 —
            // 이미지는 측정 직전 상태로 내려와 있으므로 CPU 판에 맡깁니다.
            return result;
        }
        if (swap_after(state_->curve.dispatch(
                device,
                *read,
                *write,
                to_gpu(parameters.curve, result.info.measurement.info.bands))) !=
            GpuKernelStatus::ok) {
            return result;
        }
        result.info.parametric_curve_applied = true;
    } else {
        result.info.measurement.status = ToneCurveMeasurementStatus::ok;
        result.info.measurement.kernel_status = negaflow::core::KernelStatus::ok;
    }

    if (point_curve_changes) {
        imaging::PointCurveLuts luts{};
        if (imaging::build_point_curve_luts(parameters.point_curves, luts) !=
            negaflow::core::KernelStatus::ok) {
            return result;
        }
        if (swap_after(state_->point_curve.dispatch(device, *read, *write, to_gpu(luts))) !=
            GpuKernelStatus::ok) {
            return result;
        }
        result.info.point_curve_applied = true;
    }

    if (mixer_changes) {
        if (swap_after(state_->mixer.dispatch(
                device, *read, *write, to_gpu(parameters.color_mixer))) !=
            GpuKernelStatus::ok) {
            return result;
        }
        result.info.color_mixer_applied = true;
    }

    if (grading_changes) {
        if (swap_after(state_->grade.dispatch(
                device,
                *read,
                *write,
                to_gpu(imaging::prepare_color_grading(parameters.color_grading)))) !=
            GpuKernelStatus::ok) {
            return result;
        }
        result.info.color_grading_applied = true;
    }

    if (primary_changes) {
        if (swap_after(state_->primary.dispatch(
                device, *read, *write, to_gpu(parameters.primary_calibration))) !=
            GpuKernelStatus::ok) {
            return result;
        }
        result.info.primary_calibration_applied = true;
    }

    if (download &&
        read->download(device, image.pixels.data(), image.stride_pixels) !=
            GpuImageStatus::ok) {
        return result;
    }

    result.handled = true;
    result.status = WorkingToneAdjustStatus::ok;
    result.info.kernel_status = negaflow::core::KernelStatus::ok;
    return result;
}

} // namespace negaflow::gpu
