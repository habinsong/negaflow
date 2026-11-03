#include "negaflow/gpu/gpu_noritsu_texture.h"

#include <windows.h>

#include <cmath>
#include <cstddef>
#include <cstdint>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/noritsu_texture_NoritsuTextureHorizontalMain.h"
#include "negaflow/gpu/shaders/noritsu_texture_NoritsuTextureVerticalMain.h"

namespace negaflow::gpu {
namespace {

constexpr std::size_t max_taps = imaging::ScannerTargetTextureSetup::max_taps;
constexpr std::size_t weight_vectors = (max_taps + 3U) / 4U;

// HLSL `cbuffer NoritsuTextureConstants` 와 같은 배치여야 합니다.
struct alignas(16) NoritsuTextureConstants final {
    GpuPointwiseExtent extent{};
    float weights[weight_vectors][4]{};
    float amount{0.0F};
    float floor_ratio{0.0F};
    float floor_absolute{0.0F};
    float luma_gate{0.0F};
    std::uint32_t tap_count{0U};
    std::uint32_t padding[3]{0U, 0U, 0U};
};

static_assert(weight_vectors == 7U, "shader declares seven weight vectors");
static_assert(sizeof(NoritsuTextureConstants) == 16U + (16U * weight_vectors) + 16U + 16U,
              "extent + weight vectors + four floats + tap count");

}  // namespace

GpuKernelStatus GpuNoritsuTexture::create(
    const GpuDevice& device,
    GpuNoritsuTexture& kernel) noexcept {
    if (GpuPointwiseKernel::create(
            device,
            negaflow_noritsu_texture_horizontal_cs,
            sizeof(negaflow_noritsu_texture_horizontal_cs),
            sizeof(NoritsuTextureConstants),
            kernel.horizontal_) != GpuKernelStatus::ok) {
        return GpuKernelStatus::resource_creation_failed;
    }
    if (GpuPointwiseKernel::create(
            device,
            negaflow_noritsu_texture_vertical_cs,
            sizeof(negaflow_noritsu_texture_vertical_cs),
            sizeof(NoritsuTextureConstants),
            kernel.vertical_) != GpuKernelStatus::ok) {
        return GpuKernelStatus::resource_creation_failed;
    }
    return GpuKernelStatus::ok;
}

GpuKernelStatus GpuNoritsuTexture::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage* const scratch,
    GpuWorkingImage& destination,
    const imaging::ScannerTargetTextureSetup& setup) const noexcept {
    if (!is_valid()) {
        return GpuKernelStatus::device_unavailable;
    }
    if (scratch == nullptr) {
        return GpuKernelStatus::invalid_arguments;
    }
    if (!std::isfinite(setup.amount) ||
        !std::isfinite(setup.floor_ratio) ||
        !std::isfinite(setup.floor_absolute) ||
        !std::isfinite(setup.luma_gate)) {
        return GpuKernelStatus::non_finite_parameter;
    }

    if (setup.tap_count == 0U || setup.tap_count > max_taps || (setup.tap_count % 2U) == 0U) {
        return GpuKernelStatus::invalid_arguments;
    }
    NoritsuTextureConstants payload{};
    payload.tap_count = setup.tap_count;
    for (std::size_t index = 0U; index < setup.tap_count; ++index) {
        if (!std::isfinite(setup.weights[index])) {
            return GpuKernelStatus::non_finite_parameter;
        }
        payload.weights[index >> 2U][index & 3U] = setup.weights[index];
    }
    payload.amount = setup.amount;
    payload.floor_ratio = setup.floor_ratio;
    payload.floor_absolute = setup.floor_absolute;
    payload.luma_gate = setup.luma_gate;

    if (horizontal_.dispatch(device, source, scratch[0], &payload, sizeof(payload)) !=
        GpuKernelStatus::ok) {
        return GpuKernelStatus::resource_creation_failed;
    }
    return vertical_.dispatch_pair(
        device, scratch[0], source, destination, &payload, sizeof(payload));
}

}  // namespace negaflow::gpu
