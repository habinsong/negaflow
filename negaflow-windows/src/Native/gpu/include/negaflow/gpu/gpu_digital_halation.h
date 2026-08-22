#pragma once

// macOS `digitalHalation`(`ChromabaseMetalKernels.swift:712`) 와
// Windows CPU `imaging/digital_halation.cpp` `apply_digital_halation_material` 입니다.
//
// 원본을 세 반경으로 흐려 산란·헐레이션을 재분배합니다. 블러는 `GpuGaussianBlur` 가
// 하고, 이 클래스는 **덜어내기와 누적**만 합니다 — macOS 도 그렇게 나눠 놓았습니다.
//
// 가중치는 `GpuGaussianBlur::weights_for_halation_sigma` 로 만듭니다.
// `weights_for_sigma`(Core Image 판)와 **다른 식**입니다. 섞으면 값이 갈립니다.
//
// 주의 CPU 는 512px 타일로 돌지만 여기는 전체를 한 번에 돌아도 됩니다 —
// 이 가우시안은 **직접 컨볼루션이라 누적 이력이 없습니다.**
// (러닝 섬을 쓰는 `film_scan_denoise` 와 다릅니다. `gpu_film_scan.h` 의 경고 참고.)

#include <array>
#include <cstdint>

#include "negaflow/gpu/gpu_neighborhood.h"
#include "negaflow/gpu/gpu_pointwise.h"
#include "negaflow/imaging/digital_halation.h"

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

class GpuDigitalHalation final {
public:
    // 중간 텍스처를 몇 장 쓰는지. 호출부가 미리 잡아 두라고 공개합니다.
    static constexpr int scratch_count = 4;

    // 이미지마다 한 번 정해지는 값들입니다.
    // `apply_digital_halation_material:219-263` 이 화소 루프 밖에서 계산하는 것과 같습니다.
    struct Parameters final {
        // `max(1 - scatter - halation, 0)` — 호스트에서 계산합니다.
        std::array<float, 3> keep{};
        std::array<float, 3> scatter{};
        std::array<float, 3> far_scale{};
        std::array<float, 3> wide_scale{};
        float near_sigma{0.0F};
        float far_sigma{0.0F};
        float wide_sigma{0.0F};
        // CPU 의 조기 반환과 같은 자리입니다 — 세기가 너무 작거나 이미지가 너무 작거나
        // 반경 비율이 0 이면 **원본 그대로**입니다. 커널을 돌리면 반올림이 붙습니다.
        bool applied{false};
    };

    [[nodiscard]] static Parameters resolve(
        const imaging::DigitalHalationMaterial& material,
        double strength,
        std::uint32_t width,
        std::uint32_t height) noexcept;

    GpuDigitalHalation() noexcept = default;
    ~GpuDigitalHalation();

    GpuDigitalHalation(const GpuDigitalHalation&) = delete;
    GpuDigitalHalation& operator=(const GpuDigitalHalation&) = delete;
    GpuDigitalHalation(GpuDigitalHalation&& other) noexcept;
    GpuDigitalHalation& operator=(GpuDigitalHalation&& other) noexcept;

    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuDigitalHalation& kernel) noexcept;

    // `scratch` 는 `scratch_count` 장이어야 하고 전부 `source` 와 같은 크기여야 합니다.
    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuGaussianBlur& gaussian,
        const GpuWorkingImage& source,
        GpuWorkingImage* scratch,
        GpuWorkingImage& destination,
        const Parameters& parameters) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return base_ != nullptr; }

private:
    void reset() noexcept;

    // 누적 패스가 SRV 를 **둘** 묶으므로 `GpuPointwiseKernel`(하나) 을 쓸 수 없습니다.
    ID3D11ComputeShader* base_{nullptr};
    ID3D11ComputeShader* accumulate_{nullptr};
    ID3D11Buffer* constants_{nullptr};
};

} // namespace negaflow::gpu
