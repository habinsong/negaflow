#pragma once

// 프리뷰 전용 채널 클리핑 오버레이 GPU 판입니다.
//
// macOS  : `ChromabaseMetalKernels.swift:604` `channelClippingOverlay`
// CPU 판 : `imaging/channel_clipping_overlay.h`
// 셰이더 : `src/Native/gpu/shaders/channel_clipping_overlay.hlsl`
//
// 출력은 오버레이 레이어입니다. 현상 결과는 바꾸지 않습니다.

#include "negaflow/gpu/gpu_pointwise.h"

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

class GpuChannelClippingOverlay final {
public:
    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuChannelClippingOverlay& kernel) noexcept;

    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return kernel_.is_valid(); }

private:
    GpuPointwiseKernel kernel_{};
};

}  // namespace negaflow::gpu
