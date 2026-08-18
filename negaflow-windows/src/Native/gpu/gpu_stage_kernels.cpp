#include "negaflow/gpu/gpu_stage_kernels.h"

// fxc 가 만든 헤더는 `const BYTE ...[]` 로 나오므로 Windows 타입이 먼저 보여야 합니다.
#include <windows.h>

#include <cmath>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/exposure_ExposureMain.h"
#include "negaflow/gpu/shaders/point_curve_PointCurveMain.h"

namespace negaflow::gpu {
namespace {

// HLSL `cbuffer ExposureConstants` 와 같은 배치여야 합니다.
struct alignas(16) ExposureConstants final {
    GpuPointwiseExtent extent{};
    float multiplier{1.0F};
    float padding[3]{0.0F, 0.0F, 0.0F};
};

static_assert(sizeof(ExposureConstants) == 32U, "two constant registers");

// HLSL `cbuffer PointCurveConstants` 와 같은 배치여야 합니다.
// 상수 버퍼의 배열은 원소마다 16바이트라 64샘플을 `float4[16]` 으로 묶습니다.
struct alignas(16) PointCurveConstants final {
    GpuPointwiseExtent extent{};
    float red[16][4]{};
    float green[16][4]{};
    float blue[16][4]{};
};

static_assert(sizeof(PointCurveConstants) == 784U, "extent + three 16-element float4 arrays");

void fill_lut(const float (&source)[GpuPointCurveLuts::lut_size], float (&destination)[16][4]) {
    for (std::size_t index = 0U; index < GpuPointCurveLuts::lut_size; ++index) {
        destination[index >> 2U][index & 3U] = source[index];
    }
}

[[nodiscard]] bool finite_lut(const float (&values)[GpuPointCurveLuts::lut_size]) noexcept {
    for (const float value : values) {
        if (!std::isfinite(value)) {
            return false;
        }
    }
    return true;
}

}  // namespace

GpuKernelStatus GpuExposure::create(const GpuDevice& device, GpuExposure& kernel) noexcept {
    return GpuPointwiseKernel::create(
        device,
        negaflow_exposure_cs,
        sizeof(negaflow_exposure_cs),
        sizeof(ExposureConstants),
        kernel.kernel_);
}

GpuKernelStatus GpuExposure::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage& destination,
    const float stops) const noexcept {
    // CPU 판 `apply_exposure` 와 같은 두 단계 판정입니다 — 스톱이 유한한지 보고,
    // 그 다음 배수가 유한한지 봅니다. 큰 스톱은 `exp2` 에서 무한이 될 수 있습니다.
    if (!std::isfinite(stops)) {
        return GpuKernelStatus::non_finite_parameter;
    }
    const float multiplier = std::exp2(stops);
    if (!std::isfinite(multiplier)) {
        return GpuKernelStatus::non_finite_parameter;
    }
    ExposureConstants payload{};
    payload.multiplier = multiplier;
    return kernel_.dispatch(device, source, destination, &payload, sizeof(payload));
}

GpuKernelStatus GpuPointCurve::create(const GpuDevice& device, GpuPointCurve& kernel) noexcept {
    return GpuPointwiseKernel::create(
        device,
        negaflow_point_curve_cs,
        sizeof(negaflow_point_curve_cs),
        sizeof(PointCurveConstants),
        kernel.kernel_);
}

GpuKernelStatus GpuPointCurve::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage& destination,
    const GpuPointCurveLuts& luts) const noexcept {
    if (!finite_lut(luts.red) || !finite_lut(luts.green) || !finite_lut(luts.blue)) {
        return GpuKernelStatus::non_finite_parameter;
    }
    PointCurveConstants payload{};
    fill_lut(luts.red, payload.red);
    fill_lut(luts.green, payload.green);
    fill_lut(luts.blue, payload.blue);
    return kernel_.dispatch(device, source, destination, &payload, sizeof(payload));
}

}  // namespace negaflow::gpu
