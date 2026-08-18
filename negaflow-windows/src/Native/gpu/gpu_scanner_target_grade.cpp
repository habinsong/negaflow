#include "negaflow/gpu/gpu_scanner_target_grade.h"

// fxc 가 만든 헤더는 `const BYTE ...[]` 로 나오므로 Windows 타입이 먼저 보여야 합니다.
#include <windows.h>

#include <cmath>
#include <cstddef>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/scanner_target_grade_ScannerTargetGradeMain.h"

namespace negaflow::gpu {
namespace {

using Setup = imaging::ScannerTargetGradeSetup;

// HLSL `cbuffer ScannerTargetGradeConstants` 와 같은 배치여야 합니다.
//
// ⚠️ 상수 버퍼의 배열은 원소마다 **16바이트**입니다. 9개짜리 톤 배열을 `float[9]` 로 두면
//    144바이트를 먹고 인덱싱도 어긋납니다 — `float4[3]` 으로 묶습니다.
struct alignas(16) ScannerTargetGradeConstants final {
    GpuPointwiseExtent extent{};
    float tone_xs[3][4]{};
    float tone_ys[3][4]{};
    float neutral_bins[Setup::neutral_capacity][4]{};
    float hue_anchors[Setup::hue_capacity][4]{};
    float chroma_bands[Setup::chroma_capacity][4]{};
    std::uint32_t neutral_count{0U};
    std::uint32_t hue_count{0U};
    float strength{0.0F};
    float chroma_keep{0.0F};
    std::uint32_t monochrome{0U};
    float padding[3]{0.0F, 0.0F, 0.0F};
};

static_assert(
    sizeof(ScannerTargetGradeConstants) == 16U + 48U + 48U + 160U + 128U + 48U + 16U + 16U,
    "constant layout must match the shader");
static_assert((sizeof(ScannerTargetGradeConstants) % 16U) == 0U, "16-byte registers");

[[nodiscard]] bool finite_setup(const Setup& setup) noexcept {
    for (std::size_t i = 0U; i < Setup::tone_knots; ++i) {
        if (!std::isfinite(setup.tone_xs[i]) || !std::isfinite(setup.tone_ys[i])) {
            return false;
        }
    }
    for (std::size_t i = 0U; i < Setup::neutral_capacity; ++i) {
        for (int c = 0; c < 3; ++c) {
            if (!std::isfinite(setup.neutral_bins[i][c])) {
                return false;
            }
        }
    }
    for (std::size_t i = 0U; i < Setup::hue_capacity; ++i) {
        for (int c = 0; c < 3; ++c) {
            if (!std::isfinite(setup.hue_anchors[i][c])) {
                return false;
            }
        }
    }
    for (std::size_t i = 0U; i < Setup::chroma_capacity; ++i) {
        if (!std::isfinite(setup.chroma_bands[i][0]) ||
            !std::isfinite(setup.chroma_bands[i][1])) {
            return false;
        }
    }
    return std::isfinite(setup.strength) && std::isfinite(setup.chroma_keep);
}

}  // namespace

GpuKernelStatus GpuScannerTargetGrade::create(
    const GpuDevice& device,
    GpuScannerTargetGrade& kernel) noexcept {
    return GpuPointwiseKernel::create(
        device,
        negaflow_scanner_target_grade_cs,
        sizeof(negaflow_scanner_target_grade_cs),
        sizeof(ScannerTargetGradeConstants),
        kernel.kernel_);
}

GpuKernelStatus GpuScannerTargetGrade::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage& destination,
    const Setup& setup) const noexcept {
    if (!finite_setup(setup)) {
        return GpuKernelStatus::non_finite_parameter;
    }
    // ☠️ 색상 앵커의 로그 보간은 이득이 양수여야 합니다. 0 이나 음수가 들어오면
    //    `log` 가 −inf/NaN 을 내고 전 화소가 망가집니다 — CPU 표에는 없는 값이지만
    //    여기서 막아 두면 표가 바뀌어도 조용히 깨지지 않습니다.
    for (std::uint32_t i = 0U; i < setup.hue_count; ++i) {
        if (!(setup.hue_anchors[i][1] > 0.0F)) {
            return GpuKernelStatus::non_finite_parameter;
        }
    }
    for (std::size_t i = 0U; i < Setup::chroma_capacity; ++i) {
        if (!(setup.chroma_bands[i][1] > 0.0F)) {
            return GpuKernelStatus::non_finite_parameter;
        }
    }
    if (setup.hue_count == 0U || setup.hue_count > Setup::hue_capacity ||
        setup.neutral_count > Setup::neutral_capacity) {
        return GpuKernelStatus::invalid_arguments;
    }

    ScannerTargetGradeConstants payload{};
    for (std::size_t i = 0U; i < Setup::tone_knots; ++i) {
        payload.tone_xs[i >> 2U][i & 3U] = setup.tone_xs[i];
        payload.tone_ys[i >> 2U][i & 3U] = setup.tone_ys[i];
    }
    for (std::size_t i = 0U; i < Setup::neutral_capacity; ++i) {
        for (int c = 0; c < 3; ++c) {
            payload.neutral_bins[i][c] = setup.neutral_bins[i][c];
        }
    }
    for (std::size_t i = 0U; i < Setup::hue_capacity; ++i) {
        for (int c = 0; c < 3; ++c) {
            payload.hue_anchors[i][c] = setup.hue_anchors[i][c];
        }
    }
    for (std::size_t i = 0U; i < Setup::chroma_capacity; ++i) {
        payload.chroma_bands[i][0] = setup.chroma_bands[i][0];
        payload.chroma_bands[i][1] = setup.chroma_bands[i][1];
    }
    payload.neutral_count = setup.neutral_count;
    payload.hue_count = setup.hue_count;
    payload.strength = setup.strength;
    payload.chroma_keep = setup.chroma_keep;
    payload.monochrome = setup.monochrome ? 1U : 0U;

    return kernel_.dispatch(device, source, destination, &payload, sizeof(payload));
}

}  // namespace negaflow::gpu
