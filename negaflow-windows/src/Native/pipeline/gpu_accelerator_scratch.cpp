#include "negaflow/pipeline/gpu_accelerator.h"

#include "gpu_accelerator_state.h"

#include <mutex>
#include <vector>

namespace negaflow::pipeline {
namespace {

void pack_source(
    std::vector<core::Rgba32F>& staging,
    const float* const bright,
    const std::uint8_t* const valid,
    const std::size_t count) {
    staging.resize(count);
    for (std::size_t index = 0U; index < count; ++index) {
        const float mask = valid[index] == 0U ? 0.0F : 1.0F;
        staging[index] = {bright[index], mask, 0.0F, 0.0F};
    }
}

bool run_one_angle(
    const gpu::GpuDevice& device,
    gpu::GpuScratchAngle& kernel,
    gpu::GpuWorkingImage* const pool,
    const imaging::ScratchAngleTaps& taps,
    const float balance_limit) noexcept {
    if (kernel.dispatch_ridge(device, pool[0], pool[1], taps, balance_limit) !=
        gpu::GpuKernelStatus::ok) {
        return false;
    }
    if (kernel.dispatch_integrate(
            device, pool[1], pool[2], taps.along, taps.along_count, false) !=
        gpu::GpuKernelStatus::ok) {
        return false;
    }
    if (taps.curve_count > 0) {
        if (kernel.dispatch_integrate(
                device, pool[1], pool[2], taps.curve, taps.curve_count, true) !=
            gpu::GpuKernelStatus::ok) {
            return false;
        }
    }
    return true;
}

}  // namespace

bool GpuAccelerator::apply_scratch_angle_maps(
    const float* const bright,
    const std::uint8_t* const valid,
    float* const ridge,
    float* const integrated,
    const std::uint32_t width,
    const std::uint32_t height,
    const imaging::ScratchAngleTaps* const taps,
    const float balance_limit) noexcept {
    if (!available() || bright == nullptr || valid == nullptr || ridge == nullptr ||
        integrated == nullptr || taps == nullptr) {
        return false;
    }
    if (width == 0U || height == 0U) {
        return false;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    if (!state_->scratch_angle_ready) {
        return false;
    }
    if (!state_->pool.ensure(state_->device, width, height)) {
        return false;
    }
    const std::size_t count = static_cast<std::size_t>(width) * height;
    pack_source(state_->morphology_staging, bright, valid, count);
    gpu::GpuWorkingImage* const pool = state_->pool.images();
    if (pool[0].upload_into(state_->device, state_->morphology_staging.data(), width) !=
        gpu::GpuImageStatus::ok) {
        return false;
    }
    if (!run_one_angle(
            state_->device, state_->scratch_angle, pool, *taps, balance_limit)) {
        return false;
    }
    if (pool[1].download(state_->device, state_->morphology_staging.data(), width) !=
        gpu::GpuImageStatus::ok) {
        return false;
    }
    for (std::size_t index = 0U; index < count; ++index) {
        ridge[index] = state_->morphology_staging[index].red;
    }
    if (pool[2].download(state_->device, state_->morphology_staging.data(), width) !=
        gpu::GpuImageStatus::ok) {
        return false;
    }
    for (std::size_t index = 0U; index < count; ++index) {
        integrated[index] = state_->morphology_staging[index].red;
    }
    return true;
}

bool GpuAccelerator::apply_scratch_angle_stack(
    const float* const bright,
    const std::uint8_t* const valid,
    float* const best_ridge,
    float* const best_integrated,
    const std::uint32_t width,
    const std::uint32_t height,
    const imaging::ScratchAngleTaps* const taps,
    const int angle_count,
    const float balance_limit) noexcept {
    if (!available() || bright == nullptr || valid == nullptr || best_ridge == nullptr ||
        best_integrated == nullptr || taps == nullptr || angle_count <= 0) {
        return false;
    }
    if (width == 0U || height == 0U) {
        return false;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    if (!state_->scratch_angle_ready) {
        return false;
    }
    if (!state_->pool.ensure(state_->device, width, height)) {
        return false;
    }
    const std::size_t count = static_cast<std::size_t>(width) * height;
    pack_source(state_->morphology_staging, bright, valid, count);
    gpu::GpuWorkingImage* const pool = state_->pool.images();
    if (pool[0].upload_into(state_->device, state_->morphology_staging.data(), width) !=
        gpu::GpuImageStatus::ok) {
        return false;
    }
    // 첫 각도는 max(0, x) 가 되도록 best 를 0 으로 둡니다. copy_from 은 내용이
    // 정해지지 않은 텍스처라 쓰지 않고, 같은 크기의 올린 0 화소를 씁니다.
    for (std::size_t index = 0U; index < count; ++index) {
        state_->morphology_staging[index] = {0.0F, 0.0F, 0.0F, 0.0F};
    }
    if (pool[3].upload_into(state_->device, state_->morphology_staging.data(), width) !=
        gpu::GpuImageStatus::ok) {
        return false;
    }
    for (int angle = 0; angle < angle_count; ++angle) {
        if (!run_one_angle(
                state_->device, state_->scratch_angle, pool, taps[angle], balance_limit)) {
            return false;
        }
        if (state_->scratch_angle.dispatch_max(
                state_->device, pool[2], pool[1], pool[3]) != gpu::GpuKernelStatus::ok) {
            return false;
        }
    }
    if (pool[3].download(state_->device, state_->morphology_staging.data(), width) !=
        gpu::GpuImageStatus::ok) {
        return false;
    }
    for (std::size_t index = 0U; index < count; ++index) {
        best_integrated[index] = state_->morphology_staging[index].red;
        best_ridge[index] = state_->morphology_staging[index].green;
    }
    return true;
}

bool accelerate_scratch_angle_maps(
    const float* const bright,
    const std::uint8_t* const valid,
    float* const ridge,
    float* const integrated,
    const std::uint32_t width,
    const std::uint32_t height,
    const imaging::ScratchAngleTaps* const taps,
    const float balance_limit) noexcept {
    return GpuAccelerator::shared().apply_scratch_angle_maps(
        bright, valid, ridge, integrated, width, height, taps, balance_limit);
}

bool accelerate_scratch_angle_stack(
    const float* const bright,
    const std::uint8_t* const valid,
    float* const best_ridge,
    float* const best_integrated,
    const std::uint32_t width,
    const std::uint32_t height,
    const imaging::ScratchAngleTaps* const taps,
    const int angle_count,
    const float balance_limit) noexcept {
    return GpuAccelerator::shared().apply_scratch_angle_stack(
        bright,
        valid,
        best_ridge,
        best_integrated,
        width,
        height,
        taps,
        angle_count,
        balance_limit);
}

}  // namespace negaflow::pipeline
