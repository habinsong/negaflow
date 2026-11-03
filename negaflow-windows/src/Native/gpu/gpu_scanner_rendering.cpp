#include "negaflow/gpu/gpu_scanner_rendering.h"

// fxc 가 만든 헤더는 `const BYTE ...[]` 로 나오므로 Windows 타입이 먼저 보여야 합니다.
#include <windows.h>

#include <cmath>
#include <cstddef>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/scanner_rendering_ScannerRenderingMain.h"

namespace negaflow::gpu {
namespace {

using Setup = imaging::ScannerRenderingSetup;

// HLSL `cbuffer ScannerRenderingConstants` 와 같은 배치여야 합니다.
struct alignas(16) ScannerRenderingConstants final {
    GpuPointwiseExtent extent{};
    float tone_ys[3][4]{};
    float tone_ms[3][4]{};
    float gain_ys[4]{};
    float gain_ms[4]{};
    float crosstalk0[4]{};
    float crosstalk1[4]{};
    float red_ys[4]{};
    float red_ms[4]{};
    float blue_ys[4]{};
    float blue_ms[4]{};
};

static_assert(sizeof(ScannerRenderingConstants) == 16U + 48U + 48U + (16U * 8U),
              "constant layout must match the shader");
static_assert(Setup::tone_knots == 11U && Setup::gain_knots == 4U && Setup::balance_knots == 3U,
              "shader knot counts");

template <std::size_t N>
[[nodiscard]] bool all_finite(const float (&values)[N]) noexcept {
    for (const float value : values) {
        if (!std::isfinite(value)) return false;
    }
    return true;
}

} // namespace

GpuKernelStatus GpuScannerRendering::create(
    const GpuDevice& device,
    GpuScannerRendering& kernel) noexcept {
    return GpuPointwiseKernel::create(
        device,
        negaflow_scanner_rendering_cs,
        sizeof(negaflow_scanner_rendering_cs),
        sizeof(ScannerRenderingConstants),
        kernel.kernel_);
}

GpuKernelStatus GpuScannerRendering::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage& destination,
    const Setup& setup) const noexcept {
    if (!all_finite(setup.tone_ys) || !all_finite(setup.tone_ms) ||
        !all_finite(setup.gain_ys) || !all_finite(setup.gain_ms) ||
        !all_finite(setup.crosstalk) || !all_finite(setup.red_ys) ||
        !all_finite(setup.red_ms) || !all_finite(setup.blue_ys) ||
        !all_finite(setup.blue_ms) || !std::isfinite(setup.strength)) {
        return GpuKernelStatus::non_finite_parameter;
    }
    ScannerRenderingConstants payload{};
    for (std::size_t i = 0U; i < Setup::tone_knots; ++i) {
        payload.tone_ys[i >> 2U][i & 3U] = setup.tone_ys[i];
        payload.tone_ms[i >> 2U][i & 3U] = setup.tone_ms[i];
    }
    for (std::size_t i = 0U; i < Setup::gain_knots; ++i) {
        payload.gain_ys[i] = setup.gain_ys[i];
        payload.gain_ms[i] = setup.gain_ms[i];
    }
    for (std::size_t i = 0U; i < 4U; ++i) {
        payload.crosstalk0[i] = setup.crosstalk[i];
    }
    payload.crosstalk1[0] = setup.crosstalk[4];
    payload.crosstalk1[1] = setup.crosstalk[5];
    payload.crosstalk1[2] = setup.strength;
    payload.crosstalk1[3] = setup.monochrome ? 1.0F : 0.0F;
    for (std::size_t i = 0U; i < Setup::balance_knots; ++i) {
        payload.red_ys[i] = setup.red_ys[i];
        payload.red_ms[i] = setup.red_ms[i];
        payload.blue_ys[i] = setup.blue_ys[i];
        payload.blue_ms[i] = setup.blue_ms[i];
    }
    return kernel_.dispatch(device, source, destination, &payload, sizeof(payload));
}

} // namespace negaflow::gpu
