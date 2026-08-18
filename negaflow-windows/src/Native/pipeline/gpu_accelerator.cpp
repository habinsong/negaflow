#include "negaflow/pipeline/gpu_accelerator.h"

#include "gpu_accelerator_state.h"

#include <cstdlib>
#include <mutex>
#include <new>
#include <vector>

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
    const std::lock_guard<std::mutex> guard{state_->lock};
    const gpu::GpuToneStageResult result =
        state_->tone.apply(state_->device, image, parameters, measurement_limits);
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
    const std::lock_guard<std::mutex> guard{state_->lock};
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
    const std::lock_guard<std::mutex> guard{state_->lock};
    if (!state_->morphology_ready) {
        return false;
    }

    // 검출은 단일 채널 평면을 다루고 GPU 텍스처는 RGBA 입니다. 빨강 채널에 담습니다 —
    // 형태학은 채널마다 독립이라 나머지 셋은 무엇이 들어가도 결과가 안 바뀝니다.
    const std::size_t count = static_cast<std::size_t>(width) * height;
    std::vector<core::Rgba32F>& staging = state_->morphology_staging;
    staging.resize(count);
    for (std::size_t index = 0U; index < count; ++index) {
        staging[index] = {source[index], source[index], source[index], source[index]};
    }

    gpu::GpuWorkingImage input{};
    if (gpu::GpuWorkingImage::upload(
            state_->device, staging.data(), width, height, width, input) !=
        gpu::GpuImageStatus::ok) {
        return false;
    }

    gpu::GpuWorkingImage scratch[gpu::GpuMorphology::top_hat_scratch_count]{};
    const int needed = kind == imaging::MorphologyKind::bipolar_top_hat
        ? gpu::GpuMorphology::top_hat_scratch_count
        : gpu::GpuMorphology::filter_scratch_count;
    for (int index = 0; index < needed; ++index) {
        if (gpu::GpuWorkingImage::create(state_->device, width, height, scratch[index]) !=
            gpu::GpuImageStatus::ok) {
            return false;
        }
    }
    gpu::GpuWorkingImage output{};
    if (gpu::GpuWorkingImage::create(state_->device, width, height, output) !=
        gpu::GpuImageStatus::ok) {
        return false;
    }

    gpu::GpuKernelStatus status = gpu::GpuKernelStatus::invalid_arguments;
    switch (kind) {
        case imaging::MorphologyKind::opening:
            status = state_->morphology.opening(state_->device, input, scratch, output, radius);
            break;
        case imaging::MorphologyKind::closing:
            status = state_->morphology.closing(state_->device, input, scratch, output, radius);
            break;
        case imaging::MorphologyKind::bipolar_top_hat:
            status =
                state_->morphology.bipolar_top_hat(state_->device, input, scratch, output, radius);
            break;
    }
    if (status != gpu::GpuKernelStatus::ok) {
        return false;
    }
    if (output.download(state_->device, staging.data(), width) != gpu::GpuImageStatus::ok) {
        return false;
    }
    for (std::size_t index = 0U; index < count; ++index) {
        destination[index] = staging[index].red;
    }
    return true;
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
    const std::lock_guard<std::mutex> guard{state_->lock};
    if (!state_->invert_ready) {
        return false;
    }

    if (!state_->pool.ensure(state_->device, width, height)) {
        return false;
    }
    gpu::GpuWorkingImage* const pool = state_->pool.images();
    auto* const rgba = reinterpret_cast<core::Rgba32F*>(pixels);
    gpu::GpuWorkingImage& input = pool[0];
    gpu::GpuWorkingImage& output = pool[1];
    if (input.upload_into(state_->device, rgba, stride_pixels) != gpu::GpuImageStatus::ok) {
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

    if (state_->invert.dispatch(state_->device, input, output, parameters) !=
        gpu::GpuKernelStatus::ok) {
        return false;
    }
    return output.download(state_->device, rgba, stride_pixels) == gpu::GpuImageStatus::ok;
}

}  // namespace negaflow::pipeline
