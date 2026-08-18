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

#include "negaflow/imaging/digital_film_color_preset.h"
#include "negaflow/imaging/color_model.h"
#include "negaflow/imaging/film_emulation_acutance.h"
#include "negaflow/imaging/film_emulation_color.h"
#include "negaflow/imaging/film_scan_denoise.h"
#include "negaflow/imaging/scanner_target_grade.h"
#include "negaflow/imaging/working_film_look.h"
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
    // 네거티브 반전입니다. 현상에서 가장 비싼 단계입니다(실측 프리뷰 856ms 중 353ms).
    //
    // ☠️ **근사입니다**(곱셈·초월함수, 실측 오차 1.8e-07). 호출부가
    //    `ApproximateAcceleratorScope` 안에서만 부릅니다 — 내보내기·골든은 CPU 그대로입니다.
    //    `response` 는 `{yCeil, amplitude, rate, shape}` 넷입니다.
    [[nodiscard]] bool apply_negative_inversion(
        float* pixels,
        std::uint32_t width,
        std::uint32_t height,
        std::uint32_t stride_pixels,
        const float* dmin,
        const float* dmax_normalized,
        const float* response) noexcept;

    // 디지털 필름 룩의 재료 커널 둘입니다. 필름 스캔이 아니라 **디지털 원본** 경로에서만
    // 돕니다 — 스캔본에는 이미 유제를 통과한 신호가 있어 같은 물리를 두 번 얹지 않습니다.
    //
    // ☠️ 둘 다 **근사**입니다. 호출부(`imaging/digital_halation.cpp`·`digital_film_grain.cpp`)가
    //    `ApproximateAcceleratorScope` 안에서만 부릅니다.
    //    `amplitude` 는 **이미 세기가 곱해진** 값입니다 — 여기서 다시 곱하지 마십시오.
    [[nodiscard]] bool apply_digital_halation(
        float* pixels,
        std::uint32_t width,
        std::uint32_t height,
        std::uint32_t stride_pixels,
        const double* scatter_strength,
        const double* halation_strength,
        double radius_ratio,
        double strength) noexcept;

    [[nodiscard]] bool apply_digital_film_grain(
        float* pixels,
        std::uint32_t width,
        std::uint32_t height,
        std::uint32_t stride_pixels,
        float amplitude,
        float chroma_ratio,
        float size) noexcept;

    [[nodiscard]] bool apply_digital_film_color_preset(
        float* pixels,
        std::uint32_t width,
        std::uint32_t height,
        std::uint32_t stride_pixels,
        const imaging::DigitalFilmColorPreset* preset,
        float strength) noexcept;

    [[nodiscard]] bool apply_film_emulation_cube(
        float* pixels,
        std::uint32_t width,
        std::uint32_t height,
        std::uint32_t stride_pixels,
        const imaging::FilmEmulationColorCube* cube) noexcept;

    [[nodiscard]] bool apply_film_emulation_acutance(
        float* pixels,
        std::uint32_t width,
        std::uint32_t height,
        std::uint32_t stride_pixels,
        const imaging::FilmEmulationAcutanceSetup* setup) noexcept;

    // 디지털 필름 룩 **사슬 전체**입니다. 재료별 진입점과 달리 왕복이 **한 번**입니다 —
    // 24MP 에서 재료마다 올렸다 내리면 277 MB × 10 이 오갑니다.
    [[nodiscard]] bool apply_digital_film_look(
        float* pixels,
        std::uint32_t width,
        std::uint32_t height,
        std::uint32_t stride_pixels,
        const imaging::DigitalFilmLookPlan* plan,
        imaging::DigitalFilmLookApplied* applied) noexcept;

    // 실측 `CIVibrance` 표를 쓰는 둘입니다. 표는 프로세스에 **한 벌**만 올라갑니다.
    [[nodiscard]] bool apply_muted_scene_vibrance(
        float* pixels,
        std::uint32_t width,
        std::uint32_t height,
        std::uint32_t stride_pixels,
        float amount) noexcept;

    [[nodiscard]] bool apply_color_model(
        float* pixels,
        std::uint32_t width,
        std::uint32_t height,
        std::uint32_t stride_pixels,
        const imaging::ColorModelParameters* parameters) noexcept;

    // 엔진에서 가장 비싼 화소별 커널입니다 — 노리츠 프리뷰 실측으로 병렬화 뒤에도
    // 16,201 ms 이고 전체의 90% 를 넘습니다.
    [[nodiscard]] bool apply_scanner_target_grade(
        float* pixels,
        std::uint32_t width,
        std::uint32_t height,
        std::uint32_t stride_pixels,
        const imaging::ScannerTargetGradeSetup* setup) noexcept;

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
