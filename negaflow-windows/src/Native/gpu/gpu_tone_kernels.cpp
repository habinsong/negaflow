#include "negaflow/gpu/gpu_tone_kernels.h"

// fxc 가 만든 헤더는 `const BYTE ...[]` 로 나오므로 Windows 타입이 먼저 보여야 합니다.
#include <windows.h>

#include <cmath>
#include <cstddef>

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
// 매듭 자리·값(float4 둘)과 기울기 여섯(float4 둘, 마지막 칸은 비움)입니다.
struct alignas(16) ParametricToneCurveConstants final {
    GpuPointwiseExtent extent{};
    float knot_x[4]{};
    float knot_y[4]{};
    float tangent_low[4]{};
    float tangent_high[4]{};
};

static_assert(
    sizeof(ParametricToneCurveConstants) == 80U,
    "extent + four float4 registers, same as the HLSL cbuffer");

[[nodiscard]] bool finite_basic(const GpuBasicToneParameters& parameters) noexcept {
    return std::isfinite(parameters.contrast) && std::isfinite(parameters.density) &&
        std::isfinite(parameters.highlights) && std::isfinite(parameters.shadows) &&
        std::isfinite(parameters.whites) && std::isfinite(parameters.blacks);
}

// CPU 판은 매개변수와 매듭을 **따로** 검사합니다(`finite_curve_parameters`·`finite_bands`).
// 여기서는 풀린 매듭이 유한하고 자리가 (0,1) 안에서 증가하는지 봅니다 — 구간 폭이 0 이면 나눗셈이
// 터집니다.
[[nodiscard]] bool finite_curve(const GpuParametricToneCurveParameters& parameters) noexcept {
    float previous = 0.0F;
    for (std::size_t i = 0U; i < 4U; ++i) {
        if (!std::isfinite(parameters.knot_x[i]) || !std::isfinite(parameters.knot_y[i]) ||
            parameters.knot_x[i] <= previous || parameters.knot_x[i] >= 1.0F) {
            return false;
        }
        previous = parameters.knot_x[i];
    }
    for (const float tangent : parameters.tangent) {
        if (!std::isfinite(tangent)) {
            return false;
        }
    }
    return true;
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
    for (std::size_t i = 0U; i < 4U; ++i) {
        payload.knot_x[i] = parameters.knot_x[i];
        payload.knot_y[i] = parameters.knot_y[i];
    }
    for (std::size_t i = 0U; i < 3U; ++i) {
        payload.tangent_low[i] = parameters.tangent[i];
        payload.tangent_high[i] = parameters.tangent[i + 3U];
    }
    return kernel_.dispatch(device, source, destination, &payload, sizeof(payload));
}

GpuParametricToneCurveParameters make_gpu_parametric_tone_curve(
    const imaging::ParametricToneCurveParameters& parameters,
    const imaging::ParametricToneCurveBands& bands) noexcept {
    const imaging::ParametricToneCurveShape shape = imaging::parametric_tone_curve_shape(parameters, bands);
    GpuParametricToneCurveParameters gpu{};
    for (std::size_t i = 0U; i < 4U; ++i) {
        gpu.knot_x[i] = static_cast<float>(shape.x[i + 1U]);
        gpu.knot_y[i] = static_cast<float>(shape.y[i + 1U]);
    }
    for (std::size_t i = 0U; i < 6U; ++i) {
        gpu.tangent[i] = static_cast<float>(shape.tangent[i]);
    }
    return gpu;
}

}  // namespace negaflow::gpu
