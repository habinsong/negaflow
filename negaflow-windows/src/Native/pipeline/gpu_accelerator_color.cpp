#include "negaflow/pipeline/gpu_accelerator.h"

// 실측 `CIVibrance` 표를 쓰는 진입점 둘입니다 — 흐린 장면 vibrance 와 컬러 모델.
//
// 왜 따로 뗐나 — 클래스 본체(`gpu_accelerator.cpp`)와 디지털 필름 룩
// (`gpu_accelerator_film_look.cpp`)이 이미 각자 자리를 채웠고, 500줄 규칙이 있습니다.
// 이 둘은 **같은 표를 나눠 쓰는** 한 묶음이라 같은 자리에 둡니다.
//
// ☠️ 둘 다 **근사**입니다. 호출부가 `ApproximateAcceleratorScope` 안에서만 부릅니다.

#include "gpu_accelerator_state.h"

#include <mutex>

namespace negaflow::pipeline {

bool GpuAccelerator::apply_muted_scene_vibrance(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const float amount) noexcept {
    if (!available() || pixels == nullptr) {
        return false;
    }
    if (width == 0U || height == 0U || stride_pixels < width) {
        return false;
    }
    const std::lock_guard<std::mutex> guard{state_->lock};
    if (!state_->vibrance_ready) {
        return false;
    }
    if (!state_->pool.ensure(state_->device, width, height)) {
        return false;
    }
    gpu::GpuWorkingImage* const pool = state_->pool.images();
    auto* const rgba = reinterpret_cast<core::Rgba32F*>(pixels);
    if (pool[0].upload_into(state_->device, rgba, stride_pixels) != gpu::GpuImageStatus::ok) {
        return false;
    }
    if (state_->muted_vibrance.dispatch(
            state_->device, state_->vibrance_table, pool[0], pool[1], amount) !=
        gpu::GpuKernelStatus::ok) {
        return false;
    }
    return pool[1].download(state_->device, rgba, stride_pixels) == gpu::GpuImageStatus::ok;
}

bool GpuAccelerator::apply_color_model(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const imaging::ColorModelParameters* const parameters) noexcept {
    if (!available() || pixels == nullptr || parameters == nullptr) {
        return false;
    }
    if (width == 0U || height == 0U || stride_pixels < width) {
        return false;
    }
    const std::lock_guard<std::mutex> guard{state_->lock};
    if (!state_->vibrance_ready) {
        return false;
    }
    if (!state_->pool.ensure(state_->device, width, height)) {
        return false;
    }
    gpu::GpuWorkingImage* const pool = state_->pool.images();
    auto* const rgba = reinterpret_cast<core::Rgba32F*>(pixels);
    if (pool[0].upload_into(state_->device, rgba, stride_pixels) != gpu::GpuImageStatus::ok) {
        return false;
    }
    if (state_->color_model.dispatch(
            state_->device, state_->vibrance_table, pool[0], pool[1], *parameters) !=
        gpu::GpuKernelStatus::ok) {
        return false;
    }
    return pool[1].download(state_->device, rgba, stride_pixels) == gpu::GpuImageStatus::ok;
}

bool GpuAccelerator::apply_scanner_target_grade(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const imaging::ScannerTargetGradeSetup* const setup) noexcept {
    if (!available() || pixels == nullptr || setup == nullptr) {
        return false;
    }
    if (width == 0U || height == 0U || stride_pixels < width) {
        return false;
    }
    const std::lock_guard<std::mutex> guard{state_->lock};
    if (!state_->target_grade_ready) {
        return false;
    }
    if (!state_->pool.ensure(state_->device, width, height)) {
        return false;
    }
    gpu::GpuWorkingImage* const pool = state_->pool.images();
    auto* const rgba = reinterpret_cast<core::Rgba32F*>(pixels);
    if (pool[0].upload_into(state_->device, rgba, stride_pixels) != gpu::GpuImageStatus::ok) {
        return false;
    }
    if (state_->target_grade.dispatch(state_->device, pool[0], pool[1], *setup) !=
        gpu::GpuKernelStatus::ok) {
        return false;
    }
    return pool[1].download(state_->device, rgba, stride_pixels) == gpu::GpuImageStatus::ok;
}

}  // namespace negaflow::pipeline
