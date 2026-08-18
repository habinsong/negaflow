#pragma once

// 톤 커널 두 개의 GPU 판입니다. 둘 다 `stages/look.cpp` 의
// `apply_working_tone_adjustments` 경로에 있고, 우측 인스펙터 슬라이더가 직접 미는 곳입니다.
//
// | | macOS | Windows CPU | 셰이더 |
// |---|---|---|---|
// | 기본 톤 | `ChromabaseMetalKernels.swift:185` `basicTone` | `imaging/tone_mapping.cpp:79` `apply_basic_tone` | `shaders/basic_tone.hlsl` |
// | 파라메트릭 커브 | `:242` `parametricToneCurve` | `:143` `apply_parametric_tone_curve` | `shaders/parametric_tone_curve.hlsl` |
//
// CPU 판을 **대체하지 않습니다.** 나란히 두고 상위에서 장치 가용성으로 고릅니다.
// 두 경로의 화소값은 동치 시험이 허용 오차 `1e-5` 로 묶습니다.

#include "negaflow/gpu/gpu_pointwise.h"

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

// `imaging::BasicToneParameters` 와 같은 값입니다. gpu 라이브러리가 imaging 에 의존하지
// 않도록(의존 방향이 반대여야 합니다) 같은 모양으로 여기 둡니다. 호출부가 옮겨 담습니다.
struct GpuBasicToneParameters final {
    float contrast{0.0F};
    float density{0.0F};
    float highlights{0.0F};
    float shadows{0.0F};
    float whites{0.0F};
    float blacks{0.0F};
};

// `imaging::ParametricToneCurveParameters` + `ParametricToneCurveBands` 를 합친 것입니다.
// macOS 커널이 밴드 경계 8개를 인자로 받으므로 여기서도 인자입니다 — 상수로 박지 마십시오.
struct GpuParametricToneCurveParameters final {
    float highlights{0.0F};
    float lights{0.0F};
    float darks{0.0F};
    float shadows{0.0F};
    float shadow_low{0.05F};
    float shadow_high{0.24F};
    float dark_low{0.18F};
    float dark_high{0.36F};
    float light_low{0.34F};
    float light_high{0.68F};
    float highlight_low{0.36F};
    float highlight_high{0.50F};
};

class GpuBasicTone final {
public:
    [[nodiscard]] static GpuKernelStatus create(const GpuDevice& device, GpuBasicTone& kernel) noexcept;

    // `source` 를 읽어 `destination` 에 씁니다. 같은 자원을 넘기면 거절합니다 —
    // D3D11 은 한 자원을 SRV 와 UAV 로 동시에 묶을 수 없어 핑퐁 두 장이 필요합니다.
    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination,
        const GpuBasicToneParameters& parameters) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return kernel_.is_valid(); }

private:
    GpuPointwiseKernel kernel_{};
};

class GpuParametricToneCurve final {
public:
    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuParametricToneCurve& kernel) noexcept;

    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination,
        const GpuParametricToneCurveParameters& parameters) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return kernel_.is_valid(); }

private:
    GpuPointwiseKernel kernel_{};
};

}  // namespace negaflow::gpu
