#pragma once

// NORITSU 장치 질감(감마 도메인 luminance USM)의 GPU 판입니다.
//
// macOS  : `ChromabaseMetalKernels.swift:505` `noritsuTexture`
// CPU 판 : `imaging/scanner_target_grade.cpp` `apply_noritsu_texture`
// 셰이더 : `shaders/noritsu_texture.hlsl`
//
// 가중치·세기·플로어·루마 게이트는 **CPU 의 `scanner_target_texture_setup()` 이
// 만든 것을 그대로** 씁니다. 여기서 숫자를 다시 적으면 두 벌이 됩니다.
//
// ☠️ **근사한 것입니다.** CPU 는 두 패스를 `double` 로 누적하고 GPU 는 float 입니다.
//    하드 게이트(`lo < 0 || hi > 1`)가 있어 경계 화소는 1ulp 로 결과가 갈립니다.

#include "negaflow/gpu/gpu_pointwise.h"
#include "negaflow/imaging/scanner_target_grade.h"

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

class GpuNoritsuTexture final {
public:
    static constexpr int scratch_count = 1;

    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuNoritsuTexture& kernel) noexcept;

    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage* scratch,
        GpuWorkingImage& destination,
        const imaging::ScannerTargetTextureSetup& setup) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept {
        return horizontal_.is_valid() && vertical_.is_valid();
    }

private:
    GpuPointwiseKernel horizontal_{};
    GpuPointwiseKernel vertical_{};
};

}  // namespace negaflow::gpu
