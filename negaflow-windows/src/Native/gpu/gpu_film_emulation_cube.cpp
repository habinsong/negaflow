#include "negaflow/gpu/gpu_film_emulation_cube.h"

// fxc 가 만든 헤더는 `const BYTE ...[]` 로 나오므로 Windows 타입이 먼저 보여야 합니다.
#include <windows.h>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/film_emulation_cube_FilmEmulationCubeMain.h"

namespace negaflow::gpu {
namespace {

// HLSL `cbuffer FilmEmulationCubeConstants` 와 같은 배치여야 합니다.
struct alignas(16) CubeConstants final {
    GpuPointwiseExtent extent{};
};

static_assert(sizeof(CubeConstants) == 16U, "one constant register");

// 셰이더의 `StructuredBuffer<float3>` 원소 크기와 같아야 합니다.
static_assert(
    sizeof(imaging::FilmEmulationCubeEntry) == 12U,
    "cube entry must stay three floats — the shader binds it as StructuredBuffer<float3>");

}  // namespace

GpuKernelStatus GpuFilmEmulationCube::create(
    const GpuDevice& device,
    GpuFilmEmulationCube& kernel) noexcept {
    if (GpuPointwiseKernel::create(
            device,
            negaflow_film_emulation_cube_cs,
            sizeof(negaflow_film_emulation_cube_cs),
            sizeof(CubeConstants),
            kernel.kernel_) != GpuKernelStatus::ok) {
        return GpuKernelStatus::resource_creation_failed;
    }
    if (GpuLookupTable::create(
            device,
            imaging::film_emulation_cube_entry_count,
            sizeof(imaging::FilmEmulationCubeEntry),
            kernel.table_) != GpuKernelStatus::ok) {
        return GpuKernelStatus::resource_creation_failed;
    }
    kernel.loaded_ = false;
    return GpuKernelStatus::ok;
}

GpuKernelStatus GpuFilmEmulationCube::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage& destination,
    const imaging::FilmEmulationColorCube& cube) noexcept {
    if (!is_valid()) {
        return GpuKernelStatus::device_unavailable;
    }
    // CPU 판의 관문과 같습니다 — 표가 준비돼 있지 않으면 커널을 돌리지 않습니다.
    if (!cube.ready) {
        return GpuKernelStatus::invalid_arguments;
    }
    if (!loaded_ || loaded_emulation_ != cube.emulation ||
        loaded_intensity_step_ != cube.intensity_step) {
        if (table_.upload(
                device, cube.entries.data(), imaging::film_emulation_cube_entry_count) !=
            GpuKernelStatus::ok) {
            return GpuKernelStatus::resource_creation_failed;
        }
        loaded_emulation_ = cube.emulation;
        loaded_intensity_step_ = cube.intensity_step;
        loaded_ = true;
    }

    CubeConstants payload{};
    return kernel_.dispatch_with_extra(
        device, source, table_.srv(), destination, &payload, sizeof(payload));
}

}  // namespace negaflow::gpu
