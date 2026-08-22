// macOS `ChromabaseMetalKernels.swift:101` `colorGrade` — CPU `imaging/color_grading.cpp`.
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
#include "negaflow/imaging/color_grading.h"

namespace gpu_color_kernel_tests {
namespace {

using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuImageStatus;
using negaflow::gpu::GpuKernelStatus;
using negaflow::gpu::GpuWorkingImage;
using negaflow::gpu::GpuColorGrade;
using negaflow::gpu::GpuColorGradeSetup;

struct Case final {
    const char* name;
    negaflow::imaging::ColorGradingParameters parameters;
};

// 세 영역과 blending/balance 를 따로따로 밀어 각 가중치 가지를 지나게 합니다.
const Case cases[] = {
    {"grade_shadows", {{35.0F, 0.6F, 0.2F}, {}, {}, 0.5F, 0.0F}},
    {"grade_midtones", {{}, {210.0F, 0.5F, -0.3F}, {}, 0.5F, 0.0F}},
    {"grade_highlights", {{}, {}, {120.0F, 0.7F, 0.25F}, 0.5F, 0.0F}},
    {"grade_narrow_blend", {{35.0F, 0.4F, 0.1F}, {210.0F, 0.4F, 0.0F}, {120.0F, 0.4F, -0.1F}, 0.0F, 0.0F}},
    {"grade_wide_blend", {{35.0F, 0.4F, 0.1F}, {210.0F, 0.4F, 0.0F}, {120.0F, 0.4F, -0.1F}, 1.0F, 0.0F}},
    {"grade_balance_low", {{35.0F, 0.5F, 0.2F}, {}, {120.0F, 0.5F, -0.2F}, 0.5F, -1.0F}},
    {"grade_balance_high", {{35.0F, 0.5F, 0.2F}, {}, {120.0F, 0.5F, -0.2F}, 0.5F, 1.0F}},
    {"grade_all", {{20.0F, 0.8F, 0.3F}, {180.0F, 0.6F, -0.25F}, {300.0F, 0.7F, 0.15F}, 0.35F, 0.4F}},
};

} // namespace

void grade_matches_cpu(const GpuDevice& device, const char* const label) {
    GpuColorGrade kernel{};
    if (GpuColorGrade::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "grade kernel must be creatable");
        return;
    }

    const std::vector<Rgba32F> source = make_ramp();
    GpuWorkingImage input{};
    if (GpuWorkingImage::upload(device, source.data(), width, height, width, input) !=
        GpuImageStatus::ok) {
        expect(false, "grade source upload must succeed");
        return;
    }
    GpuWorkingImage output{};
    if (GpuWorkingImage::create(device, width, height, output) != GpuImageStatus::ok) {
        expect(false, "grade destination must be creatable");
        return;
    }

    for (const Case& scenario : cases) {
        // 준비 계산을 시험에서 다시 구현하지 않습니다 — CPU 와 같은 함수를 씁니다.
        // 여기서 베껴 쓰면 셰이더가 틀려도 시험이 같이 틀려 통과합니다.
        const negaflow::imaging::ColorGradingSetup cpu_setup =
            negaflow::imaging::prepare_color_grading(scenario.parameters);
        GpuColorGradeSetup gpu_setup{};
        for (int index = 0; index < 3; ++index) {
            gpu_setup.shadow_offset[index] = cpu_setup.shadow_offset[index];
            gpu_setup.midtone_offset[index] = cpu_setup.midtone_offset[index];
            gpu_setup.highlight_offset[index] = cpu_setup.highlight_offset[index];
        }
        gpu_setup.pivot = cpu_setup.pivot;
        gpu_setup.width = cpu_setup.width;

        if (kernel.dispatch(device, input, output, gpu_setup) != GpuKernelStatus::ok) {
            expect(false, "grade dispatch must succeed");
            continue;
        }
        std::vector<Rgba32F> gpu_pixels(source.size());
        if (output.download(device, gpu_pixels.data(), width) != GpuImageStatus::ok) {
            expect(false, "grade download must succeed");
            continue;
        }

        std::vector<Rgba32F> cpu_pixels(source.size());
        const negaflow::core::ConstImageView view{
            source.data(), source.size(), width, height, width};
        const negaflow::core::ImageView out{
            cpu_pixels.data(), cpu_pixels.size(), width, height, width};
        (void)negaflow::imaging::apply_color_grading(view, out, scenario.parameters);

        float worst = 0.0F;
        for (std::size_t index = 0U; index < cpu_pixels.size(); ++index) {
            worst = std::max(worst, std::abs(cpu_pixels[index].red - gpu_pixels[index].red));
            worst = std::max(worst, std::abs(cpu_pixels[index].green - gpu_pixels[index].green));
            worst = std::max(worst, std::abs(cpu_pixels[index].blue - gpu_pixels[index].blue));
            worst = std::max(worst, std::abs(cpu_pixels[index].alpha - gpu_pixels[index].alpha));
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

    GpuColorGradeSetup bad{};
    bad.pivot = std::numeric_limits<float>::quiet_NaN();
    expect(
        kernel.dispatch(device, input, output, bad) == GpuKernelStatus::non_finite_parameter,
        "NaN pivot is rejected");

    // 폭 0 은 CPU 판에서 0 나누기입니다. 조용히 값을 끼워 넣지 말고 거절해야 합니다.
    GpuColorGradeSetup zero_width{};
    zero_width.width = 0.0F;
    expect(
        kernel.dispatch(device, input, output, zero_width) == GpuKernelStatus::non_finite_parameter,
        "zero width is rejected rather than patched");
}

// 컬러 믹서 — macOS `colorMixerHSL`. 밴드 8개마다 색상/채도/광도.

} // namespace gpu_color_kernel_tests
