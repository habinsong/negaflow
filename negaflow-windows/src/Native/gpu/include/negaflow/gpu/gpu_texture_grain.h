#pragma once

// TextureStage 그레인 GPU 판입니다.
//
// macOS : `ChromabaseMetalKernels.swift:281` `filmGrain`
// + `ColorModel.swift` `TextureStage.apply` (`params.grain * 0.055`)
// CPU 판 : `imaging/texture_stage_effects.cpp` `apply_grain`
// 셰이더 : `src/Native/gpu/shaders/texture_grain.hlsl`
//
// **근사입니다.** 좌표 해시는 비트 일치, 루마·smoothstep 은 float.
// `ApproximateAcceleratorScope` 안에서만 돕니다.

#include "negaflow/gpu/gpu_pointwise.h"

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

class GpuTextureGrain final {
public:
    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuTextureGrain& kernel) noexcept;

    // `amount` 는 이미 `strength * 0.055` 입니다.
    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination,
        float amount) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return kernel_.is_valid(); }

private:
    GpuPointwiseKernel kernel_{};
};

} // namespace negaflow::gpu
