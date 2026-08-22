#pragma once

// 자동 레벨 · 자동 중성 균형의 GPU 판입니다.
//
// CPU 판 : `imaging/scene_correction.cpp`
// 셰이더 : `shaders/scene_sample_grid.hlsl`, `shaders/scene_correction.hlsl`
//
// 한 틱에 하는 일:
// 1. 표본 격자(256칸)를 컴퓨트로 모아 **격자만** 호스트로 내립니다.
// 2. 호스트가 `plan_scene_auto_levels` 로 계수를 정합니다(규칙은 CPU 한 벌).
// 3. 적용 커널을 디스패치합니다.
// 4. 표본 격자(192칸)를 **적용 결과 위에서** 다시 모아 2·3 을 중성 균형으로 반복합니다.
//
// 순서가 CPU 와 같아야 합니다 — 중성 균형은 **레벨이 적용된 화상**을 표본합니다.
//
// **근사입니다.** 표본 누적이 float 입니다. 프리뷰·검출에서만 씁니다.

#include "negaflow/gpu/gpu_pointwise.h"
#include "negaflow/imaging/scene_correction.h"

#include <cstdint>

struct ID3D11ComputeShader;
struct ID3D11Buffer;
struct ID3D11UnorderedAccessView;

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

class GpuSceneCorrection final {
public:
    GpuSceneCorrection() noexcept = default;
    ~GpuSceneCorrection();

    GpuSceneCorrection(const GpuSceneCorrection&) = delete;
    GpuSceneCorrection& operator=(const GpuSceneCorrection&) = delete;
    GpuSceneCorrection(GpuSceneCorrection&& other) noexcept;
    GpuSceneCorrection& operator=(GpuSceneCorrection&& other) noexcept;

    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuSceneCorrection& kernel) noexcept;

    // 격자를 모아 `samples` 를 채웁니다. 칸 하나라도 무효면 false 와 같은 뜻으로
    // `invalid_arguments` 를 돌려줍니다 — CPU 의 `weight_sum <= 0` 갈래와 같습니다.
    [[nodiscard]] GpuKernelStatus collect_samples(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        std::uint32_t target_width,
        imaging::SceneSampleGrid& samples) const noexcept;

    [[nodiscard]] GpuKernelStatus apply_auto_levels(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination,
        const imaging::SceneAutoLevelsPlan& plan) const noexcept;

    [[nodiscard]] GpuKernelStatus apply_neutral_balance(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination,
        const imaging::SceneNeutralBalancePlan& plan) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept {
        return grid_ != nullptr && levels_.is_valid() && balance_.is_valid();
    }

private:
    void reset() noexcept;

    ID3D11ComputeShader* grid_{nullptr};
    ID3D11Buffer* grid_constants_{nullptr};
    ID3D11Buffer* grid_buffer_{nullptr};
    ID3D11UnorderedAccessView* grid_uav_{nullptr};
    ID3D11Buffer* grid_readback_{nullptr};
    std::uint32_t grid_capacity_{0};
    GpuPointwiseKernel levels_{};
    GpuPointwiseKernel balance_{};
};

} // namespace negaflow::gpu
