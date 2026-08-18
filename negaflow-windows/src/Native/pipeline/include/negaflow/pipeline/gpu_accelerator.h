#pragma once

// GPU 가속 진입점입니다. 파이프라인이 GPU 커널을 부르는 **유일한 문**입니다.
//
// 왜 여기인가 — 의존 방향이 `gpu → imaging` 이라 `imaging` 안에서는 GPU 를 부를 수 없습니다.
// `pipeline` 은 둘 다 링크하므로 여기가 이음매입니다.
//
// ☠️ **정책: GPU 는 값이 CPU 와 다를 수 있으므로 골든이 걸린 경로에 쓰지 않습니다.**
//
//    | 커널 | CPU 와의 최대 오차(실측) |
//    |---|---:|
//    | 톤 7단계 | 6.0e-07 ~ 1.4e-06 |
//    | `film_scan_denoise` 사슬 | 2.1e-05 ~ 6.2e-05 (감마 리프트 `pow` 때문) |
//
//    바이트 일치가 아닙니다. 내보내기·골든 시험은 **CPU 그대로** 두고, 사용자가 기다리는
//    **프리뷰와 검출**에서만 켭니다. 켜고 끄는 것은 호출부가 `GpuUsePolicy` 로 정합니다.
//    자세한 근거는 `docs/audit/04-gpu-plan.md` 0.5·0.6절.
//
// ☠️ **D3D11 즉시 컨텍스트는 스레드 안전하지 않습니다.** 이 클래스가 자물쇠를 하나 들고
//    있고, 모든 GPU 호출이 그 안에서 돕니다. 자물쇠를 빼지 마십시오.

#include <cstdint>

#include "negaflow/imaging/film_scan_denoise.h"
#include "negaflow/imaging/kernel_accelerator.h"
#include "negaflow/imaging/working_tone_adjuster.h"

namespace negaflow::pipeline {

// 어느 경로에서 부르는지. 값이 바이트까지 같아야 하는 경로는 `cpu_only` 입니다.
enum class GpuUsePolicy : std::uint8_t {
    // 내보내기·골든. GPU 를 쓰지 않습니다.
    cpu_only = 0,
    // 프리뷰·검출. 사용자가 기다리는 경로입니다.
    allowed,
};

// GPU 가 실제로 처리했는지, 처리했다면 CPU 판과 같은 모양의 결과가 무엇인지.
struct GpuToneOutcome final {
    bool handled{false};
    imaging::WorkingToneAdjustInfo info{};
};

struct GpuDenoiseOutcome final {
    bool handled{false};
    imaging::FilmScanDenoiseInfo info{};
};

// 프로세스 수명 동안 하나입니다. 첫 사용 때 장치를 열고, 열지 못하면 영구히 비활성입니다.
// macOS `DevelopFrameRenderer.sharedRenderContext` 와 같은 자리 — 큐를 하나로 두는
// 이유도 같습니다(빠른 반복 렌더의 동기화 버블 제거).
class GpuAccelerator final {
public:
    [[nodiscard]] static GpuAccelerator& shared() noexcept;

    [[nodiscard]] bool available() const noexcept;
    // 어떤 장치를 잡았는지. 없으면 빈 문자열입니다. 진단·로그용입니다.
    [[nodiscard]] const char* adapter_description() const noexcept;

    // 실패하거나 정책이 막으면 `handled == false` 이고 **이미지는 손대지 않습니다.**
    // 호출부는 그대로 CPU 경로로 가면 됩니다.
    [[nodiscard]] GpuToneOutcome apply_working_tone_adjustments(
        GpuUsePolicy policy,
        imaging::WorkingImage& image,
        const imaging::WorkingToneAdjustParameters& parameters,
        const imaging::ToneCurveMeasurementLimits& measurement_limits) noexcept;

    [[nodiscard]] GpuDenoiseOutcome apply_film_scan_denoise(
        GpuUsePolicy policy,
        imaging::WorkingImage& image,
        const imaging::FilmScanDenoiseParameters& parameters) noexcept;

    // 단일 채널 평면 형태학입니다. GrainMend 검출 안쪽에서 불립니다.
    //
    // ☠️ 여기에는 `GpuUsePolicy` 가 **없습니다.** 형태학은 창 안에서 하나를 고르는 일이라
    //    부동소수 산술이 없고 CPU 와 **비트 단위로 같습니다**(시험이 전 반경에서 고정).
    //    그래서 내보내기·골든 경로에서도 켭니다 — 값이 안 바뀌므로 막을 이유가 없습니다.
    //    곱셈·덧셈이 들어가는 커널을 이 방식으로 붙이지 마십시오.
    //
    // `source` 와 `destination` 은 `width * height` 개이고 겹치지 않아야 합니다.
    // 처리했으면 `true`. `false` 면 호출부가 CPU 로 갑니다.
    [[nodiscard]] bool apply_morphology_plane(
        const float* source,
        float* destination,
        std::uint32_t width,
        std::uint32_t height,
        std::uint32_t radius,
        imaging::MorphologyKind kind) noexcept;

private:
    GpuAccelerator() noexcept;
    ~GpuAccelerator();

    GpuAccelerator(const GpuAccelerator&) = delete;
    GpuAccelerator& operator=(const GpuAccelerator&) = delete;

    struct State;
    State* state_{nullptr};
};

// `imaging` 안쪽 커널이 GPU 를 쓰게 표를 겁니다. 프로세스 시작에 한 번 부르십시오.
// 장치가 없으면 아무것도 하지 않습니다.
void install_gpu_kernel_accelerator() noexcept;

}  // namespace negaflow::pipeline
