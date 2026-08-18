#pragma once

// `GpuAccelerator` 의 내부 상태입니다. **공개 헤더가 아닙니다** — `pipeline` 안에서만 씁니다.
//
// 왜 헤더로 뗐나 — 가속기의 진입점이 열 개를 넘어가면서 한 파일이 500줄을 넘었습니다.
// 장치·톤·디노이즈·형태학·반전은 `gpu_accelerator.cpp`, 디지털 필름 룩의 재료 다섯은
// `gpu_accelerator_film_look.cpp` 가 맡습니다. 둘이 **같은 상태 하나**를 봐야 하므로
// 정의를 여기 둡니다.

#include <mutex>
#include <vector>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_digital_film_color_preset.h"
#include "negaflow/gpu/gpu_digital_film_grain.h"
#include "negaflow/gpu/gpu_digital_halation.h"
#include "negaflow/gpu/gpu_film_emulation_acutance.h"
#include "negaflow/gpu/gpu_film_emulation_cube.h"
#include "negaflow/gpu/gpu_film_look_stage.h"
#include "negaflow/gpu/gpu_image_pool.h"
#include "negaflow/gpu/gpu_film_scan_stage.h"
#include "negaflow/gpu/gpu_morphology.h"
#include "negaflow/gpu/gpu_negative_invert.h"
#include "negaflow/gpu/gpu_tone_stage.h"
#include "negaflow/gpu/gpu_vibrance.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/pipeline/gpu_accelerator.h"

namespace negaflow::pipeline {

struct GpuAccelerator::State final {
    // ☠️ D3D11 즉시 컨텍스트는 스레드 안전하지 않습니다. 모든 GPU 호출이 이 자물쇠
    //    안에서 돕니다 — 빼면 두 현상이 겹칠 때 조용히 깨집니다.
    std::mutex lock{};
    gpu::GpuDevice device{};
    gpu::GpuToneStage tone{};
    gpu::GpuFilmScanDenoiseStage denoise{};
    gpu::GpuMorphology morphology{};
    bool morphology_ready{false};
    gpu::GpuNegativeInvert invert{};
    bool invert_ready{false};
    // 디지털 필름 룩의 재료 커널 둘입니다. 둘 다 이 사슬에서만 불리므로 따로 만들고,
    // 이것만 실패해도 톤·디노이즈·반전은 그대로 돕니다.
    gpu::GpuGaussianBlur gaussian{};
    gpu::GpuDigitalHalation halation{};
    bool halation_ready{false};
    gpu::GpuDigitalFilmGrain grain{};
    bool grain_ready{false};
    gpu::GpuDigitalFilmColorPreset preset{};
    bool preset_ready{false};
    gpu::GpuFilmEmulationCube cube{};
    bool cube_ready{false};
    gpu::GpuFilmEmulationAcutance acutance{};
    bool acutance_ready{false};
    // 사슬 전체를 GPU 에 머무르게 하는 오케스트레이터. 재료별 진입점은 흑백 룩처럼
    // 사슬 밖에서 부르는 자리를 위해 그대로 둡니다.
    gpu::GpuFilmLookStage film_look{};
    bool film_look_ready{false};
    // 실측 `CIVibrance` 표는 **한 벌만** 올립니다 — 두 커널이 나눠 씁니다.
    gpu::GpuVibranceTable vibrance_table{};
    gpu::GpuMutedSceneVibrance muted_vibrance{};
    gpu::GpuColorModel color_model{};
    bool vibrance_ready{false};
    // ☠️ **작업 텍스처는 하나의 묶음을 나눠 씁니다.** 진입점마다 자기 것을 만들면
    //    24MP 에서 264 MB 텍스처를 호출마다 할당·해제하고, 실측으로 그 할당이
    //    다운로드 시간의 큰 몫이었습니다. 필름 룩 오케스트레이터도 이 묶음을 받습니다.
    gpu::GpuImagePool pool{};

    // 평면 ↔ RGBA 변환용. 매 호출 할당하지 않으려고 들고 있습니다.
    std::vector<core::Rgba32F> morphology_staging{};
    bool usable{false};
    // `GpuAdapterInfo::description` 은 고정 배열이라 수명이 장치와 같습니다.
    const char* adapter{""};
};

}  // namespace negaflow::pipeline
