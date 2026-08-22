#include "negaflow/pipeline/gpu_accelerator.h"

#include "gpu_accelerator_state.h"

#include "negaflow/gpu/gpu_working_image.h"

namespace negaflow::pipeline {

bool GpuAccelerator::flush_unlocked() noexcept {
    if (state_ == nullptr || !state_->resident.host_stale || state_->resident.host == nullptr) {
        return true;
    }
    if (!state_->usable || !state_->device.is_usable()) {
        return false;
    }
    gpu::GpuWorkingImage* const pool = state_->pool.images();
    const int slot = state_->resident.read_slot;
    if (slot < 0 || slot >= gpu::GpuImagePool::size || !pool[slot].is_valid()) {
        return false;
    }
    auto* const host = static_cast<core::Rgba32F*>(const_cast<void*>(state_->resident.host));
    if (pool[slot].download(state_->device, host, state_->resident.stride) !=
        gpu::GpuImageStatus::ok) {
        return false;
    }
    state_->resident.host_stale = false;
    return true;
}

bool GpuAccelerator::begin_resident() noexcept {
    if (!available()) {
        return false;
    }
    state_->lock.lock();
    ++state_->resident.scope_depth;
    return true;
}

void GpuAccelerator::end_resident() noexcept {
    if (state_ == nullptr) {
        return;
    }
    if (state_->resident.scope_depth <= 0) {
        return;
    }
    if (state_->resident.scope_depth == 1) {
        flush_unlocked();
        state_->resident = State::ResidentFrame{};
    } else {
        --state_->resident.scope_depth;
    }
    state_->lock.unlock();
}

// 곧 사라지는 버퍼를 위한 좁은 문입니다.
//
// 상주 프레임은 **남의 버퍼를 가리키는 생포인터**입니다. 단계가 이미지를 값으로 받아
// 다 쓰고 버리면 그 버퍼는 단계가 끝나며 사라지는데, 묶음은 그대로 남습니다. 그러면
// 스코프가 끝날 때 `flush_unlocked` 가 **해제된 메모리에 memcpy** 합니다 —
// 2026-08-20 크래시가 정확히 그것이었습니다(스택: `~GpuResidentScope` →
// `end_resident` → `flush_unlocked` → `copy_rows` → memcpy, 쓰기 위반).
//
// 그래서 버퍼를 넘기기 **직전에** 이것을 부릅니다. 그 버퍼가 묶여 있으면 지금 내리고
// 묶음을 풉니다. 아니면 아무것도 하지 않으므로 상주 최적화는 그대로입니다.
void GpuAccelerator::flush_resident_if(const void* const host) noexcept {
    if (!available() || host == nullptr) {
        return;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    if (state_->resident.host != host) {
        return;
    }
    flush_unlocked();
    // 스코프 깊이는 건드리지 않습니다 — 스코프는 아직 살아 있습니다.
    state_->resident.host = nullptr;
    state_->resident.host_stale = false;
}

void GpuAccelerator::flush_resident() noexcept {
    if (!available()) {
        return;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    flush_unlocked();
    // macOS 가 `createCGImage` 로 그래프를 평가한 뒤에야 CPU 가 화소를
    // 만집니다. 여기서 내린 뒤 별칭을 끊지 않으면 톤이 반전만 된 옛
    // 텍스처를 내려 덮어씁니다.
    state_->resident.host = nullptr;
    state_->resident.width = 0U;
    state_->resident.height = 0U;
    state_->resident.stride = 0U;
    state_->resident.read_slot = 0;
    state_->resident.host_stale = false;
}

bool GpuAccelerator::trim_idle() noexcept {
    if (!available()) {
        return false;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    flush_unlocked();
    state_->resident = State::ResidentFrame{};
    return state_->device.trim_idle();
}

bool GpuAccelerator::has_resident_image(
    const float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height) noexcept {
    if (!available() || pixels == nullptr) {
        return false;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    return state_->resident_matches(pixels, width, height);
}

bool GpuAccelerator::try_encode_preview_bgra(
    const float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    std::uint8_t* const destination,
    const std::uint32_t destination_stride_bytes,
    const float proof_scale[3],
    const float proof_bias[3],
    const imaging::ImageTransformGather* const gather) noexcept {
    if (!available() || pixels == nullptr || destination == nullptr ||
        proof_scale == nullptr || proof_bias == nullptr) {
        return false;
    }
    // `width`/`height` 는 **상주 이미지**의 크기입니다. 목표 폭은 변환 뒤 크기이므로
    // 스트라이드는 그쪽으로 확인합니다.
    const std::uint32_t destination_width =
        gather != nullptr && gather->output_width != 0U ? gather->output_width : width;
    if (width == 0U || height == 0U ||
        destination_stride_bytes < destination_width * 4U) {
        return false;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    if (!state_->preview_encode_ready ||
        !state_->resident_matches(pixels, width, height)) {
        return false;
    }
    gpu::GpuWorkingImage& source = state_->pool.images()[state_->resident.read_slot];
    if (state_->finite_ready) {
        bool finite = false;
        if (state_->finite.dispatch(state_->device, source, finite) !=
                gpu::GpuKernelStatus::ok ||
            !finite) {
            return false;
        }
    }
    if (state_->preview_encode.encode(
            state_->device,
            source,
            destination,
            destination_stride_bytes,
            proof_scale,
            proof_bias,
            gather) != gpu::GpuKernelStatus::ok) {
        return false;
    }
    // macOS `createCGImage(.RGBA8)` 가 그래프를 평가한 것과 같습니다. 호스트
    // float 은 낡은 채로 두되, 스코프가 끝나도 다시 내리지 않습니다.
    state_->resident.host_stale = false;
    return true;
}

bool GpuAccelerator::check_resident_finite(
    const float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    bool* const all_finite) noexcept {
    if (!available() || pixels == nullptr || all_finite == nullptr) {
        return false;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    if (!state_->finite_ready ||
        !state_->resident_matches(pixels, width, height) ||
        state_->resident.stride != stride_pixels) {
        return false;
    }
    gpu::GpuWorkingImage& image = state_->pool.images()[state_->resident.read_slot];
    bool finite = false;
    if (state_->finite.dispatch(state_->device, image, finite) != gpu::GpuKernelStatus::ok) {
        return false;
    }
    *all_finite = finite;
    return true;
}

GpuResidentScope::GpuResidentScope() noexcept {
    held_ = GpuAccelerator::shared().begin_resident();
}

GpuResidentScope::~GpuResidentScope() {
    if (held_) {
        GpuAccelerator::shared().end_resident();
    }
}

void reset_gpu_host_transfer_stats() noexcept {
    gpu::reset_gpu_host_transfer_stats();
}

GpuHostTransferStats gpu_host_transfer_stats() noexcept {
    const gpu::GpuHostTransferStats inner = gpu::gpu_host_transfer_stats();
    GpuHostTransferStats stats{};
    stats.uploads = inner.uploads;
    stats.downloads = inner.downloads;
    stats.uploaded_pixels = inner.uploaded_pixels;
    stats.downloaded_pixels = inner.downloaded_pixels;
    stats.downloaded_bytes = inner.downloaded_bytes;
    return stats;
}

}  // namespace negaflow::pipeline
