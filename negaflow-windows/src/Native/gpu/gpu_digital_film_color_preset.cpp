#include "negaflow/gpu/gpu_digital_film_color_preset.h"

// fxc 가 만든 헤더는 `const BYTE ...[]` 로 나오므로 Windows 타입이 먼저 보여야 합니다.
#include <windows.h>

#include <cmath>
#include <cstddef>
#include <utility>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/digital_film_color_preset_DigitalGammaDecodeMixMain.h"
#include "negaflow/gpu/shaders/digital_film_color_preset_DigitalGammaEncodeMain.h"

namespace negaflow::gpu {
namespace {

// HLSL `cbuffer DigitalFilmColorPresetConstants` 와 같은 배치여야 합니다.
struct alignas(16) PresetConstants final {
    GpuPointwiseExtent extent{};
    float strength{0.0F};
    float padding[3]{0.0F, 0.0F, 0.0F};
};

static_assert(sizeof(PresetConstants) == 32U, "two constant registers");

// 매개변수 변환은 **CPU 구조체를 그대로 옮겨 담기만** 합니다. 여기서 계산하면 두 벌이 됩니다.
[[nodiscard]] GpuColorMixerParameters to_gpu(
    const imaging::ColorMixerParameters& parameters) noexcept {
    GpuColorMixerParameters gpu{};
    for (std::size_t band = 0U; band < imaging::color_mixer_band_count; ++band) {
        gpu.hue[band] = parameters.hue[band];
        gpu.saturation[band] = parameters.saturation[band];
        gpu.luminance[band] = parameters.luminance[band];
    }
    return gpu;
}

[[nodiscard]] GpuColorGradeSetup to_gpu(const imaging::ColorGradingSetup& setup) noexcept {
    GpuColorGradeSetup gpu{};
    for (int index = 0; index < 3; ++index) {
        gpu.shadow_offset[index] = setup.shadow_offset[index];
        gpu.midtone_offset[index] = setup.midtone_offset[index];
        gpu.highlight_offset[index] = setup.highlight_offset[index];
    }
    gpu.pivot = setup.pivot;
    gpu.width = setup.width;
    return gpu;
}

[[nodiscard]] GpuPrimaryCalibrationParameters to_gpu(
    const imaging::PrimaryCalibrationParameters& parameters) noexcept {
    return {
        parameters.red_hue,
        parameters.red_saturation,
        parameters.green_hue,
        parameters.green_saturation,
        parameters.blue_hue,
        parameters.blue_saturation};
}

} // namespace

GpuKernelStatus GpuDigitalFilmColorPreset::create(
    const GpuDevice& device,
    GpuDigitalFilmColorPreset& kernel) noexcept {
    if (GpuPointwiseKernel::create(
            device,
            negaflow_digital_gamma_encode_cs,
            sizeof(negaflow_digital_gamma_encode_cs),
            sizeof(PresetConstants),
            kernel.encode_) != GpuKernelStatus::ok) {
        return GpuKernelStatus::resource_creation_failed;
    }
    if (GpuPointwiseKernel::create(
            device,
            negaflow_digital_gamma_decode_mix_cs,
            sizeof(negaflow_digital_gamma_decode_mix_cs),
            sizeof(PresetConstants),
            kernel.decode_) != GpuKernelStatus::ok) {
        return GpuKernelStatus::resource_creation_failed;
    }
    if (GpuColorMixer::create(device, kernel.mixer_) != GpuKernelStatus::ok ||
        GpuColorGrade::create(device, kernel.grade_) != GpuKernelStatus::ok ||
        GpuPrimaryCalibration::create(device, kernel.calibration_) != GpuKernelStatus::ok) {
        return GpuKernelStatus::resource_creation_failed;
    }
    return GpuKernelStatus::ok;
}

GpuKernelStatus GpuDigitalFilmColorPreset::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage* const scratch,
    const GpuWorkingImage*& result,
    const imaging::DigitalFilmColorPreset& preset,
    const float strength) const noexcept {
    result = nullptr;
    if (!is_valid()) {
        return GpuKernelStatus::device_unavailable;
    }
    if (scratch == nullptr || !std::isfinite(strength)) {
        return GpuKernelStatus::invalid_arguments;
    }

    PresetConstants payload{};
    payload.strength = strength;

    // 선형광 → 표시 도메인.
    if (encode_.dispatch(device, source, scratch[0], &payload, sizeof(payload)) !=
        GpuKernelStatus::ok) {
        return GpuKernelStatus::resource_creation_failed;
    }

    // 핑퐁. `read` 가 현재 결과, `write` 가 다음 목적지입니다.
    GpuWorkingImage* read = &scratch[0];
    GpuWorkingImage* write = &scratch[1];

    // CPU 판이 "변화 없음" 이면 커널을 안 돌리고 복사합니다. 여기서는 디스패치를
    // 건너뛰는 것이 곧 그 복사입니다 — 돌리면 반올림이 붙어 값이 갈립니다.
    if (imaging::has_color_mixer_change(preset.mixer)) {
        if (mixer_.dispatch(device, *read, *write, to_gpu(preset.mixer)) !=
            GpuKernelStatus::ok) {
            return GpuKernelStatus::resource_creation_failed;
        }
        std::swap(read, write);
    }
    if (imaging::has_color_grading_change(preset.grading)) {
        if (grade_.dispatch(
                device, *read, *write, to_gpu(imaging::prepare_color_grading(preset.grading))) !=
            GpuKernelStatus::ok) {
            return GpuKernelStatus::resource_creation_failed;
        }
        std::swap(read, write);
    }
    if (imaging::has_primary_calibration_change(preset.calibration)) {
        if (calibration_.dispatch(device, *read, *write, to_gpu(preset.calibration)) !=
            GpuKernelStatus::ok) {
            return GpuKernelStatus::resource_creation_failed;
        }
        std::swap(read, write);
    }

    // 표시 도메인 → 선형광, 그리고 원본과의 강도 혼합. CPU 도 한 루프에서 둘을 합니다.
    if (decode_.dispatch_pair(device, *read, source, *write, &payload, sizeof(payload)) !=
        GpuKernelStatus::ok) {
        return GpuKernelStatus::resource_creation_failed;
    }
    result = write;
    return GpuKernelStatus::ok;
}

} // namespace negaflow::gpu
