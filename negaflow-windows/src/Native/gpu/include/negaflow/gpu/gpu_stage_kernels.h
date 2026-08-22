#pragma once

// 톤 단계의 나머지 두 커널입니다. 이 둘이 있어야 우측 인스펙터의 톤 경로 전체가
// GPU 에 머문 채로 돕니다 — 노출 → 기본 톤 → 파라메트릭 커브 → 포인트 커브 →
// 컬러 믹서 → 컬러 그레이딩 → 원색 보정.
//
// | | macOS | Windows CPU | 셰이더 |
// |---|---|---|---|
// | 노출 | Core Image 곱셈(전용 커널 없음) | `core/pointwise.cpp` `apply_exposure` | `shaders/exposure.hlsl` |
// | 포인트 커브 | `PointCurveStage` | `imaging/point_curve.cpp` `apply_point_curves` | `shaders/point_curve.hlsl` |

#include <cstddef>

#include "negaflow/gpu/gpu_pointwise.h"

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

class GpuExposure final {
public:
    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuExposure& kernel) noexcept;

    // `stops` 는 CPU 판과 같은 스톱 값입니다. 배수(`exp2`)는 여기서 한 번 계산합니다 —
    // 셰이더에서 계산하면 `exp2` 구현 차이가 화소마다 실립니다.
    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination,
        float stops) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return kernel_.is_valid(); }

private:
    GpuPointwiseKernel kernel_{};
};

// `imaging::PointCurveLuts` 와 같은 값입니다.
//
// 커브에서 LUT 를 만드는 것은 **CPU 가 합니다**(`imaging::build_point_curve_luts`).
// 화소마다 같은 값이라 GPU 로 옮길 이유가 없고, 옮기면 두 벌이 되어 갈라집니다.
struct GpuPointCurveLuts final {
    static constexpr std::size_t lut_size = 64U;
    float red[lut_size]{};
    float green[lut_size]{};
    float blue[lut_size]{};
};

class GpuPointCurve final {
public:
    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuPointCurve& kernel) noexcept;

    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination,
        const GpuPointCurveLuts& luts) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return kernel_.is_valid(); }

private:
    GpuPointwiseKernel kernel_{};
};

} // namespace negaflow::gpu
