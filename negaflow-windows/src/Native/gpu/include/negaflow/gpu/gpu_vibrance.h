#pragma once

// 실측 `CIVibrance` 표를 쓰는 커널들입니다.
//
// | | macOS | Windows CPU | 셰이더 |
// |---|---|---|---|
// | 흐린 장면 vibrance | `ColorModel.swift` 의 `CIVibrance` | `imaging/muted_scene_vibrance.cpp` | `shaders/muted_scene_vibrance.hlsl` |
// | 컬러 모델(우측 슬라이더) | 〃 + 온도·틴트·채도·원색 | `imaging/color_model.cpp` `apply_color_model` | `shaders/color_model.hlsl` |
//
// **표는 한 벌만 올립니다.** 33³ × amount 판 6장 = 215,622 칸이고, 두 커널이 같은
// `GpuLookupTable` 을 공유합니다. 커널마다 올리면 1.7 MB 가 두 벌이 됩니다.
//
// **amount 판 두 장의 선택은 CPU 의 `select_vibrance_planes` 가 합니다.**
// 화소마다 같은 값이고, 두 곳에서 고르면 판이 어긋나는 순간 색이 통째로 달라집니다 —
// 그때는 오차가 1e-5 가 아니라 0.0x 로 나옵니다.

#include "negaflow/gpu/gpu_lookup_table.h"
#include "negaflow/gpu/gpu_pointwise.h"
#include "negaflow/imaging/color_model.h"

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

// 두 커널이 나눠 쓰는 표입니다. 한 번 만들어 두고 SRV 만 넘깁니다.
class GpuVibranceTable final {
public:
    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuVibranceTable& table) noexcept;

    [[nodiscard]] const GpuLookupTable& lookup() const noexcept { return table_; }
    [[nodiscard]] bool is_valid() const noexcept { return table_.is_valid(); }

private:
    GpuLookupTable table_{};
};

class GpuMutedSceneVibrance final {
public:
    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuMutedSceneVibrance& kernel) noexcept;

    // `amount` 는 CPU 가 장면 평균 채도에서 정한 값입니다 — 여기서 다시 재지 않습니다.
    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuVibranceTable& table,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination,
        float amount) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return kernel_.is_valid(); }

private:
    GpuPointwiseKernel kernel_{};
};

class GpuColorModel final {
public:
    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuColorModel& kernel) noexcept;

    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuVibranceTable& table,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination,
        const imaging::ColorModelParameters& parameters) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return kernel_.is_valid(); }

private:
    GpuPointwiseKernel kernel_{};
};

} // namespace negaflow::gpu
