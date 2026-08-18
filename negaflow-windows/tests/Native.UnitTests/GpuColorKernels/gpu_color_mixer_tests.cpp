// macOS `ChromabaseMetalKernels.swift:74` `colorMixerHSL` — CPU `imaging/color_mixer.cpp`.
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
#include "negaflow/imaging/color_mixer.h"

namespace gpu_color_kernel_tests {
namespace {

using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuImageStatus;
using negaflow::gpu::GpuKernelStatus;
using negaflow::gpu::GpuWorkingImage;
using negaflow::gpu::GpuColorMixer;

struct MixerCase final {
    const char* name;
    int band;          // -1 이면 전 밴드
    float hue;
    float saturation;
    float luminance;
};

const MixerCase mixer_cases[] = {
    {"mixer_neutral", -1, 0.0F, 0.0F, 0.0F},
    {"mixer_red_hue", 0, 0.8F, 0.0F, 0.0F},
    {"mixer_orange_sat", 1, 0.0F, 0.7F, 0.0F},
    {"mixer_yellow_lum", 2, 0.0F, 0.0F, 0.6F},
    {"mixer_green_all", 3, -0.5F, -0.4F, 0.3F},
    {"mixer_aqua", 4, 0.4F, 0.5F, -0.5F},
    {"mixer_blue", 5, -0.9F, 0.9F, 0.0F},
    {"mixer_purple", 6, 0.3F, -0.8F, 0.4F},
    {"mixer_magenta_wrap", 7, 0.95F, 0.2F, -0.2F},
    {"mixer_every_band", -1, 0.35F, -0.25F, 0.2F},
};

}  // namespace

void mixer_matches_cpu(const GpuDevice& device, const char* const label) {
    GpuColorMixer kernel{};
    if (GpuColorMixer::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "mixer kernel must be creatable");
        return;
    }

    const std::vector<Rgba32F> source = make_ramp();
    GpuWorkingImage input{};
    if (GpuWorkingImage::upload(device, source.data(), width, height, width, input) !=
        GpuImageStatus::ok) {
        expect(false, "mixer source upload must succeed");
        return;
    }
    GpuWorkingImage output{};
    if (GpuWorkingImage::create(device, width, height, output) != GpuImageStatus::ok) {
        expect(false, "mixer destination must be creatable");
        return;
    }

    for (const MixerCase& scenario : mixer_cases) {
        negaflow::imaging::ColorMixerParameters cpu_parameters{};
        negaflow::gpu::GpuColorMixerParameters gpu_parameters{};
        for (std::size_t band = 0U; band < negaflow::imaging::color_mixer_band_count; ++band) {
            const bool touched =
                scenario.band < 0 || static_cast<std::size_t>(scenario.band) == band;
            if (!touched) {
                continue;
            }
            cpu_parameters.hue[band] = scenario.hue;
            cpu_parameters.saturation[band] = scenario.saturation;
            cpu_parameters.luminance[band] = scenario.luminance;
            gpu_parameters.hue[band] = scenario.hue;
            gpu_parameters.saturation[band] = scenario.saturation;
            gpu_parameters.luminance[band] = scenario.luminance;
        }

        if (kernel.dispatch(device, input, output, gpu_parameters) != GpuKernelStatus::ok) {
            expect(false, "mixer dispatch must succeed");
            continue;
        }
        std::vector<Rgba32F> gpu_pixels(source.size());
        if (output.download(device, gpu_pixels.data(), width) != GpuImageStatus::ok) {
            expect(false, "mixer download must succeed");
            continue;
        }

        std::vector<Rgba32F> cpu_pixels(source.size());
        const negaflow::core::ConstImageView view{
            source.data(), source.size(), width, height, width};
        const negaflow::core::ImageView out{
            cpu_pixels.data(), cpu_pixels.size(), width, height, width};
        (void)negaflow::imaging::apply_color_mixer(view, out, cpu_parameters);

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

    negaflow::gpu::GpuColorMixerParameters bad{};
    bad.saturation[3] = std::numeric_limits<float>::quiet_NaN();
    expect(
        kernel.dispatch(device, input, output, bad) == GpuKernelStatus::non_finite_parameter,
        "NaN mixer band is rejected");
}

// 원색 보정 — macOS `calibrationPrimaries`. 믹서와 모양은 같지만 상수가 다르고 광도가 없습니다.

}  // namespace gpu_color_kernel_tests
