// CPU/GPU 동치 시험 — 디지털 원본 전용 스톡 색 프리셋.
//
// ☠️ **참조를 옮겨 적지 않습니다.** 진짜 CPU 함수 `apply_digital_film_color_preset` 을
//    그대로 부르고 그 결과와 겨룹니다.
//
// ☠️ **macOS 의 `digitalFilmColor` 커널(`ChromabaseMetalKernels.swift:774`)이 아닙니다.**
//    그 커널은 `DigitalFilmColor.apply` 만 부르고, 그 함수는 macOS 트리 어디에서도
//    불리지 않습니다. 살아 있는 것은 `DigitalFilmColorPresetStage` 이고 이 시험이 그것입니다.
//
// 겨루는 자리가 둘입니다:
//   ① 프리셋이 셋 다 바꾸는 스톡 — 감마 인코딩 → 믹서 → 그레이딩 → 캘리브레이션 →
//      감마 디코딩 → 강도 혼합, 전 경로.
//   ② **조기 반환** — 프리셋이 안 바꾸는 커널은 CPU 가 커널을 안 돌리고 복사합니다.
//      GPU 가 그 자리에서 디스패치를 건너뛰지 않으면 HSL 왕복의 반올림이 붙습니다.

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <utility>
#include <vector>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_digital_film_color_preset.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/imaging/digital_film_color_preset.h"

namespace {

using negaflow::core::Rgba32F;
using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuDevicePreference;
using negaflow::gpu::GpuDigitalFilmColorPreset;
using negaflow::gpu::GpuImageStatus;
using negaflow::gpu::GpuKernelStatus;
using negaflow::gpu::GpuWorkingImage;
using negaflow::imaging::DigitalFilmColorPreset;
using negaflow::imaging::FilmEmulation;
using negaflow::imaging::WorkingImage;

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

constexpr float tolerance = 1.0e-5F;
// CPU 는 1M 화소마다 타일을 나눕니다. 셋 다 화소별이라 타일이 값의 조건은 아니지만,
// 타일 경계를 여러 번 지나가게 두어 그 주장을 시험이 지키게 합니다.
constexpr std::uint32_t width = 1200U;
constexpr std::uint32_t height = 1000U;

[[nodiscard]] std::vector<Rgba32F> make_pattern() {
    std::vector<Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::uint32_t seed = (x * 73856093U) ^ (y * 19349663U);
            const std::uint32_t mixed = (seed ^ (seed >> 13U)) * 1274126177U;
            const float noise = static_cast<float>(mixed >> 8U) / 16777216.0F;
            // 색상환을 한 바퀴 돌립니다 — 믹서·캘리브레이션은 밴드마다 다른 자리를 씁니다.
            const float hue = static_cast<float>(x) / static_cast<float>(width);
            const float level = 0.02F + (0.96F * static_cast<float>(y) /
                                         static_cast<float>(height));
            pixels[(static_cast<std::size_t>(y) * width) + x] = Rgba32F{
                std::clamp(level * (0.5F + 0.5F * std::sin(hue * 6.2831853F)), 0.0F, 1.0F),
                std::clamp(level * (0.5F + 0.5F * std::sin((hue + 0.333F) * 6.2831853F)),
                           0.0F, 1.0F),
                std::clamp(level * (0.5F + 0.5F * std::sin((hue + 0.667F) * 6.2831853F)),
                           0.0F, 1.0F),
                0.3F + (0.5F * noise)};
        }
    }
    return pixels;
}

[[nodiscard]] WorkingImage make_working_image(const std::vector<Rgba32F>& pixels) {
    WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels = pixels;
    return image;
}

[[nodiscard]] float max_delta(
    const std::vector<Rgba32F>& left,
    const std::vector<Rgba32F>& right) {
    float worst = 0.0F;
    for (std::size_t index = 0U; index < left.size(); ++index) {
        worst = std::max(worst, std::abs(left[index].red - right[index].red));
        worst = std::max(worst, std::abs(left[index].green - right[index].green));
        worst = std::max(worst, std::abs(left[index].blue - right[index].blue));
        worst = std::max(worst, std::abs(left[index].alpha - right[index].alpha));
    }
    return worst;
}

void preset_matches_cpu(
    const GpuDevice& device,
    const char* const label,
    const FilmEmulation emulation,
    const double intensity) {
    const DigitalFilmColorPreset* const preset =
        negaflow::imaging::digital_film_color_preset(emulation);
    if (preset == nullptr) {
        expect(false, "preset table must know this emulation");
        return;
    }
    const std::vector<Rgba32F> pixels = make_pattern();

    auto cpu = negaflow::imaging::apply_digital_film_color_preset(
        make_working_image(pixels), {emulation, intensity});
    expect(
        cpu.status == negaflow::imaging::DigitalFilmColorPresetStatus::ok,
        "CPU preset must succeed");
    expect(cpu.info.applied, "CPU preset must actually apply");

    GpuDigitalFilmColorPreset kernel{};
    if (GpuDigitalFilmColorPreset::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "preset kernel must be creatable");
        return;
    }
    GpuWorkingImage source{};
    if (GpuWorkingImage::upload(device, pixels.data(), width, height, width, source) !=
        GpuImageStatus::ok) {
        expect(false, "preset upload must succeed");
        return;
    }
    GpuWorkingImage scratch[GpuDigitalFilmColorPreset::scratch_count]{};
    for (int index = 0; index < GpuDigitalFilmColorPreset::scratch_count; ++index) {
        if (GpuWorkingImage::create(device, width, height, scratch[index]) !=
            GpuImageStatus::ok) {
            expect(false, "preset scratch must be creatable");
            return;
        }
    }
    const GpuWorkingImage* result = nullptr;
    if (kernel.dispatch(
            device,
            source,
            scratch,
            result,
            *preset,
            static_cast<float>(std::clamp(intensity, 0.0, 1.0))) != GpuKernelStatus::ok ||
        result == nullptr) {
        expect(false, "preset dispatch must succeed");
        return;
    }
    std::vector<Rgba32F> gpu(pixels.size());
    if (result->download(device, gpu.data(), width) != GpuImageStatus::ok) {
        expect(false, "preset download must succeed");
        return;
    }

    const float worst = max_delta(cpu.image.pixels, gpu);
    if (worst > tolerance) {
        std::cerr << "FAIL: " << label << " preset delta " << worst << " exceeds "
                  << tolerance << '\n';
        ++failures;
    } else {
        std::cout << label << " preset max delta " << worst << '\n';
    }
}

void run_all(const GpuDevice& device, const char* const label) {
    // 프리셋 표에서 성격이 다른 스톡 셋을 고릅니다 — 하나만 보면 어느 커널이
    // 건너뛰어지는지가 우연히 고정됩니다.
    preset_matches_cpu(device, label, FilmEmulation::portra_400, 0.8);
    preset_matches_cpu(device, label, FilmEmulation::velvia_50, 0.5);
    preset_matches_cpu(device, label, FilmEmulation::vision3_500t, 1.0);
    // 세기가 아주 작으면 원본이 거의 그대로 나와야 합니다 — 혼합 항을 시험합니다.
    preset_matches_cpu(device, label, FilmEmulation::portra_400, 0.01);
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
    std::cout << "gpu digital film color preset tests passed\n";
    return 0;
}
