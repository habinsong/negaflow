#include "negaflow/pipeline/gpu_accelerator.h"

#include <mutex>
#include <vector>
#include <new>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_film_scan_stage.h"
#include "negaflow/gpu/gpu_morphology.h"
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
    // 평면 ↔ RGBA 변환용. 매 호출 할당하지 않으려고 들고 있습니다.
    std::vector<core::Rgba32F> morphology_staging{};
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
        // 형태학은 따로 만듭니다. 이것만 실패해도 톤·디노이즈는 그대로 돕니다.
        state->morphology_ready =
            gpu::GpuMorphology::create(state->device, state->morphology) ==
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

namespace {

// `imaging` 안쪽 커널을 GPU 로 보내는 표입니다. `imaging` 은 `gpu` 를 링크할 수 없으므로
// (링크하면 순환) 함수 표만 알고, 둘 다 링크하는 이 층이 채웁니다.
//
// ☠️ **형태학만 넣습니다.** 창 안에서 하나를 고르는 일이라 부동소수 산술이 없고, 창과
//    가장자리 처리가 같으면 고른 값도 같습니다 — 시험이 전 반경에서 **비트 단위 일치**로
//    고정해 두었습니다. 그래서 내보내기·골든 경로에서도 켭니다.
//    곱셈·덧셈이 들어가는 커널은 여기 넣지 마십시오. `KernelAccelerator` 헤더의
//    "근사한 것" 칸과 `ApproximateAcceleratorScope` 를 쓰십시오.

[[nodiscard]] bool run_morphology(
    const float* const source,
    float* const destination,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius,
    const imaging::MorphologyKind kind) noexcept {
    GpuAccelerator& accelerator = GpuAccelerator::shared();
    if (!accelerator.available()) {
        return false;
    }
    return accelerator.apply_morphology_plane(source, destination, width, height, radius, kind);
}

bool accelerate_opening(
    const float* const source,
    float* const destination,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) noexcept {
    return run_morphology(
        source, destination, width, height, radius, imaging::MorphologyKind::opening);
}

bool accelerate_closing(
    const float* const source,
    float* const destination,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) noexcept {
    return run_morphology(
        source, destination, width, height, radius, imaging::MorphologyKind::closing);
}

bool accelerate_bipolar_top_hat(
    const float* const source,
    float* const destination,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) noexcept {
    return run_morphology(
        source, destination, width, height, radius, imaging::MorphologyKind::bipolar_top_hat);
}

// 프로세스 수명 동안 살아 있어야 합니다 — `install_kernel_accelerator` 는 포인터만 갖습니다.
const imaging::KernelAccelerator morphology_table{
    accelerate_opening,
    accelerate_closing,
    accelerate_bipolar_top_hat,
    nullptr,
};

}  // namespace

void install_gpu_kernel_accelerator() noexcept {
    // 여러 번 불려도 한 번만 겁니다. 검출이 돌 때마다 부르는 자리라 필요합니다.
    static std::once_flag once{};
    std::call_once(once, []() noexcept {
        // 장치가 없으면 표를 걸지 않습니다 — 매 호출 실패보다 아예 안 묻는 편이 쌉니다.
        if (!GpuAccelerator::shared().available()) {
            return;
        }
        imaging::install_kernel_accelerator(&morphology_table);
    });
}

}  // namespace negaflow::pipeline
