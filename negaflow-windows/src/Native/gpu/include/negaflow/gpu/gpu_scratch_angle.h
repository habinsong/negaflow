#pragma once

// GrainMend 스크래치 각도. CPU 는 `imaging/grain_mend_scratch_angles.cpp`.
// 탭은 CPU 가 만든 것을 그대로 받습니다.

#include "negaflow/gpu/gpu_pointwise.h"
#include "negaflow/imaging/kernel_accelerator.h"

#include <cstdint>

struct ID3D11ComputeShader;
struct ID3D11Buffer;

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

class GpuScratchAngle final {
public:
    GpuScratchAngle() noexcept = default;
    ~GpuScratchAngle();

    GpuScratchAngle(const GpuScratchAngle&) = delete;
    GpuScratchAngle& operator=(const GpuScratchAngle&) = delete;
    GpuScratchAngle(GpuScratchAngle&& other) noexcept;
    GpuScratchAngle& operator=(GpuScratchAngle&& other) noexcept;

    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuScratchAngle& kernel) noexcept;

    [[nodiscard]] GpuKernelStatus dispatch_ridge(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination,
        const imaging::ScratchAngleTaps& taps,
        float balance_limit) const noexcept;

    [[nodiscard]] GpuKernelStatus dispatch_integrate(
        const GpuDevice& device,
        const GpuWorkingImage& ridge,
        GpuWorkingImage& destination,
        const std::int32_t (*along)[2],
        int tap_count,
        bool accumulate) const noexcept;

    [[nodiscard]] GpuKernelStatus dispatch_max(
        const GpuDevice& device,
        const GpuWorkingImage& integrated,
        const GpuWorkingImage& ridge,
        GpuWorkingImage& best) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return ridge_ != nullptr; }

private:
    void reset() noexcept;

    ID3D11ComputeShader* ridge_{nullptr};
    ID3D11ComputeShader* integrate_{nullptr};
    ID3D11ComputeShader* max_{nullptr};
    ID3D11Buffer* constants_{nullptr};
};
}  // namespace negaflow::gpu
