#include "negaflow/pipeline/gpu_accelerator.h"

// 디지털 원본 전용 필름 룩의 재료 다섯입니다 — 헐레이션 · 색 큐브 · 아큐턴스 ·
// 색 프리셋 · 그레인. **필름 스캔 경로는 이 사슬을 지나지 않습니다**
// (`imaging/working_film_look.cpp`) — 스캔본에는 이미 유제를 통과한 신호가 들어 있어
// 같은 물리를 두 번 얹지 않기 때문입니다.
//
// ☠️ 다섯 다 **근사**입니다. 호출부가 `ApproximateAcceleratorScope` 안에서만 부릅니다.
//
// ⚠️ 지금은 재료마다 올렸다 내립니다. 사슬 전체를 GPU 에 머무르게 하는 오케스트레이터가
//    다음 단계이고, 그러면 왕복이 다섯에서 하나로 줍니다.

#include "gpu_accelerator_state.h"

#include <cstddef>
#include <mutex>

namespace negaflow::pipeline {

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

bool GpuAccelerator::apply_digital_film_color_preset(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const imaging::DigitalFilmColorPreset* const preset,
    const float strength) noexcept {
    if (!available() || pixels == nullptr || preset == nullptr) {
        return false;
    }
    if (width == 0U || height == 0U || stride_pixels < width) {
        return false;
    }
    const std::lock_guard<std::mutex> guard{state_->lock};
    if (!state_->preset_ready) {
        return false;
    }
    auto* const rgba = reinterpret_cast<core::Rgba32F*>(pixels);
    gpu::GpuWorkingImage source{};
    if (gpu::GpuWorkingImage::upload(state_->device, rgba, width, height, stride_pixels, source) !=
        gpu::GpuImageStatus::ok) {
        return false;
    }
    gpu::GpuWorkingImage scratch[gpu::GpuDigitalFilmColorPreset::scratch_count]{};
    for (int index = 0; index < gpu::GpuDigitalFilmColorPreset::scratch_count; ++index) {
        if (gpu::GpuWorkingImage::create(state_->device, width, height, scratch[index]) !=
            gpu::GpuImageStatus::ok) {
            return false;
        }
    }
    const gpu::GpuWorkingImage* result = nullptr;
    if (state_->preset.dispatch(
            state_->device, source, scratch, result, *preset, strength) !=
            gpu::GpuKernelStatus::ok ||
        result == nullptr) {
        return false;
    }
    return result->download(state_->device, rgba, stride_pixels) == gpu::GpuImageStatus::ok;
}

bool GpuAccelerator::apply_film_emulation_cube(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const imaging::FilmEmulationColorCube* const cube) noexcept {
    if (!available() || pixels == nullptr || cube == nullptr) {
        return false;
    }
    if (width == 0U || height == 0U || stride_pixels < width) {
        return false;
    }
    const std::lock_guard<std::mutex> guard{state_->lock};
    if (!state_->cube_ready) {
        return false;
    }
    auto* const rgba = reinterpret_cast<core::Rgba32F*>(pixels);
    gpu::GpuWorkingImage source{};
    gpu::GpuWorkingImage destination{};
    if (gpu::GpuWorkingImage::upload(state_->device, rgba, width, height, stride_pixels, source) !=
            gpu::GpuImageStatus::ok ||
        gpu::GpuWorkingImage::create(state_->device, width, height, destination) !=
            gpu::GpuImageStatus::ok) {
        return false;
    }
    if (state_->cube.dispatch(state_->device, source, destination, *cube) !=
        gpu::GpuKernelStatus::ok) {
        return false;
    }
    return destination.download(state_->device, rgba, stride_pixels) == gpu::GpuImageStatus::ok;
}

bool GpuAccelerator::apply_film_emulation_acutance(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const imaging::FilmEmulationAcutanceSetup* const setup) noexcept {
    if (!available() || pixels == nullptr || setup == nullptr || !setup->applied) {
        return false;
    }
    if (width == 0U || height == 0U || stride_pixels < width) {
        return false;
    }
    const std::lock_guard<std::mutex> guard{state_->lock};
    if (!state_->acutance_ready) {
        return false;
    }
    auto* const rgba = reinterpret_cast<core::Rgba32F*>(pixels);
    gpu::GpuWorkingImage source{};
    gpu::GpuWorkingImage scratch[gpu::GpuFilmEmulationAcutance::scratch_count]{};
    gpu::GpuWorkingImage destination{};
    if (gpu::GpuWorkingImage::upload(state_->device, rgba, width, height, stride_pixels, source) !=
            gpu::GpuImageStatus::ok ||
        gpu::GpuWorkingImage::create(state_->device, width, height, scratch[0]) !=
            gpu::GpuImageStatus::ok ||
        gpu::GpuWorkingImage::create(state_->device, width, height, destination) !=
            gpu::GpuImageStatus::ok) {
        return false;
    }
    if (state_->acutance.dispatch(state_->device, source, scratch, destination, *setup) !=
        gpu::GpuKernelStatus::ok) {
        return false;
    }
    return destination.download(state_->device, rgba, stride_pixels) == gpu::GpuImageStatus::ok;
}

bool GpuAccelerator::apply_digital_film_look(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const imaging::DigitalFilmLookPlan* const plan,
    imaging::DigitalFilmLookApplied* const applied) noexcept {
    if (!available() || pixels == nullptr || plan == nullptr || applied == nullptr) {
        return false;
    }
    if (width == 0U || height == 0U || stride_pixels < width) {
        return false;
    }
    const std::lock_guard<std::mutex> guard{state_->lock};
    if (!state_->film_look_ready) {
        return false;
    }
    const gpu::GpuFilmLookResult result = state_->film_look.apply(
        state_->device, pixels, width, height, stride_pixels, *plan);
    if (!result.handled) {
        return false;
    }
    *applied = result.applied;
    return true;
}

}  // namespace negaflow::pipeline
