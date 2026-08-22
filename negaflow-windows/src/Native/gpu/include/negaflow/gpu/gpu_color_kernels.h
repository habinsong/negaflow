#pragma once

// 색 커널의 GPU 판입니다. 톤 커널은 `gpu_tone_kernels.h` 에 있습니다.
//
// | | macOS | Windows CPU | 셰이더 |
// |---|---|---|---|
// | 컬러 그레이딩 | `ChromabaseMetalKernels.swift:101` `colorGrade` | `imaging/color_grading.cpp` `apply_color_grading` | `shaders/color_grade.hlsl` |
// | 컬러 믹서(HSL) | `:74` `colorMixerHSL` | `imaging/color_mixer.cpp` `apply_color_mixer` | `shaders/color_mixer.hlsl` |
// | 원색 보정 | `:151` `calibrationPrimaries` | `imaging/primary_calibration.cpp` | `shaders/primary_calibration.hlsl` |
// | 흑백 조색 | `:123` `bwToning` | `imaging/bw_toning.cpp` `apply_bw_toning` | `shaders/bw_toning.hlsl` |
// | 디지털 흑백 유제 | `:826` `digitalBWFilm` | `imaging/digital_bw_emulsion_response.cpp` | `shaders/digital_bw_film.hlsl` |
//
// CPU 판을 **대체하지 않습니다.** 나란히 두고 상위에서 장치 가용성으로 고릅니다.

#include "negaflow/gpu/gpu_pointwise.h"

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

// `imaging::ColorGradingSetup` 과 같은 값입니다. gpu 라이브러리가 imaging 에 의존하지 않도록
// (의존 방향이 반대여야 합니다) 같은 모양으로 여기 둡니다.
//
// 이 값들을 **여기서 계산하지 마십시오.** `imaging::prepare_color_grading` 이 만든 것을
// 그대로 옮겨 담으십시오. 두 벌이 되면 CPU 와 GPU 가 조용히 갈라집니다.
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

// `imaging::BwToningSetup` 과 같은 값입니다.
//
// 색조를 **여기서 계산하지 마십시오.** `imaging::prepare_bw_toning` 이 만든 것을 그대로
// 옮겨 담으십시오(채도 0.78 고정의 HSV 변환입니다).
struct GpuBwToningSetup final {
    float shadow_tint[3]{1.0F, 1.0F, 1.0F};
    float highlight_tint[3]{1.0F, 1.0F, 1.0F};
    float strength{0.0F};
    float mode{0.0F};
    // 거짓이면 **중성화만** 합니다. 커널을 건너뛰면 안 됩니다 — 흑백 변환이 사라집니다.
    bool tone{false};
};

class GpuBwToning final {
public:
    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuBwToning& kernel) noexcept;

    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination,
        const GpuBwToningSetup& setup) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return kernel_.is_valid(); }

private:
    GpuPointwiseKernel kernel_{};
};

// `imaging::DigitalBwEmulsionSetup` 과 같은 값입니다.
//
// **여기서 계산하지 마십시오.** `imaging::prepare_digital_bw_emulsion_response` 가 만든 것을
// 그대로 옮겨 담으십시오 — 필름 프로파일 표가 CPU 쪽에 있습니다.
struct GpuDigitalBwFilmSetup final {
    float weights[3]{0.2126F, 0.7152F, 0.0722F};
    float contrast{0.0F};
    float toe{0.0F};
    float shoulder{0.0F};
    float deepen{0.0F};
    float black{0.0F};
    float white{1.0F};
    float intensity{0.0F};
    // 거짓이면 CPU 는 원본을 그대로 복사합니다. GPU 도 그렇게 합니다.
    bool active{false};
};

class GpuDigitalBwFilm final {
public:
    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuDigitalBwFilm& kernel) noexcept;

    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination,
        const GpuDigitalBwFilmSetup& setup) const noexcept;

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

} // namespace negaflow::gpu
