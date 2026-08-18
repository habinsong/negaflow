// CPU/GPU 동치 시험입니다. **이 시험이 GPU 이식의 유일한 증명입니다.**
//
// macOS  : `ChromabaseMetalKernels.swift:185` `basicTone`
// CPU 판 : `imaging/tone_mapping.cpp:79` `apply_basic_tone`
// GPU 판 : `gpu/shaders/basic_tone.hlsl` + `gpu/gpu_basic_tone.cpp`
//
// 허용 오차 `1e-5` 는 float32 반올림 범위입니다. 이보다 크게 벌어지면 반올림이 아니라
// 이식 실수입니다 — 오차를 늘리지 말고 커널을 고치십시오.

#include "negaflow/gpu/gpu_basic_tone.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <string_view>
#include <vector>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/imaging/tone_mapping.h"

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

using negaflow::core::Rgba32F;
using negaflow::gpu::GpuBasicTone;
using negaflow::gpu::GpuBasicToneParameters;
using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuDevicePreference;
using negaflow::gpu::GpuImageStatus;
using negaflow::gpu::GpuKernelStatus;
using negaflow::gpu::GpuWorkingImage;

constexpr float tolerance = 1.0e-5F;
constexpr std::uint32_t width = 64U;
constexpr std::uint32_t height = 48U;

// 커널의 모든 마스크 경계를 지나도록 값을 넓게 깝니다. 0 아래·1 위 값도 넣습니다 —
// 작업 이미지는 그런 값을 일부러 남기고, `tone_safe_unit_rgb` 가 그것을 다룹니다.
[[nodiscard]] std::vector<Rgba32F> make_ramp() {
    std::vector<Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float u = static_cast<float>(x) / static_cast<float>(width - 1U);
            const float v = static_cast<float>(y) / static_cast<float>(height - 1U);
            pixels[(static_cast<std::size_t>(y) * width) + x] = Rgba32F{
                (u * 1.30F) - 0.15F,
                v,
                (1.0F - u) * (0.25F + (0.75F * v)),
                1.0F};
        }
    }
    return pixels;
}

struct Case final {
    const char* name;
    negaflow::imaging::BasicToneParameters parameters;
};

// 매개변수마다 다른 가지를 탑니다 — 양수 대비는 blend=1, 음수 대비는 저역 가드를 지납니다.
const Case cases[] = {
    {"neutral", {}},
    {"contrast_positive", {0.75F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F}},
    {"contrast_negative", {-0.80F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F}},
    {"contrast_below_threshold", {5.0e-5F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F}},
    {"contrast_clamped_high", {2.5F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F}},
    {"density", {0.0F, 0.6F, 0.0F, 0.0F, 0.0F, 0.0F}},
    {"highlights", {0.0F, 0.0F, -0.9F, 0.0F, 0.0F, 0.0F}},
    {"shadows", {0.0F, 0.0F, 0.0F, 0.85F, 0.0F, 0.0F}},
    {"whites", {0.0F, 0.0F, 0.0F, 0.0F, 1.8F, 0.0F}},
    {"blacks", {0.0F, 0.0F, 0.0F, 0.0F, 0.0F, -1.7F}},
    {"all_together", {0.35F, -0.25F, 0.4F, -0.3F, 0.9F, 0.6F}},
};

[[nodiscard]] std::vector<Rgba32F> run_cpu(
    const std::vector<Rgba32F>& source,
    const negaflow::imaging::BasicToneParameters& parameters) {
    std::vector<Rgba32F> destination(source.size());
    const negaflow::core::ConstImageView input{
        source.data(), source.size(), width, height, width};
    const negaflow::core::ImageView output{
        destination.data(), destination.size(), width, height, width};
    (void)negaflow::imaging::apply_basic_tone(input, output, parameters);
    return destination;
}

