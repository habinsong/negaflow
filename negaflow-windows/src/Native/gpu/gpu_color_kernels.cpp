#include "negaflow/gpu/gpu_color_kernels.h"

// fxc 가 만든 헤더는 `const BYTE ...[]` 로 나오므로 Windows 타입이 먼저 보여야 합니다.
#include <windows.h>

#include <cmath>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/color_grade_ColorGradeMain.h"
#include "negaflow/gpu/shaders/color_mixer_ColorMixerMain.h"
#include "negaflow/gpu/shaders/primary_calibration_PrimaryCalibrationMain.h"

namespace negaflow::gpu {
namespace {

// HLSL `cbuffer ColorGradeConstants` 와 같은 배치여야 합니다.
// HLSL 은 `float3` + `float` 를 16바이트 레지스터 하나에 채웁니다 — 그래서 pivot/width 가
// 오프셋 뒤에 하나씩 붙어 있습니다. 순서를 바꾸면 조용히 어긋납니다.
struct alignas(16) ColorGradeConstants final {
    GpuPointwiseExtent extent{};
    float shadow_offset[3]{0.0F, 0.0F, 0.0F};
    float pivot{0.0F};
    float midtone_offset[3]{0.0F, 0.0F, 0.0F};
    float width{0.0F};
    float highlight_offset[3]{0.0F, 0.0F, 0.0F};
    float padding{0.0F};
};

static_assert(sizeof(ColorGradeConstants) == 64U, "four constant registers");

[[nodiscard]] bool finite_offsets(const float (&offset)[3]) noexcept {
    return std::isfinite(offset[0]) && std::isfinite(offset[1]) && std::isfinite(offset[2]);
}

[[nodiscard]] bool finite_setup(const GpuColorGradeSetup& setup) noexcept {
    return finite_offsets(setup.shadow_offset) && finite_offsets(setup.midtone_offset) &&
        finite_offsets(setup.highlight_offset) && std::isfinite(setup.pivot) &&
        std::isfinite(setup.width);
}

// HLSL `cbuffer ColorMixerConstants` 와 같은 배치여야 합니다.
// 상수 버퍼의 배열은 **원소마다 16바이트**를 차지합니다 — `float[8]` 로 두면 셰이더가 읽는
// 자리와 어긋나 조용히 틀린 밴드를 씁니다. 그래서 `float4` 로 채웁니다.
struct alignas(16) ColorMixerConstants final {
    GpuPointwiseExtent extent{};
    float hue[GpuColorMixerParameters::band_count][4]{};
    float saturation[GpuColorMixerParameters::band_count][4]{};
    float luminance[GpuColorMixerParameters::band_count][4]{};
};

static_assert(sizeof(ColorMixerConstants) == 400U, "extent + three 8-element float4 arrays");

// `imaging/color_mixer.cpp` 의 `identity_epsilon` 과 같은 값이어야 합니다.
constexpr float mixer_identity_epsilon = 1.0e-4F;

// CPU 판 `has_color_mixer_change` 와 같은 판정입니다.
[[nodiscard]] bool mixer_changes(const GpuColorMixerParameters& parameters) noexcept {
    for (int index = 0; index < GpuColorMixerParameters::band_count; ++index) {
        if (std::abs(parameters.hue[index]) >= mixer_identity_epsilon ||
            std::abs(parameters.saturation[index]) >= mixer_identity_epsilon ||
            std::abs(parameters.luminance[index]) >= mixer_identity_epsilon) {
            return true;
        }
    }
    return false;
}

[[nodiscard]] bool finite_mixer(const GpuColorMixerParameters& parameters) noexcept {
    for (int index = 0; index < GpuColorMixerParameters::band_count; ++index) {
        if (!std::isfinite(parameters.hue[index]) ||
            !std::isfinite(parameters.saturation[index]) ||
            !std::isfinite(parameters.luminance[index])) {
            return false;
        }
    }
    return true;
}

// HLSL `cbuffer PrimaryCalibrationConstants` 와 같은 배치여야 합니다.
struct alignas(16) PrimaryCalibrationConstants final {
    GpuPointwiseExtent extent{};
    float hue[3][4]{};
    float saturation[3][4]{};
};

static_assert(sizeof(PrimaryCalibrationConstants) == 112U, "extent + two 3-element float4 arrays");

// `imaging/primary_calibration.cpp` 의 `identity_epsilon` 과 같은 값이어야 합니다.
constexpr float primary_identity_epsilon = 1.0e-4F;

[[nodiscard]] bool primary_values_finite(
    const GpuPrimaryCalibrationParameters& parameters) noexcept {
    return std::isfinite(parameters.red_hue) && std::isfinite(parameters.red_saturation) &&
        std::isfinite(parameters.green_hue) && std::isfinite(parameters.green_saturation) &&
        std::isfinite(parameters.blue_hue) && std::isfinite(parameters.blue_saturation);
}

// CPU 판 `has_primary_calibration_change` 와 같은 판정입니다.
[[nodiscard]] bool primary_changes(const GpuPrimaryCalibrationParameters& parameters) noexcept {
    return std::abs(parameters.red_hue) >= primary_identity_epsilon ||
        std::abs(parameters.red_saturation) >= primary_identity_epsilon ||
        std::abs(parameters.green_hue) >= primary_identity_epsilon ||
        std::abs(parameters.green_saturation) >= primary_identity_epsilon ||
        std::abs(parameters.blue_hue) >= primary_identity_epsilon ||
        std::abs(parameters.blue_saturation) >= primary_identity_epsilon;
}

}  // namespace

GpuKernelStatus GpuPrimaryCalibration::create(
    const GpuDevice& device,
    GpuPrimaryCalibration& kernel) noexcept {
    return GpuPointwiseKernel::create(
        device,
        negaflow_primary_calibration_cs,
        sizeof(negaflow_primary_calibration_cs),
        sizeof(PrimaryCalibrationConstants),
        kernel.kernel_);
}

GpuKernelStatus GpuPrimaryCalibration::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage& destination,
    const GpuPrimaryCalibrationParameters& parameters) const noexcept {
    if (!primary_values_finite(parameters)) {
        return GpuKernelStatus::non_finite_parameter;
    }
    if (!primary_changes(parameters)) {
        // CPU 판과 같은 자리에서 원본을 그대로 내보냅니다 — 커널을 돌리면 HSL 왕복이
        // [0,1] 밖 값을 클램프해 CPU 와 갈립니다.
        const GpuImageStatus copied = destination.copy_from(device, source);
        return copied == GpuImageStatus::ok ? GpuKernelStatus::ok
                                            : GpuKernelStatus::invalid_arguments;
    }
    PrimaryCalibrationConstants payload{};
    payload.hue[0][0] = parameters.red_hue;
    payload.hue[1][0] = parameters.green_hue;
    payload.hue[2][0] = parameters.blue_hue;
    payload.saturation[0][0] = parameters.red_saturation;
    payload.saturation[1][0] = parameters.green_saturation;
    payload.saturation[2][0] = parameters.blue_saturation;
    return kernel_.dispatch(device, source, destination, &payload, sizeof(payload));
}

