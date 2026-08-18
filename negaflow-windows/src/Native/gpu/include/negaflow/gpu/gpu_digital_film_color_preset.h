#pragma once

// 디지털 원본 전용 스톡 색 프리셋의 GPU 판입니다.
//
// macOS  : `DigitalFilmColorPresetStage.swift` — `digitalToDisplayGamma` →
//          `ColorMixerStage` → `ColorGradingStage` → `CalibrationStage` →
//          `digitalToLinearLight` → `CIMix`
// CPU 판 : `imaging/digital_film_color_preset.cpp` `apply_digital_film_color_preset`
// 셰이더 : `shaders/digital_film_color_preset.hlsl` + 이미 있는 색 커널 셋
//
// ☠️ **macOS 의 `digitalFilmColor` 커널(`:774`)을 옮기는 것이 아닙니다.**
//    그 커널은 `DigitalFilmColor.apply` 만 부르고, 그 함수는 macOS 트리 어디에서도
//    **불리지 않습니다**(전 `.swift` grep 확인). 살아 있는 것은 이 프리셋 스테이지이고,
//    Windows CPU 가 이미 그것을 옮겨 두었습니다. 04·14 문서가 "Windows 가 다른
//    알고리즘" 이라고 적은 것은 **죽은 커널과 산 커널을 견준 것**이었습니다.
//
// ☠️ **근사한 것입니다**(감마 왕복의 `pow`, 색 커널 셋의 곱셈·HSL 왕복).
//    `ApproximateAcceleratorScope` 안에서만 도는 자리에 배선하십시오.
//
// 값이 같으려면 **CPU 의 조기 반환을 그대로** 따라야 합니다. 세 색 커널은 각자
// "변화 없음" 이면 커널을 안 돌리고 원본을 복사합니다. GPU 도 그 자리에서 디스패치를
// 건너뛰어야 합니다 — 돌리면 HSL 왕복의 반올림이 붙습니다(`colorMixerHSL` 이
// delta 0.1 로 깨졌던 것과 같은 함정).

#include "negaflow/gpu/gpu_color_kernels.h"
#include "negaflow/gpu/gpu_pointwise.h"
#include "negaflow/imaging/digital_film_color_preset.h"

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

class GpuDigitalFilmColorPreset final {
public:
    // 중간 텍스처 두 장입니다. 원본은 호출부가 준 `source` 를 그대로 씁니다 —
    // 마지막 혼합이 그것을 다시 읽으므로 복사본을 만들 이유가 없습니다.
    static constexpr int scratch_count = 2;

    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuDigitalFilmColorPreset& kernel) noexcept;

    // `scratch` 는 `scratch_count` 장이고 전부 `source` 와 같은 크기여야 합니다.
    // 결과가 어느 장에 들어갔는지는 디스패치 횟수(프리셋이 무엇을 바꾸는지)에 따라
    // 달라지므로 `result` 로 돌려줍니다. 텍스처를 한 장 더 잡아 항상 같은 곳에 두면
    // 24MP 에서 277 MB 를 더 먹습니다 — 내장 GPU 를 생각하면 그럴 이유가 없습니다.
    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage* scratch,
        const GpuWorkingImage*& result,
        const imaging::DigitalFilmColorPreset& preset,
        float strength) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept {
        return encode_.is_valid() && decode_.is_valid();
    }

private:
    GpuPointwiseKernel encode_{};
    GpuPointwiseKernel decode_{};
    GpuColorMixer mixer_{};
    GpuColorGrade grade_{};
    GpuPrimaryCalibration calibration_{};
};

}  // namespace negaflow::gpu
