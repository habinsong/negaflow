#include "negaflow/gpu/gpu_channel_clipping_overlay.h"

#include <windows.h>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/channel_clipping_overlay_ChannelClippingOverlayMain.h"

namespace negaflow::gpu {
namespace {

struct alignas(16) ChannelClippingOverlayConstants final {
    GpuPointwiseExtent extent{};
};

static_assert(sizeof(ChannelClippingOverlayConstants) == 16U, "extent only");

}  // namespace

GpuKernelStatus GpuChannelClippingOverlay::create(
    const GpuDevice& device,
    GpuChannelClippingOverlay& kernel) noexcept {
    return GpuPointwiseKernel::create(
        device,
        negaflow_channel_clipping_overlay_cs,
        sizeof(negaflow_channel_clipping_overlay_cs),
        sizeof(ChannelClippingOverlayConstants),
        kernel.kernel_);
}

GpuKernelStatus GpuChannelClippingOverlay::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage& destination) const noexcept {
    ChannelClippingOverlayConstants payload{};
    return kernel_.dispatch(device, source, destination, &payload, sizeof(payload));
}

}  // namespace negaflow::gpu
