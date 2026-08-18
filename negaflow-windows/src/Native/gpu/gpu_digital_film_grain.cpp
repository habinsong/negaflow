#include "negaflow/gpu/gpu_digital_film_grain.h"

// fxc 가 만든 헤더는 `const BYTE ...[]` 로 나오므로 Windows 타입이 먼저 보여야 합니다.
#include <windows.h>

#include <algorithm>
#include <cmath>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/digital_film_grain_DigitalFilmGrainMain.h"

namespace negaflow::gpu {
namespace {

// HLSL `cbuffer DigitalFilmGrainConstants` 와 같은 배치여야 합니다.
struct alignas(16) DigitalFilmGrainConstants final {
    GpuPointwiseExtent extent{};
    float amplitude{0.0F};
    float chroma_ratio{0.0F};
    float size{1.0F};
    float padding{0.0F};
};

static_assert(sizeof(DigitalFilmGrainConstants) == 32U, "two constant registers");

}  // namespace

GpuDigitalFilmGrain::Parameters GpuDigitalFilmGrain::resolve(
    const imaging::DigitalFilmGrainProfile& profile,
    const double strength) noexcept {
    Parameters parameters{};
    // CPU 판의 매개변수 검증(`apply_digital_film_grain_material:110-118`)과 같은 판정입니다.
    if (!std::isfinite(strength) || !std::isfinite(profile.amplitude) ||
        !std::isfinite(profile.chroma_ratio) || !std::isfinite(profile.size) ||
        profile.amplitude < 0.0 || profile.chroma_ratio < 0.0 ||
        profile.chroma_ratio > 1.0 || profile.size <= 0.0) {
        return parameters;
    }
    const double bounded = std::clamp(strength, 0.0, 1.0);
    // ☠️ 조기 반환을 그대로 옮깁니다(`:130-133`). 여기서 커널을 돌리면 CPU 가 손대지 않는
    //    화소에 반올림이 붙습니다 — `colorMixerHSL` 이 delta 0.1 로 깨졌던 것과 같은 함정입니다.
    if (profile.amplitude <= 0.0 || bounded <= 1.0e-3) {
        return parameters;
    }
    parameters.amplitude = static_cast<float>(profile.amplitude * bounded);
    parameters.chroma_ratio = static_cast<float>(profile.chroma_ratio);
    parameters.size = static_cast<float>(profile.size);
    parameters.applied = true;
    return parameters;
}

GpuKernelStatus GpuDigitalFilmGrain::create(
    const GpuDevice& device,
    GpuDigitalFilmGrain& kernel) noexcept {
    return GpuPointwiseKernel::create(
        device,
        negaflow_digital_film_grain_cs,
        sizeof(negaflow_digital_film_grain_cs),
        sizeof(DigitalFilmGrainConstants),
        kernel.kernel_);
}

GpuKernelStatus GpuDigitalFilmGrain::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage& destination,
    const Parameters& parameters) const noexcept {
    if (!std::isfinite(parameters.amplitude) || !std::isfinite(parameters.chroma_ratio) ||
        !std::isfinite(parameters.size) || parameters.size <= 0.0F) {
        return GpuKernelStatus::non_finite_parameter;
    }
    DigitalFilmGrainConstants payload{};
    payload.amplitude = parameters.amplitude;
    payload.chroma_ratio = parameters.chroma_ratio;
    payload.size = parameters.size;
    return kernel_.dispatch(device, source, destination, &payload, sizeof(payload));
}

}  // namespace negaflow::gpu
