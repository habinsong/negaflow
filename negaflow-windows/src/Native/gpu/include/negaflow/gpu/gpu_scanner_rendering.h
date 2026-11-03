#pragma once

// 스캐너 렌더링의 GPU 판입니다.
//
// macOS : `ChromabaseMetalKernels+FilterSources.swift` `scannerRendering`
// CPU 판 : `imaging/scanner_target_rendering.cpp` `render_linear`
// 셰이더 : `shaders/scanner_rendering.hlsl`
//
// 점별 커널이라 이웃을 보지 않습니다 — 띠로 나눠 돌려도 같은 값입니다. 곡선의 값·기울기는
// CPU 의 `rendering_setup` 이 만든 것을 그대로 받습니다. CPU 는 double, GPU 는 float 입니다.

#include "negaflow/gpu/gpu_pointwise.h"
#include "negaflow/imaging/scanner_target_grade.h"

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

class GpuScannerRendering final {
public:
    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuScannerRendering& kernel) noexcept;

    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination,
        const imaging::ScannerRenderingSetup& setup) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return kernel_.is_valid(); }

private:
    GpuPointwiseKernel kernel_{};
};

} // namespace negaflow::gpu
