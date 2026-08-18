#include "negaflow/pipeline/gpu_accelerator.h"

#include <mutex>
#include <cstdlib>
#include <vector>
#include <new>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_digital_film_grain.h"
#include "negaflow/gpu/gpu_digital_halation.h"
#include "negaflow/gpu/gpu_film_scan_stage.h"
#include "negaflow/gpu/gpu_morphology.h"
#include "negaflow/gpu/gpu_negative_invert.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/gpu_tone_stage.h"

namespace negaflow::pipeline {

struct GpuAccelerator::State final {
    // ☠️ D3D11 즉시 컨텍스트는 스레드 안전하지 않습니다. 모든 GPU 호출이 이 자물쇠
    //    안에서 돕니다 — 빼면 두 현상이 겹칠 때 조용히 깨집니다.
    std::mutex lock{};
    gpu::GpuDevice device{};
    gpu::GpuToneStage tone{};
    gpu::GpuFilmScanDenoiseStage denoise{};
    gpu::GpuMorphology morphology{};
    bool morphology_ready{false};
    gpu::GpuNegativeInvert invert{};
    bool invert_ready{false};
    // 디지털 필름 룩의 재료 커널 둘입니다. 둘 다 이 사슬에서만 불리므로 따로 만들고,
    // 이것만 실패해도 톤·디노이즈·반전은 그대로 돕니다.
    gpu::GpuGaussianBlur gaussian{};
    gpu::GpuDigitalHalation halation{};
    bool halation_ready{false};
    gpu::GpuDigitalFilmGrain grain{};
    bool grain_ready{false};
    // 평면 ↔ RGBA 변환용. 매 호출 할당하지 않으려고 들고 있습니다.
    std::vector<core::Rgba32F> morphology_staging{};
    bool usable{false};
    // `GpuAdapterInfo::description` 은 고정 배열이라 수명이 장치와 같습니다.
    const char* adapter{""};
};

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

    auto* const rgba = reinterpret_cast<core::Rgba32F*>(pixels);
    gpu::GpuWorkingImage input{};
    if (gpu::GpuWorkingImage::upload(
            state_->device, rgba, width, height, stride_pixels, input) !=
        gpu::GpuImageStatus::ok) {
        return false;
    }
    gpu::GpuWorkingImage output{};
    if (gpu::GpuWorkingImage::create(state_->device, width, height, output) !=
        gpu::GpuImageStatus::ok) {
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

bool GpuAccelerator::apply_digital_halation(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const double* const scatter_strength,
    const double* const halation_strength,
    const double radius_ratio,
    const double strength) noexcept {
    if (!available() || pixels == nullptr || scatter_strength == nullptr ||
        halation_strength == nullptr) {
        return false;
    }
    if (width == 0U || height == 0U || stride_pixels < width) {
        return false;
    }
    imaging::DigitalHalationMaterial material{};
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        material.scatter_strength[channel] = scatter_strength[channel];
        material.halation_strength[channel] = halation_strength[channel];
    }
    material.radius_ratio = radius_ratio;
    const gpu::GpuDigitalHalation::Parameters parameters =
        gpu::GpuDigitalHalation::resolve(material, strength, width, height);
    if (!parameters.applied) {
        // CPU 도 같은 자리에서 원본 그대로 돌려줍니다. 여기서 `false` 를 내면 CPU 가
        // 같은 판정을 한 번 더 하고 역시 원본을 냅니다 — 값은 같고 일만 두 번입니다.
        return true;
    }

    const std::lock_guard<std::mutex> guard{state_->lock};
    if (!state_->halation_ready) {
        return false;
    }
    auto* const rgba = reinterpret_cast<core::Rgba32F*>(pixels);
    gpu::GpuWorkingImage source{};
    if (gpu::GpuWorkingImage::upload(state_->device, rgba, width, height, stride_pixels, source) !=
        gpu::GpuImageStatus::ok) {
        return false;
    }
    gpu::GpuWorkingImage scratch[gpu::GpuDigitalHalation::scratch_count]{};
    for (int index = 0; index < gpu::GpuDigitalHalation::scratch_count; ++index) {
        if (gpu::GpuWorkingImage::create(state_->device, width, height, scratch[index]) !=
            gpu::GpuImageStatus::ok) {
            return false;
        }
    }
    gpu::GpuWorkingImage destination{};
    if (gpu::GpuWorkingImage::create(state_->device, width, height, destination) !=
        gpu::GpuImageStatus::ok) {
        return false;
    }
    if (state_->halation.dispatch(
            state_->device, state_->gaussian, source, scratch, destination, parameters) !=
        gpu::GpuKernelStatus::ok) {
        return false;
    }
    return destination.download(state_->device, rgba, stride_pixels) == gpu::GpuImageStatus::ok;
}

bool GpuAccelerator::apply_digital_film_grain(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const float amplitude,
    const float chroma_ratio,
    const float size) noexcept {
    if (!available() || pixels == nullptr) {
        return false;
    }
    if (width == 0U || height == 0U || stride_pixels < width) {
        return false;
    }
    const std::lock_guard<std::mutex> guard{state_->lock};
    if (!state_->grain_ready) {
        return false;
    }
    // 호출부(`digital_film_grain.cpp`)가 이미 조기 반환을 지나왔으므로 여기서는 적용이
    // 확정입니다. `resolve` 를 다시 부르면 세기가 두 번 곱해집니다 — 호출부가 준
    // `amplitude` 는 **이미 세기가 곱해진** 값입니다.
    gpu::GpuDigitalFilmGrain::Parameters parameters{};
    parameters.amplitude = amplitude;
    parameters.chroma_ratio = chroma_ratio;
    parameters.size = size;
    parameters.applied = true;

    auto* const rgba = reinterpret_cast<core::Rgba32F*>(pixels);
    gpu::GpuWorkingImage source{};
    gpu::GpuWorkingImage destination{};
    if (gpu::GpuWorkingImage::upload(state_->device, rgba, width, height, stride_pixels, source) !=
            gpu::GpuImageStatus::ok ||
        gpu::GpuWorkingImage::create(state_->device, width, height, destination) !=
            gpu::GpuImageStatus::ok) {
        return false;
    }
    if (state_->grain.dispatch(state_->device, source, destination, parameters) !=
        gpu::GpuKernelStatus::ok) {
        return false;
    }
    return destination.download(state_->device, rgba, stride_pixels) == gpu::GpuImageStatus::ok;
}

}  // namespace negaflow::pipeline
