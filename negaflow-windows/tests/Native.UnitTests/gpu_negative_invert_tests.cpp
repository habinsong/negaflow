// CPU/GPU 동치 시험 — 네거티브 반전.
//
// macOS  : `ChromabaseMetalKernels.swift:557` `negativeInvert`
// CPU 판 : `core/negative_inversion.cpp` `apply_negative_inversion`
// GPU 판 : `gpu/shaders/negative_invert.hlsl` + `gpu/gpu_negative_invert.cpp`
//
// 이 커널은 화소마다 채널별로 `log10`·`pow`·`exp` 를 돕니다. 초월함수는 구현마다 마지막
// 비트가 다를 수 있어 **오차가 다른 커널보다 큽니다.** 그래도 허용치는 `1e-5` 그대로입니다 —
// 넘으면 반올림이 아니라 이식 실수입니다.

#include "negaflow/gpu/gpu_negative_invert.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

#include "negaflow/core/negative_inversion.h"
#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

using negaflow::core::Rgba32F;
using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuDevicePreference;
using negaflow::gpu::GpuImageStatus;
using negaflow::gpu::GpuKernelStatus;
using negaflow::gpu::GpuNegativeInvert;
using negaflow::gpu::GpuNegativeInvertParameters;
using negaflow::gpu::GpuWorkingImage;

constexpr float tolerance = 1.0e-5F;
constexpr std::uint32_t width = 64U;
constexpr std::uint32_t height = 48U;

// 스캔 투과율입니다. 아주 어두운 값(1e-5 하한이 걸리는 자리)부터 베이스 근처까지 깝니다 —
// `density` 의 부호가 바뀌는 지점(토 미러링)을 반드시 지나야 합니다.
[[nodiscard]] std::vector<Rgba32F> make_transmission() {
    std::vector<Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float u = static_cast<float>(x) / static_cast<float>(width - 1U);
            const float v = static_cast<float>(y) / static_cast<float>(height - 1U);
            pixels[(static_cast<std::size_t>(y) * width) + x] = Rgba32F{
                // 0 을 포함시켜 1e-5 하한 가지를 지나게 합니다.
                u * 0.42F,
                (0.002F + (v * 0.30F)),
                (1.0F - u) * 0.25F,
                1.0F};
        }
    }
    return pixels;
}

struct Case final {
    const char* name;
    negaflow::core::NegativeInversionParameters parameters;
};

// 실측 코퍼스에서 나온 dmin 범위 근처와, 채널이 크게 갈리는 경우를 함께 봅니다.
const Case cases[] = {
    {"invert_typical", {{0.1910F, 0.0940F, 0.0711F}, {1.0F, 1.0F, 1.0F}}},
    {"invert_narrow_range", {{0.1910F, 0.0940F, 0.0711F}, {0.42F, 0.40F, 0.38F}}},
    {"invert_wide_range", {{0.36F, 0.20F, 0.11F}, {1.8F, 1.7F, 1.6F}}},
    {"invert_neutral_base", {{0.20F, 0.20F, 0.20F}, {1.0F, 1.0F, 1.0F}}},
    {"invert_low_base", {{0.02F, 0.015F, 0.012F}, {0.5F, 0.5F, 0.5F}}},
};

