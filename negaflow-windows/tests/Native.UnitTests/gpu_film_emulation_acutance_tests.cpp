// CPU/GPU 동치 시험 — 필름 스톡 아큐턴스(분리형 11탭 가우시안 언샤프).
//
// ☠️ **참조를 옮겨 적지 않습니다.** 진짜 CPU 함수 `apply_film_emulation_acutance` 를
//    그대로 부르고 그 결과와 겨룹니다. 가중치도 진짜
//    `prepare_film_emulation_acutance` 가 만든 것을 씁니다.
//
// ⚠️ CPU 는 두 패스를 `double` 로 누적하고 GPU 는 float 입니다. 11항이라 누적 오차가
//    1e-6 대이고, 언샤프 세기가 다시 눌러 출력에서는 더 작아집니다.
//
// 가장자리를 반드시 지나가게 폭·높이를 작게 잡습니다 — 지지 반경이 5 라 `clamp` 경계가
// 이미지의 5%대를 차지합니다. 큰 이미지만 시험하면 그 경로가 안 돌아갑니다.

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_film_emulation_acutance.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/imaging/film_emulation_acutance.h"

namespace {

using negaflow::core::Rgba32F;
using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuDevicePreference;
using negaflow::gpu::GpuFilmEmulationAcutance;
using negaflow::gpu::GpuImageStatus;
using negaflow::gpu::GpuKernelStatus;
using negaflow::gpu::GpuWorkingImage;
using negaflow::imaging::FilmEmulation;
using negaflow::imaging::FilmEmulationAcutanceScratch;
using negaflow::imaging::FilmEmulationAcutanceScratchPixel;

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

constexpr float tolerance = 1.0e-5F;
constexpr std::uint32_t width = 213U;
constexpr std::uint32_t height = 97U;

// 언샤프가 실제로 무엇인가를 하도록 고주파를 넣습니다. 평탄한 영역만 주면
// `source - blurred` 가 0 이라 세기를 아무렇게나 써도 시험이 통과합니다.
[[nodiscard]] std::vector<Rgba32F> make_pattern() {
    std::vector<Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::uint32_t seed = (x * 73856093U) ^ (y * 19349663U);
            const std::uint32_t mixed = (seed ^ (seed >> 13U)) * 1274126177U;
            const float noise = static_cast<float>(mixed >> 8U) / 16777216.0F;
            const bool edge = ((x / 7U) + (y / 5U)) % 3U == 0U;
            const float base = edge ? 0.92F : 0.06F;
            pixels[(static_cast<std::size_t>(y) * width) + x] = Rgba32F{
                base + (noise * 0.05F),
                base * 0.8F,
                base * 0.55F + (noise * 0.02F),
                0.25F + (0.5F * noise)};
        }
    }
    return pixels;
}

void acutance_matches_cpu(
    const GpuDevice& device,
    const char* const label,
    const FilmEmulation emulation,
    const double intensity) {
    const negaflow::imaging::FilmEmulationAcutanceParameters parameters{
        emulation, intensity};
    const negaflow::imaging::FilmEmulationAcutanceSetup setup =
        negaflow::imaging::prepare_film_emulation_acutance(parameters);
    if (!setup.applied) {
        expect(false, "setup must report that acutance applies");
        return;
    }

    const std::vector<Rgba32F> pixels = make_pattern();
    std::vector<Rgba32F> cpu = pixels;
    std::vector<FilmEmulationAcutanceScratchPixel> scratch(
        negaflow::imaging::film_emulation_acutance_scratch_pixel_count(width));
    const negaflow::core::ConstImageView input{cpu.data(), cpu.size(), width, height, width};
    const negaflow::core::ImageView output{cpu.data(), cpu.size(), width, height, width};
    if (negaflow::imaging::apply_film_emulation_acutance(
            input,
            output,
            parameters,
            FilmEmulationAcutanceScratch{scratch.data(), scratch.size()}) !=
        negaflow::core::KernelStatus::ok) {
        expect(false, "CPU acutance must succeed");
        return;
    }

    GpuFilmEmulationAcutance kernel{};
    if (GpuFilmEmulationAcutance::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "acutance kernel must be creatable");
        return;
    }
    GpuWorkingImage source{};
    GpuWorkingImage middle[GpuFilmEmulationAcutance::scratch_count]{};
    GpuWorkingImage destination{};
    if (GpuWorkingImage::upload(device, pixels.data(), width, height, width, source) !=
            GpuImageStatus::ok ||
        GpuWorkingImage::create(device, width, height, middle[0]) != GpuImageStatus::ok ||
        GpuWorkingImage::create(device, width, height, destination) != GpuImageStatus::ok) {
        expect(false, "acutance images must be creatable");
        return;
    }
    if (kernel.dispatch(device, source, middle, destination, setup) != GpuKernelStatus::ok) {
        expect(false, "acutance dispatch must succeed");
        return;
    }
    std::vector<Rgba32F> gpu(pixels.size());
    if (destination.download(device, gpu.data(), width) != GpuImageStatus::ok) {
        expect(false, "acutance download must succeed");
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
        std::cerr << "FAIL: " << label << " acutance delta " << worst << " exceeds "
                  << tolerance << '\n';
        ++failures;
    } else {
        std::cout << label << " acutance max delta " << worst << '\n';
    }
}

void run_all(const GpuDevice& device, const char* const label) {
    acutance_matches_cpu(device, label, FilmEmulation::portra_400, 1.0);
    acutance_matches_cpu(device, label, FilmEmulation::velvia_50, 0.6);
    acutance_matches_cpu(device, label, FilmEmulation::vision3_500t, 0.25);
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
    std::cout << "gpu film emulation acutance tests passed\n";
    return 0;
}
