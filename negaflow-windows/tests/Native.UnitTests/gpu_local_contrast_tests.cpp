// CPU/GPU 동치 시험 — 부분 대비(SP 기본 부분 대비 포함).
//
// CPU 판 : `imaging/detail_enhancement.cpp` `apply_local_contrast` (질감 단계로 부릅니다)
// GPU 판 : `gpu/shaders/local_contrast.hlsl` + `gpu/gpu_local_contrast.cpp`
//
// 축소 배율이 1 인 작은 화상과, 배율이 2 이고 가장자리 칸이 덜 찬 홀수 크기 화상을 봅니다.
// 축소 평면의 가우시안은 CPU 와 같은 가중치·누적 순서라 같고, 남는 차이는 감마 변환의 `pow`
// 와 `tanh` 입니다(D3D11 이 상대오차 2^-21 을 허용). 그 1~2 ulp 가 계수 a = v/(v+0.01) 에서
// 최대 100 배쯤 커지므로 허용치를 2e-4 로 둡니다 — 8 비트 한 단계(3.9e-3)의 1/20 입니다.

#include "negaflow/gpu/gpu_local_contrast.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <utility>
#include <vector>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_neighborhood.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/imaging/texture_stage.h"

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
using negaflow::gpu::GpuGaussianBlur;
using negaflow::gpu::GpuImageStatus;
using negaflow::gpu::GpuKernelStatus;
using negaflow::gpu::GpuLocalContrast;
using negaflow::gpu::GpuWorkingImage;

constexpr float tolerance = 2.0e-4F;

// 매끈한 기울기 + 질감 + 큰 경계 + 0 근처 암부 + 1 넘는 명부. 알파도 일부 바꿉니다.
[[nodiscard]] std::vector<Rgba32F> make_scene(const std::uint32_t width, const std::uint32_t height) {
    std::vector<Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float u = static_cast<float>(x) / static_cast<float>(width - 1U);
            const float v = static_cast<float>(y) / static_cast<float>(height - 1U);
            const float texture = 0.06F * std::sin(static_cast<float>(x) * 0.9F) *
                std::cos(static_cast<float>(y) * 0.7F);
            const float edge = x > width / 2U ? 0.35F : 0.0F;
            float level = std::max(0.0F, (0.08F + (0.55F * u * v) + texture + edge));
            if (x < 3U && y < 3U) {
                level = 0.0F;
            }
            if (x + 4U > width && y + 4U > height) {
                level = 1.4F;
            }
            const float alpha = (x + y) % 7U == 0U ? 0.5F : 1.0F;
            pixels[(static_cast<std::size_t>(y) * width) + x] =
                Rgba32F{level * 1.05F, level, level * 0.82F, alpha};
        }
    }
    return pixels;
}

void matches_cpu(
    const GpuDevice& device,
    const char* const label,
    const std::uint32_t width,
    const std::uint32_t height) {
    GpuGaussianBlur blur{};
    GpuLocalContrast kernel{};
    if (GpuGaussianBlur::create(device, blur) != GpuKernelStatus::ok ||
        GpuLocalContrast::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "local contrast kernels must be creatable");
        return;
    }
    const std::vector<Rgba32F> source = make_scene(width, height);
    GpuWorkingImage input{};
    GpuWorkingImage output{};
    if (GpuWorkingImage::upload(device, source.data(), width, height, width, input) !=
            GpuImageStatus::ok ||
        GpuWorkingImage::create(device, width, height, output) != GpuImageStatus::ok) {
        expect(false, "local contrast images must be creatable");
        return;
    }

    const float clarity_cases[] = {
        negaflow::imaging::sp_target_local_contrast, 1.0F, -1.0F, 0.45F};
    for (const float clarity : clarity_cases) {
        if (kernel.dispatch(device, blur, input, output, clarity) != GpuKernelStatus::ok) {
            expect(false, "local contrast dispatch must succeed");
            continue;
        }
        std::vector<Rgba32F> gpu_pixels(source.size());
        if (output.download(device, gpu_pixels.data(), width) != GpuImageStatus::ok) {
            expect(false, "local contrast download must succeed");
            continue;
        }

        negaflow::imaging::WorkingImage cpu{width, height, width, source};
        negaflow::imaging::TextureStageParameters parameters{};
        parameters.clarity = clarity;
        const auto cpu_result = negaflow::imaging::apply_texture_stage(std::move(cpu), parameters);
        if (cpu_result.status != negaflow::imaging::TextureStageStatus::ok) {
            expect(false, "CPU texture stage must succeed");
            continue;
        }

        float worst = 0.0F;
        float moved = 0.0F;
        for (std::size_t index = 0U; index < source.size(); ++index) {
            const Rgba32F& left = cpu_result.image.pixels[index];
            const Rgba32F& right = gpu_pixels[index];
            worst = std::max(worst, std::abs(left.red - right.red));
            worst = std::max(worst, std::abs(left.green - right.green));
            worst = std::max(worst, std::abs(left.blue - right.blue));
            worst = std::max(worst, std::abs(left.alpha - right.alpha));
            moved = std::max(moved, std::abs(left.green - source[index].green));
        }
        // 시험 화상이 실제로 바뀌어야 비교가 의미 있습니다.
        expect(moved > 1.0e-3F, "the scene must actually change under local contrast");
        if (worst > tolerance) {
            std::cerr << "FAIL: " << label << ' ' << width << 'x' << height << " clarity "
                      << clarity << " max delta " << worst << '\n';
            ++failures;
        } else {
            std::cout << "[gpu] " << label << ' ' << width << 'x' << height << " clarity "
                      << clarity << " max delta " << worst << " moved " << moved << '\n';
        }
    }

    expect(
        kernel.dispatch(device, blur, input, input, 0.2F) == GpuKernelStatus::invalid_arguments,
        "the same texture cannot be read and written");
    expect(
        kernel.dispatch(device, blur, input, output, std::nanf("")) ==
            GpuKernelStatus::non_finite_parameter,
        "NaN clarity is rejected");
}

void run_all(const GpuDevice& device, const char* const label) {
    matches_cpu(device, label, 96U, 64U);
    matches_cpu(device, label, 1203U, 797U);
}

} // namespace

int main() {
    const GpuDevice warp = GpuDevice::create(GpuDevicePreference::warp_only);
    if (!warp.is_usable()) {
        std::cerr << "FAIL: WARP device is required for these checks\n";
        return 1;
    }
    run_all(warp, "warp");

    const GpuDevice hardware = GpuDevice::create(GpuDevicePreference::hardware_only);
    if (hardware.is_usable()) {
        std::cout << "[gpu] hardware: " << hardware.capability().adapter.description.data() << '\n';
        run_all(hardware, "hardware");
    } else {
        std::cout << "[gpu] hardware absent, WARP only\n";
    }

    if (failures != 0) {
        std::cerr << failures << " gpu local contrast check(s) failed\n";
        return 1;
    }
    std::cout << "gpu local contrast checks passed\n";
    return 0;
}
