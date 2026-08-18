#pragma once

// 필름 스톡 색 큐브(33³ 3D LUT)의 GPU 판입니다.
//
// macOS  : `FilmEmulationStage` 의 `CIColorCube`
// CPU 판 : `imaging/film_emulation_color.cpp` `apply_film_emulation_color_cube`
// 셰이더 : `shaders/film_emulation_cube.hlsl`
//
// **큐브를 만드는 것은 CPU 가 합니다**(`build_film_emulation_color_cube`).
// 35,937 칸이고 프리셋·세기가 바뀔 때만 다시 만들어지므로 GPU 로 옮길 이유가 없고,
// 옮기면 두 벌이 되어 갈라집니다. 이 클래스는 **만들어진 표를 올리고 적용만** 합니다.
//
// ☠️ **근사한 것입니다**(sRGB 왕복의 `pow`). 표 자체와 보간은 CPU 와 같은 float
//    연산이라 그 자리에서는 오차가 안 생깁니다.

#include "negaflow/gpu/gpu_lookup_table.h"
#include "negaflow/gpu/gpu_pointwise.h"
#include "negaflow/imaging/film_emulation_color.h"

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

class GpuFilmEmulationCube final {
public:
    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuFilmEmulationCube& kernel) noexcept;

    // `cube` 는 CPU 가 만든 것을 그대로 받습니다. 내용이 바뀌었으면 올리고, 같으면
    // 올리지 않습니다 — 431 KB 를 프레임마다 밀어 넣을 이유가 없습니다.
    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination,
        const imaging::FilmEmulationColorCube& cube) noexcept;

    [[nodiscard]] bool is_valid() const noexcept {
        return kernel_.is_valid() && table_.is_valid();
    }

private:
    GpuPointwiseKernel kernel_{};
    GpuLookupTable table_{};
    // 지금 GPU 에 올라가 있는 표가 어느 것인지. CPU 큐브의 두 식별자와 같습니다.
    imaging::FilmEmulation loaded_emulation_{imaging::FilmEmulation::none};
    std::uint32_t loaded_intensity_step_{0U};
    bool loaded_{false};
};

}  // namespace negaflow::gpu
