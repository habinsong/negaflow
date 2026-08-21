// 제품 경로 — `downsample_for_statistics` GPU 밉 축소.
//
// CPU 는 스코프 밖 같은 함수, GPU 는 `apply_mip_halve_levels` 가 true 여야 한다.
// 참조를 옮겨 적지 않는다. 2x2 `halve` 는 비트 일치, 마지막 이중선형은 양쪽 CPU.

#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <vector>

#include "negaflow/imaging/kernel_accelerator.h"
#include "negaflow/imaging/mipmap_downsampler.h"
#include "negaflow/pipeline/gpu_accelerator.h"

namespace {

using negaflow::core::ConstImageView;
using negaflow::core::Rgba32F;
using negaflow::imaging::DownsampledProxy;
using negaflow::pipeline::GpuAccelerator;

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] std::vector<Rgba32F> make_pattern(
    const std::uint32_t width,
    const std::uint32_t height) {
    std::vector<Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float u = static_cast<float>(x) / 7.0F;
            const float v = static_cast<float>(y) / 11.0F;
            pixels[(static_cast<std::size_t>(y) * width) + x] = Rgba32F{
                u - static_cast<float>(static_cast<int>(u)) + 0.013F,
                v - static_cast<float>(static_cast<int>(v)) + 0.027F,
                ((u * v) / 3.0F) + 0.041F,
                1.0F};
        }
    }
    return pixels;
}

void compare_proxy(
    const char* const label,
    const DownsampledProxy& cpu,
    const DownsampledProxy& other) {
    expect(cpu.width == other.width && cpu.height == other.height, "proxy size");
    expect(cpu.pixels.size() == other.pixels.size(), "proxy pixel count");
    if (cpu.pixels.size() != other.pixels.size()) {
        return;
    }
    for (std::size_t index = 0U; index < cpu.pixels.size(); ++index) {
        if (cpu.pixels[index].red != other.pixels[index].red ||
            cpu.pixels[index].green != other.pixels[index].green ||
            cpu.pixels[index].blue != other.pixels[index].blue ||
            cpu.pixels[index].alpha != other.pixels[index].alpha) {
            std::cerr << "FAIL: " << label << " differs at " << index << " cpu "
                      << cpu.pixels[index].red << " other " << other.pixels[index].red
                      << '\n';
            ++failures;
            return;
        }
    }
    std::cout << label << " bit-exact " << cpu.width << 'x' << cpu.height << '\n';
}

void check_one(
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t target_width,
    const std::uint32_t target_height) {
    const std::vector<Rgba32F> pixels = make_pattern(width, height);
    const ConstImageView source{
        pixels.data(), pixels.size(), width, height, width};

    const DownsampledProxy cpu =
        negaflow::imaging::downsample_for_statistics(source, target_width, target_height);
    expect(!cpu.pixels.empty(), "CPU downsample must produce pixels");

    std::uint32_t last_width = width;
    std::uint32_t last_height = height;
    int steps = 0;
    const double ratio =
        static_cast<double>(width) / static_cast<double>(target_width);
    const int wanted = ratio > 1.0 ? static_cast<int>(std::floor(std::log2(ratio))) : 0;
    for (int step = 0; step < wanted; ++step) {
        if (last_width < 2U || last_height < 2U) {
            break;
        }
        last_width = last_width / 2U;
        if (last_width == 0U) {
            last_width = 1U;
        }
        last_height = last_height / 2U;
        if (last_height == 0U) {
            last_height = 1U;
        }
        ++steps;
    }
    expect(steps > 0, "test size must request at least one halve");

    std::vector<Rgba32F> gpu_last(static_cast<std::size_t>(last_width) * last_height);
    std::uint32_t out_width = 0U;
    std::uint32_t out_height = 0U;
    const bool ran = GpuAccelerator::shared().apply_mip_halve_levels(
        reinterpret_cast<const float*>(pixels.data()),
        width,
        height,
        width,
        steps,
        reinterpret_cast<float*>(gpu_last.data()),
        last_width * last_height,
        &out_width,
        &out_height);
    expect(ran, "GPU mip halve must run — fallback would make this test vacuous");
    expect(out_width == last_width && out_height == last_height, "GPU last size");
    if (!ran) {
        return;
    }

    DownsampledProxy product{};
    {
        const negaflow::imaging::ApproximateAcceleratorScope scope{};
        product = negaflow::imaging::downsample_for_statistics(
            source, target_width, target_height);
    }
    compare_proxy("product", cpu, product);
}

}  // namespace

int main() {
    _putenv_s("NEGA_GPU_MIP_HALVE", "1");
    negaflow::pipeline::install_gpu_kernel_accelerator();
    if (!GpuAccelerator::shared().available()) {
        std::cout << "GPU unavailable — mip halve product test skipped\n";
        return 0;
    }
    std::cout << "adapter: " << GpuAccelerator::shared().adapter_description() << '\n';

    check_one(97U, 53U, 20U, 10U);
    check_one(61U, 37U, 12U, 7U);

    if (failures != 0) {
        std::cerr << failures << " failure(s)\n";
        return 1;
    }
    std::cout << "gpu mip halve product tests passed\n";
    return 0;
}
