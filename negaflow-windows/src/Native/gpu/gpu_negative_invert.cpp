#include "negaflow/gpu/gpu_negative_invert.h"

// fxc 가 만든 헤더는 `const BYTE ...[]` 로 나오므로 Windows 타입이 먼저 보여야 합니다.
#include <windows.h>

#include <cmath>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/negative_invert_NegativeInvertMain.h"

namespace negaflow::gpu {
namespace {

// HLSL `cbuffer NegativeInvertConstants` 와 같은 배치여야 합니다.
// HLSL 은 `float3` + `float` 를 16바이트 레지스터 하나에 채웁니다 — 그래서 yCeiling 과
// amplitude 가 dmin/dmax 뒤에 하나씩 붙어 있습니다. 순서를 바꾸면 조용히 어긋납니다.
struct alignas(16) NegativeInvertConstants final {
    GpuPointwiseExtent extent{};
    float dmin[3]{0.0F, 0.0F, 0.0F};
    float response_y_ceiling{0.0F};
    float dmax_normalized[3]{0.0F, 0.0F, 0.0F};
    float response_amplitude{0.0F};
    float response_rate{0.0F};
    float response_shape{0.0F};
    float padding[2]{0.0F, 0.0F};
};

static_assert(sizeof(NegativeInvertConstants) == 64U, "four constant registers");

// CPU 판 `validate_parameters` 와 같은 판정입니다 — dmin·dmax 는 **양수**여야 하고
// 응답 계수는 유한해야 합니다. 0 이나 음수 dmin 은 `log10` 에서 NaN/−inf 가 되고,
// 그러면 화면이 통째로 죽습니다.
[[nodiscard]] bool valid_parameters(const GpuNegativeInvertParameters& parameters) noexcept {
    for (int index = 0; index < 3; ++index) {
        if (!std::isfinite(parameters.dmin[index]) || parameters.dmin[index] <= 0.0F) {
            return false;
        }
        if (!std::isfinite(parameters.dmax_normalized[index]) ||
            parameters.dmax_normalized[index] <= 0.0F) {
            return false;
        }
    }
    return std::isfinite(parameters.response_y_ceiling) &&
        std::isfinite(parameters.response_amplitude) &&
        std::isfinite(parameters.response_rate) && std::isfinite(parameters.response_shape);
}

}  // namespace

GpuKernelStatus GpuNegativeInvert::create(
    const GpuDevice& device,
    GpuNegativeInvert& kernel) noexcept {
    return GpuPointwiseKernel::create(
        device,
        negaflow_negative_invert_cs,
        sizeof(negaflow_negative_invert_cs),
        sizeof(NegativeInvertConstants),
        kernel.kernel_);
}

GpuKernelStatus GpuNegativeInvert::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage& destination,
    const GpuNegativeInvertParameters& parameters) const noexcept {
    if (!valid_parameters(parameters)) {
        return GpuKernelStatus::non_finite_parameter;
    }
    NegativeInvertConstants payload{};
    for (int index = 0; index < 3; ++index) {
        payload.dmin[index] = parameters.dmin[index];
        payload.dmax_normalized[index] = parameters.dmax_normalized[index];
    }
    payload.response_y_ceiling = parameters.response_y_ceiling;
    payload.response_amplitude = parameters.response_amplitude;
    payload.response_rate = parameters.response_rate;
    payload.response_shape = parameters.response_shape;
    return kernel_.dispatch(device, source, destination, &payload, sizeof(payload));
}

}  // namespace negaflow::gpu
