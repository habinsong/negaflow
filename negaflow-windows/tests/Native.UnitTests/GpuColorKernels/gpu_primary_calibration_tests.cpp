// macOS `ChromabaseMetalKernels.swift:151` `calibrationPrimaries` — CPU `imaging/primary_calibration.cpp`.
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
#include "negaflow/imaging/primary_calibration.h"

namespace gpu_color_kernel_tests {
namespace {

using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuImageStatus;
using negaflow::gpu::GpuKernelStatus;
using negaflow::gpu::GpuWorkingImage;

struct PrimaryCase final {
    const char* name;
    negaflow::imaging::PrimaryCalibrationParameters parameters;
};

const PrimaryCase primary_cases[] = {
    {"primary_neutral", {}},
    {"primary_red_hue", {0.9F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F}},
    {"primary_red_sat", {0.0F, 0.8F, 0.0F, 0.0F, 0.0F, 0.0F}},
    {"primary_green", {0.0F, 0.0F, -0.7F, 0.5F, 0.0F, 0.0F}},
    {"primary_blue", {0.0F, 0.0F, 0.0F, 0.0F, 0.6F, -0.9F}},
    {"primary_all", {0.4F, -0.3F, -0.5F, 0.35F, 0.25F, 0.45F}},
};

}  // namespace

void primary_matches_cpu(const GpuDevice& device, const char* const label) {
    negaflow::gpu::GpuPrimaryCalibration kernel{};
    if (negaflow::gpu::GpuPrimaryCalibration::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "primary kernel must be creatable");
        return;
    }

    const std::vector<Rgba32F> source = make_ramp();
    GpuWorkingImage input{};
    if (GpuWorkingImage::upload(device, source.data(), width, height, width, input) !=
        GpuImageStatus::ok) {
        expect(false, "primary source upload must succeed");
        return;
    }
    GpuWorkingImage output{};
    if (GpuWorkingImage::create(device, width, height, output) != GpuImageStatus::ok) {
        expect(false, "primary destination must be creatable");
        return;
    }

    for (const PrimaryCase& scenario : primary_cases) {
        const negaflow::gpu::GpuPrimaryCalibrationParameters gpu_parameters{
            scenario.parameters.red_hue,
            scenario.parameters.red_saturation,
            scenario.parameters.green_hue,
            scenario.parameters.green_saturation,
            scenario.parameters.blue_hue,
            scenario.parameters.blue_saturation};

        if (kernel.dispatch(device, input, output, gpu_parameters) != GpuKernelStatus::ok) {
            expect(false, "primary dispatch must succeed");
            continue;
        }
        std::vector<Rgba32F> gpu_pixels(source.size());
        if (output.download(device, gpu_pixels.data(), width) != GpuImageStatus::ok) {
            expect(false, "primary download must succeed");
            continue;
        }

        std::vector<Rgba32F> cpu_pixels(source.size());
        const negaflow::core::ConstImageView view{
            source.data(), source.size(), width, height, width};
        const negaflow::core::ImageView out{
            cpu_pixels.data(), cpu_pixels.size(), width, height, width};
        (void)negaflow::imaging::apply_primary_calibration(view, out, scenario.parameters);

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

    negaflow::gpu::GpuPrimaryCalibrationParameters bad{};
    bad.green_hue = std::numeric_limits<float>::quiet_NaN();
    expect(
        kernel.dispatch(device, input, output, bad) == GpuKernelStatus::non_finite_parameter,
        "NaN primary control is rejected");
}

// 흑백 조색 — macOS `bwToning`. CPU 판은 조색을 꺼도 **먼저 중성화**하므로 그 경우까지 봅니다.

}  // namespace gpu_color_kernel_tests
