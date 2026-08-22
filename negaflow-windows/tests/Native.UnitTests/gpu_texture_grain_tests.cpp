// CPU/GPU 동치 — TextureStage `filmGrain`.
//
// 참조를 옮겨 적지 않습니다. CPU 는 `apply_texture_stage`(스코프 밖),
// GPU 는 `GpuAccelerator::apply_texture_grain` 이 true 일 때만 겨룹니다.
// 제품 경로는 스코프 안에서 같은 `apply_texture_stage` 를 부릅니다.

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <vector>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_texture_grain.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/imaging/kernel_accelerator.h"
#include "negaflow/imaging/texture_stage.h"
#include "negaflow/pipeline/gpu_accelerator.h"

namespace {

using negaflow::core::Rgba32F;
using negaflow::imaging::TextureStageParameters;
using negaflow::imaging::WorkingImage;
using negaflow::pipeline::GpuAccelerator;

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

constexpr float tolerance = 1.0e-5F;
constexpr std::uint32_t width = 97U;
constexpr std::uint32_t height = 53U;
constexpr float grain_strength = 0.40F;

[[nodiscard]] std::vector<Rgba32F> make_pattern() {
    std::vector<Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::uint32_t seed = (x * 73856093U) ^ (y * 19349663U);
            const float noise = static_cast<float>((seed ^ (seed >> 13U)) >> 8U) / 16777216.0F;
            const float luma = 0.02F + (static_cast<float>(x) / 96.0F) * 0.96F;
            pixels[(static_cast<std::size_t>(y) * width) + x] = Rgba32F{
                luma,
                luma * 0.85F + noise * 0.05F,
                luma * 0.70F,
                0.25F + noise * 0.5F};
        }
    }
    return pixels;
}

[[nodiscard]] WorkingImage make_working(const std::vector<Rgba32F>& pixels) {
    WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels = pixels;
    return image;
}

[[nodiscard]] float channel_delta(const Rgba32F& left, const Rgba32F& right) noexcept {
    return std::max(
        {std::abs(left.red - right.red),
         std::abs(left.green - right.green),
         std::abs(left.blue - right.blue),
         std::abs(left.alpha - right.alpha)});
}

void compare(
    const char* const label,
    const std::vector<Rgba32F>& source,
    const std::vector<Rgba32F>& cpu,
    const std::vector<Rgba32F>& gpu) {
    float worst = 0.0F;
    std::size_t changed = 0U;
    std::size_t alpha_changed = 0U;
    for (std::size_t index = 0U; index < gpu.size(); ++index) {
        worst = std::max(worst, channel_delta(cpu[index], gpu[index]));
        if (channel_delta(cpu[index], source[index]) > 0.0F) {
            ++changed;
        }
        if (cpu[index].alpha != source[index].alpha || gpu[index].alpha != source[index].alpha) {
            ++alpha_changed;
        }
    }
    expect(changed > 0U, "grain must change some pixels");
    expect(alpha_changed == 0U, "grain must preserve alpha");
    if (worst > tolerance) {
        std::cerr << "FAIL: " << label << " texture grain delta " << worst << '\n';
        ++failures;
    } else {
        std::cout << label << " texture grain max delta " << worst << " (changed " << changed
                  << ")\n";
    }
}

void warp_matches_cpu(const std::vector<Rgba32F>& source, const std::vector<Rgba32F>& cpu) {
    using negaflow::gpu::GpuDevice;
    using negaflow::gpu::GpuDevicePreference;
    using negaflow::gpu::GpuImageStatus;
    using negaflow::gpu::GpuKernelStatus;
    using negaflow::gpu::GpuTextureGrain;
    using negaflow::gpu::GpuWorkingImage;

    const GpuDevice warp = GpuDevice::create(GpuDevicePreference::warp_only);
    if (!warp.is_usable()) {
        std::cout << "WARP unavailable — skipped\n";
        return;
    }
    GpuTextureGrain kernel{};
    if (GpuTextureGrain::create(warp, kernel) != GpuKernelStatus::ok) {
        expect(false, "WARP texture grain kernel must be creatable");
        return;
    }
    GpuWorkingImage uploaded{};
    GpuWorkingImage destination{};
    if (GpuWorkingImage::upload(warp, source.data(), width, height, width, uploaded) !=
            GpuImageStatus::ok ||
        GpuWorkingImage::create(warp, width, height, destination) != GpuImageStatus::ok) {
        expect(false, "WARP images must be creatable");
        return;
    }
    const float amount = grain_strength * 0.055F;
    if (kernel.dispatch(warp, uploaded, destination, amount) != GpuKernelStatus::ok) {
        expect(false, "WARP texture grain dispatch must succeed");
        return;
    }
    std::vector<Rgba32F> gpu(source.size());
    if (destination.download(warp, gpu.data(), width) != GpuImageStatus::ok) {
        expect(false, "WARP texture grain download must succeed");
        return;
    }
    compare("WARP", source, cpu, gpu);
}

} // namespace

int main() {
    _putenv_s("NEGA_GPU_TEXTURE_GRAIN", "1");
    negaflow::pipeline::install_gpu_kernel_accelerator();
    if (!GpuAccelerator::shared().available()) {
        std::cout << "GPU unavailable — texture grain test skipped\n";
        return 0;
    }
    std::cout << "adapter: " << GpuAccelerator::shared().adapter_description() << '\n';

    const std::vector<Rgba32F> source = make_pattern();
    TextureStageParameters parameters{};
    parameters.grain = grain_strength;

    auto cpu_image = make_working(source);
    auto cpu_result = negaflow::imaging::apply_texture_stage(std::move(cpu_image), parameters);
    expect(
        cpu_result.status == negaflow::imaging::TextureStageStatus::ok,
        "CPU texture stage must succeed");
    expect(cpu_result.info.grain_applied, "CPU grain must apply");
    const std::vector<Rgba32F> cpu = cpu_result.image.pixels;

    std::vector<Rgba32F> gpu = source;
    const bool ran = GpuAccelerator::shared().apply_texture_grain(
        reinterpret_cast<float*>(gpu.data()),
        width,
        height,
        width,
        grain_strength * 0.055F);
    expect(ran, "GPU texture grain must run — fallback would make this test vacuous");
    if (!ran) {
        return 1;
    }
    compare("direct", source, cpu, gpu);

    auto product_image = make_working(source);
    {
        const negaflow::imaging::ApproximateAcceleratorScope scope{};
        auto product = negaflow::imaging::apply_texture_stage(
            std::move(product_image), parameters);
        expect(
            product.status == negaflow::imaging::TextureStageStatus::ok,
            "product-path texture stage must succeed");
        expect(product.info.grain_applied, "product-path grain must apply");
        compare("product", source, cpu, product.image.pixels);
    }

    warp_matches_cpu(source, cpu);

    if (failures != 0) {
        std::cerr << failures << " failure(s)\n";
        return 1;
    }
    std::cout << "gpu texture grain tests passed\n";
    return 0;
}
