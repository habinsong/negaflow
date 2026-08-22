#include "negaflow/pipeline/gpu_accelerator.h"

// 실측 `CIVibrance` 표를 쓰는 진입점 둘입니다 — 흐린 장면 vibrance 와 컬러 모델.
//
// 왜 따로 뗐나 — 클래스 본체(`gpu_accelerator.cpp`)와 디지털 필름 룩
// (`gpu_accelerator_film_look.cpp`)이 이미 각자 자리를 채웠고, 500줄 규칙이 있습니다.
// 이 둘은 **같은 표를 나눠 쓰는** 한 묶음이라 같은 자리에 둡니다.
//
// 둘 다 **근사**입니다. 호출부가 `ApproximateAcceleratorScope` 안에서만 부릅니다.

#include "gpu_accelerator_state.h"

#include <algorithm>
#include <cmath>
#include <mutex>
#include <utility>

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
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    if (!state_->vibrance_ready) {
        return false;
    }
    if (!state_->pool.ensure(state_->device, width, height)) {
        return false;
    }
    gpu::GpuWorkingImage* const pool = state_->pool.images();
    auto* const rgba = reinterpret_cast<core::Rgba32F*>(pixels);
    int read_slot = 0;
    int write_slot = 1;
    if (state_->resident_matches(pixels, width, height)) {
        read_slot = state_->resident.read_slot;
        write_slot = 1 - read_slot;
    } else if (
        pool[0].upload_into(state_->device, rgba, stride_pixels) != gpu::GpuImageStatus::ok) {
        return false;
    }
    if (state_->muted_vibrance.dispatch(
            state_->device,
            state_->vibrance_table,
            pool[read_slot],
            pool[write_slot],
            amount) != gpu::GpuKernelStatus::ok) {
        return false;
    }
    if (state_->resident.scope_depth > 0) {
        state_->bind_resident(pixels, width, height, stride_pixels, write_slot);
        return true;
    }
    return pool[write_slot].download(state_->device, rgba, stride_pixels) ==
        gpu::GpuImageStatus::ok;
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
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    if (!state_->vibrance_ready) {
        return false;
    }
    if (!state_->pool.ensure(state_->device, width, height)) {
        return false;
    }
    gpu::GpuWorkingImage* const pool = state_->pool.images();
    auto* const rgba = reinterpret_cast<core::Rgba32F*>(pixels);
    int read_slot = 0;
    int write_slot = 1;
    if (state_->resident_matches(pixels, width, height)) {
        read_slot = state_->resident.read_slot;
        write_slot = 1 - read_slot;
    } else if (
        pool[0].upload_into(state_->device, rgba, stride_pixels) != gpu::GpuImageStatus::ok) {
        return false;
    }
    if (state_->color_model.dispatch(
            state_->device,
            state_->vibrance_table,
            pool[read_slot],
            pool[write_slot],
            *parameters) != gpu::GpuKernelStatus::ok) {
        return false;
    }
    if (state_->resident.scope_depth > 0) {
        state_->bind_resident(pixels, width, height, stride_pixels, write_slot);
        return true;
    }
    return pool[write_slot].download(state_->device, rgba, stride_pixels) ==
        gpu::GpuImageStatus::ok;
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
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
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