GpuKernelStatus GpuColorMixer::create(const GpuDevice& device, GpuColorMixer& kernel) noexcept {
    return GpuPointwiseKernel::create(
        device,
        negaflow_color_mixer_cs,
        sizeof(negaflow_color_mixer_cs),
        sizeof(ColorMixerConstants),
        kernel.kernel_);
}

GpuKernelStatus GpuColorMixer::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage& destination,
    const GpuColorMixerParameters& parameters) const noexcept {
    if (!finite_mixer(parameters)) {
        return GpuKernelStatus::non_finite_parameter;
    }
    if (!mixer_changes(parameters)) {
        // ☠️ CPU 판 `apply_color_mixer` 는 변화가 없으면 `copy_validated_rows` 로 **원본을
        //    그대로** 내보냅니다(`color_mixer.cpp:227`). 여기서 커널을 돌리면 HSL 왕복이
        //    [0,1] 밖 값을 클램프해 CPU 와 갈립니다 — 작업 이미지는 그 범위 밖 값을
        //    일부러 남기므로 실제로 갈립니다(실측: 최대 0.1).
        const GpuImageStatus copied = destination.copy_from(device, source);
        return copied == GpuImageStatus::ok ? GpuKernelStatus::ok
                                            : GpuKernelStatus::invalid_arguments;
    }
    ColorMixerConstants payload{};
    for (int index = 0; index < GpuColorMixerParameters::band_count; ++index) {
        payload.hue[index][0] = parameters.hue[index];
        payload.saturation[index][0] = parameters.saturation[index];
        payload.luminance[index][0] = parameters.luminance[index];
    }
    return kernel_.dispatch(device, source, destination, &payload, sizeof(payload));
}

GpuKernelStatus GpuColorGrade::create(const GpuDevice& device, GpuColorGrade& kernel) noexcept {
    return GpuPointwiseKernel::create(
        device,
        negaflow_color_grade_cs,
        sizeof(negaflow_color_grade_cs),
        sizeof(ColorGradeConstants),
        kernel.kernel_);
}

GpuKernelStatus GpuColorGrade::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage& destination,
    const GpuColorGradeSetup& setup) const noexcept {
    if (!finite_setup(setup)) {
        return GpuKernelStatus::non_finite_parameter;
    }
    // 폭이 0 이면 미드톤 가중치가 0 나누기가 됩니다. CPU 판은 `prepare_color_grading` 이
    // 0.10 이상을 보장해서 그 자리에 가드가 없습니다 — 여기서는 그 보장이 깨진 채로
    // 들어오는 것을 거절합니다. 조용히 0.001 을 끼워 넣으면 CPU 와 값이 갈립니다.
    if (!(setup.width > 0.0F)) {
        return GpuKernelStatus::non_finite_parameter;
    }
    ColorGradeConstants payload{};
    for (int index = 0; index < 3; ++index) {
        payload.shadow_offset[index] = setup.shadow_offset[index];
        payload.midtone_offset[index] = setup.midtone_offset[index];
        payload.highlight_offset[index] = setup.highlight_offset[index];
    }
    payload.pivot = setup.pivot;
    payload.width = setup.width;
    return kernel_.dispatch(device, source, destination, &payload, sizeof(payload));
}

}  // namespace negaflow::gpu
