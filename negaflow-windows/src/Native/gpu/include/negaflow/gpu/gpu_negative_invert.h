#pragma once

// 네거티브 반전의 GPU 판입니다.
//
// macOS : `ChromabaseMetalKernels.swift:557` `negativeInvert`
// CPU 판 : `core/negative_inversion.cpp` `apply_negative_inversion` / `invert_channel`
// 셰이더 : `src/Native/gpu/shaders/negative_invert.hlsl`
//
// CPU 판 주석이 적은 대로 **현상 전체에서 가장 비싼 단계**입니다(16MP 기준, 거의 전부 초월함수).
//
// 주의 CPU 판은 화소마다 결과가 유한한지 보고 아니면 `non_finite_output` 으로 전체를 실패시킵니다.
// GPU 판에는 그 경로가 **없습니다.** 호출부는 CPU 쪽 매개변수 검증을 그대로 유지해야 합니다.

#include "negaflow/gpu/gpu_pointwise.h"

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

// `core::NegativeInversionParameters` + `core::PrintResponse` 중 커널이 실제로 쓰는 값만
// 옮겨 담은 것입니다. gpu 라이브러리가 core 의 전체 구조체에 묶이지 않도록 여기 둡니다.
//
// `PrintResponse` 의 나머지 필드(`normal_range`·`base_toe`·`white_output`·`ceiling`)는
// 이 커널이 쓰지 않습니다. macOS 커널도 `response` 를 `float4(yCeil, amplitude, rate, shape)`
// 넷만 받습니다. 나머지를 여기 끌어오지 마십시오.
struct GpuNegativeInvertParameters final {
    float dmin[3]{1.0F, 1.0F, 1.0F};
    float dmax_normalized[3]{1.0F, 1.0F, 1.0F};
    float response_y_ceiling{0.0F};
    float response_amplitude{0.0F};
    float response_rate{0.0F};
    float response_shape{0.0F};
};

class GpuNegativeInvert final {
public:
    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuNegativeInvert& kernel) noexcept;

    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination,
        const GpuNegativeInvertParameters& parameters) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return kernel_.is_valid(); }

private:
    GpuPointwiseKernel kernel_{};
};

} // namespace negaflow::gpu
