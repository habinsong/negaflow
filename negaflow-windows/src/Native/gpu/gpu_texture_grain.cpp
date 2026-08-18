#include "negaflow/gpu/gpu_texture_grain.h"

#include <windows.h>

#include <cmath>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/texture_grain_TextureGrainMain.h"

namespace negaflow::gpu {
namespace {

struct alignas(16) TextureGrainConstants final {
    GpuPointwiseExtent extent{};
    float amount{0.0F};
    float padding[3]{};
};

static_assert(sizeof(TextureGrainConstants) == 32U, "extent + amount + pad");

}  // namespace

GpuKernelStatus GpuTextureGrain::create(
    const GpuDevice& device,
    GpuTextureGrain& kernel) noexcept {
    return GpuPointwiseKernel::create(
        device,
        negaflow_texture_grain_cs,
        sizeof(negaflow_texture_grain_cs),
        sizeof(TextureGrainConstants),
        kernel.kernel_);
}

GpuKernelStatus GpuTextureGrain::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage& destination,
    const float amount) const noexcept {
    if (!std::isfinite(amount)) {
        return GpuKernelStatus::non_finite_parameter;
    }
    TextureGrainConstants payload{};
    payload.amount = amount;
    return kernel_.dispatch(device, source, destination, &payload, sizeof(payload));
}

}  // namespace negaflow::gpu
