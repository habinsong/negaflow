#include "negaflow/pipeline/gpu_accelerator.h"

#include <mutex>
#include <new>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_film_scan_stage.h"
#include "negaflow/gpu/gpu_tone_stage.h"

namespace negaflow::pipeline {

struct GpuAccelerator::State final {
    // ☠️ D3D11 즉시 컨텍스트는 스레드 안전하지 않습니다. 모든 GPU 호출이 이 자물쇠
    //    안에서 돕니다 — 빼면 두 현상이 겹칠 때 조용히 깨집니다.
    std::mutex lock{};
    gpu::GpuDevice device{};
    gpu::GpuToneStage tone{};
    gpu::GpuFilmScanDenoiseStage denoise{};
    bool usable{false};
    // `GpuAdapterInfo::description` 은 고정 배열이라 수명이 장치와 같습니다.
    const char* adapter{""};
};

GpuAccelerator::GpuAccelerator() noexcept {
    auto* const state = new (std::nothrow) State{};
    if (state == nullptr) {
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

}  // namespace negaflow::pipeline
