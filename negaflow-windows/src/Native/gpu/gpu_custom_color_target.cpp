#include "negaflow/gpu/gpu_custom_color_target.h"
#include <windows.h>
#include "negaflow/gpu/shaders/custom_color_target_CustomColorTargetMain.h"

namespace negaflow::gpu {
namespace {
struct alignas(16) CustomConstants final {
    GpuPointwiseExtent extent{};
    float tone[10][4]{};
    float hue_a[8][4]{};
    float hue_b[8][4]{};
    float controls[4]{};
    float tint_shadow_mid[4]{};
    float tint_high[4]{};
};
static_assert(sizeof(CustomConstants) == 480U);
static_assert(offsetof(CustomConstants, controls) == 432U);
} // namespace

GpuKernelStatus GpuCustomColorTarget::create(const GpuDevice& device, GpuCustomColorTarget& kernel) noexcept {
    return GpuPointwiseKernel::create(device, negaflow_custom_color_target_cs,
        sizeof(negaflow_custom_color_target_cs), sizeof(CustomConstants), kernel.kernel_);
}
GpuKernelStatus GpuCustomColorTarget::dispatch(const GpuDevice& device, const GpuWorkingImage& source,
    GpuWorkingImage& destination, const imaging::CustomColorTargetProfile& p) const noexcept {
    CustomConstants payload{};
    for (std::size_t i = 0; i < 10; ++i) {
        payload.tone[i][0] = static_cast<float>(p.tone[i]);
        payload.tone[i][1] = static_cast<float>(p.slopes[i]);
    }
    for (std::size_t i = 0; i < 8; ++i) {
        payload.hue_a[i][0] = static_cast<float>(p.gain[i]);
        payload.hue_a[i][1] = static_cast<float>(p.density[i]);
        payload.hue_a[i][2] = static_cast<float>(p.hue_shadow[i]);
        payload.hue_a[i][3] = static_cast<float>(p.hue_mid[i]);
        payload.hue_b[i][0] = static_cast<float>(p.hue_high[i]);
        payload.hue_b[i][1] = static_cast<float>(p.highlight_hue[i]);
    }
    for (std::size_t i = 0; i < 4; ++i) { payload.controls[i] = static_cast<float>(p.controls[i]); }
    for (std::size_t i = 0; i < 2; ++i) {
        payload.tint_shadow_mid[i] = static_cast<float>(p.tint_shadow[i]);
        payload.tint_shadow_mid[i + 2] = static_cast<float>(p.tint_mid[i]);
        payload.tint_high[i] = static_cast<float>(p.tint_high[i]);
    }
    return kernel_.dispatch(device, source, destination, &payload, sizeof(payload));
}
} // namespace negaflow::gpu
