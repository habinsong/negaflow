#include "negaflow/gpu/gpu_vibrance.h"

// fxc 가 만든 헤더는 `const BYTE ...[]` 로 나오므로 Windows 타입이 먼저 보여야 합니다.
#include <windows.h>

#include <cmath>
#include <cstddef>
#include <vector>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/color_model_ColorModelMain.h"
#include "negaflow/gpu/shaders/muted_scene_vibrance_MutedSceneVibranceMain.h"
#include "negaflow/imaging/muted_scene_vibrance.h"
#include "negaflow/imaging/muted_scene_vibrance_table.h"

namespace negaflow::gpu {
namespace {

using negaflow::imaging::detail::vibrance_table_entry_count;
using negaflow::imaging::detail::vibrance_table_g;
using negaflow::imaging::detail::vibrance_table_quantum;

// CPU 판의 `identity_threshold`(`color_model.cpp:16`)와 같은 값이어야 합니다.
constexpr float identity_threshold = 1.0e-3F;

// HLSL `cbuffer MutedSceneVibranceConstants` 와 같은 배치여야 합니다.
struct alignas(16) MutedSceneVibranceConstants final {
    GpuPointwiseExtent extent{};
    float amount{0.0F};
    float blend{0.0F};
    float quantum{0.0F};
    std::uint32_t low{0U};
};

static_assert(sizeof(MutedSceneVibranceConstants) == 32U, "two constant registers");

// HLSL `cbuffer ColorModelConstants` 와 같은 배치여야 합니다.
struct alignas(16) ColorModelConstants final {
    GpuPointwiseExtent extent{};
    float warmth{0.0F};
    float tint{0.0F};
    float color_depth{0.0F};
    float vibrance{0.0F};
    float saturation{0.0F};
    float red_primary{0.0F};
    float green_primary{0.0F};
    float blue_primary{0.0F};
    std::uint32_t gates{0U};
    std::uint32_t vibrance_low{0U};
    float vibrance_blend{0.0F};
    float vibrance_quantum{0.0F};
    float vibrance_amount{0.0F};
    float padding[3]{0.0F, 0.0F, 0.0F};
};

static_assert(sizeof(ColorModelConstants) == 80U, "five constant registers");

} // namespace

GpuKernelStatus GpuVibranceTable::create(
    const GpuDevice& device,
    GpuVibranceTable& table) noexcept {
    if (GpuLookupTable::create(
            device, vibrance_table_entry_count, sizeof(float), table.table_) !=
        GpuKernelStatus::ok) {
        return GpuKernelStatus::resource_creation_failed;
    }
    // 표는 `uint16` 이고 CPU 는 읽을 때마다 `static_cast<float>` 합니다. 셰이더에서
    // 언패킹하면 화소마다 비트 연산이 붙으므로 **한 번 펴서** 올립니다. 값은 같습니다 —
    // `uint16` 은 float 로 정확히 표현됩니다.
    std::vector<float> flattened;
    try {
        flattened.resize(vibrance_table_entry_count);
    } catch (...) {
        return GpuKernelStatus::resource_creation_failed;
    }
    for (std::size_t index = 0U; index < vibrance_table_entry_count; ++index) {
        flattened[index] = static_cast<float>(vibrance_table_g[index]);
    }
    if (table.table_.upload(device, flattened.data(), vibrance_table_entry_count) !=
        GpuKernelStatus::ok) {
        return GpuKernelStatus::resource_creation_failed;
    }
    return GpuKernelStatus::ok;
}

GpuKernelStatus GpuMutedSceneVibrance::create(
    const GpuDevice& device,
    GpuMutedSceneVibrance& kernel) noexcept {
    return GpuPointwiseKernel::create(
        device,
        negaflow_muted_scene_vibrance_cs,
        sizeof(negaflow_muted_scene_vibrance_cs),
        sizeof(MutedSceneVibranceConstants),
        kernel.kernel_);
}

GpuKernelStatus GpuMutedSceneVibrance::dispatch(
    const GpuDevice& device,
    const GpuVibranceTable& table,
    const GpuWorkingImage& source,
    GpuWorkingImage& destination,
    const float amount) const noexcept {
    if (!table.is_valid()) {
        return GpuKernelStatus::device_unavailable;
    }
    if (!std::isfinite(amount)) {
        return GpuKernelStatus::non_finite_parameter;
    }
    // 판 선택은 **CPU 의 공개 함수**를 그대로 부릅니다. 여기서 다시 고르면 두 벌입니다.
    const imaging::VibrancePlaneSelection selection =
        imaging::select_vibrance_planes(amount);

    MutedSceneVibranceConstants payload{};
    payload.amount = amount;
    payload.blend = selection.blend;
    payload.quantum = vibrance_table_quantum;
    payload.low = selection.low;
    return kernel_.dispatch_with_extra(
        device, source, table.lookup().srv(), destination, &payload, sizeof(payload));
}

GpuKernelStatus GpuColorModel::create(
    const GpuDevice& device,
    GpuColorModel& kernel) noexcept {
    return GpuPointwiseKernel::create(
        device,
        negaflow_color_model_cs,
        sizeof(negaflow_color_model_cs),
        sizeof(ColorModelConstants),
        kernel.kernel_);
}

GpuKernelStatus GpuColorModel::dispatch(
    const GpuDevice& device,
    const GpuVibranceTable& table,
    const GpuWorkingImage& source,
    GpuWorkingImage& destination,
    const imaging::ColorModelParameters& parameters) const noexcept {
    if (!table.is_valid()) {
        return GpuKernelStatus::device_unavailable;
    }
    if (!imaging::valid_color_model_parameters(parameters)) {
        return GpuKernelStatus::non_finite_parameter;
    }

    ColorModelConstants payload{};
    payload.warmth = parameters.warmth;
    payload.tint = parameters.tint;
    payload.color_depth = parameters.color_depth;
    payload.vibrance = parameters.vibrance;
    payload.saturation = parameters.saturation;
    payload.red_primary = parameters.red_primary;
    payload.green_primary = parameters.green_primary;
    payload.blue_primary = parameters.blue_primary;

    // 게이트는 **호스트가** 판정합니다. CPU 판(`apply_pixel`)의 조건과 같아야 합니다 —
    // 임계 이하이면 그 항목을 아예 건너뜁니다. 돌리면 `1 + 0` 곱셈의 반올림이 붙습니다.
    std::uint32_t gates = 0U;
    if (std::abs(parameters.warmth) > identity_threshold) gates |= 1U;
    if (std::abs(parameters.tint) > identity_threshold) gates |= 2U;
    if (std::abs(parameters.color_depth) > identity_threshold) gates |= 4U;
    if (std::abs(parameters.vibrance) > identity_threshold) gates |= 8U;
    if (std::abs(parameters.saturation) > identity_threshold) gates |= 16U;
    if (std::abs(parameters.red_primary) > identity_threshold ||
        std::abs(parameters.green_primary) > identity_threshold ||
        std::abs(parameters.blue_primary) > identity_threshold) {
        gates |= 32U;
    }
    payload.gates = gates;

    // `color_model.cpp:81` — 슬라이더의 0.8배가 표의 amount 입니다.
    const float vibrance_amount = parameters.vibrance * 0.8F;
    const imaging::VibrancePlaneSelection selection =
        imaging::select_vibrance_planes(vibrance_amount);
    payload.vibrance_amount = vibrance_amount;
    payload.vibrance_low = selection.low;
    payload.vibrance_blend = selection.blend;
    payload.vibrance_quantum = vibrance_table_quantum;

    return kernel_.dispatch_with_extra(
        device, source, table.lookup().srv(), destination, &payload, sizeof(payload));
}

} // namespace negaflow::gpu
