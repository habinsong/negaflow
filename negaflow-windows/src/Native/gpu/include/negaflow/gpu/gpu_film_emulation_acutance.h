#pragma once

// 필름 스톡 아큐턴스(분리형 11탭 가우시안 언샤프)의 GPU 판입니다.
//
// CPU 판 : `imaging/film_emulation_acutance.cpp` `apply_film_emulation_acutance`
// 셰이더 : `shaders/film_emulation_acutance.hlsl`
//
// 가중치와 세기는 **CPU 의 `prepare_film_emulation_acutance` 가 만든 것을 그대로** 씁니다.
// 여기서 다시 만들면 두 벌이 되고 `exp` 구현 차이가 화소마다 실립니다.
//
// ☠️ **근사한 것입니다.** CPU 는 두 패스를 `double` 로 누적하고 GPU 는 float 입니다.

#include "negaflow/gpu/gpu_pointwise.h"
#include "negaflow/imaging/film_emulation_acutance.h"

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

class GpuFilmEmulationAcutance final {
public:
    // 수평 결과를 담을 중간 텍스처 한 장.
    static constexpr int scratch_count = 1;

    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuFilmEmulationAcutance& kernel) noexcept;

    // `scratch` 는 `scratch_count` 장이고 `source` 와 같은 크기여야 합니다.
    // `destination` 은 `source`·`scratch` 와 달라야 합니다.
    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage* scratch,
        GpuWorkingImage& destination,
        const imaging::FilmEmulationAcutanceSetup& setup) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept {
        return horizontal_.is_valid() && vertical_.is_valid();
    }

private:
    GpuPointwiseKernel horizontal_{};
    GpuPointwiseKernel vertical_{};
};

}  // namespace negaflow::gpu
