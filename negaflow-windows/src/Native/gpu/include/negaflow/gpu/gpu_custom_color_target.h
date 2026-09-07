#pragma once
#include "negaflow/gpu/gpu_pointwise.h"
#include "negaflow/imaging/custom_color_target.h"

namespace negaflow::gpu {
class GpuCustomColorTarget final {
public:
    [[nodiscard]] static GpuKernelStatus create(const GpuDevice& device, GpuCustomColorTarget& kernel) noexcept;
    [[nodiscard]] GpuKernelStatus dispatch(const GpuDevice& device, const GpuWorkingImage& source,
        GpuWorkingImage& destination, const imaging::CustomColorTargetProfile& profile) const noexcept;
private:
    GpuPointwiseKernel kernel_{};
};
} // namespace negaflow::gpu