void kernel_matches_cpu(const GpuDevice& device, const char* const label) {
    GpuBasicTone kernel{};
    const GpuKernelStatus created = GpuBasicTone::create(device, kernel);
    expect(created == GpuKernelStatus::ok, "kernel must be creatable");
    if (created != GpuKernelStatus::ok) {
        std::cerr << "  " << negaflow::gpu::gpu_kernel_status_name(created) << " on " << label
                  << '\n';
        return;
    }

    const std::vector<Rgba32F> source = make_ramp();

    GpuWorkingImage input{};
    if (GpuWorkingImage::upload(device, source.data(), width, height, width, input) !=
        GpuImageStatus::ok) {
        expect(false, "source upload must succeed");
        return;
    }
    GpuWorkingImage output{};
    if (GpuWorkingImage::create(device, width, height, output) != GpuImageStatus::ok) {
        expect(false, "destination must be creatable");
        return;
    }

    for (const Case& scenario : cases) {
        const GpuBasicToneParameters gpu_parameters{
            scenario.parameters.contrast,
            scenario.parameters.density,
            scenario.parameters.highlights,
            scenario.parameters.shadows,
            scenario.parameters.whites,
            scenario.parameters.blacks};
        if (kernel.dispatch(device, input, output, gpu_parameters) != GpuKernelStatus::ok) {
            expect(false, "dispatch must succeed");
            continue;
        }

        std::vector<Rgba32F> gpu_pixels(source.size());
        if (output.download(device, gpu_pixels.data(), width) != GpuImageStatus::ok) {
            expect(false, "download must succeed");
            continue;
        }

        const std::vector<Rgba32F> cpu_pixels = run_cpu(source, scenario.parameters);

        float worst = 0.0F;
        std::size_t worst_index = 0U;
        for (std::size_t index = 0U; index < cpu_pixels.size(); ++index) {
            const float differences[4] = {
                std::abs(cpu_pixels[index].red - gpu_pixels[index].red),
                std::abs(cpu_pixels[index].green - gpu_pixels[index].green),
                std::abs(cpu_pixels[index].blue - gpu_pixels[index].blue),
                std::abs(cpu_pixels[index].alpha - gpu_pixels[index].alpha)};
            const float largest = *std::max_element(std::begin(differences), std::end(differences));
            if (largest > worst) {
                worst = largest;
                worst_index = index;
            }
        }

        if (worst > tolerance) {
            std::cerr << "FAIL: " << label << ' ' << scenario.name << " max delta " << worst
                      << " at pixel " << worst_index << " (cpu "
                      << cpu_pixels[worst_index].red << ',' << cpu_pixels[worst_index].green << ','
                      << cpu_pixels[worst_index].blue << " gpu " << gpu_pixels[worst_index].red
                      << ',' << gpu_pixels[worst_index].green << ','
                      << gpu_pixels[worst_index].blue << ")\n";
            ++failures;
        } else {
            std::cout << "[gpu] " << label << ' ' << scenario.name << " max delta " << worst
                      << '\n';
        }
    }
}

void rejects_bad_arguments(const GpuDevice& device) {
    GpuBasicTone kernel{};
    if (GpuBasicTone::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "kernel needed for argument checks");
        return;
    }

    const std::vector<Rgba32F> source = make_ramp();
    GpuWorkingImage input{};
    (void)GpuWorkingImage::upload(device, source.data(), width, height, width, input);
    GpuWorkingImage output{};
    (void)GpuWorkingImage::create(device, width, height, output);

    GpuBasicToneParameters bad{};
    bad.contrast = std::numeric_limits<float>::quiet_NaN();
    expect(
        kernel.dispatch(device, input, output, bad) == GpuKernelStatus::non_finite_parameter,
        "NaN parameter is rejected like the CPU path");

    GpuWorkingImage mismatched{};
    (void)GpuWorkingImage::create(device, width + 1U, height, mismatched);
    expect(
        kernel.dispatch(device, input, mismatched, GpuBasicToneParameters{}) ==
            GpuKernelStatus::invalid_arguments,
        "size mismatch is rejected");

    // 같은 자원을 SRV·UAV 로 동시에 묶을 수 없습니다. 조용히 잘못된 결과를 내면 안 됩니다.
    expect(
        kernel.dispatch(device, input, input, GpuBasicToneParameters{}) ==
            GpuKernelStatus::invalid_arguments,
        "aliasing source and destination is rejected");

    const GpuDevice empty{};
    GpuBasicTone unusable{};
    expect(
        GpuBasicTone::create(empty, unusable) == GpuKernelStatus::device_unavailable,
        "kernel creation on an unusable device is reported");
}

void status_names_are_stable() {
    using negaflow::gpu::gpu_kernel_status_name;
    expect(std::string_view{gpu_kernel_status_name(GpuKernelStatus::ok)} == "ok", "ok name");
    expect(
        std::string_view{gpu_kernel_status_name(GpuKernelStatus::non_finite_parameter)} ==
            "non_finite_parameter",
        "non_finite_parameter name");
    expect(
        std::string_view{gpu_kernel_status_name(GpuKernelStatus::invalid_arguments)} ==
            "invalid_arguments",
        "invalid_arguments name");
}

}  // namespace

int main() {
    // WARP 먼저 — 하드웨어가 없는 CI 에서도 동치가 지켜지는지 봅니다.
    const GpuDevice warp = GpuDevice::create(GpuDevicePreference::warp_only);
    if (!warp.is_usable()) {
        std::cerr << "FAIL: WARP device is required for these checks\n";
        return 1;
    }
    kernel_matches_cpu(warp, "warp");
    rejects_bad_arguments(warp);

    // 하드웨어가 있으면 같은 것을 하드웨어에서도 봅니다. 드라이버마다 부동소수 재배열이
    // 다를 수 있어 **벤더별로 따로 확인해야** 합니다.
    const GpuDevice hardware = GpuDevice::create(GpuDevicePreference::hardware_only);
    if (hardware.is_usable()) {
        std::cout << "[gpu] hardware: " << hardware.capability().adapter.description.data() << '\n';
        kernel_matches_cpu(hardware, "hardware");
        rejects_bad_arguments(hardware);
    } else {
        std::cout << "[gpu] hardware absent, WARP only\n";
    }

    status_names_are_stable();

    if (failures != 0) {
        std::cerr << failures << " gpu basic tone check(s) failed\n";
        return 1;
    }
    std::cout << "gpu basic tone checks passed\n";
    return 0;
}
