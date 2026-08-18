#pragma once

// 밀도 의존 그레인의 GPU 판입니다.
//
// macOS  : `ChromabaseMetalKernels.swift:800` `digitalFilmGrainDensity`
// CPU 판 : `imaging/digital_film_grain.cpp` `apply_digital_film_grain_material`
// 셰이더 : `src/Native/gpu/shaders/digital_film_grain.hlsl`
//
// ☠️ **노이즈의 기준은 Apple 이 아니라 Windows CPU 필드입니다.**
//    macOS 는 `CIRandomGenerator` 를 받는데 그 수열은 비공개입니다 — 공식 문서에 필터의
//    존재와 파라미터만 있고 알고리즘·수열이 없으며, 역공개 자료도 찾지 못했습니다.
//    그래서 `digital_film_grain.h` 가 *"statistical, not pixel-exact"* 를 이미 계약으로
//    적어 두었고, 이 GPU 판이 맞춰야 하는 상대는 **좌표 해시 CPU 필드**입니다.
//    해시는 전부 uint32 정수라 **비트 단위로 같아야** 하고, 시험이 그것을 따로 겁니다.
//
// ☠️ **근사한 것입니다.** 밀도 응답이 `log10`·`sqrt`·`exp`·`pow` 라 CPU 와 마지막 비트가
//    다를 수 있습니다. `ApproximateAcceleratorScope` 안에서만 도는 자리에 배선하십시오.

#include <cstdint>

#include "negaflow/gpu/gpu_pointwise.h"
#include "negaflow/imaging/digital_film_physics.h"

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

class GpuDigitalFilmGrain final {
public:
    // 이미지마다 한 번 정해지는 값입니다. `apply_digital_film_grain_material` 이
    // 화소 루프 **밖에서** 계산하는 것과 같은 자리입니다.
    struct Parameters final {
        // `profile.amplitude * clamp(strength, 0, 1)` 을 float 로 내린 값.
        float amplitude{0.0F};
        float chroma_ratio{0.0F};
        float size{1.0F};
        // CPU 의 조기 반환과 같습니다 — 진폭이 0 이거나 세기가 1e-3 이하이면
        // **원본 그대로**입니다. 커널을 돌리면 반올림이 붙습니다.
        bool applied{false};
    };

    [[nodiscard]] static Parameters resolve(
        const imaging::DigitalFilmGrainProfile& profile,
        double strength) noexcept;

    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuDigitalFilmGrain& kernel) noexcept;

    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination,
        const Parameters& parameters) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return kernel_.is_valid(); }

private:
    GpuPointwiseKernel kernel_{};
};

}  // namespace negaflow::gpu
