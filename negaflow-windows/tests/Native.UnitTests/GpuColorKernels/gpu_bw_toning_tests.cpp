// macOS `ChromabaseMetalKernels.swift:123` `bwToning` — CPU `imaging/bw_toning.cpp`.
//
// 허용 오차 `1e-5` 는 float32 반올림 범위입니다 — 넘으면 커널을 고치십시오.

#include "gpu_color_kernel_test_support.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <limits>
#include <string_view>
#include <utility>
#include <vector>

#include "negaflow/gpu/gpu_color_kernels.h"
#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/imaging/bw_toning.h"

namespace gpu_color_kernel_tests {
namespace {

using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuImageStatus;
using negaflow::gpu::GpuKernelStatus;
using negaflow::gpu::GpuWorkingImage;

struct BwCase final {
    const char* name;
    negaflow::imaging::BwToningParameters parameters;
};

const BwCase bw_cases[] = {
    {"bw_none", {negaflow::imaging::BwToningMode::none, 285.0, 34.0, 0.0}},
    // 모드는 켰지만 강도가 임계(1e-4) 아래 — CPU 는 중성화만 합니다.
    {"bw_below_threshold", {negaflow::imaging::BwToningMode::sepia, 285.0, 34.0, 5.0e-5}},
    {"bw_selenium_half", {negaflow::imaging::BwToningMode::selenium, 285.0, 34.0, 0.5}},
    {"bw_selenium_full", {negaflow::imaging::BwToningMode::selenium, 285.0, 34.0, 1.0}},
    {"bw_sepia_half", {negaflow::imaging::BwToningMode::sepia, 285.0, 34.0, 0.5}},
    {"bw_sepia_full", {negaflow::imaging::BwToningMode::sepia, 285.0, 34.0, 1.0}},
    {"bw_custom_hues", {negaflow::imaging::BwToningMode::sepia, 200.0, 90.0, 0.8}},
};

} // namespace

void bw_matches_cpu(const GpuDevice& device, const char* const label) {
    negaflow::gpu::GpuBwToning kernel{};
    if (negaflow::gpu::GpuBwToning::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "bw kernel must be creatable");
        return;
    }

    const std::vector<Rgba32F> source = make_ramp();
    GpuWorkingImage input{};
    if (GpuWorkingImage::upload(device, source.data(), width, height, width, input) !=
        GpuImageStatus::ok) {
        expect(false, "bw source upload must succeed");
        return;
    }
    GpuWorkingImage output{};
    if (GpuWorkingImage::create(device, width, height, output) != GpuImageStatus::ok) {
        expect(false, "bw destination must be creatable");
        return;
    }

    for (const BwCase& scenario : bw_cases) {
        // 색조 계산을 시험에서 다시 구현하지 않습니다 — CPU 와 같은 함수를 씁니다.
        const negaflow::imaging::BwToningSetup cpu_setup =
            negaflow::imaging::prepare_bw_toning(scenario.parameters);
        negaflow::gpu::GpuBwToningSetup gpu_setup{};
        for (int index = 0; index < 3; ++index) {
            gpu_setup.shadow_tint[index] = cpu_setup.shadow_tint[index];
            gpu_setup.highlight_tint[index] = cpu_setup.highlight_tint[index];
        }
        gpu_setup.strength = cpu_setup.strength;
        gpu_setup.mode = cpu_setup.mode;
        gpu_setup.tone = cpu_setup.tone;

        if (kernel.dispatch(device, input, output, gpu_setup) != GpuKernelStatus::ok) {
            expect(false, "bw dispatch must succeed");
            continue;
        }
        std::vector<Rgba32F> gpu_pixels(source.size());
        if (output.download(device, gpu_pixels.data(), width) != GpuImageStatus::ok) {
            expect(false, "bw download must succeed");
            continue;
        }

        // CPU 판은 이미지를 값으로 받아 제자리에서 바꿉니다.
        negaflow::imaging::WorkingImage cpu_image{};
        cpu_image.width = width;
        cpu_image.height = height;
        cpu_image.stride_pixels = width;
        cpu_image.pixels = source;
        const negaflow::imaging::BwToningResult cpu_result = negaflow::imaging::apply_bw_toning(
            std::move(cpu_image),
            negaflow::imaging::NegativeFilmType::black_and_white,
            scenario.parameters);
        if (cpu_result.status != negaflow::imaging::BwToningStatus::ok) {
            expect(false, "cpu bw reference must succeed");
            continue;
        }

        float worst = 0.0F;
        for (std::size_t index = 0U; index < gpu_pixels.size(); ++index) {
            const Rgba32F& cpu = cpu_result.image.pixels[index];
            worst = std::max(worst, std::abs(cpu.red - gpu_pixels[index].red));
            worst = std::max(worst, std::abs(cpu.green - gpu_pixels[index].green));
            worst = std::max(worst, std::abs(cpu.blue - gpu_pixels[index].blue));
            worst = std::max(worst, std::abs(cpu.alpha - gpu_pixels[index].alpha));
        }
        if (worst > tolerance) {
            std::cerr << "FAIL: " << label << ' ' << scenario.name << " max delta " << worst
                      << '\n';
            ++failures;
        } else {
            std::cout << "[gpu] " << label << ' ' << scenario.name << " max delta " << worst
                      << '\n';
        }
    }
}

// 디지털 흑백 유제 — macOS `digitalBWFilm`. CPU 판이 화소 계산을 `double` 로 하므로
// float32 GPU 와의 오차가 다른 커널보다 클 수 있습니다. 허용치는 그대로 `1e-5` 입니다.

} // namespace gpu_color_kernel_tests
