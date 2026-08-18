#pragma once

// 색 커널의 GPU 판입니다. 톤 커널은 `gpu_tone_kernels.h` 에 있습니다.
//
// | | macOS | Windows CPU | 셰이더 |
// |---|---|---|---|
// | 컬러 그레이딩 | `ChromabaseMetalKernels.swift:101` `colorGrade` | `imaging/color_grading.cpp` `apply_color_grading` | `shaders/color_grade.hlsl` |
// | 컬러 믹서(HSL) | `:74` `colorMixerHSL` | `imaging/color_mixer.cpp` `apply_color_mixer` | `shaders/color_mixer.hlsl` |
//
// CPU 판을 **대체하지 않습니다.** 나란히 두고 상위에서 장치 가용성으로 고릅니다.

#include "negaflow/gpu/gpu_pointwise.h"

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

// `imaging::ColorGradingSetup` 과 같은 값입니다. gpu 라이브러리가 imaging 에 의존하지 않도록
// (의존 방향이 반대여야 합니다) 같은 모양으로 여기 둡니다.
//
// ☠️ 이 값들을 **여기서 계산하지 마십시오.** `imaging::prepare_color_grading` 이 만든 것을
//    그대로 옮겨 담으십시오. 두 벌이 되면 CPU 와 GPU 가 조용히 갈라집니다.
struct GpuColorGradeSetup final {
    float shadow_offset[3]{0.0F, 0.0F, 0.0F};
    float midtone_offset[3]{0.0F, 0.0F, 0.0F};
    float highlight_offset[3]{0.0F, 0.0F, 0.0F};
    float pivot{0.5F};
    float width{0.30F};
};

// `imaging::ColorMixerParameters` 와 같은 값입니다. 밴드 8개(빨강·주황·노랑·초록·하늘·파랑·
// 보라·자홍) 각각 색상/채도/광도.
struct GpuColorMixerParameters final {
    static constexpr int band_count = 8;
    float hue[band_count]{};
    float saturation[band_count]{};
    float luminance[band_count]{};
};

class GpuColorMixer final {
public:
    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuColorMixer& kernel) noexcept;

    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination,
        const GpuColorMixerParameters& parameters) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return kernel_.is_valid(); }

private:
    GpuPointwiseKernel kernel_{};
};

// `imaging::PrimaryCalibrationParameters` 와 같은 값입니다. 원색 3개의 색상/채도.
// 믹서와 달리 **광도 조정이 없습니다.**
struct GpuPrimaryCalibrationParameters final {
    float red_hue{0.0F};
    float red_saturation{0.0F};
    float green_hue{0.0F};
    float green_saturation{0.0F};
    float blue_hue{0.0F};
    float blue_saturation{0.0F};
};

class GpuPrimaryCalibration final {
public:
    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuPrimaryCalibration& kernel) noexcept;

    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination,
        const GpuPrimaryCalibrationParameters& parameters) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return kernel_.is_valid(); }

private:
    GpuPointwiseKernel kernel_{};
};

class GpuColorGrade final {
public:
    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuColorGrade& kernel) noexcept;

    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination,
        const GpuColorGradeSetup& setup) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return kernel_.is_valid(); }

private:
    GpuPointwiseKernel kernel_{};
};

}  // namespace negaflow::gpu
