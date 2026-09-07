#include "gpu_accelerator_state.h"

namespace negaflow::pipeline {
bool GpuAccelerator::apply_custom_color_target(float* pixels, std::uint32_t width,
    std::uint32_t height, std::uint32_t stride_pixels, std::uint32_t target) noexcept {
    const auto* profile = imaging::custom_color_target_profile(target);
    if (!available() || pixels == nullptr || profile == nullptr || width == 0U ||
        height == 0U || stride_pixels < width) { return false; }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    if (!state_->custom_color_target_ready || !state_->pool.ensure(state_->device, width, height)) {
        return false;
    }
    auto* pool = state_->pool.images();
    auto* rgba = reinterpret_cast<core::Rgba32F*>(pixels);
    int read_slot = 0, write_slot = 1;
    if (state_->resident_matches(pixels, width, height)) {
        read_slot = state_->resident.read_slot;
        write_slot = 1 - read_slot;
    } else if (pool[0].upload_into(state_->device, rgba, stride_pixels) != gpu::GpuImageStatus::ok) {
        return false;
    }
    if (state_->custom_color_target.dispatch(state_->device, pool[read_slot], pool[write_slot], *profile)
        != gpu::GpuKernelStatus::ok) { return false; }
    if (state_->resident.scope_depth > 0) {
        state_->bind_resident(pixels, width, height, stride_pixels, write_slot);
        return true;
    }
    return pool[write_slot].download(state_->device, rgba, stride_pixels) == gpu::GpuImageStatus::ok;
}
} // namespace negaflow::pipeline
