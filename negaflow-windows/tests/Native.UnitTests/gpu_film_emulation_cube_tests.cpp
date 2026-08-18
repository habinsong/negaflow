// CPU/GPU 동치 시험 — 필름 스톡 색 큐브(33³ 3D LUT).
//
// ☠️ **참조를 옮겨 적지 않습니다.** 진짜 CPU 함수 `apply_film_emulation_color_cube` 를
//    그대로 부르고 그 결과와 겨룹니다. 큐브도 진짜 `build_film_emulation_color_cube` 로
//    만듭니다 — 표를 지어내면 시험이 아무것도 증명하지 않습니다.
//
// ☠️ **하드웨어 삼선형을 쓰지 않는다는 것을 이 시험이 지킵니다.** `Texture3D` +
//    `SampleLevel` 로 바꾸면 필터 가중치가 8비트로 양자화돼 오차가 1e-5 를 넘습니다.
//    이 시험이 깨지면 먼저 그것부터 의심하십시오.

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <memory>
#include <vector>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_film_emulation_cube.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/imaging/film_emulation_color.h"

namespace {

using negaflow::core::Rgba32F;
using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuDevicePreference;
using negaflow::gpu::GpuFilmEmulationCube;
using negaflow::gpu::GpuImageStatus;
using negaflow::gpu::GpuKernelStatus;
using negaflow::gpu::GpuWorkingImage;
using negaflow::imaging::FilmEmulation;
using negaflow::imaging::FilmEmulationColorCube;

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

constexpr float tolerance = 1.0e-5F;
constexpr std::uint32_t width = 512U;
constexpr std::uint32_t height = 256U;

// 큐브 격자 사이를 촘촘히 지나가게 만듭니다. 격자점만 밟으면 보간이 시험되지 않습니다.
// [0,1] 밖 값도 섞습니다 — CPU 는 그것을 클램프해 큐브에 넣으므로 GPU 도 같아야 합니다.
[[nodiscard]] std::vector<Rgba32F> make_pattern() {
    std::vector<Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float u = static_cast<float>(x) / static_cast<float>(width - 1U);
            const float v = static_cast<float>(y) / static_cast<float>(height - 1U);
            pixels[(static_cast<std::size_t>(y) * width) + x] = Rgba32F{
                -0.05F + (1.15F * u),
                -0.05F + (1.15F * v),
                -0.05F + (1.15F * std::fabs(u - v)),
                0.25F + (0.5F * u)};
        }
    }
    return pixels;
}

void cube_matches_cpu(
    const GpuDevice& device,
    const char* const label,
    const FilmEmulation emulation,
    const double intensity) {
    const negaflow::imaging::FilmEmulationColorParameters parameters{emulation, intensity};
    auto cube = std::make_unique<FilmEmulationColorCube>();
    if (negaflow::imaging::build_film_emulation_color_cube(parameters, *cube) !=
        negaflow::core::KernelStatus::ok) {
        expect(false, "cube must build");
        return;
    }

    const std::vector<Rgba32F> pixels = make_pattern();
    std::vector<Rgba32F> cpu = pixels;
    const negaflow::core::ConstImageView input{
        cpu.data(), cpu.size(), width, height, width};
    const negaflow::core::ImageView output{cpu.data(), cpu.size(), width, height, width};
    if (negaflow::imaging::apply_film_emulation_color_cube(
            input, output, parameters, cube.get()) != negaflow::core::KernelStatus::ok) {
        expect(false, "CPU cube must succeed");
        return;
    }

    GpuFilmEmulationCube kernel{};
    if (GpuFilmEmulationCube::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "cube kernel must be creatable");
        return;
    }
    GpuWorkingImage source{};
    GpuWorkingImage destination{};
    if (GpuWorkingImage::upload(device, pixels.data(), width, height, width, source) !=
            GpuImageStatus::ok ||
        GpuWorkingImage::create(device, width, height, destination) != GpuImageStatus::ok) {
        expect(false, "cube images must be creatable");
        return;
    }
    if (kernel.dispatch(device, source, destination, *cube) != GpuKernelStatus::ok) {
        expect(false, "cube dispatch must succeed");
        return;
    }
    std::vector<Rgba32F> gpu(pixels.size());
    if (destination.download(device, gpu.data(), width) != GpuImageStatus::ok) {
        expect(false, "cube download must succeed");
        return;
    }

    float worst = 0.0F;
    for (std::size_t index = 0U; index < gpu.size(); ++index) {
        worst = std::max(worst, std::abs(cpu[index].red - gpu[index].red));
        worst = std::max(worst, std::abs(cpu[index].green - gpu[index].green));
        worst = std::max(worst, std::abs(cpu[index].blue - gpu[index].blue));
        worst = std::max(worst, std::abs(cpu[index].alpha - gpu[index].alpha));
    }
    if (worst > tolerance) {
        std::cerr << "FAIL: " << label << " cube delta " << worst << " exceeds " << tolerance
                  << '\n';
        ++failures;
    } else {
        std::cout << label << " cube max delta " << worst << '\n';
    }
}

void run_all(const GpuDevice& device, const char* const label) {
    cube_matches_cpu(device, label, FilmEmulation::portra_400, 0.8);
    cube_matches_cpu(device, label, FilmEmulation::velvia_50, 1.0);
    cube_matches_cpu(device, label, FilmEmulation::vision3_500t, 0.35);
}

}  // namespace

int main() {
    const GpuDevice warp = GpuDevice::create(GpuDevicePreference::warp_only);
    if (warp.is_usable()) {
        run_all(warp, "WARP");
    } else {
        std::cout << "WARP unavailable — skipped\n";
    }

    const GpuDevice hardware = GpuDevice::create(GpuDevicePreference::hardware_only);
    if (hardware.is_usable()) {
        run_all(hardware, hardware.capability().adapter.description.data());
    } else {
        std::cout << "hardware adapter unavailable — skipped\n";
    }

    if (failures != 0) {
        std::cerr << failures << " failure(s)\n";
        return 1;
    }
    std::cout << "gpu film emulation cube tests passed\n";
    return 0;
}