bool GpuAccelerator::apply_noritsu_texture(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const imaging::ScannerTargetTextureSetup* const setup) noexcept {
    if (!available() || pixels == nullptr || setup == nullptr) {
        return false;
    }
    if (width == 0U || height == 0U || stride_pixels < width) {
        return false;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    if (!state_->noritsu_texture_ready) {
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
    if (state_->noritsu_texture.dispatch(
            state_->device,
            pool[0],
            &pool[gpu::GpuImagePool::scratch_first],
            pool[1],
            *setup) != gpu::GpuKernelStatus::ok) {
        return false;
    }
    return pool[1].download(state_->device, rgba, stride_pixels) == gpu::GpuImageStatus::ok;
}

bool GpuAccelerator::apply_texture_grain(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const float amount) noexcept {
    if (!available() || pixels == nullptr) {
        return false;
    }
    if (width == 0U || height == 0U || stride_pixels < width || !std::isfinite(amount)) {
        return false;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    if (!state_->texture_grain_ready) {
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
    if (state_->texture_grain.dispatch(state_->device, pool[0], pool[1], amount) !=
        gpu::GpuKernelStatus::ok) {
        return false;
    }
    return pool[1].download(state_->device, rgba, stride_pixels) == gpu::GpuImageStatus::ok;
}

bool GpuAccelerator::apply_channel_clipping_overlay(
    const float* const source,
    float* const destination,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t source_stride_pixels,
    const std::uint32_t destination_stride_pixels) noexcept {
    if (!available() || source == nullptr || destination == nullptr) {
        return false;
    }
    if (width == 0U || height == 0U || source_stride_pixels < width ||
        destination_stride_pixels < width) {
        return false;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    if (!state_->clipping_overlay_ready) {
        return false;
    }
    if (!state_->pool.ensure(state_->device, width, height)) {
        return false;
    }
    gpu::GpuWorkingImage* const pool = state_->pool.images();
    const auto* const src = reinterpret_cast<const core::Rgba32F*>(source);
    auto* const dst = reinterpret_cast<core::Rgba32F*>(destination);
    if (pool[0].upload_into(state_->device, src, source_stride_pixels) !=
        gpu::GpuImageStatus::ok) {
        return false;
    }
    if (state_->clipping_overlay.dispatch(state_->device, pool[0], pool[1]) !=
        gpu::GpuKernelStatus::ok) {
        return false;
    }
    return pool[1].download(state_->device, dst, destination_stride_pixels) ==
        gpu::GpuImageStatus::ok;
}

bool GpuAccelerator::apply_area_average(
    const float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const std::uint32_t origin_x,
    const std::uint32_t origin_y,
    const std::uint32_t extent_width,
    const std::uint32_t extent_height,
    float mean[4],
    std::uint64_t* const count) noexcept {
    if (!available() || pixels == nullptr || mean == nullptr || count == nullptr) {
        return false;
    }
    if (width == 0U || height == 0U || stride_pixels < width) {
        return false;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    if (!state_->area_average_ready) {
        return false;
    }
    if (!state_->pool.ensure(state_->device, width, height)) {
        return false;
    }
    gpu::GpuWorkingImage* const pool = state_->pool.images();
    const auto* const rgba = reinterpret_cast<const core::Rgba32F*>(pixels);
    if (pool[0].upload_into(state_->device, rgba, stride_pixels) != gpu::GpuImageStatus::ok) {
        return false;
    }
    return state_->area_average.dispatch(
               state_->device,
               pool[0],
               origin_x,
               origin_y,
               extent_width,
               extent_height,
               mean,
               *count) == gpu::GpuKernelStatus::ok;
}

namespace {

[[nodiscard]] bool ensure_mip_image(
    const gpu::GpuDevice& device,
    gpu::GpuWorkingImage& image,
    const std::uint32_t width,
    const std::uint32_t height) noexcept {
    if (image.is_valid() && image.width() == width && image.height() == height) {
        return true;
    }
    gpu::GpuWorkingImage next{};
    if (gpu::GpuWorkingImage::create(device, width, height, next) != gpu::GpuImageStatus::ok) {
        return false;
    }
    image = std::move(next);
    return true;
}

} // namespace

bool GpuAccelerator::apply_mip_halve_levels(
    const float* const source,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const int wanted_levels,
    float* const destination,
    const std::uint32_t destination_capacity,
    std::uint32_t* const out_width,
    std::uint32_t* const out_height) noexcept {
    if (!available() || source == nullptr || destination == nullptr ||
        out_width == nullptr || out_height == nullptr) {
        return false;
    }
    if (width == 0U || height == 0U || stride_pixels < width || wanted_levels <= 0) {
        return false;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    if (!state_->mip_halve_ready) {
        return false;
    }
    if (!state_->pool.ensure(state_->device, width, height)) {
        return false;
    }
    gpu::GpuWorkingImage* const pool = state_->pool.images();
    const gpu::GpuWorkingImage* current = &pool[0];
    if (state_->resident_matches(source, width, height)) {
        current = &pool[state_->resident.read_slot];
    } else {
        const auto* const rgba = reinterpret_cast<const core::Rgba32F*>(source);
        if (pool[0].upload_into(state_->device, rgba, stride_pixels) !=
            gpu::GpuImageStatus::ok) {
            return false;
        }
    }
    gpu::GpuWorkingImage* scratch[2] = {&state_->mip_a, &state_->mip_b};
    int scratch_index = 0;
    std::uint32_t current_width = width;
    std::uint32_t current_height = height;
    int steps = 0;
    for (int step = 0; step < wanted_levels; ++step) {
        if (current_width < 2U || current_height < 2U) {
            break;
        }
        const std::uint32_t child_width = std::max(1U, current_width / 2U);
        const std::uint32_t child_height = std::max(1U, current_height / 2U);
        gpu::GpuWorkingImage& dest = *scratch[scratch_index];
        if (!ensure_mip_image(state_->device, dest, child_width, child_height)) {
            return false;
        }
        if (state_->mip_halve.dispatch(state_->device, *current, dest) !=
            gpu::GpuKernelStatus::ok) {
            return false;
        }
        current = &dest;
        current_width = child_width;
        current_height = child_height;
        scratch_index ^= 1;
        ++steps;
    }
    if (steps == 0) {
        return false;
    }
    if (destination_capacity < current_width * current_height) {
        return false;
    }
    auto* const out = reinterpret_cast<core::Rgba32F*>(destination);
    if (current->download(state_->device, out, current_width) != gpu::GpuImageStatus::ok) {
        return false;
    }
    *out_width = current_width;
    *out_height = current_height;
    return true;
}

} // namespace negaflow::pipeline
