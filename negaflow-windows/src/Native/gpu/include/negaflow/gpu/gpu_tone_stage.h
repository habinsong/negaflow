#pragma once

// 톤 단계 **전체**를 GPU 에 머문 채로 돌립니다.
// Windows CPU 대응은 `imaging/working_tone_adjuster.cpp` `apply_working_tone_adjustments`
// 이고, 우측 인스펙터 슬라이더가 직접 미는 경로입니다.
//
// **커널만 있고 이것이 없으면 아무것도 빨라지지 않습니다.** 단계마다 올렸다 내리면
// 24MP float32 RGBA 에서 왕복 한 번이 384 MB 이고, 커널이 아무리 빨라도 전송이
// 지배합니다. 여기가 **업로드 1회 → 7단계 GPU 상주 → 다운로드 1회** 를 만드는 자리입니다.
//
// **CPU 판의 게이트를 하나도 빠뜨리지 마십시오.** CPU 는 매개변수가 안 움직인 단계를
// 아예 건너뜁니다. GPU 가 그 단계를 돌리면 클램프·반올림이 붙어 값이 갈립니다
// (`13-performance-playbook.md` 12절). 이 파일은 게이트를 CPU 와 1:1 로 옮깁니다.
//
// 주의 파라메트릭 커브가 켜져 있으면 **중간에 한 번 내립니다.**
// `measure_parametric_tone_curve_bands` 가 전 화소를 `double` 로 훑어 다운샘플하고
// 정렬해 백분위를 뽑는데, D3D11 의 double 은 선택 기능(`D3D11_FEATURE_DOUBLES`)이라
// 내장 GPU 범용성이 보장되지 않습니다. **값을 지키려고 그 한 걸음만 CPU 로 둡니다.**
// 커브가 꺼져 있으면(대부분의 슬라이더 조작) 왕복이 없습니다.

#include "negaflow/gpu/gpu_pointwise.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/imaging/working_tone_adjuster.h"

namespace negaflow::gpu {

class GpuDevice;

// CPU 판과 같은 결과를 냅니다. 실패하면 `WorkingToneAdjustStatus` 로 이유를 돌려주고,
// 호출부는 CPU 경로로 갈 수 있습니다 — 이미지는 그대로 남습니다.
struct GpuToneStageResult final {
    // 참이면 GPU 가 실제로 처리했습니다. 거짓이면 이미지는 손대지 않았고 CPU 로 가야 합니다.
    bool handled{false};
    imaging::WorkingToneAdjustStatus status{imaging::WorkingToneAdjustStatus::ok};
    imaging::WorkingToneAdjustInfo info{};
};

// 커널과 핑퐁 텍스처를 들고 있습니다. **한 번 만들어 재사용하십시오** — 슬라이더를 끄는
// 동안 프레임마다 만들면 그 비용이 커널보다 큽니다.
class GpuToneStage final {
public:
    GpuToneStage() noexcept = default;
    ~GpuToneStage();

    GpuToneStage(const GpuToneStage&) = delete;
    GpuToneStage& operator=(const GpuToneStage&) = delete;
    GpuToneStage(GpuToneStage&& other) noexcept = delete;
    GpuToneStage& operator=(GpuToneStage&& other) noexcept = delete;

    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuToneStage& stage) noexcept;

    // `image` 를 제자리에서 바꿉니다. `handled` 가 거짓이면 손대지 않았습니다.
    [[nodiscard]] GpuToneStageResult apply(
        const GpuDevice& device,
        imaging::WorkingImage& image,
        const imaging::WorkingToneAdjustParameters& parameters,
        const imaging::ToneCurveMeasurementLimits& measurement_limits) const noexcept;

    // 이미 GPU 에 있는 텍스처에서 돌립니다. 올리지 않습니다.
    // `download` 가 참이면 마지막 결과를 `image` 로 내립니다.
    [[nodiscard]] GpuToneStageResult apply_on(
        const GpuDevice& device,
        GpuWorkingImage& input,
        GpuWorkingImage& scratch,
        imaging::WorkingImage& image,
        const imaging::WorkingToneAdjustParameters& parameters,
        const imaging::ToneCurveMeasurementLimits& measurement_limits,
        bool download) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept;

private:
    struct State;
    State* state_{nullptr};
};

} // namespace negaflow::gpu