void invert_matches_cpu(const GpuDevice& device, const char* const label) {
    GpuNegativeInvert kernel{};
    if (GpuNegativeInvert::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "invert kernel must be creatable");
        return;
    }

    const std::vector<Rgba32F> source = make_transmission();
    GpuWorkingImage input{};
    if (GpuWorkingImage::upload(device, source.data(), width, height, width, input) !=
        GpuImageStatus::ok) {
        expect(false, "invert source upload must succeed");
        return;
    }
    GpuWorkingImage output{};
    if (GpuWorkingImage::create(device, width, height, output) != GpuImageStatus::ok) {
        expect(false, "invert destination must be creatable");
        return;
    }

    // ☠️ 응답 계수를 시험에서 베껴 쓰지 않습니다 — 엔진의 것을 그대로 씁니다.
    //    베껴 쓰면 셰이더가 틀려도 시험이 같이 틀려 통과합니다.
    const negaflow::core::PrintResponse response =
        negaflow::core::color_negative_print_response();

    for (const Case& scenario : cases) {
        GpuNegativeInvertParameters gpu_parameters{};
        for (int index = 0; index < 3; ++index) {
            gpu_parameters.dmin[index] = scenario.parameters.dmin[index];
            gpu_parameters.dmax_normalized[index] = scenario.parameters.dmax_normalized[index];
        }
        gpu_parameters.response_y_ceiling = response.y_ceiling;
        gpu_parameters.response_amplitude = response.amplitude;
        gpu_parameters.response_rate = response.rate;
        gpu_parameters.response_shape = response.shape;

        if (kernel.dispatch(device, input, output, gpu_parameters) != GpuKernelStatus::ok) {
            expect(false, "invert dispatch must succeed");
            continue;
        }
        std::vector<Rgba32F> gpu_pixels(source.size());
        if (output.download(device, gpu_pixels.data(), width) != GpuImageStatus::ok) {
            expect(false, "invert download must succeed");
            continue;
        }

        std::vector<Rgba32F> cpu_pixels(source.size());
        const negaflow::core::ConstImageView view{
            source.data(), source.size(), width, height, width};
        const negaflow::core::ImageView out{
            cpu_pixels.data(), cpu_pixels.size(), width, height, width};
        const negaflow::core::KernelStatus cpu_status =
            negaflow::core::apply_negative_inversion(view, out, scenario.parameters, response);
        if (cpu_status != negaflow::core::KernelStatus::ok) {
            expect(false, "cpu reference must succeed for these parameters");
            continue;
        }

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

    // dmin 0 은 `log10` 에서 죽습니다. CPU 판이 매개변수 단계에서 거부하므로 GPU 도 거부해야
    // 합니다 — 통과시키면 화면이 통째로 검게 죽습니다.
    GpuNegativeInvertParameters zero_dmin{};
    zero_dmin.dmin[1] = 0.0F;
    zero_dmin.response_y_ceiling = response.y_ceiling;
    zero_dmin.response_amplitude = response.amplitude;
    zero_dmin.response_rate = response.rate;
    zero_dmin.response_shape = response.shape;
    expect(
        kernel.dispatch(device, input, output, zero_dmin) == GpuKernelStatus::non_finite_parameter,
        "zero dmin is rejected like the CPU path");

    GpuNegativeInvertParameters negative_range{};
    negative_range.dmin[0] = 0.2F;
    negative_range.dmin[1] = 0.2F;
    negative_range.dmin[2] = 0.2F;
    negative_range.dmax_normalized[0] = -1.0F;
    expect(
        kernel.dispatch(device, input, output, negative_range) ==
            GpuKernelStatus::non_finite_parameter,
        "non-positive dmax is rejected");
}

}  // namespace

int main() {
    const GpuDevice warp = GpuDevice::create(GpuDevicePreference::warp_only);
    if (!warp.is_usable()) {
        std::cerr << "FAIL: WARP device is required for these checks\n";
        return 1;
    }
    invert_matches_cpu(warp, "warp");

    const GpuDevice hardware = GpuDevice::create(GpuDevicePreference::hardware_only);
    if (hardware.is_usable()) {
        std::cout << "[gpu] hardware: " << hardware.capability().adapter.description.data() << '\n';
        invert_matches_cpu(hardware, "hardware");
    } else {
        std::cout << "[gpu] hardware absent, WARP only\n";
    }

    if (failures != 0) {
        std::cerr << failures << " gpu negative invert check(s) failed\n";
        return 1;
    }
    std::cout << "gpu negative invert checks passed\n";
    return 0;
}
