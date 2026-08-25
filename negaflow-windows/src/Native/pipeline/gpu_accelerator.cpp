#include "negaflow/pipeline/gpu_accelerator.h"

#include "gpu_accelerator_state.h"

#include <cstdlib>
#include <mutex>
#include <new>

namespace negaflow::pipeline {


namespace {

[[nodiscard]] bool gpu_disabled_by_environment() noexcept {
    // `NEGA_GPU=0` 이면 GPU 를 아예 열지 않습니다. 문제를 가를 때와 전후를 잴 때 씁니다 —
    // 코드를 고쳐 끄면 무엇을 껐는지 기록이 안 남습니다.
    char value[8]{};
    std::size_t length = 0U;
    if (getenv_s(&length, value, sizeof(value), "NEGA_GPU") != 0 || length == 0U) {
        return false;
    }
    return value[0] == 48;  // 48 == 0
}

}  // namespace

GpuAccelerator::GpuAccelerator() noexcept {
    auto* const state = new (std::nothrow) State{};
    if (state == nullptr) {
        return;
    }
    if (gpu_disabled_by_environment()) {
        state_ = state;
        return;
    }
    // `automatic` — 하드웨어를 먼저 찾고 없으면 WARP 입니다. 벤더로 거르지 않습니다.
    state->device = gpu::GpuDevice::create(gpu::GpuDevicePreference::automatic);
    if (state->device.is_usable() &&
        gpu::GpuToneStage::create(state->device, state->tone) == gpu::GpuKernelStatus::ok &&
        gpu::GpuFilmScanDenoiseStage::create(state->device, state->denoise) ==
            gpu::GpuKernelStatus::ok) {
        state->usable = true;
        state->adapter = state->device.capability().adapter.description.data();
        // 형태학은 따로 만듭니다. 이것만 실패해도 톤·디노이즈는 그대로 돕니다.
        state->morphology_ready =
            gpu::GpuMorphology::create(state->device, state->morphology) ==
            gpu::GpuKernelStatus::ok;
        // 반전은 현상에서 가장 비싼 단계입니다(실측 41%). 따로 만들어 이것만 실패해도
        // 나머지가 그대로 돌게 합니다.
        state->invert_ready =
            gpu::GpuNegativeInvert::create(state->device, state->invert) ==
            gpu::GpuKernelStatus::ok;
        state->halation_ready =
            gpu::GpuGaussianBlur::create(state->device, state->gaussian) ==
                gpu::GpuKernelStatus::ok &&
            gpu::GpuDigitalHalation::create(state->device, state->halation) ==
                gpu::GpuKernelStatus::ok;
        state->grain_ready =
            gpu::GpuDigitalFilmGrain::create(state->device, state->grain) ==
            gpu::GpuKernelStatus::ok;
        state->preset_ready =
            gpu::GpuDigitalFilmColorPreset::create(state->device, state->preset) ==
            gpu::GpuKernelStatus::ok;
        state->cube_ready =
            gpu::GpuFilmEmulationCube::create(state->device, state->cube) ==
            gpu::GpuKernelStatus::ok;
        state->acutance_ready =
            gpu::GpuFilmEmulationAcutance::create(state->device, state->acutance) ==
            gpu::GpuKernelStatus::ok;
        state->film_look_ready =
            gpu::GpuFilmLookStage::create(state->device, state->film_look) ==
            gpu::GpuKernelStatus::ok;
        state->vibrance_ready =
            gpu::GpuVibranceTable::create(state->device, state->vibrance_table) ==
                gpu::GpuKernelStatus::ok &&
            gpu::GpuMutedSceneVibrance::create(state->device, state->muted_vibrance) ==
                gpu::GpuKernelStatus::ok &&
            gpu::GpuColorModel::create(state->device, state->color_model) ==
                gpu::GpuKernelStatus::ok;
        state->target_grade_ready =
            gpu::GpuScannerTargetGrade::create(state->device, state->target_grade) ==
            gpu::GpuKernelStatus::ok;
        state->noritsu_texture_ready =
            gpu::GpuNoritsuTexture::create(state->device, state->noritsu_texture) ==
            gpu::GpuKernelStatus::ok;
        state->texture_grain_ready =
            gpu::GpuTextureGrain::create(state->device, state->texture_grain) ==
            gpu::GpuKernelStatus::ok;
        state->clipping_overlay_ready =
            gpu::GpuChannelClippingOverlay::create(
                state->device, state->clipping_overlay) ==
            gpu::GpuKernelStatus::ok;
        state->area_average_ready =
            gpu::GpuAreaAverage::create(state->device, state->area_average) ==
            gpu::GpuKernelStatus::ok;
        state->scene_correction_ready =
            gpu::GpuSceneCorrection::create(state->device, state->scene_correction) ==
            gpu::GpuKernelStatus::ok;
        state->mip_halve_ready =
            gpu::GpuMipHalve::create(state->device, state->mip_halve) ==
            gpu::GpuKernelStatus::ok;
        state->scratch_angle_ready =
            gpu::GpuScratchAngle::create(state->device, state->scratch_angle) ==
            gpu::GpuKernelStatus::ok;
        state->finite_ready =
            gpu::GpuFiniteCheck::create(state->device, state->finite) ==
            gpu::GpuKernelStatus::ok;
        state->preview_encode_ready =
            gpu::GpuPreviewDisplayEncode::create(
                state->device, state->preview_encode) ==
            gpu::GpuKernelStatus::ok;
    }
    state_ = state;
}

GpuAccelerator::~GpuAccelerator() {
    delete state_;
    state_ = nullptr;
}

GpuAccelerator& GpuAccelerator::shared() noexcept {
    // 함수 지역 정적이라 첫 사용 때 한 번만 만들어지고, 초기화가 스레드 안전합니다.
    static GpuAccelerator accelerator{};
    return accelerator;
}

bool GpuAccelerator::available() const noexcept {
    return state_ != nullptr && state_->usable;
}

const gpu::GpuDevice& GpuAccelerator::device() const noexcept {
    return state_->device;
}

const char* GpuAccelerator::adapter_description() const noexcept {
    return state_ != nullptr ? state_->adapter : "";
}

GpuToneOutcome GpuAccelerator::apply_working_tone_adjustments(
    const GpuUsePolicy policy,
    imaging::WorkingImage& image,
    const imaging::WorkingToneAdjustParameters& parameters,
    const imaging::ToneCurveMeasurementLimits& measurement_limits) noexcept {
    GpuToneOutcome outcome{};
    if (policy != GpuUsePolicy::allowed || !available()) {
        return outcome;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    gpu::GpuToneStageResult result{};
    if (state_->resident_matches(image.pixels.data(), image.width, image.height) &&
        state_->pool.images()[0].is_valid() && state_->pool.images()[1].is_valid()) {
        gpu::GpuWorkingImage* const pool = state_->pool.images();
        const int read = state_->resident.read_slot;
        const int write = 1 - read;
        result = state_->tone.apply_on(
            state_->device,
            pool[read],
            pool[write],
            image,
            parameters,
            measurement_limits,
            false);
        if (result.handled) {
            int applied = 0;
            if (result.info.exposure_applied) {
                ++applied;
            }
            if (result.info.basic_tone_applied) {
                ++applied;
            }
            if (result.info.parametric_curve_applied) {
                ++applied;
            }
            if (result.info.point_curve_applied) {
                ++applied;
            }
            if (result.info.color_mixer_applied) {
                ++applied;
            }
            if (result.info.color_grading_applied) {
                ++applied;
            }
            if (result.info.primary_calibration_applied) {
                ++applied;
            }
            const int slot = (applied % 2 == 0) ? read : write;
            state_->bind_resident(
                image.pixels.data(), image.width, image.height, image.stride_pixels, slot);
        }
    } else {
        result = state_->tone.apply(state_->device, image, parameters, measurement_limits);
    }
    if (!result.handled || result.status != imaging::WorkingToneAdjustStatus::ok) {
        return outcome;
    }
    outcome.handled = true;
    outcome.info = result.info;
    return outcome;
}

GpuDenoiseOutcome GpuAccelerator::apply_film_scan_denoise(
    const GpuUsePolicy policy,
    imaging::WorkingImage& image,
    const imaging::FilmScanDenoiseParameters& parameters) noexcept {
    GpuDenoiseOutcome outcome{};
    if (policy != GpuUsePolicy::allowed || !available()) {
        return outcome;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    const gpu::GpuFilmScanDenoiseResult result =
        state_->denoise.apply(state_->device, image, parameters);
    if (!result.handled || result.status != imaging::FilmScanDenoiseStatus::ok) {
        return outcome;
    }
    outcome.handled = true;
    outcome.info = result.info;
    return outcome;
}

bool GpuAccelerator::apply_morphology_plane(
    const float* const source,
    float* const destination,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius,
    const imaging::MorphologyKind kind) noexcept {
    if (!available() || source == nullptr || destination == nullptr) {
        return false;
    }
    if (width == 0U || height == 0U) {
        return false;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    if (!state_->morphology_ready) {
        return false;
    }
    const bool bipolar = kind == imaging::MorphologyKind::bipolar_top_hat;
    if (!state_->pool.ensure(state_->device, width, height, bipolar ? 6 : 3)) {
        return false;
    }

    gpu::GpuWorkingImage* const pool = state_->pool.images();
    if (pool[0].upload_planes_into(state_->device, source, nullptr, nullptr, width) !=
        gpu::GpuImageStatus::ok) {
        return false;
    }

    gpu::GpuKernelStatus status = gpu::GpuKernelStatus::invalid_arguments;
    gpu::GpuWorkingImage* const scratch =
        bipolar ? &pool[gpu::GpuImagePool::scratch_first] : &pool[1];
    switch (kind) {
        case imaging::MorphologyKind::opening:
            status = state_->morphology.opening(state_->device, pool[0], scratch, pool[0], radius);
            break;
        case imaging::MorphologyKind::closing:
            status = state_->morphology.closing(state_->device, pool[0], scratch, pool[0], radius);
            break;
        case imaging::MorphologyKind::bipolar_top_hat:
            status = state_->morphology.bipolar_top_hat(
                state_->device, pool[0], scratch, pool[1], radius);
            break;
    }
    if (status != gpu::GpuKernelStatus::ok) {
        return false;
    }
    gpu::GpuWorkingImage& output = bipolar ? pool[1] : pool[0];
    return output.download_planes(
               state_->device, destination, nullptr, nullptr, width) ==
        gpu::GpuImageStatus::ok;
}

bool GpuAccelerator::apply_morphology_rgb(
    const float* const red,
    const float* const green,
    const float* const blue,
    float* const out_red,
    float* const out_green,
    float* const out_blue,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius,
    const imaging::MorphologyKind kind) noexcept {
    if (!available() || red == nullptr || green == nullptr || blue == nullptr ||
        out_red == nullptr || out_green == nullptr || out_blue == nullptr) {
        return false;
    }
    if (width == 0U || height == 0U) {
        return false;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    if (!state_->morphology_ready) {
        return false;
    }
    const bool bipolar = kind == imaging::MorphologyKind::bipolar_top_hat;
    if (!state_->pool.ensure(state_->device, width, height, bipolar ? 6 : 3)) {
        return false;
    }

    gpu::GpuWorkingImage* const pool = state_->pool.images();
    if (pool[0].upload_planes_into(state_->device, red, green, blue, width) !=
        gpu::GpuImageStatus::ok) {
        return false;
    }
    gpu::GpuWorkingImage* const scratch =
        bipolar ? &pool[gpu::GpuImagePool::scratch_first] : &pool[1];
    gpu::GpuKernelStatus status = gpu::GpuKernelStatus::invalid_arguments;
    switch (kind) {
        case imaging::MorphologyKind::opening:
            status = state_->morphology.opening(state_->device, pool[0], scratch, pool[0], radius);
            break;
        case imaging::MorphologyKind::closing:
            status = state_->morphology.closing(state_->device, pool[0], scratch, pool[0], radius);
            break;
        case imaging::MorphologyKind::bipolar_top_hat:
            status = state_->morphology.bipolar_top_hat(
                state_->device, pool[0], scratch, pool[1], radius);
            break;
    }
    if (status != gpu::GpuKernelStatus::ok) {
        return false;
    }
    gpu::GpuWorkingImage& output = bipolar ? pool[1] : pool[0];
    return output.download_planes(
               state_->device, out_red, out_green, out_blue, width) ==
        gpu::GpuImageStatus::ok;
}

bool GpuAccelerator::apply_morphology_close_open_rgb(
    const float* const red,
    const float* const green,
    const float* const blue,
    float* const out_red,
    float* const out_green,
    float* const out_blue,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) noexcept {
    if (!available() || red == nullptr || green == nullptr || blue == nullptr ||
        out_red == nullptr || out_green == nullptr || out_blue == nullptr) {
        return false;
    }
    if (width == 0U || height == 0U || radius == 0U) {
        return false;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    if (!state_->morphology_ready || !state_->pool.ensure(state_->device, width, height, 3)) {
        return false;
    }

    gpu::GpuWorkingImage* const pool = state_->pool.images();
    if (pool[0].upload_planes_into(state_->device, red, green, blue, width) !=
        gpu::GpuImageStatus::ok) {
        return false;
    }
    gpu::GpuWorkingImage* const scratch = &pool[1];
    if (state_->morphology.closing(
            state_->device, pool[0], scratch, pool[0], radius) !=
        gpu::GpuKernelStatus::ok) {
        return false;
    }
    if (state_->morphology.opening(
            state_->device, pool[0], scratch, pool[0], radius) !=
        gpu::GpuKernelStatus::ok) {
        return false;
    }
    return pool[0].download_planes(
               state_->device, out_red, out_green, out_blue, width) ==
        gpu::GpuImageStatus::ok;
}

bool GpuAccelerator::apply_morphology_bipolar_top_hat_rgb(
    const float* const red,
    const float* const green,
    const float* const blue,
    float* const out_red,
    float* const out_green,
    float* const out_blue,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) noexcept {
    return apply_morphology_rgb(
        red,
        green,
        blue,
        out_red,
        out_green,
        out_blue,
        width,
        height,
        radius,
        imaging::MorphologyKind::bipolar_top_hat);
}

bool GpuAccelerator::apply_negative_inversion(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const float* const dmin,
    const float* const dmax_normalized,
    const float* const response) noexcept {
    if (!available() || pixels == nullptr || dmin == nullptr || dmax_normalized == nullptr ||
        response == nullptr) {
        return false;
    }
    if (width == 0U || height == 0U || stride_pixels < width) {
        return false;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    if (!state_->invert_ready) {
        return false;
    }

    if (!state_->pool.ensure(state_->device, width, height)) {
        return false;
    }
    gpu::GpuWorkingImage* const pool = state_->pool.images();
    auto* const rgba = reinterpret_cast<core::Rgba32F*>(pixels);
    int read_slot = 0;
    int write_slot = 1;
    if (state_->resident_matches(pixels, width, height) && !state_->resident.host_stale) {
        read_slot = state_->resident.read_slot;
        write_slot = 1 - read_slot;
    } else if (
        pool[0].upload_into(state_->device, rgba, stride_pixels) != gpu::GpuImageStatus::ok) {
        return false;
    }

    gpu::GpuNegativeInvertParameters parameters{};
    for (int channel = 0; channel < 3; ++channel) {
        parameters.dmin[channel] = dmin[channel];
        parameters.dmax_normalized[channel] = dmax_normalized[channel];
    }
    parameters.response_y_ceiling = response[0];
    parameters.response_amplitude = response[1];
    parameters.response_rate = response[2];
    parameters.response_shape = response[3];

    if (state_->invert.dispatch(
            state_->device, pool[read_slot], pool[write_slot], parameters) !=
        gpu::GpuKernelStatus::ok) {
        return false;
    }
    if (state_->resident.scope_depth > 0) {
        state_->bind_resident(pixels, width, height, stride_pixels, write_slot);
        return true;
    }
    return pool[write_slot].download(state_->device, rgba, stride_pixels) ==
        gpu::GpuImageStatus::ok;
}

}  // namespace negaflow::pipeline
