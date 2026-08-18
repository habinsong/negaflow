#include "negaflow/gpu/gpu_film_emulation_acutance.h"

// fxc 가 만든 헤더는 `const BYTE ...[]` 로 나오므로 Windows 타입이 먼저 보여야 합니다.
#include <windows.h>

#include <cmath>
#include <cstddef>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/film_emulation_acutance_AcutanceHorizontalMain.h"
#include "negaflow/gpu/shaders/film_emulation_acutance_AcutanceVerticalMain.h"

namespace negaflow::gpu {
namespace {

constexpr std::size_t tap_count = imaging::film_emulation_acutance_scratch_rows;
constexpr std::size_t weight_vectors = 3U;

// HLSL `cbuffer FilmEmulationAcutanceConstants` 와 같은 배치여야 합니다.
struct alignas(16) AcutanceConstants final {
    GpuPointwiseExtent extent{};
    float weights[weight_vectors][4]{};
    float amount{0.0F};
    float padding[3]{0.0F, 0.0F, 0.0F};
};

static_assert(sizeof(AcutanceConstants) == 80U, "extent + three weight vectors + amount");
static_assert(tap_count == 11U, "shader unrolls eleven taps");

}  // namespace

GpuKernelStatus GpuFilmEmulationAcutance::create(
    const GpuDevice& device,
    GpuFilmEmulationAcutance& kernel) noexcept {
    if (GpuPointwiseKernel::create(
            device,
            negaflow_acutance_horizontal_cs,
            sizeof(negaflow_acutance_horizontal_cs),
            sizeof(AcutanceConstants),
            kernel.horizontal_) != GpuKernelStatus::ok) {
        return GpuKernelStatus::resource_creation_failed;
    }
    if (GpuPointwiseKernel::create(
            device,
            negaflow_acutance_vertical_cs,
            sizeof(negaflow_acutance_vertical_cs),
            sizeof(AcutanceConstants),
            kernel.vertical_) != GpuKernelStatus::ok) {
        return GpuKernelStatus::resource_creation_failed;
    }
    return GpuKernelStatus::ok;
}

GpuKernelStatus GpuFilmEmulationAcutance::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage* const scratch,
    GpuWorkingImage& destination,
    const imaging::FilmEmulationAcutanceSetup& setup) const noexcept {
    if (!is_valid()) {
        return GpuKernelStatus::device_unavailable;
    }
    if (scratch == nullptr || !setup.applied) {
        return GpuKernelStatus::invalid_arguments;
    }
    if (!std::isfinite(setup.amount)) {
        return GpuKernelStatus::non_finite_parameter;
    }

    AcutanceConstants payload{};
    for (std::size_t index = 0U; index < tap_count; ++index) {
        if (!std::isfinite(setup.weights[index])) {
            return GpuKernelStatus::non_finite_parameter;
        }
        payload.weights[index >> 2U][index & 3U] = setup.weights[index];
    }
    payload.amount = setup.amount;

    if (horizontal_.dispatch(device, source, scratch[0], &payload, sizeof(payload)) !=
        GpuKernelStatus::ok) {
        return GpuKernelStatus::resource_creation_failed;
    }
    // 수직 패스는 수평 결과(`t0`)와 원본(`t1`) 둘을 읽습니다.
    return vertical_.dispatch_pair(
        device, scratch[0], source, destination, &payload, sizeof(payload));
}

}  // namespace negaflow::gpu
