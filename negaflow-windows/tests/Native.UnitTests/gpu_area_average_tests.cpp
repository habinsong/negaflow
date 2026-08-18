// CPU/GPU 동치 — CIAreaAverage 대응 면적 평균.
//
// ☠️ 참조를 옮겨 적지 않습니다. CPU 는 스코프 밖 `area_average`,
//    GPU 는 `GpuAccelerator::apply_area_average` 가 true 일 때만 겨룹니다.
//    제품 경로는 스코프 안에서 같은 `area_average` 를 부릅니다.

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <vector>

#include "negaflow/imaging/area_average.h"
#include "negaflow/imaging/kernel_accelerator.h"
#include "negaflow/pipeline/gpu_accelerator.h"

namespace {

using negaflow::core::Rgba32F;
using negaflow::imaging::AreaAverage;
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

[[nodiscard]] WorkingImage make_pattern() {
    WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.resize(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float fx = static_cast<float>(x) / 96.0F;
            const float fy = static_cast<float>(y) / 52.0F;
            image.pixels[(static_cast<std::size_t>(y) * width) + x] = Rgba32F{
                0.05F + fx * 0.7F,
                0.10F + fy * 0.6F,
                0.20F + (1.0F - fx) * 0.4F,
                0.80F};
        }
    }
    return image;
}

void compare_mean(
    const char* const label,
    const AreaAverage& cpu,
    const float gpu[4],
    const std::uint64_t gpu_count) {
    expect(cpu.count == gpu_count, "count must match");
    const float dr = std::abs(static_cast<float>(cpu.red) - gpu[0]);
    const float dg = std::abs(static_cast<float>(cpu.green) - gpu[1]);
    const float db = std::abs(static_cast<float>(cpu.blue) - gpu[2]);
    const float worst = std::max({dr, dg, db});
    if (worst > tolerance) {
        std::cerr << "FAIL: " << label << " area average delta " << worst
                  << " (cpu " << cpu.red << "," << cpu.green << "," << cpu.blue
                  << " gpu " << gpu[0] << "," << gpu[1] << "," << gpu[2] << ")\n";
        ++failures;
    } else {
        std::cout << label << " area average max delta " << worst << " count " << cpu.count
                  << '\n';
    }
}

}  // namespace

int main() {
    _putenv_s("NEGA_GPU_AREA_AVERAGE", "1");
    negaflow::pipeline::install_gpu_kernel_accelerator();
    if (!GpuAccelerator::shared().available()) {
        std::cout << "GPU unavailable — area average test skipped\n";
        return 0;
    }
    std::cout << "adapter: " << GpuAccelerator::shared().adapter_description() << '\n';

    const WorkingImage image = make_pattern();
    AreaAverage cpu{};
    expect(
        negaflow::imaging::area_average(image, 0U, 0U, width, height, cpu),
        "CPU full-frame average must succeed");
    expect(cpu.count == static_cast<std::uint64_t>(width) * height, "full-frame count");

    float gpu[4]{};
    std::uint64_t gpu_count = 0U;
    const bool ran = GpuAccelerator::shared().apply_area_average(
        reinterpret_cast<const float*>(image.pixels.data()),
        width,
        height,
        width,
        0U,
        0U,
        width,
        height,
        gpu,
        &gpu_count);
    expect(ran, "GPU area average must run — fallback would make this test vacuous");
    if (!ran) {
        return 1;
    }
    compare_mean("direct", cpu, gpu, gpu_count);

    AreaAverage product{};
    {
        const negaflow::imaging::ApproximateAcceleratorScope scope{};
        expect(
            negaflow::imaging::area_average(image, 0U, 0U, width, height, product),
            "product-path average must succeed");
    }
    const float product_mean[4]{
        static_cast<float>(product.red),
        static_cast<float>(product.green),
        static_cast<float>(product.blue),
        static_cast<float>(product.alpha)};
    compare_mean("product", cpu, product_mean, product.count);

    AreaAverage cpu_roi{};
    expect(
        negaflow::imaging::area_average(image, 7U, 5U, 40U, 20U, cpu_roi),
        "CPU ROI average must succeed");
    float gpu_roi[4]{};
    std::uint64_t gpu_roi_count = 0U;
    expect(
        GpuAccelerator::shared().apply_area_average(
            reinterpret_cast<const float*>(image.pixels.data()),
            width,
            height,
            width,
            7U,
            5U,
            40U,
            20U,
            gpu_roi,
            &gpu_roi_count),
        "GPU ROI average must run");
    compare_mean("roi", cpu_roi, gpu_roi, gpu_roi_count);

    if (failures != 0) {
        std::cerr << failures << " failure(s)\n";
        return 1;
    }
    std::cout << "gpu area average tests passed\n";
    return 0;
}
