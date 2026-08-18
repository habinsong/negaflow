#include "negaflow/gpu/gpu_tone_kernels.h"

// fxc 가 만든 헤더는 `const BYTE ...[]` 로 나오므로 Windows 타입이 먼저 보여야 합니다.
#include <windows.h>

#include <cmath>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/basic_tone_BasicToneMain.h"
#include "negaflow/gpu/shaders/parametric_tone_curve_ParametricToneCurveMain.h"

namespace negaflow::gpu {
namespace {

// HLSL `cbuffer BasicToneConstants` 와 같은 배치여야 합니다.
struct alignas(16) BasicToneConstants final {
    GpuPointwiseExtent extent{};
    float contrast{0.0F};
    float density{0.0F};
    float highlights{0.0F};
    float shadows{0.0F};
    float whites{0.0F};
    float blacks{0.0F};
    float padding[2]{0.0F, 0.0F};
};

static_assert(sizeof(BasicToneConstants) % 16U == 0U, "constant buffers are 16-byte aligned");

// HLSL `cbuffer ParametricToneCurveConstants` 와 같은 배치여야 합니다.
// 밴드 경계 8개까지 상수 버퍼로 넘깁니다 — macOS 도 인자로 받습니다.
struct alignas(16) ParametricToneCurveConstants final {
    GpuPointwiseExtent extent{};
    float highlights{0.0F};
    float lights{0.0F};
    float darks{0.0F};
    float shadows{0.0F};
    float shadow_low{0.0F};
    float shadow_high{0.0F};
    float dark_low{0.0F};
    float dark_high{0.0F};
    float light_low{0.0F};
    float light_high{0.0F};
    float highlight_low{0.0F};
    float highlight_high{0.0F};
};

static_assert(
    sizeof(ParametricToneCurveConstants) % 16U == 0U,
    "constant buffers are 16-byte aligned");

[[nodiscard]] bool finite_basic(const GpuBasicToneParameters& parameters) noexcept {
    return std::isfinite(parameters.contrast) && std::isfinite(parameters.density) &&
        std::isfinite(parameters.highlights) && std::isfinite(parameters.shadows) &&
        std::isfinite(parameters.whites) && std::isfinite(parameters.blacks);
}

// CPU 판은 매개변수와 밴드를 **따로** 검사합니다(`finite_curve_parameters`·`finite_bands`).
// 둘 중 하나만 검사하면 밴드에 NaN 이 들어와 마스크가 통째로 죽습니다.
[[nodiscard]] bool finite_curve(const GpuParametricToneCurveParameters& parameters) noexcept {
    return std::isfinite(parameters.highlights) && std::isfinite(parameters.lights) &&
        std::isfinite(parameters.darks) && std::isfinite(parameters.shadows) &&
        std::isfinite(parameters.shadow_low) && std::isfinite(parameters.shadow_high) &&
        std::isfinite(parameters.dark_low) && std::isfinite(parameters.dark_high) &&
        std::isfinite(parameters.light_low) && std::isfinite(parameters.light_high) &&
        std::isfinite(parameters.highlight_low) && std::isfinite(parameters.highlight_high);
}

}  // namespace

GpuKernelStatus GpuBasicTone::create(const GpuDevice& device, GpuBasicTone& kernel) noexcept {
    return GpuPointwiseKernel::create(
        device,
        negaflow_basic_tone_cs,
        sizeof(negaflow_basic_tone_cs),
        sizeof(BasicToneConstants),
        kernel.kernel_);
}

GpuKernelStatus GpuBasicTone::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage& destination,
    const GpuBasicToneParameters& parameters) const noexcept {
    if (!finite_basic(parameters)) {
        // CPU 판 `apply_basic_tone` 과 같은 판정입니다. 조용히 0 으로 바꾸지 않습니다.
        return GpuKernelStatus::non_finite_parameter;
    }
    BasicToneConstants payload{};
    payload.contrast = parameters.contrast;
    payload.density = parameters.density;
    payload.highlights = parameters.highlights;
    payload.shadows = parameters.shadows;
    payload.whites = parameters.whites;
    payload.blacks = parameters.blacks;
    return kernel_.dispatch(device, source, destination, &payload, sizeof(payload));
}

GpuKernelStatus GpuParametricToneCurve::create(
    const GpuDevice& device,
    GpuParametricToneCurve& kernel) noexcept {
    return GpuPointwiseKernel::create(
        device,
        negaflow_parametric_tone_curve_cs,
        sizeof(negaflow_parametric_tone_curve_cs),
        sizeof(ParametricToneCurveConstants),
        kernel.kernel_);
}

GpuKernelStatus GpuParametricToneCurve::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage& destination,
    const GpuParametricToneCurveParameters& parameters) const noexcept {
    if (!finite_curve(parameters)) {
        return GpuKernelStatus::non_finite_parameter;
    }
    ParametricToneCurveConstants payload{};
    payload.highlights = parameters.highlights;
    payload.lights = parameters.lights;
    payload.darks = parameters.darks;
    payload.shadows = parameters.shadows;
    payload.shadow_low = parameters.shadow_low;
    payload.shadow_high = parameters.shadow_high;
    payload.dark_low = parameters.dark_low;
    payload.dark_high = parameters.dark_high;
    payload.light_low = parameters.light_low;
    payload.light_high = parameters.light_high;
    payload.highlight_low = parameters.highlight_low;
    payload.highlight_high = parameters.highlight_high;
    return kernel_.dispatch(device, source, destination, &payload, sizeof(payload));
}

}  // namespace negaflow::gpu
